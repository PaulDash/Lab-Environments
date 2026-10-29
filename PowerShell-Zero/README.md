# PowerShell Zero-to-Hero

Azure DevTest Labs environment for the PowerShell Zero-to-Hero course. Domain: `lab.graydaycafe.com`.

| VM | OS | Role |
|---|---|---|
| GDC-DC | Windows Server 2025 Core | AD DS, DNS, sample OUs/users/groups, PowerShell 7 |
| GDC-Cli | Windows 11 Pro | Student workstation: RSAT (incl. AD Administrative Center), PowerShell 7, Sysinternals, VS Code |
| GDC-Web (optional) | Windows Server 2025 Desktop | IIS, file shares, seeded services/event log, PowerShell 7, Sysinternals |

Accounts: `labadmin` (domain admin) and, optionally, `labuser` (standard user) with the same password.

## Before publishing

1. Create `dsc\FQDN.bgi` once: run `Bginfo64.exe`, delete all fields, enter `<Host Name>.<DNS Domain>` at a large font size, and use *File > Save As*. Without this file the VMs deploy without the wallpaper.
2. Run `Build-DscArchives.ps1` to rebuild the `dsc\*.zip` files whenever a DSC script, `SeedUsers.csv` or `FQDN.bgi` changes.
3. Register the repo as a lab artifact source, then run `Deploy.ps1`.

## Key parameters

`deployWebServer`, `createLabUser`, `addPublicIPToClient`, `deployBastion`, `rdpSourceAddressPrefix` (required), `clientImageSku`.
