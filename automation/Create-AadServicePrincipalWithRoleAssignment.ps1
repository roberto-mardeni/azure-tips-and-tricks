<#   
.SYNOPSIS   
    Create a Service Principal in Azure Active Directory with Role Assignment to the given Resource Group
   
.DESCRIPTION   
    This script will create the Service Principal with the given Display Name with no specific assignments if not found.
    It will then add a role assignment to the Resource Group given.

.PARAMETER DisplayName
    Display name of the Service Principal.

.PARAMETER ResourceGroupName
    Name of the Resource Group to add the role assignment.

.PARAMETER ResourceGroupRole
    Name of the Role Definition to create the role assingment with.

.NOTES   
    Author: Roberto Mardeni   
    Last Updated: 02/24/2020
#>
param
(
    # Display Name of the Service Principal
    [parameter(Mandatory = $true)]  
    [string] $DisplayName,
    # Resource Group Name to create role assignment for
    [parameter(Mandatory = $true)]  
    [string] $ResourceGroupName,
    # Resource Group Role to create role assignment for
    [parameter(Mandatory = $false)]  
    [string] $ResourceGroupRole = "Contributor"
)

$ErrorActionPreference = "Stop"

$sp = Get-AzADServicePrincipal -DisplayName $DisplayName

if ($sp -eq $null) {
    New-AzADServicePrincipal -DisplayName $DisplayName -SkipAssignment
    $sp = Get-AzADServicePrincipal -DisplayName $DisplayName

    # Wait for 5 seconds to wait for replication
    Start-Sleep -Seconds 5
} else {
    Write-Host "Service Principal $DisplayName already exists"
}

$roleAssignment = Get-AzRoleAssignment -ResourceGroupName $ResourceGroupName -ObjectId $sp.Id -RoleDefinitionName $ResourceGroupRole

if ($roleAssignment -eq $null) {
    New-AzRoleAssignment -ResourceGroupName $ResourceGroupName -ObjectId $sp.Id -RoleDefinitionName $ResourceGroupRole
    Write-Host "Role assignment added"
} else {
    Write-Host "Role assignment already present"
}
