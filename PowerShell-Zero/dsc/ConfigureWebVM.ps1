configuration ConfigureWebVM {
    param (
        [Parameter(Mandatory)] [String]$DNSServer,
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$DomainAdminCreds
    )

    Import-DscResource -ModuleName ComputerManagementDsc, NetworkingDsc, xActiveDirectory

    [String] $DomainNetbiosName = (Get-NetBIOSName -DomainFQDN $DomainFQDN)
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)
    # ComputerManagementDsc's Computer resource can emit a false authentication
    # error during its LDAP pre-check when the credential uses DOMAIN\user.
    # UPN format works for both that pre-check and Add-Computer.
    [PSCredential] $DomainAdminCredsQualified = New-Object PSCredential ("$($DomainAdminCreds.UserName)@$DomainFQDN", $DomainAdminCreds.Password)
    $ComputerName = Get-Content env:computername

    [Int] $RetryCount = 10
    [Int] $RetryIntervalSec = 30

    Node localhost {
        LocalConfigurationManager {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        #**********************************************************
        # Initialization of VM
        #**********************************************************
        DnsServerAddress DnsServerAddress { Address = $DNSServer; InterfaceAlias = $InterfaceAlias; AddressFamily = 'IPv4' }

        Firewall IcmpV4Echo {
            Name      = 'FPS-ICMP4-ERQ-In'
            Enabled   = 'True'
        }

        xWaitForADDomain DscForestWait {
            DomainName           = $DomainFQDN
            DomainUserCredential = $DomainAdminCredsQualified
            RetryCount           = $RetryCount
            RetryIntervalSec     = $RetryIntervalSec
            DependsOn            = "[DnsServerAddress]DnsServerAddress"
        }

        #**********************************************************
        # Web and file services
        #**********************************************************
        WindowsFeature IIS          { Ensure = 'Present'; Name = 'Web-Server' }
        WindowsFeature IISConsole   { Ensure = 'Present'; Name = 'Web-Mgmt-Console'; DependsOn = '[WindowsFeature]IIS' }
        WindowsFeature IISScripting { Ensure = 'Present'; Name = 'Web-Scripting-Tools'; DependsOn = '[WindowsFeature]IIS' }
        WindowsFeature FileServer   { Ensure = 'Present'; Name = 'FS-FileServer' }

        File DefaultPage {
            DestinationPath = 'C:\inetpub\wwwroot\iisstart.htm'
            Type            = 'File'
            Force           = $true
            Contents        = "<html><body><h1>$ComputerName.$DomainFQDN</h1><p>PowerShell lab web server.</p></body></html>"
            DependsOn       = '[WindowsFeature]IIS'
        }

        File FilesRoot  { DestinationPath = 'C:\Files';         Type = 'Directory'; Ensure = 'Present' }
        File ReportsDir { DestinationPath = 'C:\Files\Reports'; Type = 'Directory'; Ensure = 'Present'; DependsOn = '[File]FilesRoot' }
        File LogsDir    { DestinationPath = 'C:\Files\Logs';    Type = 'Directory'; Ensure = 'Present'; DependsOn = '[File]FilesRoot' }

        File SampleReport {
            DestinationPath = 'C:\Files\Reports\sales-2026.csv'
            Type            = 'File'
            Contents        = "Region,Month,Revenue`r`nNorth,Jan,12000`r`nNorth,Feb,13500`r`nSouth,Jan,9800`r`nSouth,Feb,10200`r`nEast,Jan,15100`r`nEast,Feb,14900`r`nWest,Jan,8700`r`nWest,Feb,9100`r`n"
            DependsOn       = '[File]ReportsDir'
        }

        File SampleLog {
            DestinationPath = 'C:\Files\Logs\app.log'
            Type            = 'File'
            Contents        = "2026-01-05 08:01:12 INFO  Service started`r`n2026-01-05 08:15:40 WARN  Slow response from backend (2300 ms)`r`n2026-01-05 09:02:03 ERROR Database connection failed`r`n2026-01-05 09:02:33 INFO  Retry succeeded`r`n2026-01-05 11:47:58 ERROR Timeout while writing report`r`n2026-01-05 12:00:00 INFO  Nightly job completed`r`n"
            DependsOn       = '[File]LogsDir'
        }

        Firewall SmbIn {
            Name      = 'FPS-SMB-In-TCP'
            Enabled   = 'True'
            DependsOn = '[WindowsFeature]FileServer'
        }

        #**********************************************************
        # Seeded state for and event log demo
        #**********************************************************

        Script SeedEventLog {
            GetScript  = { @{ Result = [System.Diagnostics.EventLog]::SourceExists('GDC-WebApp') } }
            TestScript = { [System.Diagnostics.EventLog]::SourceExists('GDC-WebApp') }
            SetScript  = {
                New-EventLog -LogName Application -Source 'GDC-WebApp'
                Write-EventLog -LogName Application -Source 'GDC-WebApp' -EventId 1000 -EntryType Information -Message 'GDC web application started.'
                Write-EventLog -LogName Application -Source 'GDC-WebApp' -EventId 2001 -EntryType Warning -Message 'Response time above threshold (2300 ms).'
                Write-EventLog -LogName Application -Source 'GDC-WebApp' -EventId 3001 -EntryType Error -Message 'Database connection failed.'
                Write-EventLog -LogName Application -Source 'GDC-WebApp' -EventId 3002 -EntryType Error -Message 'Report generation timed out.'
            }
        }

        #**********************************************************
        # Join the domain after all local configuration is complete
        #**********************************************************
        Computer DomainJoin {
            Name       = $ComputerName
            DomainName = $DomainFQDN
            Credential = $DomainAdminCredsQualified
            DependsOn  = @(
                '[xWaitForADDomain]DscForestWait'
                '[Firewall]IcmpV4Echo'
                '[WindowsFeature]IISConsole'
                '[WindowsFeature]IISScripting'
                '[File]DefaultPage'
                '[File]SampleReport'
                '[File]SampleLog'
                '[Firewall]SmbIn'
                '[Script]SeedEventLog'
            )
        }

        PendingReboot Reboot1 {
            Name      = 'RebootServer'
            DependsOn = '[Computer]DomainJoin'
        }

    }
}

function Get-NetBIOSName {
    [OutputType([string])]
    param(
        [string]$DomainFQDN
    )

    if ($DomainFQDN.Contains('.')) {
        $length=$DomainFQDN.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainFQDN.Substring(0,$length)
    }
    else {
        if ($DomainFQDN.Length -gt 15) {
            return $DomainFQDN.Substring(0,15)
        }
        else {
            return $DomainFQDN
        }
    }
}
