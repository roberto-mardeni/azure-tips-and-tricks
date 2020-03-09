<#   
.SYNOPSIS
    Create a Service Connection to Azure Resource Manager in Azure DevOps in Automatic mode with a Service Principal.

.DESCRIPTION   
    This script will create an Azure Resource Manager service connection, based on a Service Principal that will be 
    created automatically with the given scope to an Azure Resource Group.

.PARAMETER AzureDevOpsUri
    URL of the Azure DevOps Service or Server.

.PARAMETER AzureDevOpsOrganization
    Name of the Azure DevOps Organization

.PARAMETER AzureDevOpsPAT
    Personal Access Token for the Azure DevOps Organization, see https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate

.PARAMETER AzureEnvironment
    The Azure environment to target

.PARAMETER AzureScope
    Scope for the service connection, defaults to Subscription

.PARAMETER ServiceConnectionName
    Name for the service connection

.PARAMETER ServiceConnectionDescription
    Description for the service connection

.PARAMETER SubscriptionID
    ID of the Azure Subscription

.PARAMETER SubscriptionName
    Name of the Azure Subscription

.PARAMETER ResourceGroup
    Name of the Resource Group for the service 

.PARAMETER TenantID
    ID of the Active Directory Tenant

.PARAMETER AzureDevOpsProjectID
    ID of the Azure DevOps Project

.PARAMETER AzureDevOpsProjectName
    Name of the Azure DevOps Project

.EXAMPLE 
    .\Create-AzureDevOpsServiceConnectionToAzureResourceManager.ps1 -ServiceConnectionName "MyConnection" -ServiceConnectionDescription "My Description" -SubscriptionID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -SubscriptionName "Subscription Name" -TenantID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -AzureDevOpsOrganization myorganization -AzureDevOpsProjectID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -AzureDevOpsProjectName myproject -AzureDevOpsPAT "PAT" -ResourceGroup development

.NOTES   
    Author: Roberto Mardeni   
    Last Updated: 03/09/2020
#>

param
(
    [parameter(Mandatory = $false)]  
    [string] $AzureDevOpsUri = "https://dev.azure.com",

    [parameter(Mandatory = $true)]  
    [string] $AzureDevOpsOrganization,

    [parameter(Mandatory = $true)]  
    [string] $AzureDevOpsPAT,

    [parameter(Mandatory = $false)]
    [ValidateSet("AzureCloud", "AzureChinaCloud", "AzureUSGovernment", "AzureGermanCloud")]  
    [string] $AzureEnvironment = "AzureCloud",

    [parameter(Mandatory = $false)]
    [ValidateSet("Subscription")]  
    [string] $AzureScope = "Subscription",

    [parameter(Mandatory = $true)]  
    [string] $ServiceConnectionName,

    [parameter(Mandatory = $true)]  
    [string] $ServiceConnectionDescription,

    [parameter(Mandatory = $true)]  
    [string] $SubscriptionID,

    [parameter(Mandatory = $true)]  
    [string] $SubscriptionName,

    [parameter(Mandatory = $true)]  
    [string] $ResourceGroup,

    [parameter(Mandatory = $true)]  
    [string] $TenantID,

    [parameter(Mandatory = $true)]  
    [string]$AzureDevOpsProjectID,

    [parameter(Mandatory = $true)]  
    [string]$AzureDevOpsProjectName
)

$ErrorActionPreference = "Stop"

class AuthorizationParameters {
  [string]$tenantid
  [string]$serviceprincipalid
  [string]$serviceprincipalkey
  [string]$authenticationType
  [string]$scope
  AuthorizationParameters([string]$tenantid, [string]$subscriptionId, [string]$resourceGroupName){
    $this.authenticationType = "spnKey"
    $this.tenantid = $tenantid
    $this.scope = "/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName"
    $this.serviceprincipalid = ""
    $this.serviceprincipalkey = ""
  }
}

class Authorization {
  [string]$scheme
  [AuthorizationParameters]$parameters
  Authorization([AuthorizationParameters]$parameters){
    $this.scheme = "ServicePrincipal"
    $this.parameters = $parameters
  }
}

class AzureResourceManagerServiceConnectionRequestData {
  [string]$environment
  [string]$scopeLevel
  [string]$creationMode
  [string]$appObjectId
  [string]$azureSpnPermissions
  [string]$azureSpnRoleAssignmentId
  [string]$spnObjectId
  [string]$subscriptionId
  [string]$subscriptionName
  AzureResourceManagerServiceConnectionRequestData([string]$environment, [string]$scopeLevel, [string]$subscriptionId, [string]$subscriptionName, [string]$creationMode){
    $this.environment = $environment
    $this.scopeLevel = $scopeLevel
    $this.subscriptionId = $subscriptionId
    $this.subscriptionName = $subscriptionName
    $this.creationMode = $creationMode
    $this.appObjectId = ""
    $this.azureSpnPermissions = ""
    $this.azureSpnRoleAssignmentId = ""
    $this.spnObjectId = ""
  }
}

class ProjectReference {
  [string]$id
  [string]$name
  ProjectReference([string]$id, [string]$name){
    $this.id = $id
    $this.name = $name
  }
}

class ServiceEndpointProjectReference {
  [string]$description
  [string]$name
  [ProjectReference]$projectReference
  ServiceEndpointProjectReference([string]$description, [string]$name, [string]$projectReferenceId, [string]$projectReferenceName){
    $this.description = $description
    $this.name = $name
    $this.projectReference = [ProjectReference]::new($projectReferenceId, $projectReferenceName)
  }
}

class AzureResourceManagerServiceConnectionRequest {
  [Authorization]$authorization
  [string]$createdBy
  [AzureResourceManagerServiceConnectionRequestData]$data
  [bool]$isShared
  [string]$name
  [string]$owner
  [string]$type
  [string]$url
  [string]$administratorsGroup
  [string]$description
  [string]$groupScopeId
  [string]$operationStatus
  [string]$readersGroup
  [ServiceEndpointProjectReference[]]$serviceEndpointProjectReferences
  AzureResourceManagerServiceConnectionRequest() {
    $this.type = "azurerm"
    $this.url = "https://management.azure.com/"
    $this.isShared = $false
    $this.owner = "library"
  }
}

function Write-VerboseInfo {
  Param (
    [string]$text
  )
  Write-Verbose "[DEBUG] $text"
}

Write-VerboseInfo "Debugging"

$uri = "$AzureDevOpsUri/$AzureDevOpsOrganization/$AzureDevOpsProjectName/_apis/serviceendpoint/endpoints?api-version=5.0-preview.2"

Write-VerboseInfo "Will post to $uri"

$pair = "Basic:$($AzureDevOpsPAT)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"

$headers = @{ 
  Authorization = $basicAuthValue
  "Content-Type" = "application/json"
}

Write-VerboseInfo "Authorization Header: $basicAuthValue"

# Putting together the payload
$body = [AzureResourceManagerServiceConnectionRequest]::new()
$body.authorization = [Authorization]::new([AuthorizationParameters]::new($TenantID, $SubscriptionID, $ResourceGroup))
$body.data = [AzureResourceManagerServiceConnectionRequestData]::new($AzureEnvironment, $AzureScope, $SubscriptionID, $SubscriptionName, "Automatic")
$body.description = $ServiceConnectionDescription
$body.name = $ServiceConnectionName
$body.serviceEndpointProjectReferences = @([ServiceEndpointProjectReference]::new($ServiceConnectionDescription, $ServiceConnectionName, $AzureDevOpsProjectID, $AzureDevOpsProjectName))

$payload = $body | ConvertTo-Json -Depth 10 -Compress

Write-VerboseInfo "PAYLOAD: $payload"

Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $payload
