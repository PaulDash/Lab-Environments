configuration ConfigureCliVM {
    param (
        [Parameter(Mandatory)] [String]$DNSServer,
        [Parameter(Mandatory)] [String]$DomainFQDN,
        [Parameter(Mandatory)] [System.Management.Automation.PSCredential]$DomainAdminCreds,
        [Parameter()] [bool]$IncludeWebTools = $true
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

        # The client does not accept remoting by default; needed for one-to-many demos.
        Script EnablePSRemoting {
            GetScript  = { @{ Result = [bool](Get-PSSessionConfiguration -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue) } }
            TestScript = { [bool](Get-PSSessionConfiguration -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue) }
            SetScript  = { Enable-PSRemoting -Force -SkipNetworkProfileCheck }
            DependsOn  = "[PendingReboot]Reboot1"
        }

        Script InstallPowerShell7 {
            GetScript  = { @{ Result = (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") } }
            TestScript = { Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe" }
            SetScript  = {
                $ProgressPreference = 'SilentlyContinue'
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $installer = Invoke-RestMethod -Uri 'https://aka.ms/install-powershell.ps1'
                & ([scriptblock]::Create($installer)) -UseMSI -Quiet -EnablePSRemoting
            }
            DependsOn  = "[Script]EnablePSRemoting"
        }

        #**********************************************************
        # RSAT for the roles deployed in the lab (includes AD Administrative Center)
        #**********************************************************
        Script InstallRSAT {
            GetScript  = { @{ Result = '' } }
            TestScript = {
                $missing = Get-WindowsCapability -Online -Name 'Rsat.*' |
                    Where-Object { $_.Name -match 'ActiveDirectory\.DS-LDS|Dns\.Tools|GroupPolicy|ServerManager|FileServices' -and $_.State -ne 'Installed' }
                -not $missing
            }
            SetScript  = {
                $ProgressPreference = 'SilentlyContinue'
                Get-WindowsCapability -Online -Name 'Rsat.*' |
                    Where-Object { $_.Name -match 'ActiveDirectory\.DS-LDS|Dns\.Tools|GroupPolicy|ServerManager|FileServices' -and $_.State -ne 'Installed' } |
                    ForEach-Object { Add-WindowsCapability -Online -Name $_.Name | Out-Null }
            }
            DependsOn  = "[PendingReboot]Reboot1"
        }

        if ($IncludeWebTools) {
            WindowsOptionalFeature IISManagementConsole {
                Name      = 'IIS-ManagementConsole'
                Ensure    = 'Enable'
                DependsOn = "[PendingReboot]Reboot1"
            }
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

        #**********************************************************
        # VS Code with the PowerShell extension (extensions in a shared folder)
        #**********************************************************
        Script InstallVSCode {
            GetScript  = { @{ Result = (Test-Path "$env:ProgramFiles\Microsoft VS Code\Code.exe") } }
            TestScript = { Test-Path "$env:ProgramFiles\Microsoft VS Code\Code.exe" }
            SetScript  = {
                $ProgressPreference = 'SilentlyContinue'
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $installer = Join-Path $env:TEMP 'VSCodeSetup-x64.exe'
                Invoke-WebRequest -Uri 'https://update.code.visualstudio.com/latest/win32-x64/stable' -OutFile $installer -UseBasicParsing
                Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/NORESTART', '/MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,addtopath' -Wait
                Remove-Item $installer -Force

                $extDir = 'C:\ProgramData\VSCodeExtensions'
                New-Item -Path $extDir -ItemType Directory -Force | Out-Null
                & "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd" --install-extension ms-vscode.PowerShell --extensions-dir $extDir --user-data-dir 'C:\Windows\Temp\vscode-data' | Out-Null
                icacls $extDir /grant 'BUILTIN\Users:(OI)(CI)M' /T | Out-Null
                [Environment]::SetEnvironmentVariable('VSCODE_EXTENSIONS', $extDir, 'Machine')
            }
            DependsOn  = "[PendingReboot]Reboot1"
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
