# Enable auto export
set -a

# All the variables for the deployment
subscriptionName="AzureDev"
aadAdminGroupContains="janne''s"

aksName="myaksidentity"
acrName="myacridentity0000010"
keyvaultName="myacridentity0000010"
workspaceName="myidentityworkspace"
vnetName="myidentity-vnet"
subnetAks="AksSubnet"
clusterIdentityName="myaksclusteridentity"
kubeletIdentityName="myakskubeletidentity"
resourceGroupName="rg-myaksidentity"
location="westeurope"

# Login and set correct context
az login -o table
az account set --subscription $subscriptionName -o table

# Prepare extensions and providers
az extension add --upgrade --yes --name aks-preview

# Enable features
az feature register --namespace "Microsoft.ContainerService" --name "EnableOIDCIssuerPreview"
az feature register --namespace "Microsoft.ContainerService" --name "EnablePodIdentityPreview"
az feature register --namespace "Microsoft.ContainerService" --name "AKS-ScaleDownModePreview"
az feature register --namespace "Microsoft.ContainerService" --name "PodSubnetPreview"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/EnableOIDCIssuerPreview')].{Name:name,State:properties.state}"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/EnablePodIdentityPreview')].{Name:name,State:properties.state}"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/AKS-ScaleDownModePreview')].{Name:name,State:properties.state}"
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/PodSubnetPreview')].{Name:name,State:properties.state}"
az provider register --namespace Microsoft.ContainerService

# Remove extension in case conflicting previews
# az extension remove --name aks-preview

resourcegroupid=$(az group create -l $location -n $resourceGroupName -o table --query id -o tsv)
echo $resourcegroupid

acrid=$(az acr create -l $location -g $resourceGroupName -n $acrName --sku Basic --query id -o tsv)
echo $acrid

aadAdmingGroup=$(az ad group list --display-name $aadAdminGroupContains --query [].id -o tsv)
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

# Create cluster identity
# https://docs.microsoft.com/en-us/azure/aks/use-managed-identity#summary-of-managed-identities
clusterIdentityJson=$(az identity create --name $clusterIdentityName --resource-group $resourceGroupName -o json)
clusterIdentityid=$(echo $clusterIdentityJson | jq -r .id)
clusterIdentityclientid=$(echo $clusterIdentityJson | jq -r .clientId)
clusterIdentityobjectid=$(echo $clusterIdentityJson | jq -r .principalId)
echo $clusterIdentityid
echo $clusterIdentityclientid
echo $clusterIdentityobjectid

# Create kubelet identity
kubeletIdentityJson=$(az identity create --name $kubeletIdentityName --resource-group $resourceGroupName -o json)
kubeletIdentityid=$(echo $kubeletIdentityJson | jq -r .id)
kubeletIdentityclientid=$(echo $kubeletIdentityJson | jq -r .clientId)
kubeletIdentityobjectid=$(echo $kubeletIdentityJson | jq -r .principalId)
echo $kubeletIdentityid
echo $kubeletIdentityclientid
echo $kubeletIdentityobjectid

az aks get-versions -l $location -o table

# Note: for public cluster you need to authorize your ip to use api
myip=$(curl -s https://api.ipify.org)
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
 --kubernetes-version 1.23.8 \
 --enable-addons monitoring,azure-keyvault-secrets-provider \
 --enable-aad \
 --enable-azure-rbac \
 --enable-pod-identity \
 --disable-local-accounts \
 --enable-oidc-issuer \
 --aad-admin-group-object-ids $aadAdmingGroup \
 --workspace-resource-id $workspaceid \
 --attach-acr $acrid \
 --load-balancer-sku standard \
 --vnet-subnet-id $subnetaksid \
 --assign-identity $clusterIdentityid \
 --assign-kubelet-identity $kubeletIdentityid \
 --enable-secret-rotation \
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
kubelogin convert-kubeconfig -l azurecli

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
#region Base setup demo

# Deploy all items from demos namespace
kubectl apply -f demos/

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
#endregion

###############################
#  ____   ____     _     ____
# |  _ \ | __ )   / \   / ___|
# | |_) ||  _ \  / _ \ | |
# |  _ < | |_) |/ ___ \| |___
# |_| \_\|____//_/   \_\\____|
# Azure RBAC for Kubernetes
###############################
#region Azure RBAC for Kubernetes

# Create namespace for out "team1"
kubectl create ns team1-ns

exampleUser="aksuser@contoso.com"

aksid=$(az aks show -g $resourceGroupName -n $aksName --query id -o tsv)

# Grant access to fetch kubeconfig for cluserUser role
# https://docs.microsoft.com/en-us/azure/aks/control-kubeconfig-access#available-cluster-roles-permissions
az role assignment create \
  --role "Azure Kubernetes Service Cluster User Role" \
  --assignee $exampleUser \
  --scope $aksid

# Grant write access to that namespace
az role assignment create \
  --role "Azure Kubernetes Service RBAC Writer" \
  --assignee $exampleUser \
  --scope "$aksid/namespaces/team1-ns"

# Login as $exampleUser
az login -o table
az account set --subscription $subscriptionName -o table

az aks get-credentials -n $aksName -g $resourceGroupName --overwrite-existing

# List kubeconfig
cat ~/.kube/config

kubectl get ns
# -> Error from server (Forbidden): namespaces is forbidden

kubectl get ns team1-ns
# NAME       STATUS   AGE
# team1-ns   Active   6m7s

kubectl create deployment app-deployment --image "jannemattila/webapp-network-tester" --replicas 1 -n team1-ns
kubectl get all -n team1-ns

kubectl create ns team1-another-ns
# -> Error

kubectl auth can-i get pods -n kube-system
# no - User does not have access to the resource in Azure. Update role assignment to allow access.

kubectl auth can-i get pods -n team1-ns
# yes

#endregion

# ##########################################################
#     _         _                        _   _
#    / \  _   _| |_ ___  _ __ ___   __ _| |_(_) ___  _ __
#   / _ \| | | | __/ _ \| '_ ` _ \ / _` | __| |/ _ \| '_ \
#  / ___ \ |_| | || (_) | | | | | | (_| | |_| | (_) | | | |
# /_/   \_\__,_|\__\___/|_| |_| |_|\__,_|\__|_|\___/|_| |_|
# Azure CLI automation demo
# ##########################################################
#region Azure CLI Automation demo

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

#endregion

#############################
#   ___  ___  ____    ____
#  / _ \|_ _||  _ \  / ___|
# | | | || | | | | || |
# | |_| || | | |_| || |___
#  \___/|___||____/  \____|
# Issuer & Azure AD Workload
#          Identity
#############################
#region OIDC Issuer & Azure AD Workload Identity
issuerUrl=$(az aks show -n $aksName -g $resourceGroupName --query "oidcIssuerProfile.issuerUrl" -o tsv)
echo $issuerUrl

tenantId=$(az account show -s $subscriptionName --query tenantId -o tsv)
echo $tenantId

# Install Azure AD Workload Identity Mutating Admission Webhook
helm repo add azure-workload-identity https://azure.github.io/azure-workload-identity/charts
helm repo update
helm install workload-identity-webhook azure-workload-identity/workload-identity-webhook \
   --namespace azure-workload-identity-system \
   --create-namespace \
   --set azureTenantID="${tenantId}"

# Download azwi from GitHub Releases
download=$(curl -sL https://api.github.com/repos/Azure/azure-workload-identity/releases/latest | jq -r '.assets[].browser_download_url' | grep linux-amd64)
wget $download -O azwi.zip
tar -xf azwi.zip --exclude=*.md --exclude=LICENSE
./azwi --help
./azwi version

# AAD application
azwiAppName="$aksName-wi-demo"
echo $azwiAppName

azwiServiceAccount="azwi-sa"
azwiNamespace="azwi-demo"

# Create an AAD application and grant permissions to access the secret
./azwi serviceaccount create phase app --aad-application-name "$azwiAppName"

# Create a Kubernetes service account
kubectl create ns $azwiNamespace
./azwi serviceaccount create phase sa \
  --aad-application-name "$azwiAppName" \
  --service-account-namespace "$azwiNamespace" \
  --service-account-name "$azwiServiceAccount"

# Check namespace content
kubectl get serviceaccount -n $azwiNamespace

# Establish federated identity credential between the AAD application and the service account issuer & subject
./azwi serviceaccount create phase federated-identity \
  --aad-application-name "$azwiAppName" \
  --service-account-namespace "$azwiNamespace" \
  --service-account-name "$azwiServiceAccount" \
  --service-account-issuer-url "$issuerUrl"

# Deploy workload
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: az-cli
  namespace: ${azwiNamespace}
spec:
  serviceAccountName: ${azwiServiceAccount}
  containers:
    - image: mcr.microsoft.com/azure-cli:2.35.0
      name: oidc
      command: ["/bin/sh"]
      args: ["-c", "while true; do echo Waiting; sleep 10;done"]
  nodeSelector:
    kubernetes.io/os: linux
EOF

kubectl get pod -n $azwiNamespace
kubectl describe pod -n $azwiNamespace
# Note environment variables and mounts

azwipod=$(kubectl get pod -n $azwiNamespace -o name | head -n 1)
echo $azwipod
kubectl logs $azwipod -n $azwiNamespace
kubectl exec --stdin --tty $azwipod -n $azwiNamespace -- /bin/bash

echo $AZURE_CLIENT_ID
echo $AZURE_TENANT_ID
echo $AZURE_FEDERATED_TOKEN_FILE
echo $AZURE_AUTHORITY_HOST
cat $AZURE_FEDERATED_TOKEN_FILE
# Output:
# -------
# {
#   "aud": [
#     "api://AzureADTokenExchange"
#   ],
#   "exp": 1651580447,
#   "iat": 1651576847,
#   "iss": "https://oidc.prod-aks.azure.com/291168e9-1ded-42d8-8608-c9ff8fe7c21b/",
#   "kubernetes.io": {
#     "namespace": "azwi-demo",
#     "pod": {
#       "name": "az-cli",
#       "uid": "1708aba8-6ffc-47cc-97aa-1b38bdadf8b7"
#     },
#     "serviceaccount": {
#       "name": "azwi-sa",
#       "uid": "f6d4c1a6-b507-49c1-9e68-8dae67047cd7"
#     }
#   },
#   "nbf": 1651576847,
#   "sub": "system:serviceaccount:azwi-demo:azwi-sa"
# }

ls /var/run/secrets/kubernetes.io/serviceaccount
cat /var/run/secrets/kubernetes.io/serviceaccount/token

# Login using federated token
az login --allow-no-subscriptions --service-principal -u $AZURE_CLIENT_ID -t $AZURE_TENANT_ID --federated-token $(cat $AZURE_FEDERATED_TOKEN_FILE) 

# Continue automations based on granted access rights etc.
graphAccessToken=$(az account get-access-token --resource https://graph.microsoft.com/ -o tsv --query accessToken)
echo $graphAccessToken
curl -s -H "Authorization: Bearer $graphAccessToken" "https://graph.microsoft.com/v1.0"
curl -s -H "Authorization: Bearer $graphAccessToken" "https://graph.microsoft.com/v1.0/users"

# Exit az-cli container
exit

# Delete az wi demo
kubectl delete pod az-cli -n "$azwiNamespace"
kubectl delete sa "$azwiServiceAccount" --namespace "$azwiNamespace"

azwiClientId="$(az ad sp list --display-name "$azwiAppName" --query '[0].appId' -otsv)"
echo $azwiClientId

# Remove Azure AD app
az ad sp delete --id "$azwiClientId"
#endregion

#####################################
#  ____                  _
# / ___|  ___ _ ____   _(_) ___ ___
# \___ \ / _ \ '__\ \ / / |/ __/ _ \
#  ___) |  __/ |   \ V /| | (_|  __/
# |____/ \___|_|    \_/ |_|\___\___|
# account demos
#####################################
#region Service account demos
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

#endregion

#############################################
#  _  __           __     __          _ _
# | |/ /___ _   _  \ \   / /_ _ _   _| | |_
# | ' // _ \ | | |  \ \ / / _` | | | | | __|
# | . \  __/ |_| |   \ V / (_| | |_| | | |_
# |_|\_\___|\__, |    \_/ \__,_|\__,_|_|\__|
#           |___/
# and secret demos
#############################################
#region Key Vault demos

# Verify the Azure Key Vault Provider for Secrets Store CSI Driver installation
kubectl get pods -n kube-system -l "app in (secrets-store-csi-driver, secrets-store-provider-azure)"
# NAME                                     READY   STATUS    RESTARTS      AGE
# aks-secrets-store-csi-driver-nj7sm       3/3     Running   2 (11m ago)   11m
# aks-secrets-store-provider-azure-9jtpl   1/1     Running   0             11m

# You can configure polling frequency
az aks update -g $resourceGroupName -n $aksName --enable-secret-rotation --rotation-poll-interval 5m

# Either configure Pod identity or disable it for this app or disable it completely
# az aks update -g $resourceGroupName -n $aksName --disable-pod-identity

# Create Key vault
keyvaultjson=$(az keyvault create \
  --name $keyvaultName \
  --resource-group $resourceGroupName \
  --enable-rbac-authorization true \
  --location $location -o json)
keyvaultid=$(echo $keyvaultjson | jq -r .id)
keyvault=$(echo $keyvaultjson | jq -r .properties.vaultUri)
echo $keyvaultid
echo $keyvault

# Get current account context
accountJson=$(az account show -o json)
tenantID=$(echo $accountJson | jq -r .tenantId)

# Grant permissions for current user to be able manage
# all Key Vault content
me=$(echo $accountJson | jq -r .user.name)
echo $me
az role assignment create \
  --role "Key Vault Administrator" \
  --assignee $me \
  --scope $keyvaultid

# Grant "Key Vault Administrator" for our kubelet managed identity
# https://docs.microsoft.com/en-us/azure/key-vault/general/rbac-guide
az role assignment create \
  --role "Key Vault Administrator" \
  --assignee-object-id $kubeletIdentityobjectid \
  --assignee-principal-type ServicePrincipal \
  --scope $keyvaultid

# Store application configuration values to the Key Vault
secretvar1=$(openssl rand -base64 32)
secretvar2=$(openssl rand -base64 32)
echo $secretvar1
echo $secretvar2

az keyvault secret set --name "secretvar1" --value $secretvar1 --vault-name $keyvaultName
az keyvault secret set --name "secretvar2" --value $secretvar2 --vault-name $keyvaultName

az keyvault secret set --name "secretvar3" --file /usr/bin/uptime --encoding base64 --vault-name $keyvaultName
sha256sum /usr/bin/uptime

# Deploy secrets demo app
kubectl apply -f secrets/00_namespace.yaml
kubectl apply -f secrets/01_aadpodexception.yaml
kubectl apply -f secrets/02_service.yaml
cat secrets/03_secretprovider-volume.yaml | envsubst | kubectl apply -f -
cat secrets/04_secretprovider-secret.yaml | envsubst | kubectl apply -f -
kubectl apply -f secrets/05_deployment.yaml

kubectl get deployment -n secrets
kubectl describe deployment -n secrets
kubectl get pods -n secrets
kubectl describe pods -n secrets
# Example output:
# ...
# Events:
#   Type    Reason                  Age                  From                        Message
#   ----    ------                  ----                 ----                        -------
#   Normal  Scheduled               7m56s                default-scheduler           Successfully assigned secrets/webapp-secrets-demo-64555569-r5fwk to aks-nodepool1-28886745-vmss000000
#   Normal  Pulled                  7m55s                kubelet                     Container image "jannemattila/webapp-update:1.0.9" already present on machine
#   Normal  Created                 7m55s                kubelet                     Created container webapp-secrets-demo
#   Normal  Started                 7m55s                kubelet                     Started container webapp-secrets-demo
#   Normal  SecretRotationComplete  75s (x2 over 6m15s)  csi-secrets-store-rotation  successfully rotated K8s secret keyvault
#   Normal  MountRotationComplete   75s                  csi-secrets-store-rotation  successfully rotated mounted contents for spc secrets/secretprovider-keyvault-webapp-secrets-demo

kubectl get svc -n secrets
kubectl get secrets -n secrets
kubectl describe secrets -n secrets

# Get value of the secret
kubectl get secrets keyvault -n secrets --template={{.data.secretvar2}} | base64 -d

kubectl get SecretProviderClass -n secrets -o wide
kubectl describe SecretProviderClass -n secrets

secretsip=$(kubectl get service -n secrets -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
echo $secretsip

# Get information about currently running application
curl $secretsip/api/update

# Connect to pod and check the file system content
secretspod=$(kubectl get pod -n secrets -o name | head -n 1)
echo $secretspod
kubectl exec --stdin --tty $secretspod -n secrets -- /bin/sh

ls /mnt/secretsvolume
ls /mnt/secretsenv

cat /mnt/secretsvolume/secretvar1
cat /mnt/secretsvolume/secretvar3
cat /mnt/secretsenv/secretvar2

# Convert base64 to file
cat /mnt/secretsvolume/secretvar3 | base64 -d > uptime
sha256sum /app/uptime

env
echo $SECRET_VAR2

# Note related limitations for environment vars!
# https://secrets-store-csi-driver.sigs.k8s.io/known-limitations.html
# https://secrets-store-csi-driver.sigs.k8s.io/topics/secret-auto-rotation.html
# -> https://github.com/stakater/Reloader

# Exit container
exit

# Rotate key and observe changes in ~5 minutes timeframe
az keyvault secret set --name "secretvar2" --value "Updated value!" --vault-name $keyvaultName

#endregion

#############################################################################
#  ____                  _          ____       _            _             _ 
# / ___|  ___ _ ____   _(_) ___ ___|  _ \ _ __(_)_ __   ___(_)_ __   __ _| |
# \___ \ / _ \ '__\ \ / / |/ __/ _ \ |_) | '__| | '_ \ / __| | '_ \ / _` | |
#  ___) |  __/ |   \ V /| | (_|  __/  __/| |  | | | | | (__| | |_) | (_| | |
# |____/ \___|_|    \_/ |_|\___\___|_|   |_|  |_|_| |_|\___|_| .__/ \__,_|_|
# demo                                                       |_|            
#############################################################################
#region ServicePrincipal demos

servicePrincipal="myaks-demo-spn-deployment"

# Create service principal
spnClientSecret=$(az ad sp create-for-rbac -n $servicePrincipal --query password -o tsv)
spnJson=$(az ad sp list --display-name $servicePrincipal --query [] -o json)
spnClientId=$(echo $spnJson | jq -r .[].appId)
spnObjectId=$(echo $spnJson | jq -r .[].id)
echo $spnClientId
echo $spnObjectId
echo $spnClientSecret

aksid=$(az aks show -g $resourceGroupName -n $aksName --query id -o tsv)

# Grant access to fetch kubeconfig for cluserUser role
# https://docs.microsoft.com/en-us/azure/aks/control-kubeconfig-access#available-cluster-roles-permissions
az role assignment create \
  --role "Azure Kubernetes Service Cluster User Role" \
  --assignee $spnObjectId \
  --scope $aksid

# Grant write access to AKS
# https://docs.microsoft.com/en-us/azure/aks/manage-azure-rbac#create-role-assignments-for-users-to-access-cluster
az role assignment create \
  --role "Azure Kubernetes Service RBAC Writer" \
  --assignee $spnObjectId \
  --scope "$aksid"
# Remember you can limit it to namespace e.g., "$aksid/namespaces/team1-ns"

tenantId=$(az account show -s $subscriptionName --query tenantId -o tsv)
echo $tenantId

az login \
  --service-principal \
  -u $spnClientId \
  -p $spnClientSecret \
  --tenant $tenantId

kubelogin convert-kubeconfig -l azurecli

kubectl get nodes
kubectl create ns spn-ns
kubectl auth can-i get pods -n kube-system

kubelogin remove-tokens
az logout

az login -o table
az ad sp delete --id $spnClientId

#endregion

# Wipe out the resources
az group delete --name $resourceGroupName -y
az keyvault purge --name $keyvaultName # Otherwise it will be in "Deleted vaults" but name is reserved
