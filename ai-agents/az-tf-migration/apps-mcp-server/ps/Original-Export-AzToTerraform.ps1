<#
.SYNOPSIS
    Exports Azure Resource Group resources to Terraform using aztfexport.

.DESCRIPTION
    Accepts a Resource Group name, builds an exclusion list for reference 
    network resources, and runs aztfexport to generate Terraform configuration.

.PARAMETER ResourceGroup
    The name of the Azure Resource Group to export.

.PARAMETER SubscriptionId
    The subscription GUID or name that contains the target resource group.

.EXAMPLE
    .\Export-AzToTerraform.ps1 -ResourceGroup "my-rg" -SubscriptionId "00000000-0000-0000-0000-000000000000"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

# Stop on errors
$ErrorActionPreference = "Stop"

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
# Always use the root of the repo for azure-export, not the ps subfolder
$repoRoot = (Resolve-Path "$PSScriptRoot\..\").Path
$subscriptionDir = Join-Path $repoRoot "azure-export" | Join-Path -ChildPath $subscriptionName
$exportDir = Join-Path $subscriptionDir -ChildPath $ResourceGroup
$excludeFile = Join-Path $repoRoot "exclude.json"

# Display Export Start Banner
Write-Host ""
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "  AZURE TO TERRAFORM EXPORT - STARTED" -ForegroundColor Cyan
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Exporting Azure Subscription: $subscriptionName" -ForegroundColor White
Write-Host "     --> Resource Group: $ResourceGroup" -ForegroundColor Yellow
Write-Host ""
Write-Host "  2. Export Start Date: $exportStartDate" -ForegroundColor White
Write-Host "     Export Start Time: $exportStartTime" -ForegroundColor White
Write-Host ""
Write-Host "  3. Export Directory: $exportDir" -ForegroundColor White
Write-Host ""

# Build exclusion file (Terraform resource types to exclude)
# CRITICAL: Network and Monitor resources are EXCLUDED to prevent accidental recreation/modification
# These resources are typically shared infrastructure and should NOT be managed by Terraform
$excludeContent = @"
azurerm_virtual_network
azurerm_subnet
azurerm_network_security_group
azurerm_network_security_rule
azurerm_network_interface
azurerm_network_interface_application_security_group_association
azurerm_network_interface_security_group_association
azurerm_subnet_network_security_group_association
azurerm_subnet_route_table_association
azurerm_public_ip
azurerm_lb
azurerm_lb_backend_address_pool
azurerm_lb_probe
azurerm_lb_rule
azurerm_lb_nat_rule
azurerm_lb_nat_pool
azurerm_lb_outbound_rule
azurerm_route_table
azurerm_route
azurerm_application_security_group
azurerm_firewall
azurerm_firewall_application_rule_collection
azurerm_firewall_network_rule_collection
azurerm_firewall_nat_rule_collection
azurerm_firewall_policy
azurerm_vpn_gateway
azurerm_virtual_network_gateway
azurerm_virtual_network_gateway_connection
azurerm_local_network_gateway
azurerm_virtual_network_peering
azurerm_private_endpoint
azurerm_private_link_service
azurerm_nat_gateway
azurerm_nat_gateway_public_ip_association
azurerm_bastion_host
azurerm_application_gateway
azurerm_monitor_diagnostic_setting
azurerm_monitor_action_group
azurerm_monitor_metric_alert
azurerm_monitor_activity_log_alert
azurerm_application_insights
azurerm_application_insights_workbook
azurerm_log_analytics_workspace
azurerm_log_analytics_solution
azurerm_log_analytics_linked_service
azurerm_log_analytics_datasource_windows_event
azurerm_log_analytics_datasource_windows_performance_counter
azurerm_security_center_subscription_pricing
azurerm_security_center_contact
azurerm_security_center_workspace
azurerm_sentinel_alert_rule
azurerm_sentinel_automation_rule
azurerm_sentinel_data_connector
azurerm_sentinel_watchlist
azurerm_sentinel_log_analytics_workspace_onboarding
azurerm_role_assignment
azurerm_role_definition
azurerm_policy_assignment
azurerm_policy_definition
azurerm_policy_set_definition
azurerm_management_lock
azurerm_management_group
azurerm_subscription_policy_assignment
"@

Set-Content -Path $excludeFile -Value $excludeContent -Encoding UTF8

Write-Host "  4. Exclusion File: $excludeFile" -ForegroundColor White
Write-Host "     Excluded Resource Types:" -ForegroundColor Gray
$excludeContent -split "`n" | ForEach-Object { if ($_.Trim()) { Write-Host "       - $($_.Trim())" -ForegroundColor DarkGray } }
Write-Host ""
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ""

# Validate resource group exists
Write-Host "Validating resource group exists..." -ForegroundColor Yellow
try {
    $rgJson = az group show --name $ResourceGroup --subscription $SubscriptionId --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Resource group not found: $ResourceGroup"
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
    Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
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
    $resourcesJson = az resource list --resource-group $ResourceGroup --subscription $SubscriptionId --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query resources in resource group: $ResourceGroup"
    }
    
    $resources = $resourcesJson | ConvertFrom-Json
    $resourceCount = $resources.Count
    
    if ($resourceCount -eq 0) {
        Write-Host ""
        Write-Host ('=' * 80) -ForegroundColor Red
        Write-Host "  ERROR: Empty Resource Group" -ForegroundColor Red
        Write-Host ('=' * 80) -ForegroundColor Red
        Write-Host ""
        Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
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
    Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
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
        
        if ($terraformType -and $excludeList -contains $terraformType) {
            $excludedResources += $resource
        }
        else {
            $exportableResources += $resource
        }
    }
    
    # Check exclusion summary (silent)
    if ($excludedResources.Count -gt 0) {
        Write-Host \"Excluded $($excludedResources.Count) resources from export\" -ForegroundColor Yellow
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
    }
    else {
        Write-Host \"Found $($exportableResources.Count) exportable resources\" -ForegroundColor Green
    }
}

# Check if resource group already exported
if (Test-Path $exportDir) {
    Write-Host ""
    Write-Host ('=' * 70) -ForegroundColor Red
    Write-Host " RESOURCE GROUP ALREADY EXPORTED!" -ForegroundColor Red
    Write-Host ('=' * 70) -ForegroundColor Red
    Write-Host ""
    Write-Host " Resource Group: $ResourceGroup" -ForegroundColor Yellow
    Write-Host " Export Directory: $exportDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host " This resource group has already been exported to Terraform." -ForegroundColor White
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

# Create output directory
Write-Host "Creating export directory...\" -ForegroundColor Yellow
try {
    New-Item -Path $exportDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Host "Created export directory: $exportDir" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: Failed to Create Export Directory\" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  Could not create directory: $exportDir\" -ForegroundColor White
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)\" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Possible causes:\" -ForegroundColor White
    Write-Host "    - Insufficient permissions on parent directory\" -ForegroundColor Gray
    Write-Host "    - Disk is full\" -ForegroundColor Gray
    Write-Host "    - Path is too long (Windows MAX_PATH limitation)\" -ForegroundColor Gray
    Write-Host "    - Directory is locked by another process\" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}

# Run aztfexport
Write-Host ""
Write-Host "Running aztfexport (displaying per-resource progress)..." -ForegroundColor Yellow
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

    # Execute aztfexport with output displayed in real-time
    # This allows users to see per-resource progress as aztfexport processes each resource
    aztfexport rg `
        --subscription-id $SubscriptionId `
        --output-dir $exportDir `
        --exclude-terraform-resource-file $excludeFile `
        --non-interactive `
        $ResourceGroup

    # Check if command succeeded
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host ('=' * 80) -ForegroundColor Red
        Write-Host "  [*]' EXPORT FAILED - aztfexport Error" -ForegroundColor Red
        Write-Host ('=' * 80) -ForegroundColor Red
        Write-Host ""
        Write-Host "  Export Details:" -ForegroundColor White
        Write-Host "    Resource Group: $ResourceGroup" -ForegroundColor White
        Write-Host "    Subscription: $subscriptionName" -ForegroundColor White
        Write-Host "    Exit Code: $LASTEXITCODE" -ForegroundColor White
        Write-Host ""
        Write-Host "  Error Description:" -ForegroundColor Yellow
        Write-Host "    The aztfexport tool failed to complete the export operation." -ForegroundColor White
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
        Write-Host "    2. Verify your Azure permissions: az role assignment list --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" -ForegroundColor Gray
        Write-Host "    3. Check resource group contents: az resource list --resource-group $ResourceGroup" -ForegroundColor Gray
        Write-Host "    4. Try exporting with updated tools: winget upgrade aztfexport" -ForegroundColor Gray
        Write-Host "    5. Check Azure service health: https://status.azure.com" -ForegroundColor Gray
        Write-Host ""
        Write-Host ('=' * 80) -ForegroundColor Red
        exit 1
    }

    # Success - Display success banner
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host "  [OK] EXPORT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host ""
    Write-Host "  Export Details:" -ForegroundColor Cyan
    Write-Host "    Resource Group: $ResourceGroup" -ForegroundColor White
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
    
    # Generate Excel Report (silent processing)
    Write-Host ""
    Write-Host "Generating export report..." -ForegroundColor Cyan
    
    # Check if ImportExcel module is available
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Host "Installing ImportExcel module..." -ForegroundColor Yellow
        try {
            Install-Module -Name ImportExcel -Force -Scope CurrentUser -ErrorAction Stop
            Write-Host "ImportExcel module installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "Warning: Could not install ImportExcel module." -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
            Write-Host "Falling back to CSV format..." -ForegroundColor Yellow
            Write-Host "To install manually later: Install-Module -Name ImportExcel -Force -Scope CurrentUser" -ForegroundColor Gray
        }
    }
    
    Import-Module ImportExcel -ErrorAction SilentlyContinue
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $useExcel = Get-Module -Name ImportExcel
    $reportFile = Join-Path $exportDir "Export-Report_$($ResourceGroup)_$timestamp$(if ($useExcel) { '.xlsx' } else { '.csv' })"
    
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
    
    if ($useExcel) {
        try {
            # ===========================================
            # SHEET 1: SUMMARY REPORT (Professional View)
            # ===========================================
            
            # Group resources by type for charts
            $managedResourcesByType = $detailedResources | Where-Object { $_.Status -eq "Managed" } | Group-Object -Property ExportedResourceType | Select-Object @{Name='Resource Type';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
            $referenceResourcesByType = $detailedResources | Where-Object { $_.Status -eq "Reference" } | Group-Object -Property ExportedResourceType | Select-Object @{Name='Resource Type';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
            $importedResourcesByType = $importedResources | Group-Object -Property ImportedResourceType | Select-Object @{Name='Resource Type';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
        
        # Build Summary Report Data
        $summaryData = @()
        
        # Header Section
        $summaryData += [PSCustomObject]@{
            'Category' = 'AZURE TO TERRAFORM EXPORT REPORT'
            'Metric' = ''
            'Value' = ''
            'Details' = ''
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = ''
            'Value' = ''
            'Details' = ''
        }
        
        # Export Information
        $summaryData += [PSCustomObject]@{
            'Category' = 'EXPORT INFORMATION'
            'Metric' = 'Subscription Name'
            'Value' = $subscriptionName
            'Details' = ''
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'Subscription ID'
            'Value' = $SubscriptionId
            'Details' = ''
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'Resource Group'
            'Value' = $ResourceGroup
            'Details' = ''
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'Export Date'
            'Value' = $exportStartDate
            'Details' = ''
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'Export Time'
            'Value' = $exportStartTime
            'Details' = ''
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'Duration'
            'Value' = "{0:hh\:mm\:ss}" -f $exportDuration
            'Details' = ''
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = ''
            'Value' = ''
            'Details' = ''
        }
        
        # Resource Summary
        $summaryData += [PSCustomObject]@{
            'Category' = 'RESOURCE SUMMARY'
            'Metric' = 'Total Exported Resources'
            'Value' = $numExportedResources
            'Details' = 'Resources exported to Terraform configuration'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'Managed Resources'
            'Value' = ($detailedResources | Where-Object { $_.Status -eq "Managed" }).Count
            'Details' = 'Will be created/managed by Terraform'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'Reference Resources'
            'Value' = ($detailedResources | Where-Object { $_.Status -eq "Reference" }).Count
            'Details' = 'Network resources - reference only'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'Reference Only - data-sources.tf'
            'Value' = $numImportedResources
            'Details' = 'Existing Azure resources (not managed)'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = ''
            'Value' = ''
            'Details' = ''
        }
        
        # Files Generated
        $summaryData += [PSCustomObject]@{
            'Category' = 'TERRAFORM FILES'
            'Metric' = 'Output Directory'
            'Value' = $exportDir
            'Details' = ''
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'main.tf'
            'Value' = if (Test-Path $mainTfPath) { 'Generated' } else { 'Not Generated' }
            'Details' = 'Resource definitions'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'provider.tf'
            'Value' = if (Test-Path $providerTfPath) { 'Generated' } else { 'Not Generated' }
            'Details' = 'Azure provider configuration'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'terraform.tf'
            'Value' = if (Test-Path $terraformTfPath) { 'Generated' } else { 'Not Generated' }
            'Details' = 'Terraform settings'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'data-sources.tf'
            'Value' = if (Test-Path $dataSourcesTfPath) { 'Generated' } else { 'Not Generated' }
            'Details' = 'Data sources (reference-only)'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = 'terraform.tfstate'
            'Value' = if (Test-Path $tfstatePath) { 'Generated' } else { 'Not Generated' }
            'Details' = 'State file'
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = ''
            'Value' = ''
            'Details' = ''
        }
        
        # Resource Type Breakdown - Managed
        $summaryData += [PSCustomObject]@{
            'Category' = 'MANAGED RESOURCES BY TYPE'
            'Metric' = 'Resource Type'
            'Value' = 'Count'
            'Details' = 'Status'
        }
        if ($managedResourcesByType.Count -gt 0) {
            foreach ($type in $managedResourcesByType) {
                $summaryData += [PSCustomObject]@{
                    'Category' = ''
                    'Metric' = $type.'Resource Type'
                    'Value' = $type.Count
                    'Details' = 'Terraform Managed'
                }
            }
        }
        else {
            $summaryData += [PSCustomObject]@{
                'Category' = ''
                'Metric' = 'No managed resources'
                'Value' = '0'
                'Details' = ''
            }
        }
        $summaryData += [PSCustomObject]@{
            'Category' = ''
            'Metric' = ''
            'Value' = ''
            'Details' = ''
        }
        
        # Resource Type Breakdown - Reference
        $summaryData += [PSCustomObject]@{
            'Category' = 'REFERENCE RESOURCES BY TYPE'
            'Metric' = 'Resource Type'
            'Value' = 'Count'
            'Details' = 'Status'
        }
        if ($referenceResourcesByType.Count -gt 0) {
            foreach ($type in $referenceResourcesByType) {
                $summaryData += [PSCustomObject]@{
                    'Category' = ''
                    'Metric' = $type.'Resource Type'
                    'Value' = $type.Count
                    'Details' = 'Reference Only'
                }
            }
        }
        else {
            $summaryData += [PSCustomObject]@{
                'Category' = ''
                'Metric' = 'No reference resources'
                'Value' = '0'
                'Details' = ''
            }
        }
        
        # Export Summary Sheet with styling
        try {
            $excel = $summaryData | Export-Excel -Path $reportFile -WorksheetName "Summary Report" -AutoSize -PassThru `
                -TableStyle Medium2 -FreezeTopRow
            
            $ws = $excel.Workbook.Worksheets["Summary Report"]
            
            # Format header row (Row 1)
            $ws.Cells["A1:D1"].Style.Font.Bold = $true
            $ws.Cells["A1:D1"].Style.Font.Size = 16
            $ws.Cells["A1:D1"].Style.Font.Color.SetColor([System.Drawing.Color]::White)
            $ws.Cells["A1:D1"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $ws.Cells["A1:D1"].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(68, 114, 196))
            $ws.Cells["A1:D1"].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
            
            # Format section headers
            $ws.Cells["A3"].Style.Font.Bold = $true
            $ws.Cells["A3"].Style.Font.Size = 12
            $ws.Cells["A3"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $ws.Cells["A3"].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(217, 225, 242))
            
            $ws.Cells["A12"].Style.Font.Bold = $true
            $ws.Cells["A12"].Style.Font.Size = 12
            $ws.Cells["A12"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $ws.Cells["A12"].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(217, 225, 242))
            
            $ws.Cells["A19"].Style.Font.Bold = $true
            $ws.Cells["A19"].Style.Font.Size = 12
            $ws.Cells["A19"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $ws.Cells["A19"].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(217, 225, 242))
        }
        catch {
            Write-Host "Warning: Failed to apply basic formatting to Summary Report" -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
        }
        
        # Find the row where Managed Resources by Type starts
        try {
            $managedStartRow = 0
            $referenceStartRow = 0
            for ($i = 1; $i -le $summaryData.Count; $i++) {
                $cellValue = $ws.Cells["A$i"].Value
                if ($cellValue -eq "MANAGED RESOURCES BY TYPE") {
                    $managedStartRow = $i
                    $ws.Cells["A$i:D$i"].Style.Font.Bold = $true
                    $ws.Cells["A$i:D$i"].Style.Font.Size = 12
                    $ws.Cells["A$i:D$i"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                    $ws.Cells["A$i:D$i"].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(217, 225, 242))
                }
                if ($cellValue -eq "REFERENCE RESOURCES BY TYPE") {
                    $referenceStartRow = $i
                    $ws.Cells["A$i:D$i"].Style.Font.Bold = $true
                    $ws.Cells["A$i:D$i"].Style.Font.Size = 12
                    $ws.Cells["A$i:D$i"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                    $ws.Cells["A$i:D$i"].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(217, 225, 242))
                }
            }
        }
        catch {
            Write-Host "Warning: Failed to format resource type section headers" -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
        }
        
        # Add Charts
        try {
            if ($managedResourcesByType.Count -gt 0 -and $managedStartRow -gt 0) {
                $managedDataRows = $managedResourcesByType.Count
                $chartStartRow = $managedStartRow + 2
                $chartEndRow = $chartStartRow + $managedDataRows - 1
                
                # Pie Chart for Managed Resources
                $chart1 = $ws.Drawings.AddChart("ManagedResourcesPie", [OfficeOpenXml.Drawing.Chart.eChartType]::Pie)
                $chart1.Title.Text = "Managed Resources Distribution"
                $chart1.SetPosition(2, 0, 5, 0)
                $chart1.SetSize(400, 300)
                $chart1.Series.Add("C$chartStartRow`:C$chartEndRow", "B$chartStartRow`:B$chartEndRow")
                $chart1.Legend.Position = [OfficeOpenXml.Drawing.Chart.eLegendPosition]::Right
                $chart1.DataLabel.ShowCategory = $true
                $chart1.DataLabel.ShowValue = $true
            }
        }
        catch {
            Write-Host "Warning: Failed to create Managed Resources pie chart" -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
        }
        

        
        # Add Resource Count Bar Chart
        try {
            $resourceCountData = @(
                [PSCustomObject]@{Type='Managed Resources';Count=($detailedResources | Where-Object { $_.Status -eq "Managed" }).Count}
                [PSCustomObject]@{Type='Reference Resources';Count=($detailedResources | Where-Object { $_.Status -eq "Reference" }).Count}
                [PSCustomObject]@{Type='Reference Only - data-sources.tf';Count=$numImportedResources}
            )
            
            # Add hidden data for bar chart
            $hiddenRow = $summaryData.Count + 3
            $ws.Cells["F$hiddenRow"].Value = "Type"
            $ws.Cells["G$hiddenRow"].Value = "Count"
            $hiddenRow++
            foreach ($item in $resourceCountData) {
                $ws.Cells["F$hiddenRow"].Value = $item.Type
                $ws.Cells["G$hiddenRow"].Value = $item.Count
                $hiddenRow++
            }
            
            $barStartRow = $summaryData.Count + 4
            $barEndRow = $barStartRow + 2
            $chart3 = $ws.Drawings.AddChart("ResourceCountBar", [OfficeOpenXml.Drawing.Chart.eChartType]::ColumnClustered)
            $chart3.Title.Text = "Resource Count Overview"
            $chart3.SetPosition(17, 0, 5, 0)
            $chart3.SetSize(500, 300)
            $chart3.Series.Add("G$barStartRow`:G$barEndRow", "F$barStartRow`:F$barEndRow")
            $chart3.Legend.Remove()
            $chart3.YAxis.Title.Text = "Count"
            $chart3.XAxis.Title.Text = "Resource Type"
        }
        catch {
            Write-Host "Warning: Failed to create Resource Count bar chart" -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
        }
        
        try {
            Close-ExcelPackage $excel
        }
        catch {
            Write-Host "Warning: Failed to close Summary Report Excel package properly" -ForegroundColor Yellow
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
        }
        
        # ===========================================
        # SHEET 2: DETAIL REPORT
        # ===========================================
        
        $detailData = @()
        
        # Exported/Managed Resources Section
        $detailData += [PSCustomObject]@{
            'Section' = 'EXPORTED RESOURCES (TERRAFORM MANAGED)'
            'Resource Name' = ''
            'Resource Type' = ''
            'Status' = ''
            'File' = ''
            'Description' = ''
        }
        $detailData += [PSCustomObject]@{
            'Section' = ''
            'Resource Name' = 'Resource Name'
            'Resource Type' = 'Resource Type'
            'Status' = 'Status'
            'File' = 'Defined In'
            'Description' = 'Description'
        }
        
        if ($detailedResources.Count -gt 0) {
            foreach ($resource in $detailedResources) {
                $description = ""
                if ($resource.Status -eq "Reference") {
                    $description = "REFERENCE ONLY - Imported from existing Azure. Will NOT be created/modified/destroyed by Terraform."
                }
                else {
                    $description = "MANAGED - Will be fully managed by Terraform (create/update/destroy)."
                }
                
                $detailData += [PSCustomObject]@{
                    'Section' = ''
                    'Resource Name' = $resource.ExportedResource
                    'Resource Type' = $resource.ExportedResourceType
                    'Status' = $resource.Status
                    'File' = $resource.File
                    'Description' = $description
                }
            }
        }
        
        # Blank row separator
        $detailData += [PSCustomObject]@{
            'Section' = ''
            'Resource Name' = ''
            'Resource Type' = ''
            'Status' = ''
            'File' = ''
            'Description' = ''
        }
        
        # Reference Only Resources Section
        $detailData += [PSCustomObject]@{
            'Section' = 'REFERENCE ONLY - data-sources.tf'
            'Resource Name' = ''
            'Resource Type' = ''
            'Status' = ''
            'File' = ''
            'Description' = ''
        }
        $detailData += [PSCustomObject]@{
            'Section' = ''
            'Resource Name' = 'Resource Name'
            'Resource Type' = 'Resource Type'
            'Status' = 'Azure Resource ID'
            'File' = 'Defined In'
            'Description' = 'Description'
        }
        
        if ($importedResources.Count -gt 0) {
            foreach ($resource in $importedResources) {
                $description = "DATA SOURCE - Existing Azure resource referenced via data-sources.tf. Terraform will NOT create/modify/destroy this resource."
                
                $detailData += [PSCustomObject]@{
                    'Section' = ''
                    'Resource Name' = $resource.ImportedResourceName
                    'Resource Type' = $resource.ImportedResourceType
                    'Status' = $resource.AzureResourceId
                    'File' = $resource.File
                    'Description' = $description
                }
            }
        }
        
        # Export Detail Sheet with styling
        try {
            $excel = $detailData | Export-Excel -Path $reportFile -WorksheetName "Detail Report" -AutoSize -PassThru `
                -TableStyle Medium2 -FreezeTopRow
            
            $ws2 = $excel.Workbook.Worksheets["Detail Report"]
            
            # Format section headers in Detail Report
            for ($i = 1; $i -le $detailData.Count; $i++) {
                $sectionValue = $ws2.Cells["A$i"].Value
                if ($sectionValue -match "^(EXPORTED RESOURCES|IMPORTED RESOURCES)") {
                    $ws2.Cells["A$i:F$i"].Merge = $true
                    $ws2.Cells["A$i:F$i"].Style.Font.Bold = $true
                    $ws2.Cells["A$i:F$i"].Style.Font.Size = 14
                    $ws2.Cells["A$i:F$i"].Style.Font.Color.SetColor([System.Drawing.Color]::White)
                    $ws2.Cells["A$i:F$i"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                    $ws2.Cells["A$i:F$i"].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(68, 114, 196))
                    $ws2.Cells["A$i:F$i"].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
                }
            }
            
            # Format column headers
            for ($i = 1; $i -le $detailData.Count; $i++) {
                $nameValue = $ws2.Cells["B$i"].Value
                if ($nameValue -eq "Resource Name") {
                    $ws2.Cells["B$i:F$i"].Style.Font.Bold = $true
                    $ws2.Cells["B$i:F$i"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                    $ws2.Cells["B$i:F$i"].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(217, 225, 242))
                }
            }
            
            # Auto-fit columns
            $ws2.Cells[$ws2.Dimension.Address].AutoFitColumns()
            
            Close-ExcelPackage $excel
            
            Write-Host "Professional Excel report saved: $reportFile" -ForegroundColor Green
            Write-Host "  - Sheet 1: Summary Report (with charts)" -ForegroundColor Cyan
            Write-Host "  - Sheet 2: Detail Report (complete resource listing)" -ForegroundColor Cyan
        }
        catch {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Red
            Write-Host "  ERROR: Failed to Create Detail Report" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "ISSUE:" -ForegroundColor Yellow
            Write-Host "  Unable to generate Detail Report sheet in Excel file" -ForegroundColor White
            Write-Host ""
            Write-Host "ERROR MESSAGE:" -ForegroundColor Yellow
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "POSSIBLE CAUSES:" -ForegroundColor Yellow
            Write-Host "  - File is open in Excel (close it and try again)" -ForegroundColor Gray
            Write-Host "  - Insufficient disk space" -ForegroundColor Gray
            Write-Host "  - File permissions issue" -ForegroundColor Gray
            Write-Host "  - ImportExcel module corruption" -ForegroundColor Gray
            Write-Host ""
            Write-Host "WHAT WAS SAVED:" -ForegroundColor Yellow
            Write-Host "  Summary Report sheet was saved successfully" -ForegroundColor Green
            Write-Host "  You can still use the report, but Detail Report is missing" -ForegroundColor Gray
            Write-Host ""
        }
        }
        catch {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Red
            Write-Host "  ERROR: Excel Report Generation Failed" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "ISSUE:" -ForegroundColor Yellow
            Write-Host "  Unable to generate professional Excel report" -ForegroundColor White
            Write-Host ""
            Write-Host "ERROR MESSAGE:" -ForegroundColor Yellow
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "POSSIBLE CAUSES:" -ForegroundColor Yellow
            Write-Host "  - ImportExcel module not properly installed" -ForegroundColor Gray
            Write-Host "  - Insufficient permissions to create files" -ForegroundColor Gray
            Write-Host "  - Disk space issues" -ForegroundColor Gray
            Write-Host "  - Excel file path too long" -ForegroundColor Gray
            Write-Host ""
            Write-Host "RECOMMENDED ACTIONS:" -ForegroundColor Yellow
            Write-Host "  1. Reinstall ImportExcel module:" -ForegroundColor Cyan
            Write-Host "     Install-Module -Name ImportExcel -Force -Scope CurrentUser" -ForegroundColor White
            Write-Host "  2. Check available disk space" -ForegroundColor Cyan
            Write-Host "  3. Try with shorter resource group names" -ForegroundColor Cyan
            Write-Host "  4. Run PowerShell as Administrator" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "NOTE:" -ForegroundColor Yellow
            Write-Host "  Terraform files were still generated successfully" -ForegroundColor Green
            Write-Host "  Only the Excel report failed to generate" -ForegroundColor Gray
            Write-Host ""
        }
    }
    else {
        # Fallback to CSV format with all data in one file
        $allData = @()
        
        # Add metadata with descriptions
        $allData += [PSCustomObject]@{
            'Type' = 'METADATA'
            'Field' = 'Export Start Date'
            'Value' = $exportStartDate
            'Description' = 'Date when the export process started'
        }
        $allData += [PSCustomObject]@{
            'Type' = 'METADATA'
            'Field' = 'Export Start Time'
            'Value' = $exportStartTime
            'Description' = 'Time when the export process started'
        }
        $allData += [PSCustomObject]@{
            'Type' = 'METADATA'
            'Field' = 'Export End Date'
            'Value' = $exportEndDate
            'Description' = 'Date when the export process completed'
        }
        $allData += [PSCustomObject]@{
            'Type' = 'METADATA'
            'Field' = 'Export End Time'
            'Value' = $exportEndTime
            'Description' = 'Time when the export process completed'
        }
        $allData += [PSCustomObject]@{
            'Type' = 'METADATA'
            'Field' = 'Number of Exported Resources'
            'Value' = $numExportedResources
            'Description' = 'Total count of resources exported to Terraform'
        }
        $allData += [PSCustomObject]@{
            'Type' = 'METADATA'
            'Field' = 'Number of Imported Resources'
            'Value' = $numImportedResources
            'Description' = 'Total count of reference-only resources'
        }
        $allData += [PSCustomObject]@{
            'Type' = 'METADATA'
            'Field' = 'Export Directory'
            'Value' = $exportDir
            'Description' = 'Local directory path where Terraform files are saved'
        }
        
        # Add blank rows
        $allData += [PSCustomObject]@{
            'Type' = ''
            'Field' = ''
            'Value' = ''
            'Description' = ''
        }
        $allData += [PSCustomObject]@{
            'Type' = ''
            'Field' = ''
            'Value' = ''
            'Description' = ''
        }
        
        # Add exported resources
        foreach ($resource in $detailedResources) {
            $description = if ($resource.Status -eq "Reference") { 
                "REFERENCE ONLY - Imported for dependency references only" 
            } else { 
                "MANAGED - Fully managed by Terraform in $($resource.File)" 
            }
            
            $allData += [PSCustomObject]@{
                'Type' = 'EXPORTED'
                'Field' = $resource.ExportedResource
                'Value' = $resource.ExportedResourceType
                'Description' = $description
            }
        }
        
        # Add imported resources
        foreach ($resource in $importedResources) {
            $allData += [PSCustomObject]@{
                'Type' = 'IMPORTED'
                'Field' = $resource.ImportedResourceName
                'Value' = $resource.ImportedResourceType
                'Description' = "IMPORT REFERENCE - Azure ID: $($resource.AzureResourceId)"
            }
        }
        
        $allData | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8
        Write-Host "CSV report saved: $reportFile" -ForegroundColor Green
        Write-Host "Note: Install ImportExcel module for better Excel format: Install-Module -Name ImportExcel -Force -Scope CurrentUser" -ForegroundColor Gray
    }
    
    # Display Final Export Summary
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host "  [OK] AZURE TO TERRAFORM EXPORT - COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host ('=' * 80) -ForegroundColor Green
    Write-Host ""
    Write-Host "  [*] Export Summary:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Resource Group: $ResourceGroup" -ForegroundColor White
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
    Write-Host ('    Resource Group: ' + $ResourceGroup) -ForegroundColor White
    Write-Host ('    Subscription ID: ' + $SubscriptionId) -ForegroundColor White
    if ($subscriptionName) {
        Write-Host ('    Subscription Name: ' + $subscriptionName) -ForegroundColor White
    }
    Write-Host ""
    Write-Host '  Troubleshooting Recommendations:' -ForegroundColor Yellow
    Write-Host '    1. Review the error message above for specific details' -ForegroundColor White
    Write-Host '    2. Verify your Azure CLI session is still active: az account show' -ForegroundColor Gray
    Write-Host '    3. Check if the resource group still exists: az group show -n $ResourceGroup' -ForegroundColor Gray
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
