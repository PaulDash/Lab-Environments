# PowerShell Zero-to-Hero

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](https://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FPaulDash%2FLab-Environments%2Fmaster%2FPowerShell-Zero%2Fazuredeploy.json
)

Azure DevTest Labs environment for the PowerShell Zero-to-Hero course. Domain: `lab.graydaycafe.com`.

| VM | OS | Role |
| ---- | ---- | ----- |
| DC | Windows Server 2025 Core | AD DS, DNS, sample OUs/users/groups |
| CLI | Windows 11 Pro | Student workstation: RSAT (incl. AD Administrative Center), PowerShell 7, Sysinternals, VS Code |
| WEB (optional) | Windows Server 2025 Desktop | IIS, file shares, seeded services/event log, PowerShell 7, Sysinternals |

Accounts: `labadmin` (domain admin) and, optionally, `labuser` (standard user) with the same password.

## Key parameters

`deployWebServer`, `createLabUser`, `addPublicIPToClient`, `deployBastion`, `rdpSourceAddressPrefix` (defaults to the blocking placeholder `0.0.0.0/32`; set it once student addresses are known).
