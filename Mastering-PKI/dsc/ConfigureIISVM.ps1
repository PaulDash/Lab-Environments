configuration ConfigureIISVM {
    param (
        [Parameter(Mandatory)] [String]$DNSServer,
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$DomainAdminCreds
    )

    Import-DscResource -ModuleName ComputerManagementDsc, NetworkingDsc, xActiveDirectory

    [String] $DomainNetbiosName = (Get-NetBIOSName -DomainFQDN $DomainFQDN)
    $Interface = Get-NetAdapter| Where-Object Name -Like "Ethernet*"| Select-Object -First 1
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
        DnsServerAddress DnsServerAddress { Address = $DNSServer; InterfaceAlias = $InterfaceAlias; AddressFamily  = 'IPv4' }

        Firewall IcmpV4Echo {
            Name      = 'FPS-ICMP4-ERQ-In'
            Enabled   = 'True'
        }

        #**********************************************************
        # Join AD forest
        #**********************************************************
        xWaitForADDomain DscForestWait {
            DomainName           = $DomainFQDN
            DomainUserCredential = $DomainAdminCredsQualified
            RetryCount           = $RetryCount
            RetryIntervalSec     = $RetryIntervalSec
            DependsOn            = "[DnsServerAddress]DnsServerAddress"
        }

        WindowsFeature IIS {
            Ensure = 'Present'
            Name = 'Web-Server'
        }

        WindowsFeature IISConsole {
            Ensure = 'Present'
            Name = 'Web-Mgmt-Console'
            DependsOn = '[WindowsFeature]IIS'
        }
        WindowsFeature IISScriptingTools {
            Ensure = 'Present'
            Name = 'Web-Scripting-Tools'
            DependsOn = '[WindowsFeature]IIS'
        }
        WindowsFeature AspNet {
            Ensure = 'Present'
            Name = 'Web-Asp-Net45'
            DependsOn = @('[WindowsFeature]IIS')
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
                '[WindowsFeature]IISScriptingTools'
                '[WindowsFeature]AspNet'
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
