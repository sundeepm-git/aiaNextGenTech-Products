<#
.SYNOPSIS
    Exports Azure Resource Group resources to Terraform using aztfexport.

.DESCRIPTION
    Accepts a Resource Group name, builds an exclusion list for reference 
    network resources, and runs aztfexport to generate Terraform configuration.
    Uploads results to Azure Blob Storage.

.PARAMETER SubscriptionId
    The subscription GUID or name that contains the target resource group.

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group to export.

.PARAMETER StorageAccount
    Azure Storage account name where exports will be uploaded.

.PARAMETER StorageContainer
    Azure Storage container name (default: aztfExport).

.EXAMPLE
    .\Export-AzToTerraform.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -ResourceGroupName "my-rg" -StorageAccount "samcpstorage"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccount = $env:storageAccount,

    [Parameter(Mandatory = $false)]
    [string]$StorageContainer = "aztfexport"
)

# Stop on errors
$ErrorActionPreference = "Stop"

# Ensure container name is lowercase (Azure Storage requirement)
$StorageContainer = $StorageContainer.ToLower()

# Debug output - Show what parameters were received
Write-Output "=== SCRIPT STARTED ==="
Write-Output "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Output "Parameters Received:"
Write-Output "  SubscriptionId: $SubscriptionId"
Write-Output "  ResourceGroupName: $ResourceGroupName"
Write-Output "  StorageAccount param: '$StorageAccount'"
Write-Output "  StorageContainer: $StorageContainer"
Write-Output "  Environment storageAccount: '$($env:storageAccount)'"
Write-Output "======================"

# Function to mask sensitive information
function Mask-String {
    param (
        [string]$Value,
        [int]$VisibleChars = 4
    )
    
    if ([string]::IsNullOrEmpty($Value)) {
        return ""
    }
    
    if ($Value.Length -le $VisibleChars * 2) {
        return "****"
    }
    
    $prefix = $Value.Substring(0, $VisibleChars)
    $suffix = $Value.Substring($Value.Length - $VisibleChars)
    $masked = "$prefix****$suffix"
    
    return $masked
}

# Function to generate standardized file header
function Get-TerraformFileHeader {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        
        [Parameter(Mandatory = $true)]
        [string]$Description,
        
        [Parameter(Mandatory = $false)]
        [string]$GeneratedBy = "Azure Export Script"
    )
    
    $currentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Try to get current user information
    try {
        $currentUser = $env:USERNAME
        $currentUserEmail = (az account show --query "user.name" -o tsv 2>$null)
        if ($currentUserEmail) {
            $GeneratedBy = "$currentUser ($currentUserEmail)"
        }
        else {
            $GeneratedBy = $currentUser
        }
    }
    catch {
        $GeneratedBy = "Automated Export"
    }
    
    $header = @"
# ==============================================================================
# FILE: $FileName
# ==============================================================================
# DESCRIPTION:
#   $Description
#
# GENERATED:
#   Date: $currentDate
#   By: $GeneratedBy
#   Tool: Azure to Terraform Export (aztfexport)
#
# MODIFICATION HISTORY:
#   Date       | Modified By | Description
#   -----------|-------------|--------------------------------------------
#   $currentDate | $GeneratedBy | Initial export from Azure
#
# NOTES:
#   - This file was automatically generated from existing Azure resources
#   - Review and modify as needed before applying to production
#   - Sensitive values may need to be parameterized
# ==============================================================================

"@
    
    return $header
}

# Track export start time
$exportStartDate = Get-Date -Format "yyyy-MM-dd"
$exportStartTime = Get-Date -Format "HH:mm:ss"
$exportStartDateTime = Get-Date

# Validate Azure CLI is installed
Write-Host "Validating Azure CLI installation..." -ForegroundColor Yellow
try {
    $azVersion = az version 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI (az) is not installed or not in PATH."
    }
    Write-Host "Azure CLI found" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: Azure CLI Not Found" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  Azure CLI (az) is required but not found." -ForegroundColor White
    Write-Host ""
    Write-Host "  To install Azure CLI:" -ForegroundColor Yellow
    Write-Host "    Windows: winget install Microsoft.AzureCLI" -ForegroundColor Gray
    Write-Host "    Or visit: https://aka.ms/InstallAzureCLIDirect" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}

# Check if user is logged in to Azure
Write-Host "Checking Azure login status..." -ForegroundColor Yellow
try {
    $accountJson = az account show --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Not logged in to Azure."
    }
    Write-Host "Azure login verified" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: Not Logged In to Azure" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  You must be logged in to Azure CLI." -ForegroundColor White
    Write-Host ""
    Write-Host "  To login:" -ForegroundColor Yellow
    Write-Host "    az login" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  For service principal login:" -ForegroundColor Yellow
    Write-Host "    az login --service-principal -u <app-id> -p <password> --tenant <tenant-id>" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}

# Get subscription name from Azure
Write-Host "Validating subscription access..." -ForegroundColor Yellow
try {
    $subInfoJson = az account show --subscription $SubscriptionId --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot access subscription: $SubscriptionId"
    }
    $subInfo = $subInfoJson | ConvertFrom-Json
    $subscriptionName = $subInfo.name
    $subscriptionState = $subInfo.state
    
    if ($subscriptionState -ne "Enabled") {
        throw "Subscription '$subscriptionName' is not enabled (State: $subscriptionState)"
    }
    
    Write-Host "Subscription validated: $subscriptionName" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: Subscription Validation Failed" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  Subscription ID: $SubscriptionId" -ForegroundColor White
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Possible causes:" -ForegroundColor White
    Write-Host "    - Subscription ID is incorrect" -ForegroundColor Gray
    Write-Host "    - You don't have access to this subscription" -ForegroundColor Gray
    Write-Host "    - Subscription is disabled or deleted" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  To list available subscriptions:" -ForegroundColor Yellow
    Write-Host "    az account list --output table" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}

# Variables
# Use temp directory for exports (will be uploaded to storage)
$tempRoot = Join-Path $env:TEMP "aztf-export"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$exportDir = Join-Path $tempRoot -ChildPath "$ResourceGroupName-$timestamp"
$excludeFile = Join-Path $PSScriptRoot "exclude.json"

# Validate storage account parameter
Write-Output "DEBUG: Checking StorageAccount parameter..."
Write-Output "DEBUG: StorageAccount value: '$StorageAccount'"
Write-Output "DEBUG: Environment variable storageAccount: '$($env:storageAccount)'"

if ([string]::IsNullOrEmpty($StorageAccount)) {
    Write-Error "ERROR: StorageAccount parameter is required"
    Write-Error "Either pass -StorageAccount parameter or set storageAccount environment variable"
    Write-Error "Current value: '$StorageAccount'"
    Write-Error "Environment variable: '$($env:storageAccount)'"
    exit 1
}

Write-Output "DEBUG: StorageAccount validated: $StorageAccount"

# Display Export Start Banner
Write-Host ""
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "  AZURE TO TERRAFORM EXPORT - STARTED" -ForegroundColor Cyan
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ""
Write-Output "DEBUG: Parameters received:"
Write-Output "  - SubscriptionId: $SubscriptionId"
Write-Output "  - ResourceGroupName: $ResourceGroupName"
Write-Output "  - StorageAccount: $StorageAccount"
Write-Output "  - StorageContainer: $StorageContainer"
Write-Output "  - Storage Path: $StorageContainer/$SubscriptionId/$ResourceGroupName/"
Write-Host ""
Write-Host "  1. Exporting Azure Subscription: $subscriptionName" -ForegroundColor White
Write-Host "     --> Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host ""
Write-Host "  2. Export Details:" -ForegroundColor White
Write-Host "     Export Start Date: $exportStartDate" -ForegroundColor White
Write-Host "     Export Start Time: $exportStartTime" -ForegroundColor White
Write-Host ""
Write-Host "  3. Temp Export Directory: $exportDir" -ForegroundColor White
Write-Host "     Storage Account: $StorageAccount" -ForegroundColor White
Write-Host "     Storage Container: $StorageContainer" -ForegroundColor White
Write-Host "     Storage Path: $StorageContainer/$SubscriptionId/$ResourceGroupName/" -ForegroundColor White
Write-Host ""

# Read exclusion list from exclude.json (one resource type per line, supports both Terraform and Azure types)
if (Test-Path $excludeFile) {
    $excludeContent = Get-Content -Path $excludeFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }
    Write-Host ('  4. Exclusion File: ' + $excludeFile) -ForegroundColor White
    Write-Host 'Excluded Resource Types:' -ForegroundColor Gray
    $excludeContent | ForEach-Object { Write-Host ('       - ' + $_) -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "Warning: Exclusion file not found: $excludeFile. No resources will be excluded." -ForegroundColor Yellow
    $excludeContent = @()
}

# Validate resource group exists
Write-Host "Validating resource group exists..." -ForegroundColor Yellow
try {
    $rgJson = az group show --name $ResourceGroupName --subscription $SubscriptionId --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Resource group not found: $ResourceGroupName"
    }
    $rgInfo = $rgJson | ConvertFrom-Json
    Write-Host "Resource group validated: $($rgInfo.name) (Location: $($rgInfo.location))" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: Resource Group Not Found" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "  Subscription: $subscriptionName ($SubscriptionId)" -ForegroundColor White
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  To list resource groups in this subscription:" -ForegroundColor Yellow
    Write-Host "    az group list --subscription $SubscriptionId --output table" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}

# Get resource information from Azure
Write-Host "Fetching resources from Azure..." -ForegroundColor Yellow

try {
    # Query Azure for resources in the resource group
    $resourcesJson = az resource list --resource-group $ResourceGroupName --subscription $SubscriptionId --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query resources in resource group: $ResourceGroupName"
    }
    
    $resources = $resourcesJson | ConvertFrom-Json
    $resourceCount = $resources.Count
    
    if ($resourceCount -eq 0) {
        Write-Host ""
        Write-Host ('=' * 80) -ForegroundColor Red
        Write-Host "  ERROR: Empty Resource Group" -ForegroundColor Red
        Write-Host ('=' * 80) -ForegroundColor Red
        Write-Host ""
        Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
        Write-Host "  The resource group exists but contains no resources." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  There is nothing to export." -ForegroundColor White
        Write-Host ""
        Write-Host ('=' * 80) -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Found $resourceCount resources in resource group" -ForegroundColor Green
    Write-Host ""
    Write-Host "  2. Number of Available Resources in Resource Group:" -ForegroundColor Cyan
    
    # Group resources by type and display count
    $resourcesByType = $resources | Group-Object -Property type | Sort-Object Count -Descending
    
    foreach ($group in $resourcesByType) {
        Write-Host "     $($group.Name): $($group.Count)" -ForegroundColor White
    }
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: Failed to Fetch Resource Information" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  Could not retrieve resources from resource group.\" -ForegroundColor White
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "  Subscription: $subscriptionName ($SubscriptionId)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  This could indicate:\" -ForegroundColor White
    Write-Host "    - Insufficient permissions to read resources\" -ForegroundColor Gray
    Write-Host "    - Network connectivity issues\" -ForegroundColor Gray
    Write-Host "    - Azure API service disruption\" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}

# Map Azure resource types to Terraform resource types for exclusion check
# Only monitoring, security, and management resources that shouldn't be in Terraform
$azureToTerraformMap = @{
    "Microsoft.Insights/diagnosticSettings" = "azurerm_monitor_diagnostic_setting"
    "Microsoft.Insights/actionGroups" = "azurerm_monitor_action_group"
    "Microsoft.Insights/metricAlerts" = "azurerm_monitor_metric_alert"
    "Microsoft.Insights/activityLogAlerts" = "azurerm_monitor_activity_log_alert"
    "Microsoft.Insights/workbooks" = "azurerm_application_insights_workbook"
    "Microsoft.OperationalInsights/workspaces" = "azurerm_log_analytics_workspace"
    "Microsoft.OperationsManagement/solutions" = "azurerm_log_analytics_solution"
    "Microsoft.Security/pricings" = "azurerm_security_center_subscription_pricing"
    "Microsoft.Security/securityContacts" = "azurerm_security_center_contact"
    "Microsoft.Authorization/roleAssignments" = "azurerm_role_assignment"
    "Microsoft.Authorization/policyAssignments" = "azurerm_policy_assignment"
    "Microsoft.Authorization/locks" = "azurerm_management_lock"
}

# Check if there are any exportable resources
$excludeList = $excludeContent -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

if ($resources) {
    # Separate resources into exportable and excluded
    $exportableResources = @()
    $excludedResources = @()
    foreach ($resource in $resources) {
        $azureType = $resource.type
        $terraformType = $azureToTerraformMap[$azureType]
        # Exclude if mapped terraform type is in excludeList, or if the Azure type itself is in excludeList
        if (
            ($terraformType -and $excludeContent -contains $terraformType) -or
            ($excludeContent -contains $azureType)
        ) {
            $excludedResources += $resource
        } else {
            $exportableResources += $resource
        }
    }
    # Check exclusion summary (silent)
    if ($excludedResources.Count -gt 0) {
        Write-Host "Excluded $($excludedResources.Count) resources from export" -ForegroundColor Yellow
    }
    # Check if we have any exportable resources
    if ($exportableResources.Count -eq 0) {
        Write-Host ""
        Write-Host ('-' * 70) -ForegroundColor Red
        Write-Host " ERROR: No resources available for export!" -ForegroundColor Red
        Write-Host ('-' * 70) -ForegroundColor Red
        Write-Host ""
        Write-Host " All $($resources.Count) resources in this resource group are in the exclusion list." -ForegroundColor Yellow
        Write-Host " aztfexport will fail with 'no resource found' error." -ForegroundColor Yellow
        Write-Host ""
        Write-Host " Options:" -ForegroundColor White
        Write-Host "   1. Modify the exclusion list to export some of the excluded resources" -ForegroundColor Gray
        Write-Host "   2. Choose a different resource group with non-excluded resources" -ForegroundColor Gray
        Write-Host ""
        Write-Host ('-' * 70) -ForegroundColor Red
        exit 1
    } else {
        Write-Host "Found $($exportableResources.Count) exportable resources" -ForegroundColor Green
        Write-Host "[Progress] Listing resources to be exported:" -ForegroundColor Cyan
        $i = 1
        # Group exportable resources by type
        $resourcesByType = $exportableResources | Group-Object -Property type | Sort-Object Name
        foreach ($group in $resourcesByType) {
            $type = $group.Name
            $count = $group.Count
            Write-Host "  [$type] $count resources" -ForegroundColor Magenta
            $j = 1
            foreach ($res in $group.Group) {
                $resName = $res.name
                Write-Host "    $j/$count $resName" -ForegroundColor White
                $j++
            }
        }
        Write-Host "Progress: All exportable resources listed above will be processed by aztfexport." -ForegroundColor Cyan
    }
}

# Check if export directory already exists
if (Test-Path $exportDir) {
    Write-Host ""
    Write-Host ('=' * 70) -ForegroundColor Red
    Write-Host " EXPORT DIRECTORY ALREADY EXISTS!" -ForegroundColor Red
    Write-Host ('=' * 70) -ForegroundColor Red
    Write-Host ""
    Write-Host " Resource Group: $ResourceGroupName" -ForegroundColor Yellow
    Write-Host " Export Directory: $exportDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host " This export has already been generated." -ForegroundColor White
    Write-Host ""
    Write-Host " Options:" -ForegroundColor Cyan
    Write-Host "   [D] - Delete existing export and continue" -ForegroundColor White
    Write-Host "   [C] - Cancel and exit (recommended)" -ForegroundColor White
    Write-Host ""
    Write-Host ('=' * 70) -ForegroundColor Red
    Write-Host ""
    
    # Get user choice
    do {
        $choice = Read-Host "Enter your choice [D/C]"
        $choice = $choice.ToUpper()
    } while ($choice -notin @('D', 'C'))
    
    switch ($choice) {
        'D' {
            # Delete existing
            Write-Host ""
            Write-Host "Deleting existing export: $exportDir" -ForegroundColor Yellow
            
            try {
                Remove-Item -Path $exportDir -Recurse -Force
                Write-Host "Existing export deleted successfully!" -ForegroundColor Green
                Write-Host "Proceeding with new export..." -ForegroundColor Green
            }
            catch {
                Write-Host "ERROR: Failed to delete existing export: $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            }
        }
        'C' {
            # Cancel
            Write-Host ""
            Write-Host "Export cancelled by user." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "To delete manually (if needed):" -ForegroundColor Cyan
            Write-Host "  Remove-Item -Path '$exportDir' -Recurse -Force" -ForegroundColor Gray
            Write-Host ""
            Write-Host "To create a backup before deleting:" -ForegroundColor Cyan
            Write-Host "  Copy-Item -Path '$exportDir' -Destination '$($exportDir)_backup' -Recurse" -ForegroundColor Gray
            Write-Host ""
            exit 0
        }
    }
    
    Write-Host ""
}

    # Run aztfexport with per-resource-type timing
    Write-Host ""
    Write-Host "Running aztfexport (resource-type timing enabled)..." -ForegroundColor Yellow
    Write-Host ""
    try {
        # Check if aztfexport is available
        Write-Host "Checking aztfexport installation..." -ForegroundColor Yellow
        $aztfexportPath = Get-Command aztfexport -ErrorAction SilentlyContinue
        if (-not $aztfexportPath) {
            Write-Host ""
            Write-Host ('=' * 80) -ForegroundColor Red
            Write-Host "  ERROR: aztfexport Not Found" -ForegroundColor Red
            Write-Host ('=' * 80) -ForegroundColor Red
            Write-Host ""
            Write-Host "  aztfexport is required but not found in PATH." -ForegroundColor White
            Write-Host ""
            Write-Host "  To install aztfexport:" -ForegroundColor Yellow
            Write-Host "    Windows: winget install aztfexport" -ForegroundColor Gray
            Write-Host "    macOS: brew install aztfexport" -ForegroundColor Gray
            Write-Host "    Linux: Download from https://github.com/Azure/aztfexport/releases" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Or visit: https://github.com/Azure/aztfexport" -ForegroundColor Gray
            Write-Host ""
            Write-Host ('=' * 80) -ForegroundColor Red
            exit 1
        }
        Write-Host "aztfexport found: $($aztfexportPath.Source)" -ForegroundColor Green

        # Clean up export directory if it exists (aztfexport requires empty directory)
        if (Test-Path $exportDir) {
            Write-Host "Cleaning up existing export directory..." -ForegroundColor Yellow
            try {
                Remove-Item -Path $exportDir -Recurse -Force -ErrorAction Stop
                Write-Host "Existing directory removed" -ForegroundColor Green
            } catch {
                Write-Host "Warning: Could not remove existing directory: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "Attempting to continue..." -ForegroundColor Yellow
            }
        }

        # Create fresh export directory
        Write-Host "Creating export directory..." -ForegroundColor Yellow
        try {
            New-Item -Path $exportDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Host "Export directory created: $exportDir" -ForegroundColor Green
            Write-Host "[Progress] Export directory is ready. Preparing to run aztfexport..." -ForegroundColor Cyan
        } catch {
            Write-Host ""
            Write-Host ('=' * 80) -ForegroundColor Red
            Write-Host "  ERROR: Failed to Create Export Directory" -ForegroundColor Red
            Write-Host ('=' * 80) -ForegroundColor Red
            Write-Host ""
            Write-Host "  Could not create directory: $exportDir" -ForegroundColor White
            Write-Host ""
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host ('=' * 80) -ForegroundColor Red
            exit 1
        }

        Write-Host "Progress: Starting export with aztfexport. This may take several minutes..." -ForegroundColor Yellow
        Write-Host "Note: aztfexport processes all resources together. Large resource groups may take longer." -ForegroundColor Yellow
        Write-Host ""
        
        # Display resource type summary
        $resourcesByType = $exportableResources | Group-Object -Property type | Sort-Object Name
        Write-Host "Resources to export by type:" -ForegroundColor Cyan
        foreach ($group in $resourcesByType) {
            Write-Host "  - $($group.Name): $($group.Count) resources" -ForegroundColor Gray
        }
        Write-Host ""
        
        # Run aztfexport for all resources
        $exportStartTime = Get-Date
        Write-Host "Export started at: $($exportStartTime.ToString('HH:mm:ss'))" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Running aztfexport... (this may take several minutes)" -ForegroundColor Yellow
        Write-Host ""
        
        # Run aztfexport with real-time output
        $aztfArgs = @(
            "rg",
            "--subscription-id", $SubscriptionId,
            "--output-dir", $exportDir,
            "--exclude-terraform-resource-file", $excludeFile,
            "--non-interactive",
            $ResourceGroupName
        )
        
        # Execute aztfexport and capture exit code while showing output
        $aztfCommand = "aztfexport $($aztfArgs -join ' ')"
        Write-Host "Command: $aztfCommand" -ForegroundColor Gray
        Write-Host ""
        
        & aztfexport @aztfArgs
        $exitCode = $LASTEXITCODE
        
        $exportEndTime = Get-Date
        $exportDuration = $exportEndTime - $exportStartTime
        Write-Host ""
        Write-Host "Export completed at: $($exportEndTime.ToString('HH:mm:ss'))" -ForegroundColor Green
        Write-Host "Total export duration: $($exportDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
        Write-Host ""
        
        # Check if export failed based on exit code
        if ($exitCode -ne 0) {
            Write-Host ""
            Write-Host ('=' * 80) -ForegroundColor Red
            Write-Host "  EXPORT FAILED - aztfexport Error" -ForegroundColor Red
            Write-Host ('=' * 80) -ForegroundColor Red
            Write-Host ""
            Write-Host "  Export Details:" -ForegroundColor White
            Write-Host "    Resource Group: $ResourceGroupName" -ForegroundColor White
            Write-Host "    Subscription: $subscriptionName" -ForegroundColor White
            Write-Host "    Exit Code: $exitCode" -ForegroundColor White
            Write-Host ""
            Write-Host "  Error Description:" -ForegroundColor Yellow
            Write-Host "    The aztfexport tool encountered errors during the export operation." -ForegroundColor White
            Write-Host "    This could be due to one or more of the following reasons:" -ForegroundColor White
            Write-Host ""
            Write-Host "  Common Causes:" -ForegroundColor Yellow
            Write-Host "    [*]' Insufficient permissions on the resource group" -ForegroundColor Gray
            Write-Host "       [*]' Ensure you have at least Reader role on the resource group" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "    [*]' Network connectivity issues to Azure" -ForegroundColor Gray
            Write-Host "       [*]' Check your internet connection and Azure service health" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "    [*]' Terraform provider version conflicts" -ForegroundColor Gray
            Write-Host "       [*]' Update Terraform to the latest version" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "    [*]' Resource types not supported by aztfexport" -ForegroundColor Gray
            Write-Host "       [*]' Some preview or newer Azure resources may not be supported" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "    [*]' Resource group is empty or all resources are excluded" -ForegroundColor Gray
            Write-Host "       [*]' Network resources are excluded by design for safety" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  Troubleshooting Steps:" -ForegroundColor Yellow
            Write-Host "    1. Check the detailed error messages above" -ForegroundColor White
            Write-Host "    2. Verify your Azure permissions: az role assignment list --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" -ForegroundColor Gray
            Write-Host "    3. Check resource group contents: az resource list --resource-group $ResourceGroupName" -ForegroundColor Gray
            Write-Host "    4. Try exporting with updated tools: winget upgrade aztfexport" -ForegroundColor Gray
            Write-Host "    5. Check Azure service health: https://status.azure.com" -ForegroundColor Gray
            Write-Host ""
            if ($importFailures.Count -gt 0) {
                Write-Host "  Failed Resource Details:" -ForegroundColor Yellow
                $importFailures | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor Gray
                }
                Write-Host ""
            }
            Write-Host ('=' * 80) -ForegroundColor Red
            if ($exitCode -ne 0) {
                exit 1
            }
            Write-Host ""
            Write-Host "Continuing with export despite import warnings..." -ForegroundColor Yellow
            Write-Host ""
        }
        Write-Host "[Progress] Export completed. Preparing to analyze and upload files..." -ForegroundColor Cyan

    # Success - Display success banner
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host "  [OK] EXPORT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host ""
    Write-Host "  Export Details:" -ForegroundColor Cyan
    Write-Host "    Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "    Subscription: $subscriptionName" -ForegroundColor White
    Write-Host "    Export Directory: $exportDir" -ForegroundColor White
    Write-Host ""
    Write-Host "  [OK] Azure resources have been successfully exported to Terraform!" -ForegroundColor Green
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Green
    
    # ===========================================
    # AUTOMATED DATA SOURCE GENERATION
    # ===========================================
    Write-Host ""
    Write-Host "Analyzing resource references..." -ForegroundColor Cyan
    
    try {
        # Read main.tf to find hardcoded Azure resource IDs
        $mainTfPath = Join-Path $exportDir "main.tf"
        
        if (-not (Test-Path $mainTfPath)) {
            Write-Host "Warning: main.tf not found. Skipping data source generation." -ForegroundColor Yellow
        }
        else {
            try {
                $mainTfContent = Get-Content -Path $mainTfPath -Raw -ErrorAction Stop
            }
            catch {
                Write-Host "Warning: Could not read main.tf. Skipping data source generation." -ForegroundColor Yellow
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
                throw
            }
            
            # Extract all Azure resource IDs (pattern: /subscriptions/.../resourceGroups/.../providers/...)
            $resourceIdPattern = '"/subscriptions/[a-f0-9\-]+/resourceGroups/[^/]+/providers/Microsoft\.[^/]+/[^/"]+/[^/"]+(?:/[^/"]+/[^/"]+)*"'
            
            try {
                $foundResourceIds = [regex]::Matches($mainTfContent, $resourceIdPattern) | ForEach-Object { $_.Value.Trim('"') } | Select-Object -Unique
            }
            catch {
                Write-Host "Warning: Error parsing resource IDs. Skipping data source generation." -ForegroundColor Yellow
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
                throw
            }
            
            if ($foundResourceIds.Count -gt 0) {
                Write-Host "Found $($foundResourceIds.Count) external resource references" -ForegroundColor Yellow
                
                # Parse resource IDs and generate data sources
                $dataSourcesContent = Get-TerraformFileHeader -FileName "data-sources.tf" -Description "Data sources for external Azure resources referenced by this configuration. These resources are managed outside this Terraform state and are referenced as read-only."
                
                $generatedDataSources = @()
                $dataSourceReplacements = @{}
                
                foreach ($resourceId in $foundResourceIds) {
                    try {
                        # Parse resource ID components
                        if ($resourceId -match "/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.([^/]+)/([^/]+)/([^/]+)(?:/([^/]+)/([^/]+))?") {
                            $subId = $matches[1]
                            $rgName = $matches[2]
                            $provider = $matches[3]
                            $resourceType = $matches[4]
                            $resourceName = $matches[5]
                            $subResourceType = if ($matches[6]) { $matches[6] } else { $null }
                            $subResourceName = if ($matches[7]) { $matches[7] } else { $null }
                            
                            # Map Azure resource types to Terraform data source types
                            $terraformType = $null
                            $dataSourceName = $null
                            $dataSourceBlock = $null
                            
                            switch ("$provider/$resourceType") {
                                "Network/virtualNetworks" {
                                    if ($subResourceType -eq "subnets") {
                                        $terraformType = "azurerm_subnet"
                                        $dataSourceName = $subResourceName -replace '[^a-zA-Z0-9_]', '_'
                                        $dataSourceBlock = @"

# Reference existing subnet: $subResourceName
data "$terraformType" "$dataSourceName" {
  name                 = "$subResourceName"
  virtual_network_name = "$resourceName"
  resource_group_name  = "$rgName"
}
"@
                                        $dataSourceReplacements["`"$resourceId`""] = "data.$terraformType.$dataSourceName.id"
                                    }
                                    else {
                                        $terraformType = "azurerm_virtual_network"
                                        $dataSourceName = $resourceName -replace '[^a-zA-Z0-9_]', '_'
                                        $dataSourceBlock = @"

# Reference existing virtual network: $resourceName
data "$terraformType" "$dataSourceName" {
  name                = "$resourceName"
  resource_group_name = "$rgName"
}
"@
                                        $dataSourceReplacements["`"$resourceId`""] = "data.$terraformType.$dataSourceName.id"
                                    }
                                }
                                "Network/networkInterfaces" {
                                    $terraformType = "azurerm_network_interface"
                                    $dataSourceName = $resourceName -replace '[^a-zA-Z0-9_]', '_'
                                    $dataSourceBlock = @"

# Reference existing network interface: $resourceName
data "$terraformType" "$dataSourceName" {
  name                = "$resourceName"
  resource_group_name = "$rgName"
}
"@
                                    $dataSourceReplacements["`"$resourceId`""] = "data.$terraformType.$dataSourceName.id"
                                }
                                "Network/networkSecurityGroups" {
                                    $terraformType = "azurerm_network_security_group"
                                    $dataSourceName = $resourceName -replace '[^a-zA-Z0-9_]', '_'
                                    $dataSourceBlock = @"

# Reference existing network security group: $resourceName
data "$terraformType" "$dataSourceName" {
  name                = "$resourceName"
  resource_group_name = "$rgName"
}
"@
                                    $dataSourceReplacements["`"$resourceId`""] = "data.$terraformType.$dataSourceName.id"
                                }
                                "Network/publicIPAddresses" {
                                    $terraformType = "azurerm_public_ip"
                                    $dataSourceName = $resourceName -replace '[^a-zA-Z0-9_]', '_'
                                    $dataSourceBlock = @"

# Reference existing public IP: $resourceName
data "$terraformType" "$dataSourceName" {
  name                = "$resourceName"
  resource_group_name = "$rgName"
}
"@
                                    $dataSourceReplacements["`"$resourceId`""] = "data.$terraformType.$dataSourceName.id"
                                }
                                "OperationalInsights/workspaces" {
                                    $terraformType = "azurerm_log_analytics_workspace"
                                    $dataSourceName = $resourceName -replace '[^a-zA-Z0-9_]', '_'
                                    $dataSourceBlock = @"

# Reference existing Log Analytics workspace: $resourceName
data "$terraformType" "$dataSourceName" {
  name                = "$resourceName"
  resource_group_name = "$rgName"
}
"@
                                    $dataSourceReplacements["`"$resourceId`""] = "data.$terraformType.$dataSourceName.id"
                                }
                                "Insights/components" {
                                    $terraformType = "azurerm_application_insights"
                                    $dataSourceName = $resourceName -replace '[^a-zA-Z0-9_]', '_'
                                    $dataSourceBlock = @"

# Reference existing Application Insights: $resourceName
data "$terraformType" "$dataSourceName" {
  name                = "$resourceName"
  resource_group_name = "$rgName"
}
"@
                                    $dataSourceReplacements["`"$resourceId`""] = "data.$terraformType.$dataSourceName.id"
                                }
                                "KeyVault/vaults" {
                                    if ($subResourceType -eq "secrets") {
                                        $dataSourceName = "$($resourceName)_$($subResourceName)" -replace '[^a-zA-Z0-9_]', '_'
                                        $dataSourceBlock = @"

# Reference existing Key Vault
data "azurerm_key_vault" "$($resourceName -replace '[^a-zA-Z0-9_]', '_')" {
  name                = "$resourceName"
  resource_group_name = "$rgName"
}

# Reference existing Key Vault secret: $subResourceName
data "azurerm_key_vault_secret" "$dataSourceName" {
  name         = "$subResourceName"
  key_vault_id = data.azurerm_key_vault.$($resourceName -replace '[^a-zA-Z0-9_]', '_').id
}
"@
                                        $dataSourceReplacements["`"$resourceId`""] = "data.azurerm_key_vault_secret.$dataSourceName.id"
                                    }
                                    else {
                                        $terraformType = "azurerm_key_vault"
                                        $dataSourceName = $resourceName -replace '[^a-zA-Z0-9_]', '_'
                                        $dataSourceBlock = @"

# Reference existing Key Vault: $resourceName
data "$terraformType" "$dataSourceName" {
  name                = "$resourceName"
  resource_group_name = "$rgName"
}
"@
                                        $dataSourceReplacements["`"$resourceId`""] = "data.$terraformType.$dataSourceName.id"
                                    }
                                }
                            }
                            
                            # Add data source block if type is supported
                            if ($dataSourceBlock -and $terraformType) {
                                if ($generatedDataSources -notcontains "$terraformType.$dataSourceName") {
                                    $dataSourcesContent += $dataSourceBlock
                                    $generatedDataSources += "$terraformType.$dataSourceName"
                                    Write-Host "  - Generated data source: $terraformType.$dataSourceName" -ForegroundColor Gray
                                }
                            }
                        }
                    }
                    catch {
                        Write-Host "  Warning: Could not parse resource ID: $resourceId" -ForegroundColor Yellow
                        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
                        # Continue processing other resource IDs
                        continue
                    }
                }
                
                # Create data-sources.tf file if we generated any data sources
                if ($generatedDataSources.Count -gt 0) {
                    $dataSourcesPath = Join-Path $exportDir "data-sources.tf"
                    
                    try {
                        Set-Content -Path $dataSourcesPath -Value $dataSourcesContent -Encoding UTF8 -ErrorAction Stop
                        Write-Host ""
                        Write-Host "Created data-sources.tf with $($generatedDataSources.Count) data sources" -ForegroundColor Green
                    }
                    catch {
                        Write-Host ""
                        Write-Host "Warning: Could not create data-sources.tf file" -ForegroundColor Yellow
                        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
                        Write-Host "Path: $dataSourcesPath" -ForegroundColor Gray
                        throw
                    }
                    
                    # Update main.tf to replace hardcoded IDs with data source references
                    Write-Host "Updating main.tf to use data sources..." -ForegroundColor Cyan
                    
                    try {
                        $updatedMainTf = $mainTfContent
                        $replacementCount = 0
                        
                        foreach ($replacement in $dataSourceReplacements.GetEnumerator()) {
                            try {
                                if ($updatedMainTf -match [regex]::Escape($replacement.Key)) {
                                    $updatedMainTf = $updatedMainTf -replace [regex]::Escape($replacement.Key), $replacement.Value
                                    $replacementCount++
                                }
                            }
                            catch {
                                Write-Host "  Warning: Could not replace reference: $($replacement.Key)" -ForegroundColor Yellow
                                continue
                            }
                        }
                        
                        if ($replacementCount -gt 0) {
                            try {
                                Set-Content -Path $mainTfPath -Value $updatedMainTf -Encoding UTF8 -ErrorAction Stop
                                Write-Host "Updated $replacementCount resource references to use data sources" -ForegroundColor Green
                            }
                            catch {
                                Write-Host "Warning: Could not update main.tf with data source references" -ForegroundColor Yellow
                                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
                                Write-Host "Original file preserved." -ForegroundColor Gray
                                throw
                            }
                        }
                        
                        Write-Host ""
                        Write-Host ('-' * 50) -ForegroundColor Cyan
                        Write-Host " Automated refactoring completed!" -ForegroundColor Cyan
                        Write-Host ('-' * 50) -ForegroundColor Cyan
                        Write-Host "  - Created: data-sources.tf" -ForegroundColor White
                        Write-Host "  - Updated: main.tf" -ForegroundColor White
                        Write-Host "  - Data sources: $($generatedDataSources.Count)" -ForegroundColor White
                        Write-Host "  - References updated: $replacementCount" -ForegroundColor White
                        Write-Host ('-' * 50) -ForegroundColor Cyan
                    }
                    catch {
                        Write-Host ""
                        Write-Host "Warning: Automated refactoring encountered errors" -ForegroundColor Yellow
                        Write-Host "data-sources.tf was created but main.tf may not be fully updated" -ForegroundColor Yellow
                        Write-Host "You can manually reference data sources from data-sources.tf" -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host "No supported resource types found for data source generation" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "No external resource references found" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host ""
        Write-Host "Warning: Automated data source generation failed" -ForegroundColor Yellow
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host "Continuing with export report generation..." -ForegroundColor Gray
        Write-Host "You can manually create data sources if needed." -ForegroundColor Gray
    }
    
    # ===========================================
    # ADD HEADERS TO ALL GENERATED TERRAFORM FILES
    # ===========================================
    Write-Host ""
    Write-Host "Adding standardized headers to Terraform files..." -ForegroundColor Cyan
    
    try {
        # Define file descriptions
        $fileDescriptions = @{
            "main.tf" = "Main Terraform configuration containing all Azure resource definitions exported from the resource group."
            "provider.tf" = "Azure provider configuration and authentication settings for Terraform."
            "terraform.tf" = "Terraform backend and required provider version constraints."
            "variables.tf" = "Input variable definitions for parameterizing the Terraform configuration."
            "outputs.tf" = "Output value definitions to expose resource attributes after deployment."
        }
        
        # Add headers to each Terraform file
        foreach ($file in $fileDescriptions.Keys) {
            $filePath = Join-Path $exportDir $file
            
            if (Test-Path $filePath) {
                try {
                    $currentContent = Get-Content -Path $filePath -Raw -Encoding UTF8
                    
                    # Only add header if it doesn't already exist
                    if ($currentContent -notmatch "# FILE:") {
                        $header = Get-TerraformFileHeader -FileName $file -Description $fileDescriptions[$file]
                        $newContent = $header + $currentContent
                        Set-Content -Path $filePath -Value $newContent -Encoding UTF8
                        Write-Host "  - Added header to: $file" -ForegroundColor Gray
                    }
                    else {
                        Write-Host "  - Header already exists in: $file" -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Host "  - Warning: Could not add header to $file" -ForegroundColor Yellow
                    Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkGray
                }
            }
        }
        
        Write-Host "Standardized headers added successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Error adding headers to Terraform files" -ForegroundColor Yellow
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host "Files are still usable without headers." -ForegroundColor Gray
    }
    
    Write-Host ""
    
    # ===========================================
    # CONTINUE WITH REPORT GENERATION
    # ===========================================
    
    # Get all Terraform files
    $tfFiles = Get-ChildItem -Path $exportDir -Filter "*.tf" -File
    $tfFileCount = $tfFiles.Count
    
    # Parse resource types from Terraform files
    $resourceTypes = @{}
    
    foreach ($file in $tfFiles) {
        $content = Get-Content -Path $file.FullName -Raw
        # Match resource blocks: resource "type" "name"
        $matches = [regex]::Matches($content, 'resource\s+"([^"]+)"\s+"([^"]+)"')
        
        foreach ($match in $matches) {
            $resourceType = $match.Groups[1].Value
            if ($resourceTypes.ContainsKey($resourceType)) {
                $resourceTypes[$resourceType]++
            }
            else {
                $resourceTypes[$resourceType] = 1
            }
        }
    }
    
    # Calculate totals
    $sortedResources = $resourceTypes.GetEnumerator() | Sort-Object Value -Descending
    $totalResources = ($resourceTypes.Values | Measure-Object -Sum).Sum
    
    # Calculate export end time
    $exportEndDate = Get-Date -Format "yyyy-MM-dd"
    $exportEndTime = Get-Date -Format "HH:mm:ss"
    $exportEndDateTime = Get-Date
    $exportDuration = $exportEndDateTime - $exportStartDateTime
    
    # Generate HTML Report
    Write-Host ""
    Write-Host "Generating HTML export report..." -ForegroundColor Cyan
    
    # Use consistent filename (without timestamp) to ensure only latest report is kept
    $reportFile = Join-Path $exportDir "Export-Report-Latest.html"
    
    # Parse individual resources from Terraform files
    $detailedResources = @()
    $importedResources = @()
    
    foreach ($file in $tfFiles) {
        $content = Get-Content -Path $file.FullName -Raw
        
        # Match resource blocks: resource "type" "name"
        $resourceMatches = [regex]::Matches($content, 'resource\s+"([^"]+)"\s+"([^"]+)"[\s\S]*?(?=\nresource|\nimport|\n\s*$|$)')
        
        foreach ($match in $resourceMatches) {
            $resourceType = $match.Groups[1].Value
            $resourceName = $match.Groups[2].Value
            $isNetwork = $resourceType -match "azurerm_(virtual_network|subnet|network_security_group|network_security_rule|network_interface|lb|public_ip|route_table|application_security_group|firewall|vpn_gateway|virtual_network_gateway|private_endpoint|nat_gateway|bastion_host|application_gateway)"
            
            $detailedResources += [PSCustomObject]@{
                'ExportedResource' = $resourceName
                'ExportedResourceType' = $resourceType
                'Status' = if ($isNetwork) { "Reference" } else { "Managed" }
                'File' = $file.Name
            }
        }
        
        # Match data source blocks: data "type" "name"
        $dataMatches = [regex]::Matches($content, 'data\s+"([^"]+)"\s+"([^"]+)"')
        
        foreach ($match in $dataMatches) {
            $dataType = $match.Groups[1].Value
            $dataName = $match.Groups[2].Value
            
            # Use data blocks as "Imported/Reference" resources
            $importedResources += [PSCustomObject]@{
                'ImportedResourceName' = $dataName
                'ImportedResourceType' = $dataType
                'AzureResourceId' = "Referenced in data-sources.tf"
                'File' = $file.Name
            }
        }
    }
    
    # Get file locations
    $mainTfPath = Join-Path $exportDir "main.tf"
    $providerTfPath = Join-Path $exportDir "provider.tf"
    $terraformTfPath = Join-Path $exportDir "terraform.tf"
    $variablesTfPath = Join-Path $exportDir "variables.tf"
    $outputsTfPath = Join-Path $exportDir "outputs.tf"
    $dataSourcesTfPath = Join-Path $exportDir "data-sources.tf"
    $tfstatePath = Join-Path $exportDir "terraform.tfstate"
    
    # Count resources
    $numExportedResources = $detailedResources.Count
    $numImportedResources = $importedResources.Count
    
    # Group resources by type
    $managedResourcesByType = $detailedResources | Where-Object { $_.Status -eq "Managed" } | Group-Object -Property ExportedResourceType | Select-Object @{Name='ResourceType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
    $referenceResourcesByType = $detailedResources | Where-Object { $_.Status -eq "Reference" } | Group-Object -Property ExportedResourceType | Select-Object @{Name='ResourceType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
    $importedResourcesByType = $importedResources | Group-Object -Property ImportedResourceType | Select-Object @{Name='ResourceType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
    
    # Build HTML Report
    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure to Terraform Export Report - $ResourceGroupName</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #4472C4 0%, #2E5090 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 32px;
            margin-bottom: 10px;
        }
        
        .header p {
            font-size: 16px;
            opacity: 0.9;
        }
        
        .content {
            padding: 30px;
        }
        
        .section {
            margin-bottom: 40px;
        }
        
        .section-title {
            background: #D9E1F2;
            padding: 15px 20px;
            font-size: 20px;
            font-weight: bold;
            color: #2E5090;
            border-left: 5px solid #4472C4;
            margin-bottom: 20px;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .info-item {
            background: #F8F9FA;
            padding: 15px;
            border-radius: 5px;
            border-left: 3px solid #4472C4;
        }
        
        .info-label {
            font-weight: bold;
            color: #2E5090;
            font-size: 14px;
            margin-bottom: 5px;
        }
        
        .info-value {
            color: #333;
            font-size: 16px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }
        
        .stat-number {
            font-size: 36px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .stat-label {
            font-size: 14px;
            opacity: 0.9;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        
        table thead {
            background: #4472C4;
            color: white;
        }
        
        table th {
            padding: 12px;
            text-align: left;
            font-weight: 600;
            font-size: 14px;
        }
        
        table tbody tr {
            border-bottom: 1px solid #E0E0E0;
        }
        
        table tbody tr:hover {
            background: #F5F5F5;
        }
        
        table td {
            padding: 12px;
            font-size: 13px;
        }
        
        .status-managed {
            background: #28A745;
            color: white;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: bold;
        }
        
        .status-reference {
            background: #FFC107;
            color: #333;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: bold;
        }
        
        .file-list {
            list-style: none;
            padding-left: 0;
        }
        
        .file-list li {
            background: #F8F9FA;
            padding: 10px 15px;
            margin-bottom: 8px;
            border-left: 3px solid #4472C4;
            border-radius: 3px;
        }
        
        .file-status {
            color: #28A745;
            font-weight: bold;
        }
        
        .footer {
            background: #F8F9FA;
            padding: 20px 30px;
            text-align: center;
            color: #666;
            font-size: 14px;
        }
        
        .type-count {
            display: flex;
            justify-content: space-between;
            padding: 8px 15px;
            background: #F8F9FA;
            margin-bottom: 5px;
            border-radius: 3px;
        }
        
        .type-name {
            font-weight: 500;
            color: #333;
        }
        
        .type-number {
            font-weight: bold;
            color: #4472C4;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Azure to Terraform Export Report</h1>
            <p>Resource Group: $ResourceGroupName</p>
        </div>
        
        <div class="content">
            <!-- Export Information Section -->
            <div class="section">
                <div class="section-title">Export Information</div>
                <div class="info-grid">
                    <div class="info-item">
                        <div class="info-label">Subscription Name</div>
                        <div class="info-value">$subscriptionName</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Subscription ID</div>
                        <div class="info-value">$SubscriptionId</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Resource Group</div>
                        <div class="info-value">$ResourceGroupName</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Export Date</div>
                        <div class="info-value">$exportStartDate</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Export Time</div>
                        <div class="info-value">$exportStartTime</div>
                    </div>
                    <div class="info-item">
                        <div class="info-label">Duration</div>
                        <div class="info-value">$("{0:hh\:mm\:ss}" -f $exportDuration)</div>
                    </div>
                </div>
            </div>
            
            <!-- Resource Summary Section -->
            <div class="section">
                <div class="section-title">Resource Summary</div>
                <div class="stats-grid">
                    <div class="stat-card">
                        <div class="stat-number">$numExportedResources</div>
                        <div class="stat-label">Total Exported Resources</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">$(($detailedResources | Where-Object { $_.Status -eq "Managed" }).Count)</div>
                        <div class="stat-label">Managed Resources</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">$(($detailedResources | Where-Object { $_.Status -eq "Reference" }).Count)</div>
                        <div class="stat-label">Reference Resources</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">$numImportedResources</div>
                        <div class="stat-label">Data Sources</div>
                    </div>
                </div>
            </div>
            
            <!-- Terraform Files Section -->
            <div class="section">
                <div class="section-title">Terraform Files Generated</div>
                <div class="info-item" style="margin-bottom: 15px;">
                    <div class="info-label">Output Directory</div>
                    <div class="info-value">$exportDir</div>
                </div>
                <ul class="file-list">
                    <li><strong>main.tf</strong> - $(if (Test-Path $mainTfPath) { '<span class="file-status">✓ Generated</span>' } else { 'Not Generated' }) - Resource definitions</li>
                    <li><strong>provider.tf</strong> - $(if (Test-Path $providerTfPath) { '<span class="file-status">✓ Generated</span>' } else { 'Not Generated' }) - Azure provider configuration</li>
                    <li><strong>terraform.tf</strong> - $(if (Test-Path $terraformTfPath) { '<span class="file-status">✓ Generated</span>' } else { 'Not Generated' }) - Terraform settings</li>
                    <li><strong>data-sources.tf</strong> - $(if (Test-Path $dataSourcesTfPath) { '<span class="file-status">✓ Generated</span>' } else { 'Not Generated' }) - Data sources (reference-only)</li>
                    <li><strong>terraform.tfstate</strong> - $(if (Test-Path $tfstatePath) { '<span class="file-status">✓ Generated</span>' } else { 'Not Generated' }) - State file</li>
                </ul>
            </div>
            
            <!-- Managed Resources by Type -->
            <div class="section">
                <div class="section-title">Managed Resources by Type</div>
"@
    
    if ($managedResourcesByType.Count -gt 0) {
        foreach ($type in $managedResourcesByType) {
            $htmlContent += @"
                <div class="type-count">
                    <span class="type-name">$($type.ResourceType)</span>
                    <span class="type-number">$($type.Count)</span>
                </div>
"@
        }
    } else {
        $htmlContent += '<p style="color: #666; font-style: italic;">No managed resources found.</p>'
    }
    
    $htmlContent += @"
            </div>
            
            <!-- Reference Resources by Type -->
            <div class="section">
                <div class="section-title">Reference Resources by Type</div>
"@
    
    if ($referenceResourcesByType.Count -gt 0) {
        foreach ($type in $referenceResourcesByType) {
            $htmlContent += @"
                <div class="type-count">
                    <span class="type-name">$($type.ResourceType)</span>
                    <span class="type-number">$($type.Count)</span>
                </div>
"@
        }
    } else {
        $htmlContent += '<p style="color: #666; font-style: italic;">No reference resources found.</p>'
    }
    
    $htmlContent += @"
            </div>
            
            <!-- Detailed Resource Listing -->
            <div class="section">
                <div class="section-title">Exported Resources - Detailed Listing</div>
                <table>
                    <thead>
                        <tr>
                            <th>Resource Name</th>
                            <th>Resource Type</th>
                            <th>Status</th>
                            <th>File</th>
                            <th>Description</th>
                        </tr>
                    </thead>
                    <tbody>
"@
    
    foreach ($resource in $detailedResources) {
        $statusClass = if ($resource.Status -eq "Managed") { "status-managed" } else { "status-reference" }
        $description = if ($resource.Status -eq "Reference") { 
            "REFERENCE ONLY - Imported from existing Azure. Will NOT be created/modified/destroyed by Terraform." 
        } else { 
            "MANAGED - Will be fully managed by Terraform (create/update/destroy)." 
        }
        
        $htmlContent += @"
                        <tr>
                            <td>$($resource.ExportedResource)</td>
                            <td>$($resource.ExportedResourceType)</td>
                            <td><span class="$statusClass">$($resource.Status)</span></td>
                            <td>$($resource.File)</td>
                            <td>$description</td>
                        </tr>
"@
    }
    
    $htmlContent += @"
                    </tbody>
                </table>
            </div>
            
            <!-- Data Sources / Reference Only Resources -->
            <div class="section">
                <div class="section-title">Data Sources - Reference Only</div>
"@
    
    if ($importedResources.Count -gt 0) {
        $htmlContent += @"
                <table>
                    <thead>
                        <tr>
                            <th>Resource Name</th>
                            <th>Resource Type</th>
                            <th>Azure Resource ID</th>
                            <th>File</th>
                            <th>Description</th>
                        </tr>
                    </thead>
                    <tbody>
"@
        
        foreach ($resource in $importedResources) {
            $htmlContent += @"
                        <tr>
                            <td>$($resource.ImportedResourceName)</td>
                            <td>$($resource.ImportedResourceType)</td>
                            <td>$($resource.AzureResourceId)</td>
                            <td>$($resource.File)</td>
                            <td>DATA SOURCE - Existing Azure resource referenced via data-sources.tf. Terraform will NOT create/modify/destroy this resource.</td>
                        </tr>
"@
        }
        
        $htmlContent += @"
                    </tbody>
                </table>
"@
    } else {
        $htmlContent += '<p style="color: #666; font-style: italic;">No data sources found.</p>'
    }
    
    $htmlContent += @"
            </div>
        </div>
        
        <div class="footer">
            <p>Report Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>Azure to Terraform Export Tool</p>
        </div>
    </div>
</body>
</html>
"@
    
    # Save HTML report
    try {
        $htmlContent | Out-File -FilePath $reportFile -Encoding UTF8
        Write-Host "HTML report generated successfully: $reportFile" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "  ERROR: HTML Report Generation Failed" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "ISSUE:" -ForegroundColor Yellow
        Write-Host "  Unable to generate HTML report" -ForegroundColor White
        Write-Host ""
        Write-Host "ERROR MESSAGE:" -ForegroundColor Yellow
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "NOTE:" -ForegroundColor Yellow
        Write-Host "  Terraform files were still generated successfully" -ForegroundColor Green
        Write-Host "  Only the HTML report failed to generate" -ForegroundColor Gray
        Write-Host ""
    }
    
    # Upload exported files to Azure Blob Storage
    Write-Host ""
    Write-Host "Uploading exported files to Azure Storage..." -ForegroundColor Yellow
    
    # Get storage account resource group from environment variable or use default
    $StorageAccountRG = if ([string]::IsNullOrEmpty($env:storageAccountRG)) { $ResourceGroupName } else { $env:storageAccountRG }
    Write-Host "DEBUG: Storage Account Resource Group: $StorageAccountRG" -ForegroundColor Cyan
    
    Write-Host "  Storage Account: $StorageAccount" -ForegroundColor White
    Write-Host "  Storage RG: $StorageAccountRG" -ForegroundColor White
    Write-Host "  Container: $StorageContainer" -ForegroundColor White
    Write-Host "  Blob Path: $SubscriptionId/$ResourceGroupName/" -ForegroundColor White
    Write-Host ""
    
    # Verify Azure CLI is logged in
    Write-Host "DEBUG: Verifying Azure CLI authentication..." -ForegroundColor Cyan
    $azAccount = az account show 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Not logged in to Azure CLI" -ForegroundColor Red
        Write-Host "Please run: az login" -ForegroundColor Yellow
        Write-Host "Skipping upload to storage" -ForegroundColor Yellow
        return
    } else {
        Write-Host "DEBUG: Azure CLI authenticated as: $($azAccount.user.name)" -ForegroundColor Cyan
    }
    
    # Check if storage account exists and is accessible
    Write-Host "DEBUG: Checking storage account accessibility..." -ForegroundColor Cyan
    $storageCheck = az storage account show --name $StorageAccount --resource-group $StorageAccountRG 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Cannot access storage account '$StorageAccount' in resource group '$StorageAccountRG'" -ForegroundColor Red
        Write-Host "Please verify:" -ForegroundColor Yellow
        Write-Host "  1. Storage account name is correct" -ForegroundColor White
        Write-Host "  2. Storage account exists in resource group '$StorageAccountRG'" -ForegroundColor White
        Write-Host "  3. You have permissions to access the storage account" -ForegroundColor White
        Write-Host "Skipping upload to storage" -ForegroundColor Yellow
        return
    } else {
        Write-Host "DEBUG: Storage account '$StorageAccount' verified - Location: $($storageCheck.location), SKU: $($storageCheck.sku.name)" -ForegroundColor Cyan
    }
    
    # Check if container exists, create if it doesn't
    Write-Host "DEBUG: Checking if container '$StorageContainer' exists..." -ForegroundColor Cyan
    $containerExists = az storage container exists --account-name $StorageAccount --name $StorageContainer --auth-mode login 2>&1 | ConvertFrom-Json
    
    if ($containerExists.exists -eq $false) {
        Write-Host "Container '$StorageContainer' does not exist. Creating..." -ForegroundColor Yellow
        $createResult = az storage container create --account-name $StorageAccount --name $StorageContainer --auth-mode login 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Container created successfully" -ForegroundColor Green
        } else {
            Write-Host "ERROR: Failed to create container" -ForegroundColor Red
            Write-Host "Error: $createResult" -ForegroundColor Yellow
            Write-Host "Skipping upload to storage" -ForegroundColor Yellow
            return
        }
    } else {
        Write-Host "DEBUG: Container '$StorageContainer' exists" -ForegroundColor Cyan
    }
    
    # Clean up old HTML reports from blob storage (keep only the latest)
    Write-Host "DEBUG: Cleaning up old HTML reports from blob storage..." -ForegroundColor Cyan
    try {
        $blobPrefix = "$SubscriptionId/$ResourceGroupName/"
        $existingBlobs = az storage blob list --account-name $StorageAccount --container-name $StorageContainer --prefix $blobPrefix --auth-mode login --query "[?contains(name, '.html')].name" -o json 2>&1 | ConvertFrom-Json
        
        if ($existingBlobs -and $existingBlobs.Count -gt 0) {
            Write-Host "DEBUG: Found $($existingBlobs.Count) existing HTML report(s) - deleting..." -ForegroundColor Yellow
            foreach ($blobName in $existingBlobs) {
                Write-Host "  Deleting old report: $blobName" -ForegroundColor Gray
                az storage blob delete --account-name $StorageAccount --container-name $StorageContainer --name $blobName --auth-mode login 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [DELETED] $blobName" -ForegroundColor Green
                }
            }
        } else {
            Write-Host "DEBUG: No old HTML reports found" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "WARNING: Could not clean up old reports: $($_.Exception.Message)" -ForegroundColor Yellow
        # Continue with upload even if cleanup fails
    }
    
    try {
        # Get all files in export directory, excluding .terraform directory
        $filesToUpload = Get-ChildItem -Path $exportDir -File -Recurse | Where-Object { 
            $_.FullName -notlike "*\.terraform\*"
        }
        Write-Host "DEBUG: Found $($filesToUpload.Count) files to upload from '$exportDir'" -ForegroundColor Cyan
        Write-Host "DEBUG: Excluding .terraform directory (provider binaries)" -ForegroundColor Cyan
        $uploadCount = 0
        $failedUploads = @()
        
        if ($filesToUpload.Count -eq 0) {
            Write-Host "WARNING: No files found to upload" -ForegroundColor Yellow
            return
        }
        
        foreach ($file in $filesToUpload) {
            # Calculate relative path for blob name
            $relativePath = $file.FullName.Substring($exportDir.Length + 1)
            # Replace backslashes with forward slashes for blob path
            $blobName = "$SubscriptionId/$ResourceGroupName/$relativePath".Replace('\', '/')
            
            Write-Host "  Uploading: $relativePath" -ForegroundColor Gray
            Write-Host "  Blob name: $blobName" -ForegroundColor DarkGray
            Write-Host "  File path: $($file.FullName)" -ForegroundColor DarkGray
            Write-Host "  File exists: $(Test-Path $file.FullName)" -ForegroundColor DarkGray
            
            # Test file size
            $fileSize = (Get-Item $file.FullName).Length
            Write-Host "  File size: $fileSize bytes" -ForegroundColor DarkGray
            
            # Upload file to blob storage
            az storage blob upload --account-name $StorageAccount --container-name $StorageContainer --name $blobName --file $file.FullName --auth-mode login --overwrite true
            
            $exitCode = $LASTEXITCODE
            Write-Host "  Exit code: $exitCode" -ForegroundColor DarkGray
            
            if ($exitCode -eq 0) {
                $uploadCount++
                Write-Host "  [SUCCESS] Upload successful" -ForegroundColor Green
            } else {
                Write-Host "  [FAILED] Failed to upload: $relativePath" -ForegroundColor Red
                $failedUploads += $relativePath
            }
        }
        
        Write-Host ""
        if ($failedUploads.Count -gt 0) {
            Write-Host "Upload completed with errors:" -ForegroundColor Yellow
            Write-Host "  Successfully uploaded: $uploadCount of $($filesToUpload.Count) files" -ForegroundColor White
            Write-Host "  Failed uploads:" -ForegroundColor Red
            foreach ($failed in $failedUploads) {
                Write-Host "    - $failed" -ForegroundColor Gray
            }
        } else {
            Write-Host "Successfully uploaded $uploadCount of $($filesToUpload.Count) files" -ForegroundColor Green
        }
        
        Write-Host "Storage URL: https://$StorageAccount.blob.core.windows.net/$StorageContainer/$SubscriptionId/$ResourceGroupName/" -ForegroundColor Cyan
        Write-Host ""
        
        # Check if GitHub output is also enabled
        $envFilePath = Join-Path $PSScriptRoot "..\.env"
        if (Test-Path $envFilePath) {
            $envConfig = @{}
            Get-Content $envFilePath | ForEach-Object {
                if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim().Trim('"')
                    $envConfig[$key] = $value
                }
            }
            
            $outputDest = $envConfig["OUTPUT_DESTINATION"]
            if ($outputDest -eq "github" -or $outputDest -eq "both") {
                Write-Host ""
                Write-Host "=== Uploading to GitHub ===" -ForegroundColor Cyan
                
                Import-Module "$PSScriptRoot\GitHubHelper.psm1" -Force
                
                $githubParams = @{
                    LocalDirectory = $exportDir
                    RemoteBasePath = "$($envConfig['AZTFEXPORT_FOLDER'])/$SubscriptionId/$ResourceGroupName"
                    Token = $envConfig["GITHUB_TOKEN"]
                    Owner = $envConfig["GITHUB_OWNER"]
                    Repo = $envConfig["GITHUB_REPO"]
                    Branch = $envConfig["GITHUB_BRANCH"]
                    CommitMessagePrefix = "Export Terraform for $ResourceGroupName"
                }
                
                $githubResults = Upload-DirectoryToGitHub @githubParams
                $githubSuccess = ($githubResults.Values | Where-Object { $_ -eq $true }).Count
                
                Write-Host ""
                Write-Host "GitHub upload completed: $githubSuccess of $($githubResults.Count) files" -ForegroundColor Green
                Write-Host "GitHub URL: https://github.com/$($envConfig['GITHUB_OWNER'])/$($envConfig['GITHUB_REPO'])/tree/$($envConfig['GITHUB_BRANCH'])/$($envConfig['AZTFEXPORT_FOLDER'])/$SubscriptionId/$ResourceGroupName" -ForegroundColor Cyan
            }
        }
        
        # Only clean up temp directory after successful upload of ALL files
        if ($failedUploads.Count -eq 0) {
            Write-Host ""
            Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
            Remove-Item -Path $exportDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Temp files cleaned up" -ForegroundColor Green
        } else {
            Write-Host "Keeping temporary files due to upload failures" -ForegroundColor Yellow
            Write-Host "Location: $exportDir" -ForegroundColor White
        }
        
    }
    catch {
        Write-Host ""
        Write-Host "WARNING: Failed to upload files to storage" -ForegroundColor Yellow
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Error Details: $($_.Exception.GetType().FullName)" -ForegroundColor Gray
        Write-Host "At Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Gray
        Write-Host "Files are still available locally at: $exportDir" -ForegroundColor White
        Write-Host ""
        
        # Show what files were found
        if ($filesToUpload) {
            Write-Host "Files that were attempted:" -ForegroundColor Cyan
            $filesToUpload | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
        }
    }
    
    # Display Final Export Summary
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host "  [OK] AZURE TO TERRAFORM EXPORT - COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host ""
    Write-Host "  [*] Export Summary:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "    Subscription: $subscriptionName" -ForegroundColor White
    Write-Host ""
    Write-Host "  [*] Generated Files:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    [*] Terraform Configuration Files:" -ForegroundColor White
    Write-Host "       - main.tf (resource definitions)" -ForegroundColor Gray
    Write-Host "       - data-sources.tf (external resource references)" -ForegroundColor Gray
    Write-Host "       - provider.tf (Azure provider configuration)" -ForegroundColor Gray
    Write-Host "       - terraform.tf (backend configuration)" -ForegroundColor Gray
    Write-Host "       - *.tf (additional configuration files)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    [*] Export Report:" -ForegroundColor White
    Write-Host "       - $reportFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [*] Exported Resources:" -ForegroundColor Cyan
    Write-Host ""
    
    # Group exported resources by type
    $exportedByType = $detailedResources | Group-Object -Property ExportedResourceType | Sort-Object Count -Descending
    foreach ($group in $exportedByType) {
        Write-Host "       - $($group.Name): $($group.Count)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "       [*] Total Exported Resources: $numExportedResources" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "  [*] Referenced Resources (Not Exported):" -ForegroundColor Cyan
    Write-Host ""
    
    if ($importedResources.Count -gt 0) {
        # Group imported resources by type
        $importedByType = $importedResources | Group-Object -Property ImportedResourceType | Sort-Object Count -Descending
        foreach ($group in $importedByType) {
            Write-Host "       - $($group.Name): $($group.Count)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "       [*]  Total Referenced Resources: $numImportedResources" -ForegroundColor Yellow
        Write-Host "       (These resources are managed externally - read-only references)" -ForegroundColor DarkGray
    } else {
        Write-Host "       [*]  No external resource references" -ForegroundColor Gray
    }
    Write-Host ""
    
    Write-Host '  [*]  Export Time Summary:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('       Start: ' + $exportStartDate + ' ' + $exportStartTime) -ForegroundColor White
    Write-Host ('       End:   ' + $exportEndDate + ' ' + $exportEndTime) -ForegroundColor White
    Write-Host '       Duration: ' -NoNewline -ForegroundColor White
    Write-Host ('{0:hh\:mm\:ss}' -f $exportDuration) -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  [*] Output Location:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('       Directory: ' + $exportDir) -ForegroundColor White
    Write-Host ('       Report: ' + $reportFile) -ForegroundColor White
    Write-Host ''
    Write-Host '  [*] Next Steps:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '       1. Review the generated Terraform files in the export directory' -ForegroundColor White
    Write-Host '       2. Initialize Terraform: terraform init' -ForegroundColor Gray
    Write-Host '       3. Validate configuration: terraform validate' -ForegroundColor Gray
    Write-Host '       4. Review planned changes: terraform plan' -ForegroundColor Gray
    Write-Host '       5. Check the Excel report for detailed resource information' -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host ''
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host '  [X] EXPORT FAILED - Unexpected Error' -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ''
    Write-Host '  [!] An unexpected error occurred during the export process:' -ForegroundColor White
    Write-Host ''
    Write-Host '  Error Details:' -ForegroundColor Yellow
    Write-Host ('    Type: ' + $_.Exception.GetType().Name) -ForegroundColor White
    Write-Host ('    Message: ' + $_.Exception.Message) -ForegroundColor White
    Write-Host ''
    if ($_.ScriptStackTrace) {
        Write-Host '  Location Information:' -ForegroundColor Yellow
        Write-Host ('    Script: ' + $_.InvocationInfo.ScriptName) -ForegroundColor Gray
        Write-Host ('    Line: ' + $_.InvocationInfo.ScriptLineNumber) -ForegroundColor Gray
        Write-Host ('    Command: ' + $_.InvocationInfo.Line.Trim()) -ForegroundColor Gray
    }
    Write-Host ''
    Write-Host '  Export Context:' -ForegroundColor Yellow
    Write-Host ('    Resource Group: ' + $ResourceGroupName) -ForegroundColor White
    Write-Host ('    Subscription ID: ' + $SubscriptionId) -ForegroundColor White
    if ($subscriptionName) {
        Write-Host ('    Subscription Name: ' + $subscriptionName) -ForegroundColor White
    }
    Write-Host ""
    Write-Host '  Troubleshooting Recommendations:' -ForegroundColor Yellow
    Write-Host '    1. Review the error message above for specific details' -ForegroundColor White
    Write-Host '    2. Verify your Azure CLI session is still active: az account show' -ForegroundColor Gray
    Write-Host "    3. Check if the resource group still exists: az group show -n $ResourceGroupName" -ForegroundColor Gray
    Write-Host '    4. Ensure you have sufficient permissions on the resource group' -ForegroundColor Gray
    Write-Host '    5. Try running the export again with the same parameters' -ForegroundColor Gray
    Write-Host '    6. If the issue persists, check Azure service health' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  For Additional Help:' -ForegroundColor Yellow
    Write-Host '    - Refer to the help.md file in the repository' -ForegroundColor Gray
    Write-Host '    - Check Azure CLI documentation: https://docs.microsoft.com/cli/azure/' -ForegroundColor Gray
    Write-Host '    - Reference aztfexport documentation: https://github.com/Azure/aztfexport' -ForegroundColor Gray
    Write-Host ''
    Write-Host '================================================================================' -ForegroundColor Red
    exit 1
}
