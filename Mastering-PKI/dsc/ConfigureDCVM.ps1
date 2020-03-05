configuration ConfigureDCVM
{
    param
    (
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$Admincreds,
        [Parameter(Mandatory)] [String]$PrivateIP
    )

    Import-DscResource -ModuleName xActiveDirectory, NetworkingDsc, xPSDesiredStateConfiguration, ActiveDirectoryCSDsc, CertificateDsc, xDnsServer, ComputerManagementDsc
    [String] $DomainNetbiosName = (Get-NetBIOSName -DomainFQDN $DomainFQDN)
    [System.Management.Automation.PSCredential] $DomainCredsNetbios = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface = Get-NetAdapter| Where-Object Name -Like "Ethernet*"| Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)
    $ComputerName = Get-Content env:computername
    [String] $SPTrustedSitesName = "SPSites"

    Node localhost
    {
        LocalConfigurationManager
        {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        WindowsFeature ADDS { Name = "AD-Domain-Services"; Ensure = "Present" }
        WindowsFeature DNS  { Name = "DNS"; Ensure = "Present" }

        Script script1
        {
            SetScript =  {
                Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics" 
            }
            GetScript =  { @{} }
            TestScript = { $false }
            DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature DnsTools { Name = "RSAT-DNS-Server"; Ensure = "Present" }

        DnsServerAddress DnsServerAddress 
        {
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn = "[WindowsFeature]DNS"
        }

        xADDomain FirstDS
        {
            DomainName = $DomainFQDN
            DomainAdministratorCredential = $DomainCredsNetbios
            SafemodeAdministratorPassword = $DomainCredsNetbios
            DatabasePath = "C:\NTDS"
            LogPath = "C:\NTDS"
            SysvolPath = "C:\SYSVOL"
            DependsOn = "[DnsServerAddress]DnsServerAddress"
        }

        PendingReboot Reboot1
        {
            Name = "RebootServer"
            DependsOn = "[xADDomain]FirstDS"
        }       

        #**********************************************************
        # Misc: Set email of AD domain admin and add remote AD tools
        #**********************************************************
        xADUser SetEmailOfDomainAdmin
        {
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
        xADUser CreateADUser1
        {
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

        xADUser CreateADUser2
        {
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


# CONSIDER CREATING DNS ENTIRES FOR
# CA-LINUX
# CA-ROOT
<#
            xDnsRecord AddADFSHostDNS {
                Name = $ADFSSiteName
                Zone = $DomainFQDN
                Target = $PrivateIP
                Type = "ARecord"
                Ensure = "Present"
                DependsOn = "[PendingReboot]Reboot1"
            }        
#>
    }
}

function Get-NetBIOSName
{
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


<#
# Azure DSC extension logging: C:\WindowsAzure\Logs\Plugins\Microsoft.Powershell.DSC\2.21.0.0
# Azure DSC extension configuration: C:\Packages\Plugins\Microsoft.Powershell.DSC\2.21.0.0\DSCWork

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name xAdcsDeployment
Install-Module -Name xCertificate
Install-Module -Name xPSDesiredStateConfiguration
Install-Module -Name xCredSSP
Install-Module -Name xWebAdministration
Install-Module -Name xDisk
Install-Module -Name xNetworking

help ConfigureDCVM

$Admincreds = Get-Credential -Credential "yvand"
$DomainFQDN = "contoso.local"
$PrivateIP = "10.20.1.20"

$outputPath = "C:\Packages\Plugins\Microsoft.Powershell.DSC\2.80.0.0\DSCWork\ConfigureDCVM.0\ConfigureDCVM"
ConfigureDCVM -Admincreds $Admincreds -AdfsSvcCreds $AdfsSvcCreds -DomainFQDN $DomainFQDN -PrivateIP $PrivateIP -ConfigureADFS $ConfigureADFS -ConfigurationData @{AllNodes=@(@{ NodeName="localhost"; PSDscAllowPlainTextPassword=$true })} -OutputPath $outputPath
Set-DscLocalConfigurationManager -Path $outputPath
Start-DscConfiguration -Path $outputPath -Wait -Verbose -Force

https://github.com/PowerShell/xActiveDirectory/issues/27
Uninstall-WindowsFeature "ADFS-Federation"
https://msdn.microsoft.com/library/mt238290.aspx
\\.\pipe\MSSQL$MICROSOFT##SSEE\sql\query
#>
