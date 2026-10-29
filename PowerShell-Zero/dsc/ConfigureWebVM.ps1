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
    [PSCredential] $DomainAdminCredsQualified = New-Object PSCredential ("${DomainNetbiosName}\$($DomainAdminCreds.UserName)", $DomainAdminCreds.Password)
    $ComputerName = Get-Content env:computername
    [Int] $RetryCount = 30
    [Int] $RetryIntervalSec = 30
    $BgInfoConfigSource = Join-Path $PSScriptRoot 'FQDN.bgi'

    Node localhost {
        LocalConfigurationManager {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        DnsServerAddress DnsServerAddress { Address = $DNSServer; InterfaceAlias = $InterfaceAlias; AddressFamily = 'IPv4' }

        xWaitForADDomain DscForestWait {
            DomainName           = $DomainFQDN
            DomainUserCredential = $DomainAdminCredsQualified
            RetryCount           = $RetryCount
            RetryIntervalSec     = $RetryIntervalSec
            DependsOn            = "[DnsServerAddress]DnsServerAddress"
        }

        Computer DomainJoin {
            Name       = $ComputerName
            DomainName = $DomainFQDN
            Credential = $DomainAdminCredsQualified
            DependsOn  = "[xWaitForADDomain]DscForestWait"
        }

        PendingReboot Reboot1 {
            Name      = "RebootServer"
            DependsOn = "[Computer]DomainJoin"
        }

        Firewall IcmpV4Echo {
            Name      = 'FPS-ICMP4-ERQ-In'
            Enabled   = 'True'
            DependsOn = "[PendingReboot]Reboot1"
        }

        Script InstallPowerShell7 {
            GetScript  = { @{ Result = (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") } }
            TestScript = { Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe" }
            SetScript  = {
                $ProgressPreference = 'SilentlyContinue'
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $installer = Invoke-RestMethod -Uri 'https://aka.ms/install-powershell.ps1'
                & ([scriptblock]::Create($installer)) -UseMSI -Quiet
            }
            DependsOn  = "[PendingReboot]Reboot1"
        }

        #**********************************************************
        # Web and file services
        #**********************************************************
        WindowsFeature IIS        { Ensure = 'Present'; Name = 'Web-Server';       DependsOn = "[PendingReboot]Reboot1" }
        WindowsFeature IISConsole { Ensure = 'Present'; Name = 'Web-Mgmt-Console'; DependsOn = '[WindowsFeature]IIS' }
        WindowsFeature IISScripting { Ensure = 'Present'; Name = 'Web-Scripting-Tools'; DependsOn = '[WindowsFeature]IIS' }
        WindowsFeature FileServer { Ensure = 'Present'; Name = 'FS-FileServer';    DependsOn = "[PendingReboot]Reboot1" }

        File DefaultPage {
            DestinationPath = 'C:\inetpub\wwwroot\iisstart.htm'
            Type            = 'File'
            Force           = $true
            Contents        = "<html><body><h1>$ComputerName.$DomainFQDN</h1><p>PowerShell lab web server.</p></body></html>"
            DependsOn       = '[WindowsFeature]IIS'
        }

        File SharesRoot   { DestinationPath = 'C:\Shares';         Type = 'Directory'; Ensure = 'Present' }
        File ReportsShare { DestinationPath = 'C:\Shares\Reports'; Type = 'Directory'; Ensure = 'Present'; DependsOn = '[File]SharesRoot' }
        File LogsShare    { DestinationPath = 'C:\Shares\Logs';    Type = 'Directory'; Ensure = 'Present'; DependsOn = '[File]SharesRoot' }

        File SampleReport {
            DestinationPath = 'C:\Shares\Reports\sales-2026.csv'
            Type            = 'File'
            Contents        = "Region,Month,Revenue`r`nNorth,Jan,12000`r`nNorth,Feb,13500`r`nSouth,Jan,9800`r`nSouth,Feb,10200`r`nEast,Jan,15100`r`nEast,Feb,14900`r`nWest,Jan,8700`r`nWest,Feb,9100`r`n"
            DependsOn       = '[File]ReportsShare'
        }

        File SampleLog {
            DestinationPath = 'C:\Shares\Logs\app.log'
            Type            = 'File'
            Contents        = "2026-01-05 08:01:12 INFO  Service started`r`n2026-01-05 08:15:40 WARN  Slow response from backend (2300 ms)`r`n2026-01-05 09:02:03 ERROR Database connection failed`r`n2026-01-05 09:02:33 INFO  Retry succeeded`r`n2026-01-05 11:47:58 ERROR Timeout while writing report`r`n2026-01-05 12:00:00 INFO  Nightly job completed`r`n"
            DependsOn       = '[File]LogsShare'
        }

        Script SmbShares {
            GetScript  = { @{ Result = [bool](Get-SmbShare -Name 'Reports', 'Logs' -ErrorAction SilentlyContinue) } }
            TestScript = { (Get-SmbShare -Name 'Reports', 'Logs' -ErrorAction SilentlyContinue | Measure-Object).Count -eq 2 }
            SetScript  = {
                $domain = $using:DomainNetbiosName
                foreach ($name in 'Reports', 'Logs') {
                    if (-not (Get-SmbShare -Name $name -ErrorAction SilentlyContinue)) {
                        New-SmbShare -Name $name -Path "C:\Shares\$name" -FullAccess "$domain\Domain Admins" -ChangeAccess "$domain\Domain Users" | Out-Null
                    }
                }
            }
            DependsOn  = '[File]SampleReport', '[File]SampleLog', '[WindowsFeature]FileServer'
        }

        Firewall SmbIn {
            Name      = 'FPS-SMB-In-TCP'
            Enabled   = 'True'
            DependsOn = '[WindowsFeature]FileServer'
        }

        #**********************************************************
        # Seeded state for service, task and event log demos
        #**********************************************************
        Service Spooler {
            Name        = 'Spooler'
            State       = 'Stopped'
            StartupType = 'Manual'
            DependsOn   = "[PendingReboot]Reboot1"
        }

        ScheduledTask NightlyLogCheck {
            TaskName         = 'GDC-NightlyLogCheck'
            ActionExecutable = 'powershell.exe'
            ActionArguments  = '-NoProfile -Command "Get-ChildItem C:\Shares\Logs | Out-Null"'
            ScheduleType     = 'Daily'
            DaysInterval     = 1
            StartTime        = '02:00:00'
            Ensure           = 'Present'
            DependsOn        = '[File]LogsShare'
        }

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
            DependsOn  = "[PendingReboot]Reboot1"
        }

        #**********************************************************
        # Sysinternals Suite (includes BGInfo) and FQDN wallpaper
        #**********************************************************
        File ToolsFolder { DestinationPath = 'C:\Tools'; Type = 'Directory'; Ensure = 'Present' }

        Script InstallSysinternals {
            GetScript  = { @{ Result = (Test-Path 'C:\Tools\Sysinternals\Bginfo64.exe') } }
            TestScript = { Test-Path 'C:\Tools\Sysinternals\Bginfo64.exe' }
            SetScript  = {
                $ProgressPreference = 'SilentlyContinue'
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $zip = Join-Path $env:TEMP 'SysinternalsSuite.zip'
                Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/SysinternalsSuite.zip' -OutFile $zip -UseBasicParsing
                Expand-Archive -Path $zip -DestinationPath 'C:\Tools\Sysinternals' -Force
                Remove-Item $zip -Force
            }
            DependsOn  = "[File]ToolsFolder"
        }

        Environment SysinternalsPath {
            Name      = 'Path'
            Value     = 'C:\Tools\Sysinternals'
            Path      = $true
            Ensure    = 'Present'
            DependsOn = "[Script]InstallSysinternals"
        }

        if (Test-Path $BgInfoConfigSource) {
            File BgInfoFolder { DestinationPath = 'C:\Tools\BGInfo'; Type = 'Directory'; Ensure = 'Present'; DependsOn = "[File]ToolsFolder" }
            File BgInfoConfig {
                DestinationPath = 'C:\Tools\BGInfo\FQDN.bgi'
                SourcePath      = $BgInfoConfigSource
                Type            = 'File'
                Ensure          = 'Present'
                DependsOn       = "[File]BgInfoFolder"
            }
            Registry BgInfoAtLogon {
                Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                ValueName = 'BGInfo'
                ValueType = 'String'
                ValueData = '"C:\Tools\Sysinternals\Bginfo64.exe" "C:\Tools\BGInfo\FQDN.bgi" /timer:0 /nolicprompt /silent'
                Ensure    = 'Present'
                DependsOn = "[Script]InstallSysinternals", "[File]BgInfoConfig"
            }
        }
        else {
            Write-Warning 'FQDN.bgi not found in the DSC archive; the FQDN wallpaper will not be configured.'
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
