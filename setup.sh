#!/bin/bash

# All the variables for the deployment
subscriptionName="AzureDev"
aadAdminGroupContains="janne''s"

aksName="myaksidentity"
acrName="myacridentity0000010"
workspaceName="myidentityworkspace"
vnetName="myidentity-vnet"
subnetAks="AksSubnet"
identityName="myaksidentity"
resourceGroupName="rg-myaksidentity"
location="westeurope"

# Login and set correct context
az login -o table
az account set --subscription $subscriptionName -o table

subscriptionID=$(az account show -o tsv --query id)
resourcegroupid=$(az group create -l $location -n $resourceGroupName -o table --query id -o tsv)
echo $resourcegroupid

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

acrid=$(az acr create -l $location -g $resourceGroupName -n $acrName --sku Basic --query id -o tsv)
echo $acrid

aadAdmingGroup=$(az ad group list --display-name $aadAdminGroupContains --query [].objectId -o tsv)
echo $aadAdmingGroup

workspaceid=$(az monitor log-analytics workspace create -g $resourceGroupName -n $workspaceName --query id -o tsv)
echo $workspaceid

vnetid=$(az network vnet create -g $resourceGroupName --name $vnetName \
  --address-prefix 10.0.0.0/8 \
  --query newVNet.id -o tsv)
echo $vnetid

subnetaksid=$(az network vnet subnet create -g $resourceGroupName --vnet-name $vnetName \
  --name $subnetAks --address-prefixes 10.2.0.0/20 \
  --query id -o tsv)
echo $subnetaksid

identityid=$(az identity create --name $identityName --resource-group $resourceGroupName --query id -o tsv)
echo $identityid

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
 --aad-admin-group-object-ids $aadAdmingGroup \
 --workspace-resource-id $workspaceid \
 --attach-acr $acrid \
 --load-balancer-sku standard \
 --vnet-subnet-id $subnetaksid \
 --assign-identity $identityid \
 --api-server-authorized-ip-ranges $myip \
 -o table

###################################################################
# Enable current ip
az aks update -g $resourceGroupName -n $aksName --api-server-authorized-ip-ranges $myip

# Clear all authorized ip ranges
az aks update -g $resourceGroupName -n $aksName --api-server-authorized-ip-ranges ""
###################################################################

sudo az aks install-cli

az aks get-credentials -n $aksName -g $resourceGroupName --overwrite-existing

# If using "--enable-azure-rbac" and you need to grant more access rights:
aksid=$(az aks show -g $resourceGroupName -n $aksName --query id -o tsv)
az role assignment create \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --assignee $aadAdmingGroup \
  --scope $aksid

kubectl get nodes

############################################
#  _   _      _                      _
# | \ | | ___| |___      _____  _ __| | __
# |  \| |/ _ \ __\ \ /\ / / _ \| '__| |/ /
# | |\  |  __/ |_ \ V  V / (_) | |  |   <
# |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\
# Tester web app demo
############################################

# Deploy all items from demos namespace
kubectl apply -f demos/namespace.yaml
kubectl apply -f demos/deployment.yaml
kubectl apply -f demos/service.yaml

kubectl get deployment -n demos
kubectl describe deployment -n demos

pod1=$(kubectl get pod -n demos -o name | head -n 1)
echo $pod1

kubectl describe $pod1 -n demos
kubectl get service -n demos

ingressip=$(kubectl get service -n demos -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
echo $ingressip

curl $ingressip
# -> <html><body>Hello there!</body></html>

# If you now test this you won't get "access_token"
BODY=$(echo "HTTP GET ""http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com/"" ""Metadata=true""")
curl -X POST --data "$BODY" -H "Content-Type: text/plain" "http://$ingressip/api/commands"
# -> NotFound Not Found no azure identity found for request clientID 

# Create identity to our "webapp-network-tester-demo"
webappidentityid=$(az identity create --name $aksName-webapp --resource-group $resourceGroupName --query id -o tsv)
webappclientid=$(az identity show --name $aksName-webapp --resource-group $resourceGroupName --query principalId -o tsv)

# Assign AKS Service contributor role
az role assignment create --role "Azure Kubernetes Service Contributor Role" --assignee "$webappclientid" --scope $resourcegroupid

# Assign this identity to namespace
podidentityname="$aksName-webapp-network-tester-demo"
echo $podidentityname
appnamespace="demos"
az aks pod-identity add \
  --resource-group $resourceGroupName \
  --cluster-name $aksName \
  --namespace $appnamespace \
  --name $podidentityname \
  --identity-resource-id $webappidentityid

# Validate
az aks pod-identity exception list --resource-group $resourceGroupName --cluster-name $aksName

# Now we can see if acquiring "access_token" works
BODY=$(echo "HTTP GET ""http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com/"" ""Metadata=true""")
curl -X POST --data "$BODY" -H "Content-Type: text/plain" "http://$ingressip/api/commands"

# Copy paste token to https://jwt.ms/ and verify that "xms_mirid" has "$aksName-webapp" as value.

# ##########################################################
#     _         _                        _   _
#    / \  _   _| |_ ___  _ __ ___   __ _| |_(_) ___  _ __
#   / _ \| | | | __/ _ \| '_ ` _ \ / _` | __| |/ _ \| '_ \
#  / ___ \ |_| | || (_) | | | | | | (_| | |_| | (_) | | | |
# /_/   \_\__,_|\__\___/|_| |_| |_|\__,_|\__|_|\___/|_| |_|
# Azure CLI automation demo
# ##########################################################

# Create identity to our "az-automation"
automationidentityid=$(az identity create --name $aksName-az-automation --resource-group $resourceGroupName --query id -o tsv)
automationclientid=$(az identity show --name $aksName-az-automation --resource-group $resourceGroupName --query principalId -o tsv)

# Assign "Reader" role for the resource group of our deployment
az role assignment create --role "Reader" --assignee "$automationclientid" --scope $resourcegroupid

# Assign this identity to namespace
automationidentityname="$aksName-automation"
automationnamespace="az-automation"
az aks pod-identity add \
  --resource-group $resourceGroupName \
  --cluster-name $aksName \
  --namespace $automationnamespace \
  --name $automationidentityname \
  --identity-resource-id $automationidentityid

# Validate
az aks pod-identity exception list --resource-group $resourceGroupName --cluster-name $aksName

kubectl create namespace az-automation

az acr build --registry $acrName --image az-cli-automation-demo:v1 src/.

cat <<EOF > az-automation.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: az-automation
  namespace: az-automation
spec:
  replicas: 1
  selector:
    matchLabels:
      app: az-automation
  template:
    metadata:
      labels:
        app: az-automation
        # This needs to match your deployment
        aadpodidbinding: $automationidentityname
    spec:
      containers:
      - image: $acrName.azurecr.io/az-cli-automation-demo:v1
        name: az-automation
EOF
cat az-automation.yaml

kubectl apply -f az-automation.yaml

kubectl get deployment -n az-automation
kubectl describe deployment -n az-automation

automationpod1=$(kubectl get pod -n az-automation -o name | head -n 1)
echo $automationpod1
kubectl logs $automationpod1 -n az-automation
kubectl exec --stdin --tty $automationpod1 -n az-automation -- /bin/sh

# You can test this even yourself
az login --identity -o table
az group list -o table

# Exit container
exit

#####################################
#  ____                  _
# / ___|  ___ _ ____   _(_) ___ ___
# \___ \ / _ \ '__\ \ / / |/ __/ _ \
#  ___) |  __/ |   \ V /| | (_|  __/
# |____/ \___|_|    \_/ |_|\___\___|
# account demos
#####################################
kubectl create namespace demo-identity
kubectl get serviceaccount -n demo-identity
kubectl describe serviceaccount -n demo-identity

secret1=$(kubectl get secrets -n demo-identity -o name | head -n 1)
echo $secret1
token1=$(kubectl get $secret1 -n demo-identity -o jsonpath="{.data.token}" | base64 --decode)
echo $token1

kubectl get namespace --token $token1
# Error from server (Forbidden): namespaces is forbidden: 
# User "system:serviceaccount:demo-identity:default" 
# cannot list resource "namespaces" in API group "" at the cluster scope
# OR if you have "--enable-azure-rbac"
# Error from server (Forbidden): namespaces is forbidden: 
# User "system:serviceaccount:demo-identity:default" 
# cannot list resource "namespaces" in API group "" at the cluster scope: 
# Azure does not have opinion for this user.

kubectl create clusterrolebinding default-view \
  --clusterrole=view \
  --serviceaccount=demo-identity:default

kubectl get clusterrolebinding default-view -o yaml

# Now service account can see namespaces
kubectl get namespace --token $token1

# "Can I" examples https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access
kubectl auth can-i --help
kubectl auth can-i get pods -n kube-system --token $token1

# But you still can't create namespaces, since you have only "view" rights
kubectl create namespace demo-identity2 --token $token1
# Error from server (Forbidden): namespaces is forbidden: 
# User "system:serviceaccount:demo-identity:default" 
# cannot create resource "namespaces" in API group "" 
# at the cluster scope: Azure does not have opinion for this user.

# Wipe out the resources
az group delete --name $resourceGroupName -y
