$api = '2018-09-15'
$subscriptionId = '2e86df6f-4e12-4a53-b338-94b019c9d7b0'
$rg = 'app-lab-core-rg'
$labName = 'lab-dtl'
$templateName = 'PowerShell-Zero'

$baseUri = "/subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.DevTestLab/labs/$labName"

$response = Invoke-AzRestMethod -Method GET `
    -Path "$baseUri/artifactSources?api-version=$api"

$response.StatusCode

$repos = ($response.Content | ConvertFrom-Json).value

$repos | Select-Object Name, Id,
    @{N='DisplayName'; E={$_.properties.displayName}},
    @{N='Status'; E={$_.properties.status}},
    @{N='ARMFolder'; E={$_.properties.armTemplateFolderPath}}

$repoName = Read-Host "Enter repo name"

$response = Invoke-AzRestMethod -Method GET `
    -Path "$baseUri/artifactSources/$repoName/armTemplates?api-version=$api"

$response.StatusCode

$templates = ($response.Content | ConvertFrom-Json).value

$templates | Select-Object Name, Id,
    @{N='DisplayName'; E={$_.properties.displayName}}

$template = $templates |
    Where-Object Name -eq $templateName |
    Select-Object -First 1

if (-not $template) {
    throw "Template $templateName not found."
}

$userId = '4dd54a6f-98bd-48b0-8ee1-b909a6e276d7'

$envName = Read-Host "Enter environment name"

$labResponse = Invoke-AzRestMethod -Method GET `
    -Path "${baseUri}?api-version=$api"

$location = ($labResponse.Content | ConvertFrom-Json).location

Write-Host "Template: $($template.id)"
Write-Host "Location: $location"

$adminUser = Read-Host 'Enter admin username [labadmin]'
if (-not $adminUser) { $adminUser = 'labadmin' }
$securePassword = Read-Host 'Enter admin password' -AsSecureString
$vNetSecondOctet = Read-Host 'Enter the second octet for 10.<octet>.0.0/16 (0-255)'
if ($vNetSecondOctet -notmatch '^\d{1,3}$' -or [int]$vNetSecondOctet -gt 255) {
    throw 'The VNet second octet must be an integer from 0 through 255.'
}

$rdpSource = Read-Host 'Enter the source IP/CIDR allowed to RDP (blank = detect this machine''s public IP)'
if (-not $rdpSource) {
    $rdpSource = '{0}/32' -f (Invoke-RestMethod -Uri 'https://api.ipify.org')
}

$deployWeb = Read-Host 'Deploy GDC-Web member server? (Yes/No) [Yes]'
if (-not $deployWeb) { $deployWeb = 'Yes' }
$createLabUser = Read-Host 'Create the non-privileged labuser account? (Yes/No) [Yes]'
if (-not $createLabUser) { $createLabUser = 'Yes' }
$useBastion = Read-Host 'Use Azure Bastion instead of a public IP on GDC-Cli? (Yes/No) [No]'
if (-not $useBastion) { $useBastion = 'No' }

foreach ($answer in $deployWeb, $createLabUser, $useBastion) {
    if ($answer -notin 'Yes', 'No') { throw "Invalid answer '$answer'. Use Yes or No." }
}

Write-Host "Deploying environment..."
$body = @{
    location = $location
    properties = @{
        deploymentProperties = @{
            armTemplateId = $template.id
            parameters = @(
                @{ name = 'adminUserName'; value = $adminUser }
                @{ name = 'adminPassword'; value = ([System.Net.NetworkCredential]::new('', $securePassword).Password) }
                @{ name = 'vNetSecondOctet'; value = [int]$vNetSecondOctet }
                @{ name = 'rdpSourceAddressPrefix'; value = $rdpSource }
                @{ name = 'deployWebServer'; value = $deployWeb }
                @{ name = 'createLabUser'; value = $createLabUser }
                @{ name = 'deployBastion'; value = $useBastion }
                @{ name = 'addPublicIPToClient'; value = $(if ($useBastion -eq 'Yes') { 'No' } else { 'Yes' }) }
            )
        }
    }
} | ConvertTo-Json -Depth 10

$securePassword = $null

$path = "$baseUri/users/$userId/environments/${envName}?api-version=$api"

try {
    $response = Invoke-AzRestMethod `
        -Method PUT `
        -Path $path `
        -Payload $body `
        -ErrorAction Stop
    Write-Host "HTTP status: $($response.StatusCode)"
    $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 15
} catch {
    Write-Host "Request failed:" -ForegroundColor Red
    $_ | Format-List * -Force
} finally {
    $body = $null
}
