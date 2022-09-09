# Playground AKS Identity

This repository contains identity related examples.

## Azure AD related examples

1. Simple application that shows how you can acquire token inside your pod
2. Azure CLI based automation that uses managed identity for connecting to Azure

## Usage

1. Clone this repository to your own machine
2. Open Workspace
  - Use WSL in Windows
  - Requires Bash
3. Open [setup.sh](setup.sh) to walk through steps to deploy this demo environment
  - Execute different script steps one-by-one (hint: use [shift-enter](https://github.com/JanneMattila/some-questions-and-some-answers/blob/master/q%26a/vs_code.md#automation-tip-shift-enter))

## Identity scenarios

### Cluster management accesses

#### Enable Azure AD integration

```bash
# Find correct Azure AD Group
id=$(az ad group list --display-name "Cluster Admins" --query [].id -o tsv)

# Enable Azure AD integration
az aks create \
  # ...
  --enable-aad \
  --aad-admin-group-object-ids $id
```

Above enables you to connect to the cluster using Azure AD credentials.

More information about [Azure AD integration](https://docs.microsoft.com/en-us/azure/aks/concepts-identity#azure-ad-integration).

Normally, you would use following command to get `clusterUser` access to the cluster:

```bash
az aks get-credentials \
  -n $aks_name \
  -g $resource_group_name
```

Above requires `Azure Kubernetes Service Cluster User Role` role assignment to your AKS resource.

You can use [kubelogin](https://github.com/Azure/kubelogin) and use
Azure CLI access token to log in:

```bash
az aks get-credentials \
  -n $aks_name \
  -g $resource_group_name \
  --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
```

--- 

Alternative, you can also get `clusterAdmin` access to the cluster, although not recommended.

**Two important notes** about `clusterAdmin` access ([link](https://docs.microsoft.com/en-us/azure/aks/managed-aad#troubleshooting-access-issues-with-azure-ad) and [link](https://docs.microsoft.com/en-us/azure/aks/concepts-identity#summary)):

> If you're permanently blocked by not having access to a valid Azure AD group
> with access to your cluster, you can still obtain the **admin credentials** to access
> the cluster directly. **Use them only in an emergency**.

and

> Uses legacy (non-Azure AD) cluster admin certificate into users kubeconfig

To get `clusterAdmin` access use following command:

```bash
az aks get-credentials \
  -n $aks_name \
  -g $resource_group_name \
  --admin
```

Above requires `Azure Kubernetes Service Cluster Admin Role` role assignment to your AKS resource.

More information about [cluster role permissions](https://docs.microsoft.com/en-us/azure/aks/control-kubeconfig-access#available-cluster-roles-permissions).

#### Azure RBAC

For enabling Azure Role-Based Access Control (RBAC) based
authorization for you cluster resources, you can use following command:

```bash
# Enable Azure RBAC
az aks create \
  # ...
  --enable-aad \
  --enable-azure-rbac
```

Following built-in roles are available:

- `Azure Kubernetes Service RBAC Reader`: Allows read-only access to see most objects in a namespace. It does not allow viewing roles or role bindings. This role does not allow viewing Secrets.
- `Azure Kubernetes Service RBAC Writer`: Allows read/write access to most objects in a namespace.This role does not allow viewing or modifying roles or role bindings
- `Azure Kubernetes Service RBAC Admin`: Let's you manage all resources under cluster/namespace, except update or delete resource quotas and namespaces
- `Azure Kubernetes Service RBAC Cluster Admin`: Let's you manage all resources in the cluster

You can scope above roles to either to the entire cluster or to specific namespaces.

Here is example to grant `writer` role to `team1-ns` namespace:

```bash
az role assignment create \
  --role "Azure Kubernetes Service RBAC Writer" \ 
  --assignee $exampleUser \
  --scope $aks_id/namespaces/team1-ns
```` 

More information about [Azure RBAC](https://docs.microsoft.com/en-us/azure/aks/concepts-identity#azure-rbac-for-kubernetes-authorization)
and [built-in roles](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#azure-kubernetes-service-cluster-admin-role).

### Azure AD based authentication for user applications

You can protect your applications using Azure AD authentication as well.

Here is one example: [Cluster with Azure AD Auth](https://github.com/JanneMattila/k8s-cluster#cluster-with-azure-ad-auth)

### Workload Identity

If you need our container to access external resources
e.g., Azure SQL database using Azure AD managed identities,
then you can use [Azure AD Workload Identity](https://github.com/Azure/azure-workload-identity) for that.

See [OIDC Issuer & Azure AD Workload Identity](./setup.sh)
for more detailed example about that. For older POD Identity
based example see [Azure CLI Automation demo](./setup.sh).

## Other scenarios

### Deployment related permissions example

Example how you can test minimal required permissions, if
you have separate Platform team and App team and you want to
customize your deployment process.

See [deployment permissions](./deployment-permissions) for more details.

## Links

- [Azure AD integration](https://docs.microsoft.com/en-us/azure/aks/concepts-identity#azure-ad-integration)
  - [Available cluster roles permissions](https://docs.microsoft.com/en-us/azure/aks/control-kubeconfig-access#available-cluster-roles-permissions)
- [Azure RBAC for Kubernetes Authorization](https://docs.microsoft.com/en-us/azure/aks/concepts-identity#azure-rbac-for-kubernetes-authorization)
  - [Use Azure RBAC for Kubernetes Authorization](https://docs.microsoft.com/en-us/azure/aks/manage-azure-rbac)
- [Kubernetes RBAC](https://docs.microsoft.com/en-us/azure/aks/concepts-identity#kubernetes-rbac)
  - [Use Kubernetes RBAC with Azure AD integration](https://docs.microsoft.com/en-us/azure/aks/azure-ad-rbac)
- [Azure AD Workload Identity](https://github.com/Azure/azure-workload-identity)
