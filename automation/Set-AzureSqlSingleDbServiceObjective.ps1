<#   
.SYNOPSIS   
    Vertically scale (up or down) an Azure SQL Database (Single Instance) with Geo-Replication
   
.DESCRIPTION   
    This runbook enables one to vertically scale (up or down) an Azure SQL Database using Azure Automation.  
     
    There are many scenarios in which the performance needs of a database follow a known schedule. 
    Using the provided runbook, one could automatically schedule a database to a scale-up to a Premium/P1  
    database during peak hours (e.g., 7am to 6pm) and then scale-down the database to a Standard/S0 during 
    non peak hours (e.g., 6pm-7am). 

    This runbook assumes only one replica of the database, changes are required for more replicas to 
    be supported.

.PARAMETER ResourceGroup
    Name of the resource group where the SQL Database is located

.PARAMETER SqlServerName  
    Name of the Azure SQL Database server
       
.PARAMETER DatabaseName   
    Target Azure SQL Database name 

.PARAMETER ServiceObjectiveName   
    Desired performance level {Basic, S0, S1, S2, P1, P2, P3}  
  
.EXAMPLE   
    Set-AzureSqlSingleDbServiceObjective
        -ResourceGroup "myResourceGroup"
        -SqlServerName "mySqlServer"
        -DatabaseName "myDatabase"
        -ServiceObjectiveName "P1"
   
.NOTES   
    Author: Roberto Mardeni   
    Last Updated: 11/26/2019
#>  
#Requires -Modules @{ ModuleName="Az.Accounts"; ModuleVersion="1.6.4" }
#Requires -Modules @{ ModuleName="Az.Sql"; ModuleVersion="2.1.0" }
param
(
    # Name of the Resource Group
    [parameter(Mandatory = $true)]  
    [string] $ResourceGroup,

    # Name of the Azure SQL Database Server
    [parameter(Mandatory = $true)]  
    [string] $SqlServerName,

    # Name of the Azure SQL Database Name
    [parameter(Mandatory = $true)]  
    [string] $DatabaseName,

    # Desired performance level {Basic, S0, S1, S2, P1, P2, P3} 
    [parameter(Mandatory = $true)]  
    [string] $ServiceObjectiveName,

    # Indicates if the script will wait for the scale operation to complete
    [parameter(Mandatory = $true)]  
    [bool] $Wait = $true,

    # Amount of time to wait for the scaling operation
    [int] $WaitTimeout = 3600
)

$ErrorActionPreference = "Stop"

# Determines the scale operation name.
# Only supports Basic, Standard & Premium tiers.
Function Get-ServiceObjectiveScaleOperationName {
    param (
        [Microsoft.Azure.Commands.Sql.ServiceObjective.Model.AzureSqlServerServiceObjectiveModel] $From,
        [Microsoft.Azure.Commands.Sql.ServiceObjective.Model.AzureSqlServerServiceObjectiveModel] $To
    )

    $operationName = "tbd"

    if ($To.Capacity -gt $From.Capacity) {
        $operationName = "upgrade"
    } else {
        $operationName = "downgrade"
    } 

    return $operationName
}

# Update a Database and wait for the operation
Function UpdateDatabaseAndWait {
    param (
        [string]$ResourceGroup,
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$ServiceObjectiveName
    )

    Set-AzSqlDatabase `
        -ResourceGroupName $ResourceGroup `
        -ServerName $ServerName `
        -DatabaseName $DatabaseName `
        -RequestedServiceObjectiveName $ServiceObjectiveName | Out-Null

    $start = Get-Date

    Function Get-UpdatedDb {
        Start-Sleep -Milliseconds 1000
        $db = Get-AzSqlDatabase `
                -DatabaseName $DatabaseName `
                -ResourceGroupName $ResourceGroup `
                -ServerName $ServerName `
                -ErrorAction "SilentlyContinue"
        return $db
    }

    # Wait for the status of the activity
    Write-Output "Waiting for scale operation to complete"
    $db = Get-UpdatedDb
    while ($db.CurrentServiceObjectiveName -ne $ServiceObjectiveName) {
        Write-Output "Waiting"
        $db = Get-UpdatedDb
        if (((Get-Date) - $start).TotalSeconds -gt $WaitTimeout) { break }
    }

    # Output final status message 
    if ($db.CurrentServiceObjectiveName -eq $ServiceObjectiveName) {
        Write-Output "Completed scaling operation on database $DatabaseName in $ServerName in resource group $ResourceGroup" 
    } else {
        Write-Error "Scale operation not completed on database $DatabaseName in $ServerName in resource group $ResourceGroup"
    }
}

$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."

    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

$db = Get-AzSqlDatabase `
		-DatabaseName $DatabaseName `
		-ResourceGroupName $ResourceGroup `
		-ServerName $SqlServerName

if ($db.CurrentServiceObjectiveName -eq $ServiceObjectiveName) {
    Write-Output "Database already matches desired service objective $ServiceObjectiveName."
} else {
    # Get all service objectives available
    $serviceObjectives = Get-AzSqlServerServiceObjective `
        -ResourceGroupName $ResourceGroup `
        -ServerName $SqlServerName

    # Get desired service objective
    $desiredObjective = $serviceObjectives | ? { $_.ServiceObjectiveName -eq $ServiceObjectiveName }

    # Validate desired service objective
    if ($desiredObjective -eq $null) {
        Write-Error "Invalid desired service objective"
    } else {
        # Get current service objective
        $currentObjective = $serviceObjectives | ? { $_.ServiceObjectiveName -eq $db.CurrentServiceObjectiveName }
    
        # Determine type of scaling operation, only for reporting purposes, can be removed
        $operation = Get-ServiceObjectiveScaleOperationName -From $currentObjective -To $desiredObjective
        Write-Output "Scaling operation will be a(n) $operation from $($currentObjective.ServiceObjectiveName) ($($currentObjective.Capacity) $($currentObjective.CapacityUnit)) to $ServiceObjectiveName ($($desiredObjective.Capacity) $($desiredObjective.CapacityUnit))"

        # Determine if part of a failover group
        $failoverGroup = $null
        @(Get-AzSqlDatabaseFailoverGroup -ResourceGroupName $ResourceGroup -ServerName $SqlServerName) | ForEach-Object {
            if ($_.DatabaseNames -contains $DatabaseName) {
                $failoverGroup = $_
            }
        }

        if ($failoverGroup -ne $null) {
            Write-Output "In failover group $($failoverGroup.FailoverGroupName)"

            $primaryResourceGroup = $ResourceGroup
            $primaryServerName = $SqlServerName
            $secondaryResourceGroup = $failoverGroup.PartnerResourceGroupName
            $secondaryServerName = $failoverGroup.PartnerServerName

            # https://docs.microsoft.com/en-us/azure/sql-database/sql-database-single-database-scale#additional-considerations-when-changing-service-tier-or-rescaling-compute-size
            if ($failoverGroup.ReplicationRole -eq "Secondary") {
                $primaryResourceGroup = $failoverGroup.PartnerResourceGroupName
                $primaryServerName = $failoverGroup.PartnerServerName
                $secondaryResourceGroup = $ResourceGroup
                $secondaryServerName = $SqlServerName
            } 

            if ($operation -eq "upgrade") {
                # Upgrade secondary first
                UpdateDatabaseAndWait `
                    -ResourceGroup $secondaryResourceGroup `
                    -ServerName $secondaryServerName `
                    -DatabaseName $DatabaseName `
                    -ServiceObjectiveName $ServiceObjectiveName

                # Upgrade primary 
                UpdateDatabaseAndWait `
                    -ResourceGroup $primaryResourceGroup `
                    -ServerName $primaryServerName `
                    -DatabaseName $DatabaseName `
                    -ServiceObjectiveName $ServiceObjectiveName
            } else {
                # Downgrade primary first
                UpdateDatabaseAndWait `
                    -ResourceGroup $primaryResourceGroup `
                    -ServerName $primaryServerName `
                    -DatabaseName $DatabaseName `
                    -ServiceObjectiveName $ServiceObjectiveName

                # Downgrade secondary 
                UpdateDatabaseAndWait `
                    -ResourceGroup $secondaryResourceGroup `
                    -ServerName $secondaryServerName `
                    -DatabaseName $DatabaseName `
                    -ServiceObjectiveName $ServiceObjectiveName
            }
        } else {
            # Apply change
            UpdateDatabaseAndWait `
                -ResourceGroup $ResourceGroup `
                -ServerName $SqlServerName `
                -DatabaseName $DatabaseName `
                -ServiceObjectiveName $ServiceObjectiveName
        }
    }
}
