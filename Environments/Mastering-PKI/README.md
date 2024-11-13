# Mastering PKI lab environment template to be deployed in DevTest Labs

This template deploys a lab environment for the Mastering PKI course. This includes four Windows VMs and (optionally) one Linux VM. There's a AD DC, a stand-alone root CA, an Enterprise CA, and a workstation. The optional Linux has OpenSSL and nginx.

All subnets connected to a virtual machine are protected by a Network Security Group. You can connect to virtual machines using RDP. Each machine will have a public IP, a DNS name, and the TCP port 3389 will be allowed from the Internet.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FPaulDashe%2FLab-Environments%2Fmaster%2FEnvironments%2FMastering-PKI%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FPaulDashe%2FLab-Environments%2Fmaster%2FMastering-PKI%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>
