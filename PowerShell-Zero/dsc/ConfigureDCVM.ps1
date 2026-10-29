configuration ConfigureDCVM {
    param (
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$Admincreds,
        [Parameter(Mandatory)] [String]$PrivateIP,
        [Parameter()] [bool]$CreateLabUser = $true
    )

    Import-DscResource -ModuleName xActiveDirectory, NetworkingDsc, ComputerManagementDsc

    [String] $DomainNetbiosName = (Get-NetBIOSName -DomainFQDN $DomainFQDN)
    [String] $DomainDN = 'DC=' + (($DomainFQDN -split '\.') -join ',DC=')
    [System.Management.Automation.PSCredential] $DomainCredsNetbios = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    $SeedUsers = Import-Csv -Path (Join-Path $PSScriptRoot 'SeedUsers.csv')
    $Departments = $SeedUsers | Select-Object -ExpandProperty Department -Unique

    Node localhost {
        LocalConfigurationManager {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        WindowsFeature ADDS { Name = "AD-Domain-Services"; Ensure = "Present" }
        WindowsFeature DNS  { Name = "DNS";                Ensure = "Present" }
        WindowsFeature ADPowerShell { Name = "RSAT-AD-PowerShell"; Ensure = "Present"; DependsOn = "[WindowsFeature]ADDS" }

        DnsServerAddress DnsServerAddress {
            Address        = '127.0.0.1'
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn      = "[WindowsFeature]DNS"
        }

        xADDomain FirstDS {
            DomainName = $DomainFQDN
            DomainAdministratorCredential = $DomainCredsNetbios
            SafemodeAdministratorPassword = $DomainCredsNetbios
            DatabasePath = "C:\NTDS"
            LogPath = "C:\NTDS"
            SysvolPath = "C:\SYSVOL"
            DependsOn = "[DnsServerAddress]DnsServerAddress", "[WindowsFeature]ADDS"
        }

        PendingReboot Reboot1 {
            Name = "RebootServer"
            DependsOn = "[xADDomain]FirstDS"
        }

        Firewall IcmpV4Echo {
            Name    = 'FPS-ICMP4-ERQ-In'
            Enabled = 'True'
        }

        #**********************************************************
        # Lab accounts
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

        if ($CreateLabUser) {
            xADUser LabUser {
                DomainAdministratorCredential = $DomainCredsNetbios
                DomainName           = $DomainFQDN
                UserName             = 'labuser'
                GivenName            = 'Lab'
                Surname              = 'User'
                DisplayName          = 'Lab User'
                EmailAddress         = 'labuser@' + $DomainFQDN
                Password             = $Admincreds
                PasswordNeverExpires = $true
                Ensure               = 'Present'
                DependsOn            = "[PendingReboot]Reboot1"
            }
        }

        #**********************************************************
        # Sample directory data for the demos
        #**********************************************************
        xADOrganizationalUnit OuDepartments {
            Name = 'Departments'; Path = $DomainDN; Credential = $DomainCredsNetbios
            ProtectedFromAccidentalDeletion = $false; Ensure = 'Present'
            DependsOn = "[PendingReboot]Reboot1"
        }
        xADOrganizationalUnit OuWorkstations {
            Name = 'Workstations'; Path = $DomainDN; Credential = $DomainCredsNetbios
            ProtectedFromAccidentalDeletion = $false; Ensure = 'Present'
            DependsOn = "[PendingReboot]Reboot1"
        }
        xADOrganizationalUnit OuServers {
            Name = 'Servers'; Path = $DomainDN; Credential = $DomainCredsNetbios
            ProtectedFromAccidentalDeletion = $false; Ensure = 'Present'
            DependsOn = "[PendingReboot]Reboot1"
        }

        foreach ($Dept in $Departments) {
            xADOrganizationalUnit "OuDept_$Dept" {
                Name = $Dept; Path = "OU=Departments,$DomainDN"; Credential = $DomainCredsNetbios
                ProtectedFromAccidentalDeletion = $false; Ensure = 'Present'
                DependsOn = "[xADOrganizationalUnit]OuDepartments"
            }
        }

        foreach ($U in $SeedUsers) {
            $UserKey = $U.SamAccountName -replace '\W', '_'
            $UserEnabled = [System.Convert]::ToBoolean($U.Enabled)
            # xADUser rejects Enabled=$false together with Password, so disabled users get no password.
            if ($UserEnabled) {
                xADUser "User_$UserKey" {
                    DomainAdministratorCredential = $DomainCredsNetbios
                    DomainName           = $DomainFQDN
                    UserName             = $U.SamAccountName
                    GivenName            = $U.GivenName
                    Surname              = $U.Surname
                    DisplayName          = "$($U.GivenName) $($U.Surname)"
                    Department           = $U.Department
                    JobTitle             = $U.Title
                    EmailAddress         = "$($U.SamAccountName)@$DomainFQDN"
                    Path                 = "OU=$($U.Department),OU=Departments,$DomainDN"
                    Enabled              = $true
                    Password             = $Admincreds
                    PasswordNeverExpires = $true
                    Ensure               = 'Present'
                    DependsOn            = "[xADOrganizationalUnit]OuDept_$($U.Department)"
                }
            }
            else {
                xADUser "User_$UserKey" {
                    DomainAdministratorCredential = $DomainCredsNetbios
                    DomainName           = $DomainFQDN
                    UserName             = $U.SamAccountName
                    GivenName            = $U.GivenName
                    Surname              = $U.Surname
                    DisplayName          = "$($U.GivenName) $($U.Surname)"
                    Department           = $U.Department
                    JobTitle             = $U.Title
                    EmailAddress         = "$($U.SamAccountName)@$DomainFQDN"
                    Path                 = "OU=$($U.Department),OU=Departments,$DomainDN"
                    Enabled              = $false
                    PasswordNeverExpires = $true
                    Ensure               = 'Present'
                    DependsOn            = "[xADOrganizationalUnit]OuDept_$($U.Department)"
                }
            }
        }

        foreach ($Dept in $Departments) {
            $Members = @($SeedUsers | Where-Object Department -eq $Dept | ForEach-Object { $_.SamAccountName })
            $MemberDeps = @($Members | ForEach-Object { "[xADUser]User_$($_ -replace '\W', '_')" })
            xADGroup "Group_$Dept" {
                GroupName        = "GG-$Dept"
                GroupScope       = 'Global'
                Category         = 'Security'
                Path             = "OU=$Dept,OU=Departments,$DomainDN"
                MembersToInclude = $Members
                Credential       = $DomainCredsNetbios
                Ensure           = 'Present'
                DependsOn        = $MemberDeps
            }
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
