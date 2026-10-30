# PowerShell Zero-to-Hero

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](https://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FPaulDash%2FLab-Environments%2Fmaster%2FPowerShell-Zero%2Fazuredeploy.json
)

Azure DevTest Labs environment for the PowerShell Zero-to-Hero course. Domain: `lab.graydaycafe.com`.

| VM | OS | Role |
| ---- | ---- | ----- |
| DC | Windows Server 2025 Core | Trusted Launch AD DS, DNS, sample OUs/users/groups |
| CLI | Windows 11 + tools (Gen 2) | Trusted Launch student workstation, domain joined with RSAT |
| WEB (optional) | Windows Server 2025 Desktop | Trusted Launch IIS/file server with seeded services and event log |

Accounts: `labadmin` (domain admin) and `labuser` (standard user) with the same password.

## Key parameters

`deployWebServer`, `addPublicIPToClient`, `deployBastion`, `rdpSourceAddressPrefix` (defaults to the blocking placeholder `0.0.0.0/32`; set it once student addresses are known).
