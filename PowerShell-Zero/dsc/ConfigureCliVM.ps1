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
    [Int] $RetryCount = 30
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

        #**********************************************************
        # RSAT for the roles deployed in the lab (includes AD Administrative Center)
        #**********************************************************
        Script InstallRSAT {
            GetScript  = {
                $missing = Get-WindowsCapability -Online -Name 'Rsat.*' |
                    Where-Object { $_.Name -match 'ActiveDirectory\.DS-LDS|Dns\.Tools|GroupPolicy|ServerManager|FileServices' -and $_.State -ne 'Installed' }
                @{ Result = (($missing.Name) -join ',') }
            }
            TestScript = {
                $missing = Get-WindowsCapability -Online -Name 'Rsat.*' |
                    Where-Object { $_.Name -match 'ActiveDirectory\.DS-LDS|Dns\.Tools|GroupPolicy|ServerManager|FileServices' -and $_.State -ne 'Installed' }
                -not $missing
            }
            SetScript  = {
                $ProgressPreference = 'SilentlyContinue'
                $capabilityPattern = 'ActiveDirectory\.DS-LDS|Dns\.Tools|GroupPolicy|ServerManager|FileServices'
                $maxAttempts = 2
                $timeoutSeconds = 1200

                for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                    $names = @(Get-WindowsCapability -Online -Name 'Rsat.*' |
                        Where-Object { $_.Name -match $capabilityPattern -and $_.State -ne 'Installed' } |
                        Select-Object -ExpandProperty Name)

                    if (-not $names) { return }

                    $job = $null
                    try {
                        $job = Start-Job -ArgumentList (, $names) -ScriptBlock {
                            param([string[]]$CapabilityNames)
                            $ProgressPreference = 'SilentlyContinue'
                            foreach ($name in $CapabilityNames) {
                                Add-WindowsCapability -Online -Name $name -ErrorAction Stop | Out-Null
                            }
                        }

                        if (-not (Wait-Job -Job $job -Timeout $timeoutSeconds)) {
                            Stop-Job -Job $job -ErrorAction SilentlyContinue
                            throw "RSAT installation exceeded the $timeoutSeconds second timeout."
                        }

                        Receive-Job -Job $job -ErrorAction Stop | Out-Null
                        if ($job.State -ne 'Completed') {
                            throw "RSAT installation job ended in state '$($job.State)'."
                        }
                    }
                    catch {
                        if ($attempt -eq $maxAttempts) {
                            throw "RSAT installation failed after $maxAttempts attempts: $($_.Exception.Message)"
                        }
                        Start-Sleep -Seconds 60
                    }
                    finally {
                        if ($job) {
                            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            DependsOn  = "[PendingReboot]Reboot1"
        }
    }
}
