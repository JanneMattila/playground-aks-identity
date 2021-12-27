#!/bin/bash

# All the variables for the deployment
subscriptionName="AzureDev"
aadAdminGroupContains="janne''s"

aksName="myaksminidentity"
acrName="myacrminidentity0000010"
workspaceName="myminidentityworkspace"
vnetName="myminidentity-vnet"
subnetAks="AksSubnet"
identityName="myaksminidentity"
resourceGroupName="rg-myaksminidentity"
vnetResourceGroupName="rg-vnet-myaksminidentity"
location="westeurope"

deploymentServicePrincipal="myaks-min-perm-identity"

###################################################
#  ____  _        _  _____ _____ ___  ____  __  __
# |  _ \| |      / \|_   _|  ___/ _ \|  _ \|  \/  |
# | |_) | |     / _ \ | | | |_ | | | | |_) | |\/| |
# |  __/| |___ / ___ \| | |  _|| |_| |  _ <| |  | |
# |_|   |_____/_/   \_\_| |_|   \___/|_| \_\_|  |_|
# team does preparations first
###################################################

# Login and set correct context
az login -o table
az account set --subscription $subscriptionName -o table
subscriptionId=$(az account show -o tsv --query id)
tenantId=$(az account show -o tsv --query tenantId)

# Create custom role definition for "AKS App team"
# - Provided subnet join permissions but no other permissions
# https://docs.microsoft.com/en-us/azure/aks/configure-azure-cni#prerequisites
#
# Note: You need to evaluate if you need more permissions e.g., private endpoint
# related ones if VNet has additional subnets with additional usage requirements.
#
customRoleId="a11594cf-1972-491b-aea6-354e83c04961"
customRoleName="AKS App team"
customRoleScope="/subscriptions/$subscriptionId"
cat <<EOF > custom-aks-team-role.json
{
  "id": "/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions/$customRoleId",
  "name": "$customRoleId",
  "roleName": "$customRoleName",
  "description": "Role for AKS App development teams",
  "roleType": "CustomRole",
  "type": "Microsoft.Authorization/roleDefinitions",
  "assignableScopes": [
    "$customRoleScope"
  ],
  "permissions": [
    {
      "actions": [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/read"
      ],
      "dataActions": [],
      "notActions": [],
      "notDataActions": []
    }
  ]
}
EOF
cat custom-aks-team-role.json

# Deploy custom role to our subscription
customRoleResourceIdentifier=$(az role definition create --role-definition custom-aks-team-role.json --query name -o tsv)
echo $customRoleResourceIdentifier
az role definition list --custom-role-only
# az role definition delete --name $customRoleResourceIdentifier --custom-role-only true

# Prepare extensions and providers
az extension add --upgrade --yes --name aks-preview

# Enable features
az feature register --namespace "Microsoft.ContainerService" --name "EnablePodIdentityPreview"
az feature register --namespace "Microsoft.ContainerService" --name "AKS-ScaleDownModePreview"
az feature register --namespace "Microsoft.ContainerService" --name "PodSubnetPreview"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/EnablePodIdentityPreview')].{Name:name,State:properties.state}"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/AKS-ScaleDownModePreview')].{Name:name,State:properties.state}"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/PodSubnetPreview')].{Name:name,State:properties.state}"
az provider register --namespace Microsoft.ContainerService

# Remove extension in case conflicting previews
# az extension remove --name aks-preview

# Create service principal for App team
clientSecret=$(az ad sp create-for-rbac --skip-assignment -n $deploymentServicePrincipal -o table --query password -o tsv)
clientId=$(az ad sp list --display-name $deploymentServicePrincipal -o table --query [].appId -o tsv)
echo $clientId
objectId=$(az ad sp list --display-name $deploymentServicePrincipal -o table --query [].objectId -o tsv)
echo $objectId

# Create resource group for App team
resourceGroupId=$(az group create -l $location -n $resourceGroupName -o table --query id -o tsv)
echo $resourceGroupId

# Create resource group for our Virtual network
vnetResourceGroupId=$(az group create -l $location -n $vnetResourceGroupName -o table --query id -o tsv)
echo $vnetResourceGroupId

# Assign "Contributor" role to service principal into the resource group
# Why?
# - We want to let app teams to deploy different resources into this resource groups
#   - AKS, ACR, Log Analytics workspace, storage account, DBs etc.
# - We want teams to use automation for creating and deleting their resources
#
az role assignment create \
  --role "Contributor" \
  --assignee $objectId \
  --scope $resourceGroupId

# Assign "User Access Administrator" role to service principal into the resource group
# Why?
# - We want app teams to use Azure RBAC based configurations
#   - To be able to add "AcrPull" role to AKS identity
#   - To be able to use AKS built-in roles for providing cluster access
#     - Azure Kubernetes Service RBAC Cluster Admin
#     - Azure Kubernetes Service RBAC Admin
#     - Azure Kubernetes Service RBAC Reader
#     etc.
# - We want app teams to use Azure Active Directory 
#   pod-managed identities
#    - Access to databases or storage accounts using Azure RBAC
#
az role assignment create \
  --role "User Access Administrator" \
  --assignee $objectId \
  --scope $resourceGroupId

# Provide Azure AD group for app team for easier cluster access management
aadAdmingGroupObjectId=$(az ad group list --display-name $aadAdminGroupContains --query [].objectId -o tsv)
echo $aadAdmingGroupObjectId

# Create VNET for our cluster to use
vnetid=$(az network vnet create -g $vnetResourceGroupName --name $vnetName \
  --address-prefix 10.0.0.0/8 \
  --query newVNet.id -o tsv)
echo $vnetid

subnetaksid=$(az network vnet subnet create -g $vnetResourceGroupName --vnet-name $vnetName \
  --name $subnetAks --address-prefixes 10.2.0.0/20 \
  --query id -o tsv)
echo $subnetaksid

# Create custom control plane identity (identity AKS uses to manage the node resource group)
identityid=$(az identity create --name $identityName --resource-group $resourceGroupName --query id -o tsv)
echo $identityid

identityobjectid=$(az identity list --resource-group $resourceGroupName --query [].clientId -o tsv)
echo $identityobjectid

# Grant "Network Contributor" or custom role to our custom control plane identity
# https://docs.microsoft.com/en-us/azure/aks/configure-azure-cni#prerequisites
# az role assignment create \
#   --role "Network Contributor" \
#   --assignee-object-id $identityobjectid \
#   --assignee-principal-type ServicePrincipal \
#   --scope $subnetaksid
az role assignment create \
  --role "$customRoleResourceIdentifier" \
  --assignee-object-id $identityobjectid \
  --assignee-principal-type ServicePrincipal \
  --scope $subnetaksid

# Grant custom role to our app team
az role assignment create \
  --role "$customRoleResourceIdentifier" \
  --assignee $objectId \
  --scope $vnetResourceGroupId

# Provide following details to App team:
echo $resourceGroupName

echo $clientId
# echo $clientSecret

echo $aadAdmingGroupObjectId
echo $identityid
echo $subnetaksid

###########################################
#     _    ____  ____
#    / \  |  _ \|  _ \
#   / _ \ | |_) | |_) |
#  / ___ \|  __/|  __/
# /_/   \_\_|   |_|
# team starts using their resource group
#
# Note: In this demo we will be using
# service principal created above to test 
# the deployments and automation.
###########################################

az login \
  --service-principal \
  -u $clientId \
  -p $clientSecret \
  --tenant $tenantId

# List resource groups (two should be listed)
az group list -o table

acrid=$(az acr create -l $location -g $resourceGroupName -n $acrName --sku Basic --query id -o tsv)
echo $acrid

workspaceid=$(az monitor log-analytics workspace create -g $resourceGroupName -n $workspaceName --query id -o tsv)
echo $workspaceid

az aks get-versions -l $location -o table

# Note: for public cluster you need to authorize your ip to use api
myip=$(curl --no-progress-meter https://api.ipify.org)
echo $myip

# Note about private clusters:
# https://docs.microsoft.com/en-us/azure/aks/private-clusters

# For private cluster add these:
#  --enable-private-cluster
#  --private-dns-zone None

az aks create -g $resourceGroupName -n $aksName \
 --max-pods 50 --network-plugin azure \
 --node-count 1 --enable-cluster-autoscaler --min-count 1 --max-count 2 \
 --node-osdisk-type "Ephemeral" \
 --node-vm-size "Standard_D8ds_v4" \
 --kubernetes-version 1.21.2 \
 --enable-addons monitoring \
 --enable-aad \
 --enable-azure-rbac \
 --enable-managed-identity \
 --enable-pod-identity \
 --disable-local-accounts \
 --aad-admin-group-object-ids $aadAdmingGroupObjectId \
 --workspace-resource-id $workspaceid \
 --attach-acr $acrid \
 --load-balancer-sku standard \
 --vnet-subnet-id $subnetaksid \
 --assign-identity $identityid \
 --api-server-authorized-ip-ranges $myip \
 -o table

# Additional notes:
# - If above deployment process fails ~90 % or you get error messages like "Could not create a role assignment for subnet. Are you an Owner on this subscription?"
#   then there is very likely something in the permissions
#  - Try running deployment with "--debug" to see more detailed logs
#    and analyze potentially missing permissions
#    - You might see request going to "https://graph.windows.net/" to fetch
#      information about service principal: GET /.../servicePrincipals?$filter=servicePrincipalNames%2Fany...
#      - Above requires "Azure AD Graph API" permissions, because it tries to fetch
#    - You can bypass this problem if you add those role as part of Platform team deployment

# List resource groups after deployment
# (two should be listed, even if there is third resource group in the background: MC_*)
az group list -o table

###################################################################
# Enable current ip
az aks update -g $resourceGroupName -n $aksName --api-server-authorized-ip-ranges $myip

# Clear all authorized ip ranges
az aks update -g $resourceGroupName -n $aksName --api-server-authorized-ip-ranges ""
###################################################################

sudo az aks install-cli

az aks get-credentials -n $aksName -g $resourceGroupName --overwrite-existing

# Create role assignment for our service principal in order to use kubectl
aksid=$(az aks show -g $resourceGroupName -n $aksName --query id -o tsv)
az role assignment create \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --assignee-object-id $objectId \
  --assignee-principal-type ServicePrincipal \
  --scope $aksid

# Download kubelogin from GitHub Releases
download=$(curl -sL https://api.github.com/repos/Azure/kubelogin/releases/latest | jq -r '.assets[].browser_download_url' | grep linux-amd64)
wget $download -O kubelogin.zip
unzip -j kubelogin.zip 

./kubelogin convert-kubeconfig -l azurecli

kubectl get nodes

./kubelogin remove-tokens

# Wipe out the resources
# Note: You must re-login with platform team credentials!
az login -o table
az account set --subscription $subscriptionName -o table
az ad sp delete --id $objectId
az group delete --name $resourceGroupName -y
az role definition delete --name $customRoleResourceIdentifier --custom-role-only true
