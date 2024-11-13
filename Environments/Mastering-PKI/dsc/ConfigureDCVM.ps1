configuration ConfigureDCVM {
    param (
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$Admincreds,
        [Parameter(Mandatory)] [String]$PrivateIP
    )

    Import-DscResource -ModuleName xActiveDirectory, NetworkingDsc, xPSDesiredStateConfiguration, ActiveDirectoryCSDsc, CertificateDsc, xDnsServer, ComputerManagementDsc
    [String] $DomainNetbiosName = (Get-NetBIOSName -DomainFQDN $DomainFQDN)
    [System.Management.Automation.PSCredential] $DomainCredsNetbios = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    Node localhost {
        LocalConfigurationManager {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        WindowsFeature ADDS { Name = "AD-Domain-Services"; Ensure = "Present" }
        WindowsFeature DNS  { Name = "DNS";                Ensure = "Present" }
        WindowsFeature RSAT { Name = "RSAT";               Ensure = "Present" }

        Script script1 {
            SetScript =  {
                Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics" 
            }
            GetScript =  { @{} }
            TestScript = { $false }
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature DnsTools { Name = "RSAT-DNS-Server"; Ensure = "Present" }

        DnsServerAddress DnsServerAddress {
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn = "[WindowsFeature]DNS"
        }

        xADDomain FirstDS {
            DomainName = $DomainFQDN
            DomainAdministratorCredential = $DomainCredsNetbios
            SafemodeAdministratorPassword = $DomainCredsNetbios
            DatabasePath = "C:\NTDS"
            LogPath = "C:\NTDS"
            SysvolPath = "C:\SYSVOL"
            DependsOn = "[DnsServerAddress]DnsServerAddress"
        }

        PendingReboot Reboot1 {
            Name = "RebootServer"
            DependsOn = "[xADDomain]FirstDS"
        }       

        #**********************************************************
        # Misc: Set email of AD domain admin and add remote AD tools
        #**********************************************************
        xADUser SetEmailOfDomainAdmin {
            DomainAdministratorCredential = $DomainCredsNetbios
            DomainName = $DomainFQDN
            UserName = $Admincreds.UserName
            Password = $Admincreds
            EmailAddress = $Admincreds.UserName + "@" + $DomainFQDN
            PasswordAuthentication = 'Negotiate'
            Ensure = "Present"
            PasswordNeverExpires = $true
            DependsOn = "[PendingReboot]Reboot1"
        }

        # Create users
        xADUser CreateADUser1 {
            DomainAdministratorCredential = $DomainCredsNetbios
            DomainName                    = $DomainFQDN
            UserName                      = "John"
            GivenName                     = "John"
            Surname                       = "Smith"
            Password                      = $Admincreds
            PasswordNeverExpires          = $true
            Ensure                        = "Present"
            DependsOn                     = "[PendingReboot]Reboot1"
        }

        xADUser CreateADUser2 {
            DomainAdministratorCredential = $DomainCredsNetbios
            DomainName                    = $DomainFQDN
            UserName                      = "Jane"
            GivenName                     = "Jane"
            Surname                       = "Doe"
            Password                      = $Admincreds
            PasswordNeverExpires          = $true
            Ensure                        = "Present"
            DependsOn                     = "[PendingReboot]Reboot1"
        }

        WindowsFeature AddADFeature2    { Name = "RSAT-ADDS-Tools";     Ensure = "Present"; DependsOn = "[PendingReboot]Reboot1" }

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
