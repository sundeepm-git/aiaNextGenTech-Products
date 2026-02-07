<#
.SYNOPSIS
    Exports Azure Resource Group resources to Terraform using aztfexport.

.DESCRIPTION
    Accepts a Resource Group name, builds an exclusion list for reference 
    network resources, and runs aztfexport to generate Terraform configuration.
    Uploads results to Azure Blob Storage.
    
    Supports Service Principal authentication via environment variables or
    interactive Azure CLI login.

.PARAMETER SubscriptionId
    The subscription GUID or name that contains the target resource group.

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group to export.

.PARAMETER StorageContainer
    Azure Storage container name (default: aztfexport).

.ENVIRONMENT VARIABLES
    Required:
        storageAccount - Azure Storage account name where exports will be uploaded
        
    Optional (Service Principal Authentication):
        AZURE_CLIENT_ID - Service Principal client ID
        AZURE_CLIENT_SECRET - Service Principal secret
        AZURE_TENANT_ID - Azure AD tenant ID

.AUTHENTICATION
    Service Principal (Recommended for automation):
        Set environment variables before running:
        $env:AZURE_CLIENT_ID = "your-sp-client-id"
        $env:AZURE_CLIENT_SECRET = "your-sp-secret"
        $env:AZURE_TENANT_ID = "your-tenant-id"
        $env:storageAccount = "samcpstorage"
    
    Interactive (Manual login):
        Run 'az login' before executing this script
        Set storage account: $env:storageAccount = "samcpstorage"

.EXAMPLE
    # Using Service Principal
    $env:AZURE_CLIENT_ID = "12345678-1234-1234-1234-123456789012"
    $env:AZURE_CLIENT_SECRET = "your-secret-value"
    $env:AZURE_TENANT_ID = "87654321-4321-4321-4321-210987654321"
    $env:storageAccount = "samcpstorage"
    .\Export-AzToTerraform.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -ResourceGroupName "my-rg"

.EXAMPLE
    # Using Interactive Login
    az login
    $env:storageAccount = "samcpstorage"
    .\Export-AzToTerraform.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -ResourceGroupName "my-rg"

.OUTPUTS
    - Terraform configuration files (.tf)
    - HTML report (Export-Report-Latest.html)
    - Uploaded to Azure Storage
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$StorageContainer = "aztfexport"
)

# Stop on errors
$ErrorActionPreference = "Stop"

# Try to load .env file from script directory or parent directory
$envLocations = @(
    "$PSScriptRoot\.env",
    "$PSScriptRoot\..\.env",
    ".\.env"
)

foreach ($envFile in $envLocations) {
    if (Test-Path $envFile) {
        Write-Host "Loading environment variables from: $envFile" -ForegroundColor Cyan
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Handle inline comments (strip content after ' #' or just '#')
                # Matches "Value #Comment" or "Value#Comment" 
                if ($value -match '^(.*?)\s*#.*$') {
                    $value = $matches[1].Trim()
                }

                # Set process-level environment variable (persists for this process)
                [System.Environment]::SetEnvironmentVariable($name, $value, 'Process')
                # Set PowerShell session variable (immediate visibility)
                Set-Item -Path "env:$name" -Value $value
                # Write-Host "  Loaded: $name" -ForegroundColor DarkGray
            }
        }
        break # Load the first one found
    }
}

# Get Storage Account from environment variable (loaded from .env)
$StorageAccount = $env:storageAccount
if ([string]::IsNullOrWhiteSpace($StorageAccount)) {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: Storage Account Not Configured" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  The 'storageAccount' environment variable is required." -ForegroundColor White
    Write-Host "  It should be defined in the .env file." -ForegroundColor White
    Write-Host ""
    Write-Host "  Example .env entry:" -ForegroundColor Yellow
    Write-Host "    storageAccount=samcpstorage" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}

Write-Host "Storage Account (from .env): $StorageAccount" -ForegroundColor Gray

# Ensure container name is lowercase (Azure Storage requirement)
$StorageContainer = $StorageContainer.ToLower()

Write-Host "Starting Azure to Terraform Export..." -ForegroundColor Cyan

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
try {
    $null = az version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI (az) is not installed or not in PATH."
    }
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

# Check for Service Principal authentication first, then fall back to existing session
Write-Host "Authenticating to Azure..." -ForegroundColor Yellow

$clientId = $env:AZURE_CLIENT_ID
$clientSecret = $env:AZURE_CLIENT_SECRET
$tenantId = $env:AZURE_TENANT_ID

try {
    # Priority 1: Use Service Principal if environment variables are set
    if ($clientId -and $clientSecret -and $tenantId) {
        Write-Host "Using Service Principal authentication..." -ForegroundColor Cyan
        Write-Host "  Client ID: $(Mask-String $clientId)" -ForegroundColor Gray
        Write-Host "  Tenant ID: $(Mask-String $tenantId)" -ForegroundColor Gray
        
        $null = az login --service-principal -u $clientId -p $clientSecret --tenant $tenantId 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Service Principal authentication failed. Verify credentials."
        }
        
        $account = az account show --output json 2>&1 | ConvertFrom-Json
        Write-Host "Service Principal authentication successful!" -ForegroundColor Green
        Write-Host "  Logged in as: $($account.user.name)" -ForegroundColor Gray
        Write-Host "  Tenant: $($account.tenantId)" -ForegroundColor Gray
    }
    # Priority 2: Check if already logged in interactively
    else {
        $accountJson = az account show --output json 2>&1
        if ($LASTEXITCODE -eq 0) {
            $account = $accountJson | ConvertFrom-Json
            Write-Host "Using existing Azure CLI session" -ForegroundColor Green
            Write-Host "  User: $($account.user.name)" -ForegroundColor Gray
            Write-Host "  Tenant: $($account.tenantId)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "TIP: To use Service Principal, set environment variables:" -ForegroundColor Yellow
            Write-Host "  `$env:AZURE_CLIENT_ID = '<client-id>'" -ForegroundColor Gray
            Write-Host "  `$env:AZURE_CLIENT_SECRET = '<secret>'" -ForegroundColor Gray
            Write-Host "  `$env:AZURE_TENANT_ID = '<tenant-id>'" -ForegroundColor Gray
        } else {
            throw "Not authenticated to Azure.`n`nOptions:`n  1. Set environment variables: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID`n  2. Run: az login"
        }
    }
}
catch {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: Azure Authentication Failed" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  For Service Principal authentication:" -ForegroundColor Cyan
    Write-Host "    `$env:AZURE_CLIENT_ID = '<client-id>'" -ForegroundColor Gray
    Write-Host "    `$env:AZURE_CLIENT_SECRET = '<secret>'" -ForegroundColor Gray
    Write-Host "    `$env:AZURE_TENANT_ID = '<tenant-id>'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  For interactive authentication:" -ForegroundColor Cyan
    Write-Host "    az login" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}

# Get subscription name from Azure
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

# ===========================================
# RESOLVE SCRIPT DIRECTORY FIRST
# ===========================================
# Get script directory - handle both direct execution and container scenarios
$scriptDir = if (![string]::IsNullOrWhiteSpace($PSScriptRoot)) { 
    $PSScriptRoot 
} elseif (![string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) { 
    Split-Path -Parent $MyInvocation.MyCommand.Path 
} else { 
    "/app/ps"
}

if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Could not resolve script directory"
}

# Variables
# Use standardized project structure for exports: apps-mcp-server/azure-export/<subscription>/<rg>
# This ensures idempotency and allows the script to detect/clean existing exports
$repoRoot = (Resolve-Path "$scriptDir\..\").Path
$exportRoot = Join-Path $repoRoot "azure-export"
$subscriptionDir = Join-Path $exportRoot -ChildPath $subscriptionName
$exportDir = Join-Path $subscriptionDir -ChildPath $ResourceGroupName

# Check if export directory already exists (from previous run)
if (Test-Path $exportDir) {
    Write-Host "Existing export directory detected. Cleaning up..." -ForegroundColor Yellow
    try {
        Remove-Item -Path $exportDir -Recurse -Force -ErrorAction Stop
        Write-Host "  - Existing directory removed from: $exportDir" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "ERROR: Failed to clean up existing export directory: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Create output directory (matching Original-Export-AzToTerraform.ps1 behavior)
Write-Host "Creating export directory..." -ForegroundColor Yellow
try {
    # Ensure parent structure exists
    if (-not (Test-Path $subscriptionDir)) {
        New-Item -Path $subscriptionDir -ItemType Directory -Force | Out-Null
        Write-Host "Created subscription directory: $subscriptionDir" -ForegroundColor Green
    }
    
    # Create the export directory (empty) - this is critical for aztfexport to work without prompts
    New-Item -Path $exportDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Host "Created export directory: $exportDir" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to create export directory: $exportDir" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

# ===========================================
# EXCLUDED RESOURCES CONFIGURATION
# ===========================================
# Define resources to exclude from Terraform export
# These are typically monitoring, diagnostic, security, and reference network resources
# that shouldn't be managed by Terraform or are managed centrally

# Create the exclusion file for aztfexport to use
$excludeFile = Join-Path $repoRoot "exclude.json"

# Aligned with Original-Export-AzToTerraform.ps1
# Comprehensive list of resources to exclude (Shared Network, Monitoring, Security)
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

# Write default excludes to file if it doesn't exist or update it
Set-Content -Path $excludeFile -Value $excludeContent -Encoding UTF8
Write-Host "Exclusion file updated at: $excludeFile" -ForegroundColor Gray

# Define array for script logic usage (matching the content above)
$excludeResources = $excludeContent -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

# Validate storage account parameter
if ([string]::IsNullOrEmpty($StorageAccount)) {
    throw "StorageAccount parameter is required. Pass -StorageAccount or set storageAccount environment variable"
}

# Display Export Start Banner
Write-Host ""
Write-Host "=== Azure to Terraform Export ===" -ForegroundColor Cyan
Write-Host "Subscription: $subscriptionName" -ForegroundColor White
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Storage: $StorageAccount/$StorageContainer" -ForegroundColor Gray
Write-Host "Excluding $($excludeResources.Count) resource types" -ForegroundColor Gray
Write-Host ""

# Validate resource group exists
try {
    $rgJson = az group show --name $ResourceGroupName --subscription $SubscriptionId --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Resource group not found: $ResourceGroupName"
    }
    $rgInfo = $rgJson | ConvertFrom-Json
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
Write-Host "Analyzing resources..." -ForegroundColor Cyan

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
    
    Write-Host "Found $resourceCount resources" -ForegroundColor Green
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
# Maps Azure API types to Terraform resource types for pre-filtering before aztfexport
# This prevents aztfexport from attempting to import resources that require special permissions
$azureToTerraformMap = @{
    # Container Apps & Storage
    "Microsoft.App/containerApps" = "azurerm_container_app"
    "Microsoft.App/managedEnvironments" = "azurerm_container_app_environment"
    "Microsoft.ContainerRegistry/registries" = "azurerm_container_registry"
    "Microsoft.Storage/storageAccounts" = "azurerm_storage_account"
    "Microsoft.OperationalInsights/workspaces" = "azurerm_log_analytics_workspace"
    
    # Monitoring & Insights
    "Microsoft.Insights/diagnosticSettings" = "azurerm_monitor_diagnostic_setting"
    "Microsoft.Insights/actionGroups" = "azurerm_monitor_action_group"
    "Microsoft.Insights/metricAlerts" = "azurerm_monitor_metric_alert"
    "Microsoft.Insights/activityLogAlerts" = "azurerm_monitor_activity_log_alert"
    "Microsoft.Insights/workbooks" = "azurerm_application_insights_workbook"
    "Microsoft.Insights/components" = "azurerm_application_insights"
    
    # Log Analytics & Operations Management
    "Microsoft.OperationalInsights/workspaces/linkedServices" = "azurerm_log_analytics_linked_service"
    "Microsoft.OperationalInsights/workspaces/dataSources" = "azurerm_log_analytics_datasource_windows_event"
    "Microsoft.OperationsManagement/solutions" = "azurerm_log_analytics_solution"
    
    # Security Center & Sentinel
    "Microsoft.Security/pricings" = "azurerm_security_center_subscription_pricing"
    "Microsoft.Security/securityContacts" = "azurerm_security_center_contact"
    "Microsoft.Security/workspaceSettings" = "azurerm_security_center_workspace"
    "Microsoft.SecurityInsights/alertRules" = "azurerm_sentinel_alert_rule"
    "Microsoft.SecurityInsights/automationRules" = "azurerm_sentinel_automation_rule"
    "Microsoft.SecurityInsights/dataConnectors" = "azurerm_sentinel_data_connector"
    "Microsoft.SecurityInsights/watchlists" = "azurerm_sentinel_watchlist"
    
    # Authorization & Governance
    "Microsoft.Authorization/roleAssignments" = "azurerm_role_assignment"
    "Microsoft.Authorization/roleDefinitions" = "azurerm_role_definition"
    "Microsoft.Authorization/policyAssignments" = "azurerm_policy_assignment"
    "Microsoft.Authorization/policyDefinitions" = "azurerm_policy_definition"
    "Microsoft.Authorization/policySetDefinitions" = "azurerm_policy_set_definition"
    "Microsoft.Authorization/locks" = "azurerm_management_lock"
    "Microsoft.Management/managementGroups" = "azurerm_management_group"
    
    # Network Resources
    "Microsoft.Network/virtualNetworks" = "azurerm_virtual_network"
    "Microsoft.Network/virtualNetworks/subnets" = "azurerm_subnet"
    "Microsoft.Network/networkSecurityGroups" = "azurerm_network_security_group"
    "Microsoft.Network/networkSecurityGroups/securityRules" = "azurerm_network_security_rule"
    "Microsoft.Network/networkInterfaces" = "azurerm_network_interface"
    "Microsoft.Network/publicIPAddresses" = "azurerm_public_ip"
    "Microsoft.Network/loadBalancers" = "azurerm_lb"
    "Microsoft.Network/loadBalancers/backendAddressPools" = "azurerm_lb_backend_address_pool"
    "Microsoft.Network/loadBalancers/probes" = "azurerm_lb_probe"
    "Microsoft.Network/loadBalancers/inboundNatRules" = "azurerm_lb_nat_rule"
    "Microsoft.Network/routeTables" = "azurerm_route_table"
    "Microsoft.Network/routeTables/routes" = "azurerm_route"
    "Microsoft.Network/applicationGateways" = "azurerm_application_gateway"
    "Microsoft.Network/azureFirewalls" = "azurerm_firewall"
    "Microsoft.Network/firewallPolicies" = "azurerm_firewall_policy"
    "Microsoft.Network/bastionHosts" = "azurerm_bastion_host"
    "Microsoft.Network/privateEndpoints" = "azurerm_private_endpoint"
    "Microsoft.Network/privateLinkServices" = "azurerm_private_link_service"
    "Microsoft.Network/natGateways" = "azurerm_nat_gateway"
    "Microsoft.Network/virtualNetworkGateways" = "azurerm_virtual_network_gateway"
    "Microsoft.Network/localNetworkGateways" = "azurerm_local_network_gateway"
    "Microsoft.Network/vpnGateways" = "azurerm_vpn_gateway"
    "Microsoft.Network/applicationSecurityGroups" = "azurerm_application_security_group"
}

# Check if there are any exportable resources
$excludeList = $excludeResources

if ($resources) {
    # Separate resources into exportable and excluded
    $exportableResources = @()
    $excludedResources = @()
    foreach ($resource in $resources) {
        $azureType = $resource.type
        $terraformType = $azureToTerraformMap[$azureType]
        
        # Match Original script logic: Only exclude if there's a terraform mapping AND it's in the exclusion list
        if ($terraformType -and $excludeList -contains $terraformType) {
            $excludedResources += $resource
        } else {
            $exportableResources += $resource
        }
    }
    # Check exclusion summary
    if ($excludedResources.Count -gt 0) {
        Write-Host "Excluded $($excludedResources.Count) resources, exporting $($exportableResources.Count)" -ForegroundColor Yellow
    } else {
        Write-Host "Exporting all $($exportableResources.Count) resources" -ForegroundColor Green
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
        Write-Host "Ready to export $($exportableResources.Count) resources" -ForegroundColor Green
    }
}

    # Run aztfexport
    Write-Host ""
    Write-Host "Running aztfexport..." -ForegroundColor Cyan
    try {
        # Check if aztfexport is available
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

        # Verify export directory is truly empty before running aztfexport
        $dirContents = Get-ChildItem -Path $exportDir -Force -ErrorAction SilentlyContinue
        if ($dirContents) {
            Write-Host "WARNING: Export directory is not empty! Contents:" -ForegroundColor Yellow
            $dirContents | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
            Write-Host "Cleaning directory again..." -ForegroundColor Yellow
            Remove-Item -Path "$exportDir\*" -Recurse -Force
        }
        Write-Host "Export directory verified empty: $exportDir" -ForegroundColor Green

        # Export resources individually for speed, then consolidate files
        Write-Host "Exporting $($exportableResources.Count) resources individually..." -ForegroundColor Cyan
        $exportCount = 0
        
        foreach ($resource in $exportableResources) {
            $exportCount++
            $resourceName = $resource.name
            $resourceId = $resource.id
            
            Write-Host "[$exportCount/$($exportableResources.Count)] Exporting: $resourceName" -ForegroundColor Yellow
            
            # Export each resource (creates/appends to files)
            if ($exportCount -eq 1) {
                # First resource: create base directory and files
                aztfexport resource `
                    --subscription-id $SubscriptionId `
                    --output-dir $exportDir `
                    --non-interactive `
                    $resourceId 2>&1 | Out-Null
            } else {
                # Subsequent resources: append to existing files
                aztfexport resource `
                    --subscription-id $SubscriptionId `
                    --output-dir $exportDir `
                    --non-interactive `
                    --append `
                    $resourceId 2>&1 | Out-Null
            }
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Success" -ForegroundColor Green
            } else {
                    Write-Host "  ✗ Failed" -ForegroundColor Red
                    Write-Host "    Error: $($Error[0])" -ForegroundColor Yellow
            }
        }
        
        # Consolidate .aztfexport files into main.tf
        Write-Host ""
        Write-Host "Consolidating Terraform files..." -ForegroundColor Cyan
        
        $mainTfPath = Join-Path $exportDir "main.tf"
        $mainContent = ""
        
        # Read main.tf if it exists
        if (Test-Path $mainTfPath) {
            $mainContent = Get-Content $mainTfPath -Raw
        }
        
        # Find and merge all .aztfexport files
        $aztfexportFiles = Get-ChildItem -Path $exportDir -Filter "*.aztfexport.tf" -ErrorAction SilentlyContinue
        foreach ($file in $aztfexportFiles) {
            $content = Get-Content $file.FullName -Raw
            $mainContent += "`n`n" + $content
            Remove-Item $file.FullName -Force
            Write-Host "  Merged: $($file.Name)" -ForegroundColor Gray
        }
        
        # Write consolidated main.tf
        if ($mainContent) {
            Set-Content -Path $mainTfPath -Value $mainContent.Trim() -Force
            Write-Host "  ✓ Consolidated all resources into main.tf" -ForegroundColor Green
        }
        
        $LASTEXITCODE = 0

        # Check if command succeeded
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host ('=' * 80) -ForegroundColor Red
            Write-Host "  EXPORT FAILED - aztfexport Error" -ForegroundColor Red
            Write-Host ('=' * 80) -ForegroundColor Red
            Write-Host ""
            Write-Host "  Export Details:" -ForegroundColor White
            Write-Host "    Resource Group: $ResourceGroupName" -ForegroundColor White
            Write-Host "    Subscription: $subscriptionName" -ForegroundColor White
            Write-Host "    Exit Code: $LASTEXITCODE" -ForegroundColor White
            Write-Host ""
            Write-Host ('=' * 80) -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "Export completed successfully!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: aztfexport execution failed" -ForegroundColor Red
        Write-Host "$($_.Exception.Message)" -ForegroundColor Yellow
        exit 1
    }
    
    # ===========================================
    # AUTOMATED DATA SOURCE GENERATION
    # ===========================================
    Write-Host "Analyzing references..." -ForegroundColor Cyan
    
    try {
        # Read main.tf to find hardcoded Azure resource IDs
        $mainTfPath = Join-Path $exportDir "main.tf"
        
        if (-not (Test-Path $mainTfPath)) {
            throw "main.tf not found"
        }
        
        $mainTfContent = Get-Content -Path $mainTfPath -Raw -ErrorAction Stop
        
        # Extract all Azure resource IDs
        $resourceIdPattern = '"/subscriptions/[a-f0-9\-]+/resourceGroups/[^/]+/providers/Microsoft\.[^/]+/[^/"]+/[^/"]+(?:/[^/"]+/[^/"]+)*"'
        
        $foundResourceIds = [regex]::Matches($mainTfContent, $resourceIdPattern) | ForEach-Object { $_.Value.Trim('"') } | Select-Object -Unique
        
        if ($foundResourceIds.Count -gt 0) {
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
                                }
                            }
                        }
                    }
                    catch {
                        # Continue processing other resource IDs
                        continue
                    }
                }
                
                # Create data-sources.tf file if we generated any data sources
                if ($generatedDataSources.Count -gt 0) {
                    $dataSourcesPath = Join-Path $exportDir "data-sources.tf"
                    
                    Set-Content -Path $dataSourcesPath -Value $dataSourcesContent -Encoding UTF8 -ErrorAction Stop
                    Write-Host "Created $($generatedDataSources.Count) data sources" -ForegroundColor Green
                    
                    # Update main.tf to replace hardcoded IDs with data source references
                    
                    try {
                        $updatedMainTf = $mainTfContent
                        $replacementCount = 0
                        
                        foreach ($replacement in $dataSourceReplacements.GetEnumerator()) {
                            if ($updatedMainTf -match [regex]::Escape($replacement.Key)) {
                                $updatedMainTf = $updatedMainTf -replace [regex]::Escape($replacement.Key), $replacement.Value
                                $replacementCount++
                            }
                        }
                        
                        if ($replacementCount -gt 0) {
                            Set-Content -Path $mainTfPath -Value $updatedMainTf -Encoding UTF8 -ErrorAction Stop
                            Write-Host "Updated $replacementCount references in main.tf" -ForegroundColor Green
                        }
                    }
                    catch {
                        Write-Host "Warning: Could not update main.tf with data source references" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "No external references found" -ForegroundColor Gray
                }
            }
    }
    catch {
        Write-Host "Warning: Data source generation failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # ===========================================
    # ADD HEADERS TO ALL GENERATED TERRAFORM FILES
    # ===========================================
    Write-Host "Adding file headers..." -ForegroundColor Cyan
    
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
                    
                    if ($currentContent -notmatch "# FILE:") {
                        $header = Get-TerraformFileHeader -FileName $file -Description $fileDescriptions[$file]
                        $newContent = $header + $currentContent
                        Set-Content -Path $filePath -Value $newContent -Encoding UTF8
                    }
                }
                catch {
                    # Silently continue on header addition errors
                }
            }
        }
    }
    catch {
        Write-Host "Warning: Could not add headers" -ForegroundColor Yellow
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
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure to Terraform Export Report - $ResourceGroupName</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #F5F5F5; color: #333; line-height: 1.6; }
        .container { max-width: 1400px; margin: 0 auto; background: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px 30px; text-align: center; }
        .header h1 { font-size: 32px; margin-bottom: 10px; font-weight: 600; }
        .header p { font-size: 16px; opacity: 0.9; }
        .content { padding: 30px; }
        .section { margin-bottom: 40px; background: white; border-radius: 8px; }
        .section-title { background: #F8F9FA; padding: 15px 20px; font-size: 20px; font-weight: bold; color: #2E5090; border-left: 5px solid #4472C4; margin-bottom: 20px; border-radius: 4px; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .info-item { background: #F8F9FA; padding: 15px; border-radius: 5px; border-left: 3px solid #4472C4; }
        .info-label { font-weight: bold; color: #2E5090; font-size: 14px; margin-bottom: 5px; }
        .info-value { color: #333; font-size: 16px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; box-shadow: 0 4px 15px rgba(0,0,0,0.1); transition: transform 0.3s; }
        .stat-card:hover { transform: translateY(-5px); }
        .stat-number { font-size: 36px; font-weight: bold; margin-bottom: 5px; }
        .stat-label { font-size: 14px; opacity: 0.9; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); border-radius: 8px; overflow: hidden; }
        table thead { background: #4472C4; color: white; }
        table th { padding: 12px; text-align: left; font-weight: 600; font-size: 14px; }
        table tbody tr { border-bottom: 1px solid #E0E0E0; transition: background 0.2s; }
        table tbody tr:hover { background: #F5F5F5; }
        table tbody tr:last-child { border-bottom: none; }
        table td { padding: 12px; font-size: 13px; }
        .status-managed { background: #28A745; color: white; padding: 4px 12px; border-radius: 4px; font-size: 11px; font-weight: bold; display: inline-block; }
        .status-reference { background: #FFC107; color: #333; padding: 4px 12px; border-radius: 4px; font-size: 11px; font-weight: bold; display: inline-block; }
        .success { background-color: #dff6dd; color: #107c10; font-weight: bold; padding: 8px; }
        .warning { background-color: #fff4ce; color: #795e00; font-weight: bold; padding: 8px; }
        .neutral { background-color: #f3f2f1; color: #323130; padding: 8px; }
        .type-count { display: flex; justify-content: space-between; padding: 10px 15px; background: #F8F9FA; margin-bottom: 5px; border-radius: 3px; border-left: 3px solid #4472C4; }
        .type-name { font-weight: 500; color: #333; }
        .type-number { font-weight: bold; color: #4472C4; background: white; padding: 2px 8px; border-radius: 3px; }
        .footer { background: #F8F9FA; padding: 20px 30px; text-align: center; color: #666; font-size: 14px; border-top: 2px solid #E0E0E0; }
        .highlight-box { background: #E3F2FD; border-left: 4px solid #2196F3; padding: 15px; margin: 15px 0; border-radius: 4px; }
        .file-list { list-style: none; padding-left: 0; }
        .file-list li { background: #F8F9FA; padding: 10px 15px; margin-bottom: 8px; border-left: 3px solid #4472C4; border-radius: 3px; }
        .file-status { color: #28A745; font-weight: bold; }
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
        Write-Host "Report generated: Export-Report-Latest.html" -ForegroundColor Green
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
    Write-Host "Uploading to Azure Storage..." -ForegroundColor Cyan
    
    # Get storage account resource group from environment variable or use default
    $StorageAccountRG = if ([string]::IsNullOrEmpty($env:storageAccountRG)) { $ResourceGroupName } else { $env:storageAccountRG }
    
    # Verify Azure CLI is logged in
    $azAccount = az account show 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Not logged in to Azure CLI. Run: az login" -ForegroundColor Red
        return
    }
    
    # Check if storage account exists and is accessible
    $storageCheck = az storage account show --name $StorageAccount --resource-group $StorageAccountRG 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Cannot access storage account '$StorageAccount' in RG '$StorageAccountRG'" -ForegroundColor Red
        return
    }
    
    # Check if container exists, create if it doesn't
    $containerExists = az storage container exists --account-name $StorageAccount --name $StorageContainer --auth-mode login 2>&1 | ConvertFrom-Json
    
    if ($containerExists.exists -eq $false) {
        Write-Host "Creating container..." -ForegroundColor Gray
        $createResult = az storage container create --account-name $StorageAccount --name $StorageContainer --auth-mode login 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to create container" -ForegroundColor Red
            return
        }
    }
    
    # Clean up old HTML reports from blob storage
    try {
        $blobPrefix = "$SubscriptionId/$ResourceGroupName/"
        $existingBlobs = az storage blob list --account-name $StorageAccount --container-name $StorageContainer --prefix $blobPrefix --auth-mode login --query "[?contains(name, '.html')].name" -o json 2>&1 | ConvertFrom-Json
        
        if ($existingBlobs -and $existingBlobs.Count -gt 0) {
            foreach ($blobName in $existingBlobs) {
                az storage blob delete --account-name $StorageAccount --container-name $StorageContainer --name $blobName --auth-mode login 2>&1 | Out-Null
            }
        }
    } catch {
        # Continue with upload even if cleanup fails
    }
    
    try {
        # Get all files in export directory, excluding .terraform directory
        $filesToUpload = Get-ChildItem -Path $exportDir -File -Recurse | Where-Object { 
            $_.FullName -notlike "*\.terraform\*"
        }
        
        $uploadCount = 0
        $failedUploads = @()
        
        if ($filesToUpload.Count -eq 0) {
            Write-Host "WARNING: No files found to upload" -ForegroundColor Yellow
            return
        }
        
        Write-Host "Uploading $($filesToUpload.Count) files..." -ForegroundColor Gray
        
        foreach ($file in $filesToUpload) {
            # Calculate relative path for blob name
            $relativePath = $file.FullName.Substring($exportDir.Length + 1)
            $blobName = "$SubscriptionId/$ResourceGroupName/$relativePath".Replace('\', '/')
            
            # Upload file to blob storage
            az storage blob upload --account-name $StorageAccount --container-name $StorageContainer --name $blobName --file $file.FullName --auth-mode login --overwrite true 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                $uploadCount++
            } else {
                $failedUploads += $relativePath
            }
        }
        
        Write-Host ""
        if ($failedUploads.Count -gt 0) {
            Write-Host "Upload completed with errors: $uploadCount of $($filesToUpload.Count) files" -ForegroundColor Yellow
        } else {
            Write-Host "Successfully uploaded $uploadCount files" -ForegroundColor Green
        }
        
        Write-Host "Storage: https://$StorageAccount.blob.core.windows.net/$StorageContainer/$SubscriptionId/$ResourceGroupName/" -ForegroundColor Cyan
        
        # Check if GitHub output is also enabled
        $envFilePath = Join-Path $scriptDir "..\.env"
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
        
        # Clean up temp directory disabled to match Original behavior (keep local artifacts)
        # if ($failedUploads.Count -eq 0) {
        #     Write-Host ""
        #     Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
        #     Remove-Item -Path $exportDir -Recurse -Force -ErrorAction SilentlyContinue
        #     Write-Host "Temp files cleaned up" -ForegroundColor Green
        # } else {
        #     Write-Host "Keeping temporary files due to upload failures" -ForegroundColor Yellow
        #     Write-Host "Location: $exportDir" -ForegroundColor White
        # }
        
        Write-Host "Local files available at: $exportDir" -ForegroundColor Cyan
        
    }
    catch {
        Write-Host "WARNING: Upload failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Files available at: $exportDir" -ForegroundColor Gray
    }
    
    # Display Final Export Summary
    Write-Host ""
    Write-Host "=== Export Completed Successfully ===" -ForegroundColor Green
    Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "Resources Exported: $numExportedResources" -ForegroundColor Yellow
    Write-Host "Duration: $('{0:hh\:mm\:ss}' -f $exportDuration)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. terraform init" -ForegroundColor Gray
    Write-Host "  2. terraform validate" -ForegroundColor Gray
    Write-Host "  3. terraform plan" -ForegroundColor Gray
    Write-Host ""

