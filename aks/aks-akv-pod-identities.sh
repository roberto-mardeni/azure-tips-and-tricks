#!/bin/bash
# Shell script demonstrating how to integrate Azure Kubernetes Service with Azure Key Vault using Pod Identities
# https://docs.microsoft.com/en-us/azure/aks/use-azure-ad-pod-identity

# While still in preview, need to register if not already so and update aks-preview extension
r=$(az feature show --name EnablePodIdentityPreview --namespace Microsoft.ContainerService --query properties.state -o tsv)
if [ "$r" != "Registered" ]
then az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
fi
while [ "$r" != "Registered" ]
do
  echo -n .
  sleep 5
  r=$(az feature show --name EnablePodIdentityPreview --namespace Microsoft.ContainerService --query properties.state -o tsv)
done
echo "POD Identity registered!"
# Install the aks-preview extension
az extension add --name aks-preview
# Update the extension to make sure you have the latest version installed
az extension update --name aks-preview
echo "AZ CLI extension updated!"

# Start
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
RESOURCE_GROUP=aks-akv
CLUSTER_NAME=myakscluster
VAULT_NAME=mykeyvault
LOCATION=eastus
NODE_RESOURCE_GROUP=MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION}
IDENTITY_NAME=${CLUSTER_NAME}_ID

az group create -g $RESOURCE_GROUP -l $LOCATION

# Deploy AKS cluster with Managed Identity
az aks create -n $CLUSTER_NAME -g $RESOURCE_GROUP \
    --node-count 2 \
    --network-plugin azure \
    --generate-ssh-keys \
    --enable-pod-identity \
    --location $LOCATION 

az aks get-credentials --admin --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --overwrite-existing

az keyvault create --name $VAULT_NAME --resource-group $RESOURCE_GROUP -l $LOCATION
az keyvault secret set --vault-name $VAULT_NAME --name "MySecret" --value "A secret in Azure Key Vault"

helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts 
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name --set "grpc-supported-providers=azure"

AKS_IDENTITY_CLIENT_ID=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query identityProfile.kubeletidentity.clientId -o tsv)

az role assignment create --role "Managed Identity Operator" --assignee $AKS_IDENTITY_CLIENT_ID --scope /subscriptions/$SUB_ID/resourcegroups/$VAULT_RESOURCE_GROUP
az role assignment create --role "Managed Identity Operator" --assignee $AKS_IDENTITY_CLIENT_ID --scope /subscriptions/$SUB_ID/resourcegroups/$NODE_RESOURCE_GROUP
az role assignment create --role "Virtual Machine Contributor" --assignee $AKS_IDENTITY_CLIENT_ID --scope /subscriptions/$SUB_ID/resourcegroups/$NODE_RESOURCE_GROUP

helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
helm install pod-identity aad-pod-identity/aad-pod-identity

az identity create -g $RESOURCE_GROUP -n $AKV_IDENTITY_NAME

# Pod Identity
IDENTITY_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $AKV_IDENTITY_NAME --query clientId -o tsv)

az keyvault set-policy -g $VAULT_RESOURCE_GROUP -n $VAULT_NAME --secret-permissions get --spn $IDENTITY_CLIENT_ID
az keyvault set-policy -g $VAULT_RESOURCE_GROUP -n $VAULT_NAME --key-permissions get --spn $IDENTITY_CLIENT_ID
az keyvault set-policy -g $VAULT_RESOURCE_GROUP -n $VAULT_NAME --certificate-permissions get --spn $IDENTITY_CLIENT_ID

echo $VAULT_NAME
echo $IDENTITY_CLIENT_ID

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
    userAssignedIdentityID: "$IDENTITY_CLIENT_ID"
    keyvaultName: "$VAULT_NAME"
    cloudName: "AzurePublicCloud"
    objects:  |
      array:
        - |
          objectName: MySecret
          objectType: secret
    tenantId: "$TENANT_ID"
EOF

if [ -f "podIdentityAndBinding.yaml" ] ; then
  rm podIdentityAndBinding.yaml
fi
cat << EOF >> podIdentityAndBinding.yaml
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
    name: akskeyvaultidentity                 
spec:
    type: 0                                 
    resourceID: "/subscriptions/$SUB_ID/resourcegroups/$VAULT_NAME/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$AKV_IDENTITY_NAME"
    clientID: "$IDENTITY_CLIENT_ID"
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
    name: azure-pod-identity-binding
spec:
    azureIdentity: "akskeyvaultidentity"
    selector: azure-pod-identity-binding-selector
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
kubectl apply -f podIdentityAndBinding.yaml
kubectl apply -f podBindingDeployment.yaml

# Validate the test pod deployed correctly
kubectl describe pods nginx-secrets-store-inline

# Validate the secrets are mounted
kubectl exec nginx-secrets-store-inline -- ls /mnt/secrets-store/
kubectl exec nginx-secrets-store-inline -- cat /mnt/secrets-store/MySecret
