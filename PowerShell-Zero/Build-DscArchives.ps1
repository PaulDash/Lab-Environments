# Builds the DSC archives (with bundled modules) that azuredeploy.json references.
param(
    [string]$DscFolder = (Join-Path $PSScriptRoot 'dsc')
)

$ErrorActionPreference = 'Stop'

foreach ($module in 'xActiveDirectory', 'NetworkingDsc', 'ComputerManagementDsc') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
    }
}

$extraFiles = @(Join-Path $DscFolder 'FQDN.bgi') | Where-Object { Test-Path $_ }
if (-not $extraFiles) {
    Write-Warning 'dsc\FQDN.bgi not found; GDC-Cli and GDC-Web will have no FQDN wallpaper.'
}

$configs = @{
    ConfigureDCVM  = @(Join-Path $DscFolder 'SeedUsers.csv')
    ConfigureCliVM = $extraFiles
    ConfigureWebVM = $extraFiles
}

foreach ($name in $configs.Keys) {
    $params = @{
        ConfigurationPath  = Join-Path $DscFolder "$name.ps1"
        OutputArchivePath  = Join-Path $DscFolder "$name.zip"
        Force              = $true
    }
    if ($configs[$name]) { $params.AdditionalPath = $configs[$name] }
    Publish-AzVMDscConfiguration @params
}
