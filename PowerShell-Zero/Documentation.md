# PowerShell Zero-to-Hero lab environment

## Purpose

This document describes the environment produced by the `PowerShell-Zero` Azure Resource Manager (ARM) template. It is written for a course-planning AI agent: treat the items under **Guaranteed capabilities** as available when deployment and Desired State Configuration (DSC) complete successfully, and do not assume items listed under **Not guaranteed**.

The lab is an isolated Windows domain in Azure DevTest Labs. Students normally enter through the `CLI` server and use it to administer the domain controller and, when selected, an IIS/file-services member server. The environment supports introductory PowerShell, Windows administration, Active Directory automation, object/pipeline exercises, and multi-computer administration scenarios.

## Deployed topology

| Computer | Deployment | Operating system / image | Size | Configured role |
| --- | --- | --- | --- | --- |
| `DC` | Always | Windows Server 2025 Datacenter Core, small-disk Gen 2 marketplace image | `Standard_B2s` | AD DS forest root, DNS server, and seeded directory data |
| `CLI` | Always | Pinned custom Azure Compute Gallery image `CLI-Server2025/0.1.1` | `Standard_D2as_v7` | Interactive student entry point and domain member |
| `WEB` | Optional | Windows Server 2025 Datacenter with Desktop Experience, small-disk Gen 2 marketplace image | `Standard_B2s` | Domain member with IIS, file-server role, sample files, and sample events |

The `CLI` image is a private, subscription-specific image referenced by its full resource ID. It is a Server 2025 image with these components installed: PowerShell 7, VS Code, Putty, select RSAT tools.

### Network

- Virtual network: `10.<vNetSecondOctet>.0.0/16`; the second octet is assigned per student.
- Domain subnet: `10.<vNetSecondOctet>.1.0/24`.
- `DC` has the static address `10.<vNetSecondOctet>.1.20`.
- `CLI` and `WEB` receive dynamic private addresses.
- DSC changes `CLI` and `WEB` to use `DC` as their DNS server.
- `DC` forwards non-domain DNS queries to the Azure recursive resolver at `168.63.129.16`.
- No load balancer, NAT gateway, VPN, peering, IPv6 network, or additional subnet is created.

The access method is selected at deployment:

- `PublicIP` (default) gives only `CLI` a static public IP and DNS label. TCP 3389 is allowed only from `rdpSourceAddressPrefix`, which is replaced with the instructor or student public IP/CIDR.
- `Bastion` gives `CLI` no public IP and deploys Azure Bastion in `10.<vNetSecondOctet>.3.0/26`.

The same network security group is attached to every VM NIC. It adds an RDP rule but otherwise retains Azure's default NSG rules, including virtual-network traffic. `DC` and `WEB` have no public IP. IIS and SMB on `WEB` are intended for private, in-lab access rather than direct internet exposure.

## Deployment and configuration sequence

1. ARM creates the virtual network, NSG, selected remote-access resources, NICs, and VMs.
2. The DSC extension on `DC` installs AD DS and DNS, creates the forest, configures DNS forwarding, and seeds the directory. Reboots occur when required.
3. The `CLI` and optional `WEB` DSC extensions wait for the `DC` extension to finish, set their DNS client to `DC`, wait for the domain, join `lab.graydaycafe.com`, and reboot.
4. Before joining the domain, `WEB` also installs and seeds its web, file, and event-log workload.

The DSC Local Configuration Manager uses `ApplyOnly`. It applies the initial state but does not continuously monitor or automatically repair changes students make. This is useful for destructive administration exercises, but redeployment is the reliable reset mechanism.

The DSC archives include their required `xActiveDirectory`, `NetworkingDsc`, and `ComputerManagementDsc` resources, so configuration does not depend on downloading those modules during deployment. The VM extensions do, however, need access to the artifact URLs supplied by Azure DevTest Labs.

## Identity and sample data

The forest and DNS domain are `lab.graydaycafe.com`; the derived NetBIOS name is `LAB`.

`adminUserName` defaults to `labadmin` but can be customized per student at time of deployment. The supplied deployment password is used for:

- the local administrator account initially created on every VM;
- the `LAB\labadmin` domain administrator account created when `DC` is promoted; and
- every enabled sample domain user.

The directory contains `OU=Departments` with six child OUs and a global security group in each child OU:

| Department OU | Group | Users | Initial state |
| --- | --- | ---: | --- |
| Finance | `GG-Finance` | 4 | 3 enabled, 1 disabled |
| HR | `GG-HR` | 2 | 2 enabled |
| IT | `GG-IT` | 3 | 3 enabled |
| Marketing | `GG-Marketing` | 4 | 4 enabled |
| Sales | `GG-Sales` | 3 | 3 enabled |
| Operations | `GG-Operations` | 3 | 2 enabled, 1 disabled |

In total there are 19 sample users: 17 enabled and 2 disabled (`tbecker` and `fbraun`). Each user has given name, surname, display name, department, job title, and an email address in the lab domain. Each departmental group includes all users in that department, including its disabled user. Passwords do not expire. This intentionally simple credential model is suitable only for an isolated, short-lived training environment.

## Guaranteed capabilities

After a successful deployment, students can perform the following activities.

### PowerShell language and shell fundamentals

On the interactive Windows Server `CLI`, students can work with commands, aliases, help, providers, variables, types, operators, arrays, hash tables, script blocks, functions, error handling, formatting, the object pipeline, and standard Windows file/registry/process/service/event cmdlets. Windows PowerShell is intrinsic to the deployed Windows operating system. A particular PowerShell 7 version is not guaranteed.

### Active Directory and DNS administration

Students have domain-administrator credentials and a populated single-domain forest. They can query, create, modify, enable/disable, move, and remove users, groups, OUs, and computer accounts; filter and group realistic directory objects; inspect group membership; and work with AD-integrated DNS.

The ActiveDirectory PowerShell module is explicitly installed on `DC`. It is not explicitly installed on `CLI`, so lessons can always execute AD cmdlets in a PowerShell session on `DC` (for example through an instructor-provided remote-session workflow). Running `Get-ADUser` directly on `CLI` is conditional on the custom image containing RSAT.

### Multi-computer Windows administration

The lab has two domain-joined servers, or three when `WEB` is selected. This provides real targets for inventory, connectivity, CIM/WMI, service, process, event-log, filesystem, DNS, and computer-account exercises. Students can compare local and remote results and build scripts that accept multiple computer names.

PowerShell remoting/WinRM is not configured by the ARM template or DSC scripts. Windows Server may provide remote-management defaults through the custom/base images, but a course that requires `Enter-PSSession`, `Invoke-Command`, or CIM over WSMan must verify remoting during lab validation or include remoting setup as an exercise.

### Optional `WEB` workload

When `deployWebServer` is `Yes`, students can administer:

- IIS (`Web-Server`), IIS Management Console, and IIS scripting tools;
- the default site with a lab-specific `iisstart.htm` page;
- Windows File Server role services;
- `C:\Files\Reports\sales-2026.csv`, containing eight regional/monthly revenue rows;
- `C:\Files\Logs\app.log`, containing INFO, WARN, and ERROR records; and
- four Application log records from source `GDC-WebApp`: one information, one warning, and two errors.

These assets support CSV import, aggregation, calculated properties, text parsing, regex, error extraction, event-log filtering, HTML/IIS automation, service inspection, reporting, and cross-machine data collection.

The template creates folders and installs the file-server role but does **not** create an SMB share. Students can work with the files locally on `WEB`, access them through a remote session if remoting is available, or create and permission a share as a course exercise.

### DSC and infrastructure discussion

The deployment itself is a usable example of declarative configuration: it provisions roles, networking, a domain, accounts, files, firewall settings, and reboots with ARM and Windows PowerShell DSC. An instructor can use the repository source to teach configuration data, dependencies, idempotence, DSC resources, extension-based bootstrapping, and the distinction between Azure control-plane provisioning and guest configuration. The repository source files are not copied to the student VMs by the template.

## Suggested course scenarios

The available state is particularly well suited to:

- PowerShell discovery, syntax, objects, pipelines, filtering, sorting, grouping, and formatting;
- reusable functions and scripts that validate parameters and handle errors;
- bulk AD reporting and administration driven by CSV data;
- enabling disabled accounts, reorganizing OUs, and auditing departmental membership;
- joining identity, computer, service, event, filesystem, and network data into reports;
- parsing the sample application log and correlating it with `GDC-WebApp` events;
- IIS configuration and health checks on `WEB`;
- creating and securing an SMB share, then reporting on files and permissions;
- one-to-many remote administration after remoting has been validated or configured; and
- inspecting or extending the ARM/DSC implementation as an advanced topic.

## Not guaranteed or out of scope

A course planner must not assume the following without separate validation or installation:

- Windows 11: the current `CLI` reference is `CLI-Server2025/0.1.1`.
- RSAT for the ActiveDirectory, DNS, GroupPolicy, ServerManager, and FileServices management tools on `CLI`. Installation of these was best-effort.
- PowerShell Gallery modules beyond what the private image happens to contain.
- Azure CLI, the Az PowerShell module, an Azure managed identity, Azure RBAC rights, or student Azure credentials. The VMs are Azure-hosted, but the guest workload is a Windows/domain lab rather than an Azure-management lab.
- A preconfigured SMB share, PowerShell remoting, SSH, JEA endpoints, HTTPS certificates, a certificate authority, Group Policy objects beyond domain defaults, additional domain controllers, trusts, databases, containers, Linux hosts, Microsoft 365, or internet-hosted application endpoints.
- Direct student access to `DC` or `WEB` from the internet; only `CLI` receives the optional public IP.
- Persistence or automatic repair after students change the environment. There are no data disks, backups, snapshots, or scheduled resets in this template.

## Readiness checks before teaching

Before students begin, validate the deployed state rather than relying only on ARM reporting success:

1. RDP or Bastion access to `CLI` works with the intended domain account.
2. `CLI` resolves `dc.lab.graydaycafe.com`, is joined to the domain, and can reach `DC`.
3. All 19 sample users, six department OUs, and six groups exist.
4. If the lesson uses direct AD cmdlets on `CLI`, `Get-Module -ListAvailable ActiveDirectory` returns the module; otherwise install RSAT or plan to run the cmdlets on `DC`.
5. If the lesson uses remoting, verify `Test-WSMan`, authentication, firewall rules, and `Invoke-Command` between the intended computers.
6. If `WEB` is required, confirm it is domain joined, its default IIS page responds from `CLI`, the two sample files exist, and the `GDC-WebApp` events are present.
7. Confirm any image-dependent tools required by course material, especially PowerShell 7 and an editor.
