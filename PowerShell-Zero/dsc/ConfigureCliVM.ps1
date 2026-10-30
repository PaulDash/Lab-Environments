configuration ConfigureCliVM {
    param (
        [Parameter(Mandatory)] [String]$DNSServer,
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$DomainAdminCreds
    )

    Import-DscResource -ModuleName ComputerManagementDsc, NetworkingDsc, xActiveDirectory

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

    }
}
