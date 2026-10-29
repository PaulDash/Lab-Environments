# Mastering PKI lab environment

This ARM template deploys the Mastering PKI DevTest Labs environment: a domain controller, a standalone root CA, an Enterprise CA, and an IIS workstation. The root CA is a Windows Server 2025 Core VM and is configured manually using the course PowerShell guide. Linux is optional and defaults to off.

Set `vNetSecondOctet` to an integer from 0 through 255. The template creates `10.<value>.0.0/16`, with `10.<value>.1.0/24` for the domain subnet, `10.<value>.2.0/24` for the VPN subnet, and the DC at `10.<value>.1.20`.

The VMs share one NSG. Inbound management and web rules use `0.0.0.0/32` as a closed placeholder, so the public IPs are not reachable until you replace each rule's source prefix with the appropriate instructor or student CIDR after deployment. No Bastion resources are created.

`Deploy.ps1` deploys the registered `Mastering-PKI` template from the selected DevTest Labs artifact source. Publish the updated local ARM template and DSC artifacts to that source before expecting this script to deploy these changes.

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](https://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FPaulDash%2FLab-Environments%2Fmaster%2FEnvironments%2FMastering-PKI%2Fazuredeploy.json)
