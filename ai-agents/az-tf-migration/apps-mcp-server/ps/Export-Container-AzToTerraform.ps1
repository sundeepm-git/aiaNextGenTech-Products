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

# === PARAMETER VALIDATION AND DEBUG LOGGING ===
Write-Host ""
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "  PARAMETER VALIDATION" -ForegroundColor White
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "  SubscriptionId: $SubscriptionId" -ForegroundColor Gray
Write-Host "  ResourceGroupName: $ResourceGroupName" -ForegroundColor Gray
Write-Host "  StorageContainer: $StorageContainer" -ForegroundColor Gray
Write-Host ('=' * 80) -ForegroundColor Cyan

# Validate ResourceGroupName doesn't contain invalid characters or suspicious values
if ($ResourceGroupName -match '[\\/:*?"<>|]') {
    Write-Host ""
    Write-Host "ERROR: ResourceGroupName contains invalid characters: $ResourceGroupName" -ForegroundColor Red
    Write-Host "Valid characters: letters, numbers, hyphens, underscores, periods, and parentheses" -ForegroundColor Yellow
    exit 1
}

# Warn if ResourceGroupName looks suspicious
$suspiciousNames = @('container', 'test', 'temp', 'tmp', 'sandbox', 'sb_')
if ($suspiciousNames -contains $ResourceGroupName.ToLower()) {
    Write-Host ""
    Write-Host "WARNING: ResourceGroupName '$ResourceGroupName' looks suspicious!" -ForegroundColor Yellow
    Write-Host "Are you sure this is the correct Azure Resource Group name?" -ForegroundColor Yellow
    Write-Host "Common mistake: passing execution mode or test value instead of actual RG name" -ForegroundColor Yellow
    Write-Host ""
}

# === CONTAINER COMPATIBILITY SETUP ===
# Set environment variables for headless execution in Linux containers
$env:NO_COLOR = "1"
$env:TERM = "dumb"
$env:AZURE_EXTENSION_QUIET = "true"
$env:AZURE_CORE_NO_COLOR = "true"
$env:AZURE_CORE_OUTPUT = "json"

# Detect if running in container
$isContainer = $env:RUNNING_IN_CONTAINER -eq "true" -or (Test-Path "/.dockerenv")
if ($isContainer) {
    Write-Host "Running in container mode" -ForegroundColor Cyan
}

# Try to load .env file from script directory or parent directory
$envLocations = @(
    (Join-Path $PSScriptRoot ".env"),
    (Join-Path (Split-Path $PSScriptRoot -Parent) ".env"),
    ".env"
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
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$exportRoot = Join-Path $repoRoot "azure-export"
$subscriptionDir = Join-Path $exportRoot -ChildPath $subscriptionName
$exportDir = Join-Path $subscriptionDir -ChildPath $ResourceGroupName

# Debug logging for directory paths
Write-Host ""
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "  DIRECTORY STRUCTURE" -ForegroundColor White
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "  Script Directory: $scriptDir" -ForegroundColor Gray
Write-Host "  Repo Root: $repoRoot" -ForegroundColor Gray
Write-Host "  Export Root: $exportRoot" -ForegroundColor Gray  
Write-Host "  Subscription Directory: $subscriptionDir" -ForegroundColor Gray
Write-Host "  Target Export Directory: $exportDir" -ForegroundColor Green
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ""

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
    # 1. Environment Guardrails
    $env:NO_COLOR = "1"
    $env:TERM = "xterm"
    $env:AZURE_EXTENSION_QUIET = "true"
    $global:globalSuccess = $true 

    # 2. Setup Master Directory
    $absoluteExportDir = [System.IO.Path]::GetFullPath($exportDir)
    if (Test-Path $absoluteExportDir) {
        Get-ChildItem -Path $absoluteExportDir -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $absoluteExportDir -Force | Out-Null
    
    # Initialize Master Files
    $masterMainTf = Join-Path $absoluteExportDir "main.tf"
    $masterProviderTf = Join-Path $absoluteExportDir "provider.tf"
    "# Generated Terraform Configuration`n" | Out-File -FilePath $masterMainTf -Encoding UTF8 -Force

    # Helper function to remove terraform/provider/import blocks with proper brace counting
    function Remove-TerraformBlocks {
        param([string]$text)
        
        $lines = $text -split "`r?`n"
        $result = @()
        $inBlock = $false
        $blockType = ''
        $braceCount = 0
        
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            
            # Check if starting a block to remove (terraform, provider, import)
            if ($line -match '^\s*(terraform|import)\s*\{' -or $line -match '^\s*provider\s+"[^"]+"\s*\{') {
                $inBlock = $true
                $blockType = $matches[1]
                $braceCount = 1
                continue
            }
            
            if ($inBlock) {
                # Count braces
                $openBraces = ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                $closeBraces = ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                $braceCount += $openBraces - $closeBraces
                
                # End of block when braces balance
                if ($braceCount -le 0) {
                    $inBlock = $false
                    $blockType = ''
                    $braceCount = 0
                }
                continue
            }
            
            # Keep non-block lines
            $result += $line
        }
        
        return ($result -join "`n")
    }

    # Initialize tracking for HTML report
    $exportedResourcesList = @()
    $exportSuccessCount = 0
    $exportFailureCount = 0

    # 3. RESOURCE LOOP (Sandboxed Mode)
    Write-Host "Starting Export Job (Sandbox Mode)..." -ForegroundColor Cyan
    $exportCount = 0

    foreach ($resource in $exportableResources) {
        $exportCount++
        Write-Host "[$exportCount/$($exportableResources.Count)] Processing: $($resource.name)" -ForegroundColor Yellow

        # Create a unique sandbox for this specific resource
        $sandboxPath = Join-Path $absoluteExportDir "sb_$($exportCount)"
        New-Item -ItemType Directory -Path $sandboxPath -Force | Out-Null

        # Generate meaningful Terraform resource name from Azure resource name
        $terraformResourceName = $resource.name -replace '[^a-zA-Z0-9_]', '_'

        $argList = @(
            "resource",
            "--subscription-id", $SubscriptionId,
            "--output-dir", $sandboxPath,  # Export to sandbox
            "--non-interactive",
            "--log-level", "Panic",
            "--name", $terraformResourceName  # Use meaningful name instead of res-0
        )
        $argList += $resource.id

        # Create environment hashtable for child process
        $exportEnv = @{
            'NO_COLOR' = '1'
            'TERM' = 'dumb'
            'AZURE_EXTENSION_QUIET' = 'true'
            'AZURE_CORE_NO_COLOR' = 'true'
            'PATH' = $env:PATH
        }
        
        # Preserve Azure authentication
        if ($env:AZURE_CLIENT_ID) { $exportEnv['AZURE_CLIENT_ID'] = $env:AZURE_CLIENT_ID }
        if ($env:AZURE_CLIENT_SECRET) { $exportEnv['AZURE_CLIENT_SECRET'] = $env:AZURE_CLIENT_SECRET }
        if ($env:AZURE_TENANT_ID) { $exportEnv['AZURE_TENANT_ID'] = $env:AZURE_TENANT_ID }
        if ($env:AZURE_SUBSCRIPTION_ID) { $exportEnv['AZURE_SUBSCRIPTION_ID'] = $env:AZURE_SUBSCRIPTION_ID }
        
        # Detect container environment
        $isContainer = ($env:RUNNING_IN_CONTAINER -eq 'true') -or ($env:EXECUTION_MODE -eq 'CONTAINER')
        
        # Run aztfexport with explicit environment
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        
        if ($isContainer) {
            # Container: Write command to temp script file, then execute via BASH directly
            # We REMOVED the 'script' command wrapper as it swallows arguments in Alpine/Linux containers
            
            $tempScript = Join-Path $sandboxPath "run-aztfexport.sh"
            
            # Build clean bash script
            # Note: We build the command string manually to ensure arguments are passed correctly
            $cmdParts = @("aztfexport")
            foreach ($arg in $argList) {
                # Wrap every argument in single quotes to prevent shell expansion issues
                $cmdParts += "'$arg'"
            }
            $fullCmd = $cmdParts -join " "

            # Create the bash script content
            $scriptContent = "#!/bin/bash`ncd `"$sandboxPath`"`n$fullCmd"
            Set-Content -Path $tempScript -Value $scriptContent -Encoding UTF8 -NoNewline
            
            # Make executable
            & chmod +x $tempScript

            # Execute directly with bash (No 'timeout' command needed here, standard Process wait handles it)
            $psi.FileName = '/bin/bash'
            $psi.Arguments = "'$tempScript'"
        }
        
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true  # Redirect stdin and close it immediately
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        # Set environment variables
        foreach ($key in $exportEnv.Keys) {
            $psi.EnvironmentVariables[$key] = $exportEnv[$key]
        }
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        
        # Use event handlers to consume output asynchronously (prevents buffer deadlock)
        $outputBuilder = New-Object System.Text.StringBuilder
        $errorBuilder = New-Object System.Text.StringBuilder
        
        $outputHandler = {
            if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
                $Event.MessageData.AppendLine($EventArgs.Data) | Out-Null
            }
        }
        
        $errorHandler = {
            if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
                $Event.MessageData.AppendLine($EventArgs.Data) | Out-Null
            }
        }
        
        $outputEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $outputHandler -MessageData $outputBuilder
        $errorEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $errorHandler -MessageData $errorBuilder
        
        $process.Start() | Out-Null
        
        # Close stdin immediately to signal no input is available
        $process.StandardInput.Close()
        
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        
        # Wait with timeout (5 minutes per resource)
        $timeoutMs = 300000  # 5 minutes
        if (-not $process.WaitForExit($timeoutMs)) {
            Write-Host "   ! Warning: Export timeout for $($resource.name) - killing process" -ForegroundColor Yellow
            $process.Kill()
            $timedOut = $true
        } else {
            $timedOut = $false
        }
        
        # Cleanup event handlers
        Unregister-Event -SourceIdentifier $outputEvent.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $errorEvent.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $outputEvent.Id -Force -ErrorAction SilentlyContinue
        Remove-Job -Id $errorEvent.Id -Force -ErrorAction SilentlyContinue
        
        # Debug: Always show output in container mode to diagnose issues
        if ($env:RUNNING_IN_CONTAINER -eq 'true') {
            Write-Host "   DEBUG: Exit code: $($process.ExitCode)" -ForegroundColor Magenta
            $stdoutText = $outputBuilder.ToString()
            $stderrText = $errorBuilder.ToString()
            
            if ($stdoutText) {
                Write-Host "   DEBUG: aztfexport stdout:" -ForegroundColor Magenta
                $stdoutPreview = $stdoutText.Substring(0, [Math]::Min(1000, $stdoutText.Length))
                Write-Host "   $($stdoutPreview.Replace("`n", "`n   "))" -ForegroundColor Gray
            }
            
            if ($stderrText) {
                Write-Host "   DEBUG: aztfexport stderr:" -ForegroundColor Magenta
                $stderrPreview = $stderrText.Substring(0, [Math]::Min(1000, $stderrText.Length))
                Write-Host "   $($stderrPreview.Replace("`n", "`n   "))" -ForegroundColor Gray
            }
        }
        
        if ($timedOut) {
            Write-Host "   ! Export timed out after 5 minutes" -ForegroundColor Red
        } elseif ($process.ExitCode -ne 0) {
            Write-Host "   ! Warning: aztfexport exited with code $($process.ExitCode) for $($resource.name)" -ForegroundColor Yellow
            $errorOutput = $errorBuilder.ToString()
            if ($errorOutput) {
                Write-Host "   Error: $($errorOutput.Substring(0, [Math]::Min(200, $errorOutput.Length)))" -ForegroundColor Gray
            }
            
            # Debug: Show full output in container
            if ($env:RUNNING_IN_CONTAINER -eq 'true') {
                $stdoutText = $outputBuilder.ToString()
                if ($stdoutText) {
                    Write-Host "   DEBUG: aztfexport stdout (first 500 chars):" -ForegroundColor Magenta
                    Write-Host "   $($stdoutText.Substring(0, [Math]::Min(500, $stdoutText.Length)).Replace("`n", "`n   "))" -ForegroundColor Gray
                }
            }
        }
        
        Start-Sleep -Seconds 2 # Allow disk commit

        # 4. CONSOLIDATE FROM SANDBOX
        $genFiles = Get-ChildItem -Path $sandboxPath -Filter "*.tf" -ErrorAction SilentlyContinue
        
        # Debug: Show what files were generated
        if ($env:RUNNING_IN_CONTAINER -eq 'true') {
            Write-Host "   DEBUG: Sandbox path: $sandboxPath" -ForegroundColor Magenta
            Write-Host "   DEBUG: Checking for *.tf files..." -ForegroundColor Magenta
            
            # Show all files in sandbox (not just .tf)
            $allFiles = Get-ChildItem -Path $sandboxPath -ErrorAction SilentlyContinue
            if ($allFiles) {
                Write-Host "   DEBUG: All files in sandbox:" -ForegroundColor Magenta
                foreach ($f in $allFiles) {
                    Write-Host "   DEBUG:   - $($f.Name) ($($f.Length) bytes)" -ForegroundColor Gray
                }
            } else {
                Write-Host "   DEBUG: No files found in sandbox directory!" -ForegroundColor Red
            }
            
            Write-Host "   DEBUG: .tf files count: $($genFiles.Count)" -ForegroundColor Magenta
        }
        
        if ($genFiles -and $genFiles.Count -gt 0) {
            foreach ($file in $genFiles) {
                try {
                    $content = Get-Content $file.FullName -Raw -ErrorAction Stop
                    
                    if ([string]::IsNullOrWhiteSpace($content)) {
                        Write-Host "   ! Warning: Empty file $($file.Name)" -ForegroundColor Yellow
                        continue
                    }
                    
                    # Extract and save provider block (first occurrence only)
                    if (-not (Test-Path $masterProviderTf)) {
                        if ($content -match '(?s)provider\s+"azurerm"\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}') {
                            $providerBlock = $matches[0]
                            $providerBlock | Out-File -FilePath $masterProviderTf -Encoding UTF8 -Force
                            Write-Host "   ✓ Extracted provider block" -ForegroundColor Green
                        }
                    }

                    # Remove terraform, provider, import blocks - preserve only resource and data blocks
                    $clean = $content
                    
                    # Debug: Show what we're working with (first 500 chars)
                    if ($env:RUNNING_IN_CONTAINER -eq 'true') {
                        $preview = $content.Substring(0, [Math]::Min(500, $content.Length))
                        Write-Host "   DEBUG: File content preview (before cleanup):" -ForegroundColor Magenta
                        Write-Host "   $($preview.Replace("`n", "`n   "))" -ForegroundColor Gray
                    }
                    
                    # Remove blocks using brace counting (function defined at script level)
                    $clean = Remove-TerraformBlocks -text $clean
                    
                    # Debug: Show what's left after cleanup
                    if ($env:RUNNING_IN_CONTAINER -eq 'true') {
                        Write-Host "   DEBUG: Content after cleanup (length: $($clean.Length)):" -ForegroundColor Magenta
                        if ($clean.Length -gt 0) {
                            $cleanPreview = $clean.Substring(0, [Math]::Min(500, $clean.Length))
                            Write-Host "   $($cleanPreview.Replace("`n", "`n   "))" -ForegroundColor Gray
                        } else {
                            Write-Host "   (empty)" -ForegroundColor Red
                        }
                    }
                    
                    # Remove any orphaned terraform config lines
                    $clean = $clean -replace '(?m)^\s*subscription_id\s*=.*$', ''
                    $clean = $clean -replace '(?m)^\s*resource_group_name\s*=.*$', ''
                    # Clean up excessive whitespace
                    $clean = $clean -replace '(`r?`n){3,}', "`n`n"

                    if ($clean.Trim()) {
                        "`n# --- Resource: $($resource.name) ---`n$($clean.Trim())" | Out-File -FilePath $masterMainTf -Append -Encoding UTF8
                        Write-Host "   ✓ Merged" -ForegroundColor Green
                        
                        # Track successful export
                        $exportSuccessCount++
                        $exportedResourcesList += [PSCustomObject]@{
                            Name = $resource.name
                            Type = $resource.type
                            Status = 'Success'
                        }
                    } else {
                        Write-Host "   ! Warning: No resource content after cleanup for $($resource.name)" -ForegroundColor Yellow
                        $exportFailureCount++
                        $exportedResourcesList += [PSCustomObject]@{
                            Name = $resource.name
                            Type = $resource.type
                            Status = 'Failed - No content'
                        }
                    }
                } catch {
                    Write-Host "   ! Error processing $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            
            # Merge state file if it exists (don't overwrite, merge resources)
            $stateFile = Join-Path $sandboxPath "terraform.tfstate"
            if (Test-Path $stateFile) {
                try {
                    $stateDestination = Join-Path $absoluteExportDir "terraform.tfstate"
                    
                    if (Test-Path $stateDestination) {
                        # Merge with existing state file
                        $existingState = Get-Content $stateDestination -Raw | ConvertFrom-Json
                        $newState = Get-Content $stateFile -Raw | ConvertFrom-Json
                        
                        # Merge resources arrays
                        if ($newState.resources) {
                            if (-not $existingState.resources) {
                                $existingState.resources = @()
                            }
                            $existingState.resources += $newState.resources
                        }
                        
                        # Write merged state
                        $existingState | ConvertTo-Json -Depth 100 | Set-Content $stateDestination -Encoding UTF8
                        Write-Host "   ✓ Merged state file" -ForegroundColor Green
                    } else {
                        # First state file, just copy
                        Copy-Item $stateFile $stateDestination -Force -ErrorAction Stop
                        Write-Host "   ✓ Created state file" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "   ! Warning: Failed to merge state file: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "   ! Warning: No .tf files generated for $($resource.name)" -ForegroundColor Red
            Write-Host "   Check if resource exists and is exportable" -ForegroundColor Yellow
            $exportFailureCount++
            $exportedResourcesList += [PSCustomObject]@{
                Name = $resource.name
                Type = $resource.type
                Status = 'Failed - No files generated'
            }
        }

        # Cleanup Sandbox immediately
        Remove-Item $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # === POST-PROCESSING: Standards Enforcement ===
    Write-Host "`nEnforcing Terraform standards..." -ForegroundColor Cyan
    
    $mainTfPath = Join-Path $absoluteExportDir "main.tf"
    $providerTfPath = Join-Path $absoluteExportDir "provider.tf"
    $dataSourcesTfPath = Join-Path $absoluteExportDir "data-sources.tf"
    $terraformTfPath = Join-Path $absoluteExportDir "terraform.tf"
    $variablesTfPath = Join-Path $absoluteExportDir "variables.tf"
    $outputsTfPath = Join-Path $absoluteExportDir "outputs.tf"

    # Process main.tf
    if (Test-Path $mainTfPath) {
        $mainTfContent = Get-Content $mainTfPath -Raw
        
        # Remove ALL terraform and import blocks using brace counting
        $mainTfContent = Remove-TerraformBlocks -text $mainTfContent
        
        # Extract provider blocks to separate file (if not already created during merge)
        if (-not (Test-Path $providerTfPath)) {
            # Extract provider blocks line by line with brace counting
            $lines = $mainTfContent -split "`r?`n"
            $providerBlocks = @()
            $inProvider = $false
            $currentBlock = @()
            $braceCount = 0
            
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                
                if ($line -match '^\s*provider\s+"[^"]+"\s*\{') {
                    $inProvider = $true
                    $currentBlock = @($line)
                    $braceCount = 1
                    continue
                }
                
                if ($inProvider) {
                    $currentBlock += $line
                    $openBraces = ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                    $closeBraces = ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
                    $braceCount += $openBraces - $closeBraces
                    
                    if ($braceCount -le 0) {
                        $providerBlocks += ($currentBlock -join "`n")
                        $inProvider = $false
                        $currentBlock = @()
                        $braceCount = 0
                    }
                }
            }
            
            if ($providerBlocks.Count -gt 0) {
                $providerContent = ($providerBlocks -join "`n`n")
                Set-Content -Path $providerTfPath -Value $providerContent -Encoding UTF8
                Write-Host "  Created provider.tf with $($providerBlocks.Count) provider(s)" -ForegroundColor Green
                
                # Remove from main.tf
                $mainTfContent = Remove-TerraformBlocks -text $mainTfContent
            }
        } else {
            # Provider file already created, ensure no provider blocks in main.tf
            $mainTfContent = Remove-TerraformBlocks -text $mainTfContent
        }
        
        # Remove sensitive values
        $mainTfContent = $mainTfContent -replace '(client_secret\s*=\s*"[^"]*")', 'client_secret = "***REMOVED***"'
        $mainTfContent = $mainTfContent -replace '(access_key\s*=\s*"[^"]*")', 'access_key = "***REMOVED***"'
        $mainTfContent = $mainTfContent -replace '(connection_string\s*=\s*"[^"]*")', 'connection_string = "***REMOVED***"'
        $mainTfContent = $mainTfContent -replace '(password\s*=\s*"[^"]*")', 'password = "***REMOVED***"'
        
        # Remove any orphaned config lines that might remain
        $mainTfContent = $mainTfContent -replace '(?m)^\s*subscription_id\s*=.*$', ''
        $mainTfContent = $mainTfContent -replace '(?m)^\s*resource_group_name\s*=.*$', ''
        
        # Clean up multiple blank lines
        $mainTfContent = $mainTfContent -replace '(`r?`n\s*){3,}', "`n`n"
        
        # Ensure content is valid before writing
        if (-not [string]::IsNullOrWhiteSpace($mainTfContent.Trim())) {
            # Validate that we have actual resource blocks, not just comments
            if ($mainTfContent -match 'resource\s+"') {
                Set-Content -Path $mainTfPath -Value $mainTfContent.Trim() -Encoding UTF8
                Write-Host "  Updated main.tf (cleaned up orphaned content)" -ForegroundColor Green
            } else {
                Write-Host "  WARNING: No valid resource blocks found in main.tf after cleanup" -ForegroundColor Yellow
                # Keep the file but add a warning
                "# WARNING: No resource blocks were successfully extracted`n" + $mainTfContent.Trim() | Set-Content -Path $mainTfPath -Encoding UTF8
            }
        } else {
            Write-Host "  WARNING: main.tf would be empty after cleanup - check export logs" -ForegroundColor Red
            "# ERROR: Export produced no valid Terraform resources`n# Check the export logs and verify the resource group has exportable resources" | Set-Content -Path $mainTfPath -Encoding UTF8
        }
    } else {
        Write-Host "  WARNING: main.tf not found at $mainTfPath" -ForegroundColor Yellow
    }

    # Ensure terraform.tf exists with required_providers (always create for consistency)
    $terraformContent = @"
terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
"@
    Set-Content -Path $terraformTfPath -Value $terraformContent -Encoding UTF8
    Write-Host "  Created terraform.tf" -ForegroundColor Green

    # Ensure provider.tf exists (create with default if not present)
    if (-not (Test-Path $providerTfPath)) {
        $providerContent = @"
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
"@
        Set-Content -Path $providerTfPath -Value $providerContent -Encoding UTF8
        Write-Host "  Created provider.tf with default azurerm provider" -ForegroundColor Green
    }

    # Extract data sources from main.tf to data-sources.tf
    if (Test-Path $mainTfPath) {
        $mainContent = Get-Content $mainTfPath -Raw
        
        # Extract all data blocks using improved regex
        $dataPattern = 'data\s+"[^"]+"\s+"[^"]+"\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}'
        $dataBlockMatches = [regex]::Matches($mainContent, $dataPattern)
        
        if ($dataBlockMatches.Count -gt 0) {
            $dataBlocks = @()
            foreach ($match in $dataBlockMatches) {
                $dataBlocks += $match.Value
            }
            
            # Create data-sources.tf with extracted blocks
            $dataSourcesHeader = "# Data Sources`n# Reference existing Azure resources not managed by this configuration`n`n"
            $dataSourcesContent = $dataSourcesHeader + ($dataBlocks -join "`n`n")
            Set-Content -Path $dataSourcesTfPath -Value $dataSourcesContent -Encoding UTF8
            Write-Host "  Created data-sources.tf with $($dataBlocks.Count) data source(s)" -ForegroundColor Green
            
            # Remove data blocks from main.tf
            $mainContent = $mainContent -replace $dataPattern, ''
            $mainContent = $mainContent -replace '(`r?`n\s*){3,}', "`n`n"
            
            if (-not [string]::IsNullOrWhiteSpace($mainContent.Trim())) {
                Set-Content -Path $mainTfPath -Value $mainContent.Trim() -Encoding UTF8
                Write-Host "  Removed data sources from main.tf" -ForegroundColor Green
            }
        } else {
            # No data sources found, create placeholder
            if (-not (Test-Path $dataSourcesTfPath)) {
                $dataSourcesContent = @"
# Data Sources
# Reference existing Azure resources not managed by this configuration
"@
                Set-Content -Path $dataSourcesTfPath -Value $dataSourcesContent -Encoding UTF8
                Write-Host "  Created data-sources.tf (no data sources found)" -ForegroundColor Green
            }
        }
    } else {
        # main.tf doesn't exist, create placeholder data-sources.tf
        if (-not (Test-Path $dataSourcesTfPath)) {
            $dataSourcesContent = @"
# Data Sources
# Reference existing Azure resources not managed by this configuration
"@
            Set-Content -Path $dataSourcesTfPath -Value $dataSourcesContent -Encoding UTF8
            Write-Host "  Created data-sources.tf (placeholder)" -ForegroundColor Green
        }
    }

    # Create variables.tf with all standard variables
    $variablesContent = @"
# Variables
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
"@
    Set-Content -Path $variablesTfPath -Value $variablesContent -Encoding UTF8
    Write-Host "  Created variables.tf" -ForegroundColor Green

    # Create outputs.tf with standard structure
    $outputsContent = @"
# Outputs
# Define outputs for important resource attributes

output "resource_group_name" {
  description = "Name of the resource group"
  value       = var.resource_group_name
}

output "location" {
  description = "Azure region"
  value       = var.location
}

# Add specific resource outputs as needed
# Example:
# output "resource_id" {
#   description = "ID of the resource"
#   value       = azurerm_resource.example.id
# }
"@
    Set-Content -Path $outputsTfPath -Value $outputsContent -Encoding UTF8
    Write-Host "  Created outputs.tf" -ForegroundColor Green

    Write-Host "Standards enforcement completed" -ForegroundColor Green
    
    # Verify all required files exist
    Write-Host "`nVerifying Terraform file structure..." -ForegroundColor Cyan
    $requiredFiles = @("main.tf", "provider.tf", "terraform.tf", "data-sources.tf", "variables.tf", "outputs.tf", "terraform.tfstate")
    $missingFiles = @()
    $existingFiles = @()
    
    foreach ($fileName in $requiredFiles) {
        $filePath = Join-Path $absoluteExportDir $fileName
        if (Test-Path $filePath) {
            $fileSize = (Get-Item $filePath).Length
            $existingFiles += "  ✓ $fileName ($fileSize bytes)"
        } else {
            $missingFiles += "  ✗ $fileName (MISSING)"
        }
    }
    
    foreach ($file in $existingFiles) {
        Write-Host $file -ForegroundColor Green
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-Host "`nMissing files:" -ForegroundColor Yellow
        foreach ($file in $missingFiles) {
            Write-Host $file -ForegroundColor Yellow
        }
    } else {
        Write-Host "`n✓ All required Terraform files created successfully!" -ForegroundColor Green
    }

    # ===========================================
    # AUTOMATED DATA SOURCE GENERATION (moved before HTML report)
    # ===========================================
    Write-Host "`nAnalyzing references..." -ForegroundColor Cyan
    
    try {
        # Read main.tf to find hardcoded Azure resource IDs
        $mainTfPath = Join-Path $absoluteExportDir "main.tf"
        
        if (Test-Path $mainTfPath) {
            $mainTfContent = Get-Content -Path $mainTfPath -Raw -ErrorAction Stop
            
            # Extract all Azure resource IDs
            $resourceIdPattern = '"/subscriptions/[a-f0-9\-]+/resourceGroups/[^/]+/providers/Microsoft\.[^/]+/[^/"]+/[^/"]+(?:/[^/"]+/[^/"]+)*"'
            
            $foundResourceIds = [regex]::Matches($mainTfContent, $resourceIdPattern) | ForEach-Object { $_.Value.Trim('"') } | Select-Object -Unique
            
            if ($foundResourceIds.Count -gt 0) {
                Write-Host "  Found $($foundResourceIds.Count) external resource reference(s)" -ForegroundColor Gray
                
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
                    $dataSourcesPath = Join-Path $absoluteExportDir "data-sources.tf"
                    
                    Set-Content -Path $dataSourcesPath -Value $dataSourcesContent -Encoding UTF8 -ErrorAction Stop
                    Write-Host "  ✓ Created $($generatedDataSources.Count) data source(s)" -ForegroundColor Green
                    
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
                            Write-Host "  ✓ Updated $replacementCount reference(s) in main.tf" -ForegroundColor Green
                        }
                    }
                    catch {
                        Write-Host "  ! Warning: Failed to update main.tf references: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "  No data sources generated (no external references found)" -ForegroundColor Gray
                }
            } else {
                Write-Host "  No external resource references found" -ForegroundColor Gray
            }
        } else {
            Write-Host "  main.tf not found, skipping data source generation" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ! Warning: Data source generation failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # ===========================================
    # GENERATE DETAILED HTML REPORT (Before Upload)
    # ===========================================
    Write-Host "`nGenerating detailed HTML export report..." -ForegroundColor Cyan
    
    $exportEndDateTime = Get-Date
    $exportDuration = $exportEndDateTime - $exportStartDateTime
    $exportStartDate = $exportStartDateTime.ToString("yyyy-MM-dd")
    $exportStartTime = $exportStartDateTime.ToString("HH:mm:ss")
    
    # Get all Terraform files for report
    $tfFiles = Get-ChildItem -Path $absoluteExportDir -Filter "*.tf" -File -ErrorAction SilentlyContinue
    Write-Host "  Found $($tfFiles.Count) .tf files for report" -ForegroundColor Gray
    
    $reportFile = Join-Path $absoluteExportDir "Export-Report-Latest.html"
    
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
    
    # Get file locations for report
    $mainTfPath = Join-Path $absoluteExportDir "main.tf"
    $providerTfPath = Join-Path $absoluteExportDir "provider.tf"
    $terraformTfPath = Join-Path $absoluteExportDir "terraform.tf"
    $dataSourcesTfPath = Join-Path $absoluteExportDir "data-sources.tf"
    $tfstatePath = Join-Path $absoluteExportDir "terraform.tfstate"
    
    # Count resources
    $numExportedResources = $detailedResources.Count
    $numImportedResources = $importedResources.Count
    
    # Group resources by type
    $managedResourcesByType = $detailedResources | Where-Object { $_.Status -eq "Managed" } | Group-Object -Property ExportedResourceType | Select-Object @{Name='ResourceType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
    $referenceResourcesByType = $detailedResources | Where-Object { $_.Status -eq "Reference" } | Group-Object -Property ExportedResourceType | Select-Object @{Name='ResourceType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
    $importedResourcesByType = $importedResources | Group-Object -Property ImportedResourceType | Select-Object @{Name='ResourceType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
    
    # Build HTML Report (Complete detailed version)
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
        .type-count { display: flex; justify-content: space-between; padding: 10px 15px; background: #F8F9FA; margin-bottom: 5px; border-radius: 3px; border-left: 3px solid #4472C4; }
        .type-name { font-weight: 500; color: #333; }
        .type-number { font-weight: bold; color: #4472C4; background: white; padding: 2px 8px; border-radius: 3px; }
        .footer { background: #F8F9FA; padding: 20px 30px; text-align: center; color: #666; font-size: 14px; border-top: 2px solid #E0E0E0; }
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
                    <div class="info-value">$absoluteExportDir</div>
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
                        </tr>
                    </thead>
                    <tbody>
"@
    
    foreach ($resource in $detailedResources) {
        $statusClass = if ($resource.Status -eq "Managed") { "status-managed" } else { "status-reference" }
        
        $htmlContent += @"
                        <tr>
                            <td>$($resource.ExportedResource)</td>
                            <td>$($resource.ExportedResourceType)</td>
                            <td><span class="$statusClass">$($resource.Status)</span></td>
                            <td>$($resource.File)</td>
                        </tr>
"@
    }
    
    $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="footer">
            <p>Report Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>Azure to Terraform Export Tool v2.1</p>
        </div>
    </div>
</body>
</html>
"@
    
    # Save HTML report
    try {
        $htmlContent | Out-File -FilePath $reportFile -Encoding UTF8
        Write-Host "  ✓ Detailed HTML report generated: Export-Report-Latest.html" -ForegroundColor Green
    }
    catch {
        Write-Host "  ! Warning: Failed to create HTML report: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # 5. STORAGE UPLOAD (with error handling)
    Write-Host "`nUploading results to Storage..." -ForegroundColor Cyan
    $blobPath = "$($SubscriptionId)/$($ResourceGroupName)"
    
    $account = $env:storageAccount
    $container = "aztfexport"
    
    if ([string]::IsNullOrEmpty($account)) {
        Write-Host "  ! Warning: storageAccount not configured, skipping upload" -ForegroundColor Yellow
        Write-Host "  Files available at: $absoluteExportDir" -ForegroundColor Cyan
    } else {
        Write-Host "  Account: $account" -ForegroundColor Gray
        Write-Host "  Container: $container" -ForegroundColor Gray
        Write-Host "  Path: $blobPath" -ForegroundColor Gray
        Write-Host "  Source: $absoluteExportDir" -ForegroundColor Gray
        
        try {
            $uploadOutput = az storage blob upload-batch `
                --account-name $account `
                --destination $container `
                --destination-path $blobPath `
                --source $absoluteExportDir `
                --pattern "*" `
                --auth-mode login `
                --overwrite 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Upload completed successfully" -ForegroundColor Green
                Write-Host "  URL: https://$account.blob.core.windows.net/$container/$blobPath/" -ForegroundColor Cyan
            } else {
                Write-Host "  ! Upload failed (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
                Write-Host "  Files still available at: $absoluteExportDir" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "  ! Upload error: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  Files still available at: $absoluteExportDir" -ForegroundColor Cyan
        }
    }
    
    Write-Host "`n=== Export Completed Successfully ===" -ForegroundColor Green
    Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "Resources: $numExportedResources" -ForegroundColor Yellow
    Write-Host "Duration: $('{0:hh\:mm\:ss}' -f $exportDuration)" -ForegroundColor Cyan
    Write-Host "Location: $absoluteExportDir" -ForegroundColor Cyan
    Write-Host "Report: $reportFile" -ForegroundColor Cyan

} catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
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
            $filePath = Join-Path $absoluteExportDir $file
            
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
    Write-Host "=== Post-Processing Complete ===" -ForegroundColor Green
    Write-Host "All Terraform files standardized with headers" -ForegroundColor White
    Write-Host "HTML report already generated before upload" -ForegroundColor White
    Write-Host ""
    
    # Upload exported files to Azure Blob Storage
    # Note: In container mode, upload already happened after post-processing
    # This section is kept for backward compatibility with local/non-container runs
    
    if ($isContainer) {
        Write-Host ""
        Write-Host "Container mode: Upload already completed" -ForegroundColor Gray
    } else {
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
        $envFilePath = Join-Path (Split-Path $scriptDir -Parent) ".env"
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
                
                Import-Module (Join-Path $PSScriptRoot "GitHubHelper.psm1") -Force
                
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
    
    } # End of non-container mode upload
    
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

        # === Standards Enforcement: Post-process Terraform files ===
        $mainTfPath = Join-Path $absoluteExportDir "main.tf"
        $providerTfPath = Join-Path $absoluteExportDir "provider.tf"
        $dataSourcesTfPath = Join-Path $absoluteExportDir "data-sources.tf"


