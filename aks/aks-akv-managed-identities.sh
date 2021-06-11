# Shell script demonstrating how to integrate Azure Kubernetes Service with Azure Key Vault using Managed Identities (Not AAD Pod Identity)

SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
RESOURCE_GROUP=aks-akv
CLUSTER_NAME=myakscluster
VAULT_NAME=mykeyvault
LOCATION=eastus
NODE_RESOURCE_GROUP=MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION}

az group create -g $RESOURCE_GROUP -l $LOCATION

# Deploy AKS cluster with Managed Identity
az aks create -n $CLUSTER_NAME -g $RESOURCE_GROUP \
    --node-count 2 \
    --network-plugin azure \
    --generate-ssh-keys \
    --enable-managed-identity \
    --location $LOCATION

IDENTITY=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query identityProfile.kubeletidentity.clientId -o tsv)

az aks get-credentials --admin --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --overwrite-existing

az keyvault create --name $VAULT_NAME --resource-group $RESOURCE_GROUP -l $LOCATION
az keyvault secret set --vault-name $VAULT_NAME --name "MySecret" --value "A secret in Azure Key Vault"

helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts 
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name

az role assignment create --role "Managed Identity Operator" --assignee $IDENTITY --scope /subscriptions/$SUB_ID/resourcegroups/$NODE_RESOURCE_GROUP
az role assignment create --role "Virtual Machine Contributor" --assignee $IDENTITY --scope /subscriptions/$SUB_ID/resourcegroups/$NODE_RESOURCE_GROUP

az keyvault set-policy -g $RESOURCE_GROUP -n $VAULT_NAME --secret-permissions get --spn $IDENTITY
az keyvault set-policy -g $RESOURCE_GROUP -n $VAULT_NAME --key-permissions get --spn $IDENTITY
az keyvault set-policy -g $RESOURCE_GROUP -n $VAULT_NAME --certificate-permissions get --spn $IDENTITY

if [ -f "SecretProviderClass.yaml" ] ; then
  rm SecretProviderClass.yaml
fi
cat << EOF >> SecretProviderClass.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-kvname
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "$IDENTITY"
    keyvaultName: "$VAULT_NAME"
    cloudName: "AzurePublicCloud"
    objects:  |
      array:
        - |
          objectName: MySecret
          objectType: secret
          objectVersion: ""
    tenantId: "$TENANT_ID"
EOF

if [ -f "podBindingDeployment.yaml" ] ; then
  rm podBindingDeployment.yaml
fi
cat << EOF >> podBindingDeployment.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-secrets-store-inline
  labels:
    aadpodidbinding: azure-pod-identity-binding-selector
spec:
  containers:
    - name: nginx
      image: nginx
      volumeMounts:
        - name: secrets-store-inline
          mountPath: "/mnt/secrets-store"
          readOnly: true
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: azure-kvname
EOF

kubectl apply -f SecretProviderClass.yaml
kubectl apply -f podBindingDeployment.yaml

kubectl describe pods nginx-secrets-store-inline
