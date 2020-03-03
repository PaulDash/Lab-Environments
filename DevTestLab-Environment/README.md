# Mastering PKI lab environment template to be deployed in DevTest Labs

This template deploys a lab environment for the Mastering PKI course. This includes four Windows and (optionally) one Linux VMs. There's a AD DC, a stand-alone root CA, an Enterprise CA, and a workstation. The optional Linux has OpenSSL and nginx.

All subnets connected to a virtual machine are protected by a Network Security Group. You can connect to virtual machines using RDP. Each machine will have a public IP, a DNS name, and the TCP port 3389 will be allowed from the Internet.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-devtestlab%2Fmaster%2FEnvironments%2FSharePoint-AllVersions%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-devtestlab%2Fmaster%2FEnvironments%2FSharePoint-ADFS%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

By default, virtual machines use standard storage and are sized with a good balance between cost and performance:

* Virtual machine running the Domain Controller: [Standard_F4](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-compute#fsv2-series-sup1sup) / Standard_LRS
* Virtual machine running SQL Server: [Standard_D2_v2](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-general#dv2-series) / Standard_LRS
* Virtual machine(s) running SharePoint: [Standard_D11_v2](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-memory#dv2-series-11-15) / Standard_LRS

If you wish to get better performance, I recommended the following sizes / storage account types:

* Virtual machine running the Domain Controller: [Standard_F4](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-compute#fsv2-series-sup1sup) / Standard_LRS
* Virtual machine running SQL Server: [Standard_DS2_v2](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-general#dsv2-series) / Premium_LRS
* Virtual machine(s) running SharePoint: [Standard_DS3_v2](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-general#dsv2-series) / Premium_LRS
