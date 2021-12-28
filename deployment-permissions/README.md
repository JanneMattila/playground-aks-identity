# Deployment permissions example

[Access and identity options for Azure Kubernetes Service (AKS)](https://docs.microsoft.com/en-us/azure/aks/concepts-identity)

[Identity and access management considerations for AKS](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/aks/eslz-identity-and-access-management)

[Best practices for authentication and authorization in Azure Kubernetes Service (AKS)](https://docs.microsoft.com/en-us/azure/aks/operator-best-practices-identity)

[Baseline architecture for an Azure Kubernetes Service (AKS) cluster](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks/secure-baseline-aks)

Here is example how you can try AKS deployments with minimal permissions.
You can use these steps to test if your permissions are enough or if
you would like to further customize configuration and permissions based
on your environment. Target is to deploy working AKS and ACR combination
but avoiding too broad permissions for application teams.

See [deployment-permissions.sh](deployment-permissions.sh) for actual steps to achieve below scenario.

## Platform team

- Create resource group for virtual network
  - Create virtual network with correct IP address ranges and configuration to be used by App team
  - Create subnet for AKS
- Create resource group for App team
- Create managed identity to be use by the AKS control plane into App teams resource group
  - Add [Network Contributor](https://docs.microsoft.com/en-us/azure/aks/configure-azure-cni#prerequisites) role to the managed identity to the target AKS subnet
- Create service principal and grant required permissions for above resource group for deployment
  - Optionally provide similar access to App team users

### Roles summary

AKS control plane identity:

- `Network Contributor` to subnet
  - Azure CLI uses this to verify that AKS has correct permissions to manage subnet

App team's service principal:

- Custom role to either subnet, vnet or resource group of vnet
  - `Microsoft.Network/virtualNetworks/subnets/join/action` to be able to join AKS to subnet
  - `Microsoft.Network/virtualNetworks/subnets/read` to be able to read subnet configuration
  - `Microsoft.Authorization/*/read` to be able to verify that AKS control plane identity has `Network Contributor` role
- `Contributor` to their own resource group
  - To be able to do deployments of different Azure resources
- `User Access Administrator` to their own resource group
  - To be able to use Azure RBAC with AKS
  - To be able to manage ACR permissions

Note: You could combine `Contributor` and `User Access Administrator` to custom role.

## App team

- Connect to Azure either using your above created service principal or using your own user account
- Deploy AKS and ACR using Azure CLI
  - Use managed identity created by Platform team for custom control plane identity
  - Note: after actual cluster deployment there are [two resource groups]](https://docs.microsoft.com/en-us/azure/aks/faq#why-are-two-resource-groups-created-with-aks)
- Deploy simple container to ACR
- Deploy workload to AKS using image from ACR

## Misc

Multiple dimensions in above deployment scenario, that impact your overall design:

- Use of Azure RBAC for Kubernetes Authorization
- Use of Azure Active Directory pod-managed identities
- Pre-deployment of different Azure resources by platform team
  - VNETs, route tables, managed identities etc.
- Use of custom role definitions
