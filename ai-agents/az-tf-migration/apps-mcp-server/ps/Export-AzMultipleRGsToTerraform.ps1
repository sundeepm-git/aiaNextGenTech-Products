<#
.SYNOPSIS
    Exports multiple Azure Resource Groups to Terraform using aztfexport.

.DESCRIPTION
    Accepts multiple Resource Group names and a Subscription ID, builds an exclusion list 
    for shared reference resources, and runs aztfexport for each group.
    
    Includes automated post-processing:
    - Generates data-sources.tf for referenced external resources
    - Refactors main.tf to use data source references
    - Adds standardized headers to all files
    - Generates a comprehensive Multi-Tab Excel Report with charts

.PARAMETER ResourceGroups
    An array of Azure Resource Group names to export.

.PARAMETER SubscriptionId
    The subscription GUID or name that contains the target resource groups.

.EXAMPLE
    .\Export-AzMultipleRGsToTerraform.ps1 -ResourceGroups "rg-app1", "rg-app2" -SubscriptionId "00000000-0000-0000-0000-000000000000"
<<<<<<< HEAD
=======

.EXAMPLE
    .\Export-AzMultipleRGsToTerraform.ps1 -ResourceGroups @("rg-web", "rg-api", "rg-data") -SubscriptionId "12345678-1234-1234-1234-123456789abc"
>>>>>>> 126fa371d2e6b65f92d428feb51e83a360003ca9
#>

param (
    [Parameter(Mandatory = $true)]
    [string[]]$ResourceGroups,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

# Stop on errors mostly, but we handle per-RG errors manually
$ErrorActionPreference = "Stop"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Get-TerraformFileHeader {
    param (
        [string]$FileName,
        [string]$Description,
        [string]$GeneratedBy = "Azure Export Script"
    )
    
    $currentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Try to get current user information
    try {
        $currentUser = $env:USERNAME
        $currentUserEmail = (az account show --query "user.name" -o tsv 2>$null)
        if ($currentUserEmail) { $GeneratedBy = "$currentUser ($currentUserEmail)" }
        else { $GeneratedBy = $currentUser }
    } catch { $GeneratedBy = "Automated Export" }
    
    return @"
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
# ==============================================================================

"@
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$exportStartDate = Get-Date -Format "yyyy-MM-dd"
$exportStartTime = Get-Date -Format "HH:mm:ss"
$exportStartDateTime = Get-Date

# ==============================================================================
# PREREQUISITE VALIDATION
# ==============================================================================

# Validate Azure CLI
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

# Check aztfexport
Write-Host "Checking aztfexport installation..." -ForegroundColor Yellow
if (-not (Get-Command aztfexport -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host "  ERROR: aztfexport Not Found" -ForegroundColor Red
    Write-Host ('=' * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "  aztfexport command is required but not found." -ForegroundColor White
    Write-Host ""
    Write-Host "  To install aztfexport:" -ForegroundColor Yellow
    Write-Host "    Windows: winget install aztfexport" -ForegroundColor Gray
    Write-Host "    Or visit: https://github.com/Azure/aztfexport" -ForegroundColor Gray
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Red
    exit 1
}
Write-Host "aztfexport found" -ForegroundColor Green

# Check ImportExcel
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "Installing ImportExcel module (required for reporting)..." -ForegroundColor Yellow
    try {
        Install-Module -Name ImportExcel -Force -Scope CurrentUser -ErrorAction Stop
        Write-Host "ImportExcel module installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Could not install ImportExcel module." -ForegroundColor Yellow
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host "Falling back to console output only..." -ForegroundColor Yellow
    }
}
$useExcel = (Get-Module -ListAvailable -Name ImportExcel)

# Get Subscription Info
try {
    $subInfoJson = az account show --subscription $SubscriptionId --output json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Login failed or bad Subscription ID" }
    $subInfo = $subInfoJson | ConvertFrom-Json
    $subscriptionName = $subInfo.name
    Write-Host "Subscription: $subscriptionName ($SubscriptionId)" -ForegroundColor Green
}
catch {
    Write-Error "Subscription access failed: $($_.Exception.Message)"
    exit 1
}


# Setup Paths
# Always use the root of the repo for azure-export, not the ps subfolder
$repoRoot = Split-Path -Parent $PSScriptRoot
$baseExportDir = Join-Path $repoRoot "azure-export" | Join-Path -ChildPath $subscriptionName | Join-Path -ChildPath "multi-$subscriptionName"
$excludeFile = Join-Path $repoRoot "exclude.json"

# Ensure base export directory exists
if (-not (Test-Path $baseExportDir)) {
    New-Item -Path $baseExportDir -ItemType Directory -Force | Out-Null
}

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

# Display Export Start Banner
Write-Host ""
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "  AZURE TO TERRAFORM MULTI-RG EXPORT - STARTED" -ForegroundColor Cyan
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Exporting Azure Subscription: $subscriptionName" -ForegroundColor White
Write-Host "     --> Resource Groups ($($ResourceGroups.Count)):" -ForegroundColor Yellow
foreach ($rg in $ResourceGroups) {
    Write-Host "         - $rg" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  2. Export Start Date: $exportStartDate" -ForegroundColor White
Write-Host "     Export Start Time: $exportStartTime" -ForegroundColor White
Write-Host ""
Write-Host "  3. Base Export Directory: $baseExportDir" -ForegroundColor White
Write-Host ""
Write-Host "  4. Exclusion File: $excludeFile" -ForegroundColor White
Write-Host "     Excluded Resource Types:" -ForegroundColor Gray
$excludeContent -split "`n" | ForEach-Object { if ($_.Trim()) { Write-Host "       - $($_.Trim())" -ForegroundColor DarkGray } }
Write-Host ""
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ""

# Report Data Container
$globalReportData = @{
    Results = @()
    AllDetailedResources = @()
    AllImportedResources = @()
}

# ==============================================================================
# MAIN PROCESSING LOOP - RESOURCE GROUP BY RESOURCE GROUP
# ==============================================================================

$currentRGIndex = 0
foreach ($rg in $ResourceGroups) {
    $currentRGIndex++
    $sanitizedRGName = $rg -replace '[^a-zA-Z0-9_-]', '_'
    $exportDir = Join-Path $baseExportDir $sanitizedRGName
    $rgLogPrefix = "[$currentRGIndex/$($ResourceGroups.Count)] [$rg]"
    
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Cyan
    Write-Host "  PROCESSING $rgLogPrefix" -ForegroundColor Cyan
    Write-Host ('=' * 80) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Resource Group: $rg" -ForegroundColor White
    Write-Host "     Subscription: $subscriptionName" -ForegroundColor White
    Write-Host ""
    
    # Display resource count before export
    Write-Host "  2. Fetching resources from Azure..." -ForegroundColor Yellow
    try {
        $resourcesJson = az resource list --resource-group $rg --subscription $SubscriptionId --output json 2>&1
        if ($LASTEXITCODE -eq 0) {
            $resources = $resourcesJson | ConvertFrom-Json
            $resourceCount = $resources.Count
            Write-Host "     Found $resourceCount resources in resource group" -ForegroundColor Green
            Write-Host ""
            Write-Host "     Resources by Type:" -ForegroundColor Cyan
            $resourcesByType = $resources | Group-Object -Property type | Sort-Object Count -Descending
            foreach ($group in $resourcesByType) {
                Write-Host "       $($group.Name): $($group.Count)" -ForegroundColor White
            }
            Write-Host ""
        }
    } catch {
        Write-Host "     Warning: Could not fetch resource count" -ForegroundColor Yellow
    }
    
    Write-Host "  3. Starting aztfexport..." -ForegroundColor Yellow
    Write-Host ""

    $rgResult = [PSCustomObject]@{
        ResourceGroup = $rg
        Status = "Pending"
        ErrorCategory = ""
        ErrorMessage = ""
        OutputFolder = $exportDir
        ResourceCount = 0
        ManagedCount = 0
        ReferenceCount = 0
    }

    try {
        # 1. Clean Directory
        if (Test-Path $exportDir) {
            Write-Host "Cleaning existing directory..." -ForegroundColor Gray
            Remove-Item -Path $exportDir -Recurse -Force -ErrorAction Stop
        }
        New-Item -Path $exportDir -ItemType Directory -Force | Out-Null

        # 2. Check RG Existence
        $rgExists = az group show --name $rg --subscription $SubscriptionId --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Resource Group '$rg' not found or not accessible."
        }

        # 3. Run aztfexport
        Write-Host "Running export..." -ForegroundColor Yellow
        $output = & aztfexport rg `
            --subscription-id $SubscriptionId `
            --output-dir $exportDir `
            --exclude-terraform-resource-file $excludeFile `
            --non-interactive `
            $rg 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "aztfexport failed. Output: $output"
        }

        # 4. CRITICAL: Convert excluded resources to data sources
        Write-Host ""
        Write-Host "  4. Converting shared infrastructure to data sources..." -ForegroundColor Cyan
        
        $mainTfPath = Join-Path $exportDir "main.tf"
        if (Test-Path $mainTfPath) {
            try {
                $mainTfContent = Get-Content -Path $mainTfPath -Raw -ErrorAction Stop
                $excludedTypes = $excludeContent -split "`n" | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }
                $dataSourcesPath = Join-Path $exportDir "data-sources.tf"
                $convertedResources = @()
                $updatedMainContent = $mainTfContent
                
                foreach ($excludedType in $excludedTypes) {
                    # Find resource blocks of excluded types in main.tf
                    $pattern = 'resource\s+"' + [regex]::Escape($excludedType) + '"\s+"([^"]+)"\s+\{([^\}]*(?:\{[^\}]*\}[^\}]*)*)\}'
                    $matches = [regex]::Matches($mainTfContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                    
                    foreach ($match in $matches) {
                        $resourceLabel = $match.Groups[1].Value
                        $resourceBody = $match.Groups[2].Value
                        
                        # Extract name and resource_group_name from resource body
                        $nameMatch = [regex]::Match($resourceBody, 'name\s*=\s*"([^"]+)"')
                        $rgMatch = [regex]::Match($resourceBody, 'resource_group_name\s*=\s*"([^"]+)"')
                        
                        if ($nameMatch.Success -and $rgMatch.Success) {
                            $resName = $nameMatch.Groups[1].Value
                            $resRG = $rgMatch.Groups[1].Value
                            
                            # Generate data source block
                            $dataSourceName = $resName -replace '[^a-zA-Z0-9_]', '_'
                            $dataSourceBlock = @"

# Reference existing $excludedType`: $resName (converted from resource to data source)
data "$excludedType" "$dataSourceName" {
  name                = "$resName"
  resource_group_name = "$resRG"
}
"@
                            $convertedResources += @{
                                Type = $excludedType
                                Label = $resourceLabel
                                Name = $resName
                                DataSourceName = $dataSourceName
                                DataSourceBlock = $dataSourceBlock
                            }
                            
                            Write-Host "     Converting: $excludedType.$resourceLabel -> data.$excludedType.$dataSourceName" -ForegroundColor Yellow
                        }
                    }
                }
                
                if ($convertedResources.Count -gt 0) {
                    # Remove resource blocks from main.tf
                    foreach ($res in $convertedResources) {
                        $pattern = 'resource\s+"' + [regex]::Escape($res.Type) + '"\s+"' + [regex]::Escape($res.Label) + '"\s+\{[^\}]*(?:\{[^\}]*\}[^\}]*)*\}\s*'
                        $updatedMainContent = [regex]::Replace($updatedMainContent, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
                        
                        # Replace references in main.tf: resource_type.label.id -> data.resource_type.data_name.id
                        $oldRef = "$($res.Type)\.$($res.Label)\."
                        $newRef = "data.$($res.Type).$($res.DataSourceName)."
                        $updatedMainContent = $updatedMainContent -replace [regex]::Escape($oldRef), $newRef
                    }
                    
                    # Save updated main.tf
                    Set-Content -Path $mainTfPath -Value $updatedMainContent -Encoding UTF8 -NoNewline
                    
                    # Create or append to data-sources.tf
                    $dataHeader = Get-TerraformFileHeader -FileName "data-sources.tf" -Description "Data sources for shared Azure infrastructure referenced by this configuration. These resources are managed outside Terraform and are referenced as read-only."
                    $allDataBlocks = ($convertedResources | ForEach-Object { $_.DataSourceBlock }) -join "`n"
                    
                    if (Test-Path $dataSourcesPath) {
                        $existingData = Get-Content -Path $dataSourcesPath -Raw
                        Set-Content -Path $dataSourcesPath -Value ($existingData + "`n" + $allDataBlocks) -Encoding UTF8 -NoNewline
                    } else {
                        Set-Content -Path $dataSourcesPath -Value ($dataHeader + "`n" + $allDataBlocks) -Encoding UTF8 -NoNewline
                    }
                    
                    Write-Host "     Converted $($convertedResources.Count) shared resources to data sources" -ForegroundColor Green
                    Write-Host "     Updated main.tf to reference data sources instead" -ForegroundColor Green
                } else {
                    Write-Host "     No shared infrastructure resources found in export" -ForegroundColor Gray
                }
            } catch {
                Write-Host "     Warning: Failed to convert shared resources: $_" -ForegroundColor Yellow
            }
        }

        # 5. Post-Process - Analyze External Resource References
        Write-Host ""
        Write-Host "  5. Analyzing external resource references..." -ForegroundColor Cyan
        
        $mainTfPath = Join-Path $exportDir "main.tf"
        $generatedDataSources = @()
        
        if (-not (Test-Path $mainTfPath)) {
            Write-Host "     Warning: main.tf not found. Skipping data source generation." -ForegroundColor Yellow
        }
        else {
            try {
                $mainTfContent = Get-Content -Path $mainTfPath -Raw -ErrorAction Stop
                
                # Extract all Azure resource IDs (pattern: /subscriptions/.../resourceGroups/.../providers/...)
                $resourceIdPattern = '"/subscriptions/[a-f0-9\-]+/resourceGroups/[^/]+/providers/Microsoft\.[^/]+/[^/"]+/[^/"]+(?:/[^/"]+/[^/"]+)*"'
                $foundResourceIds = [regex]::Matches($mainTfContent, $resourceIdPattern) | ForEach-Object { $_.Value.Trim('"') } | Select-Object -Unique
                
                if ($foundResourceIds.Count -gt 0) {
                    Write-Host "     Found $($foundResourceIds.Count) external resource references" -ForegroundColor Yellow
                    
                    # Parse resource IDs and generate data sources
                    $dataSourcesContent = Get-TerraformFileHeader -FileName "data-sources.tf" -Description "Data sources for external Azure resources referenced by this configuration. These resources are managed outside this Terraform state and are referenced as read-only."
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
                                        Write-Host "       - Generated data source: $terraformType.$dataSourceName" -ForegroundColor Gray
                                    }
                                }
                            }
                        }
                        catch {
                            Write-Host "       Warning: Could not parse resource ID: $resourceId" -ForegroundColor Yellow
                            continue
                        }
                    }
                    
                    # Create data-sources.tf file if we generated any data sources
                    if ($generatedDataSources.Count -gt 0) {
                        $dataSourcesPath = Join-Path $exportDir "data-sources.tf"
                        
                        try {
                            Set-Content -Path $dataSourcesPath -Value $dataSourcesContent -Encoding UTF8 -ErrorAction Stop
                            Write-Host ""
                            Write-Host "     Created data-sources.tf with $($generatedDataSources.Count) data sources" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "     Warning: Could not create data-sources.tf file" -ForegroundColor Yellow
                        }
                        
                        # Update main.tf to replace hardcoded IDs with data source references
                        Write-Host "     Updating main.tf to use data sources..." -ForegroundColor Cyan
                        
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
                                    continue
                                }
                            }
                            
                            if ($replacementCount -gt 0) {
                                Set-Content -Path $mainTfPath -Value $updatedMainTf -Encoding UTF8 -ErrorAction Stop
                                Write-Host "     Updated $replacementCount resource references to use data sources" -ForegroundColor Green
                            }
                        }
                        catch {
                            Write-Host "     Warning: Could not update main.tf with data source references" -ForegroundColor Yellow
                        }
                    }
                }
                else {
                    Write-Host "     No external resource references found" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "     Warning: Automated data source generation failed" -ForegroundColor Yellow
                Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Gray
            }
        }
        
        # --- Add Headers to Terraform Files ---
        Write-Host ""
        Write-Host "  6. Adding standardized headers to Terraform files..." -ForegroundColor Cyan
        Get-ChildItem -Path $exportDir -Filter "*.tf" | ForEach-Object {
            $h = Get-TerraformFileHeader -FileName $_.Name -Description "Automated Export for Resource Group: $rg"
            $c = Get-Content $_.FullName -Raw
            if ($c -notmatch "# FILE:") { Set-Content $_.FullName -Value ($h + $c) -Encoding UTF8 }
        }
        Write-Host "     Terraform files prepared successfully" -ForegroundColor Green

        # 7. Collect Data for Report
        Write-Host ""
        Write-Host "  7. Collecting resource information..." -ForegroundColor Cyan
        $tfFiles = Get-ChildItem -Path $exportDir -Filter "*.tf"
        $rgManagedCount = 0
        $rgReferenceCount = 0
        
        foreach ($file in $tfFiles) {
            $content = Get-Content $file.FullName -Raw
            
            # Count Managed Resources (terraform-managed via resource blocks)
            [regex]::Matches($content, 'resource\s+"([^"]+)"\s+"([^"]+)"') | ForEach-Object {
                $rgManagedCount++
                $globalReportData.AllDetailedResources += [PSCustomObject]@{
                    ResourceGroup = $rg
                    Status = "Managed"
                    ResourceType = $_.Groups[1].Value
                    ResourceName = $_.Groups[2].Value
                    File = $file.Name
                }
            }
            
            # Count Referenced Resources (read-only via data source blocks)
            [regex]::Matches($content, 'data\s+"([^"]+)"\s+"([^"]+)"') | ForEach-Object {
                $rgReferenceCount++
                $globalReportData.AllImportedResources += [PSCustomObject]@{
                    ResourceGroup = $rg
                    Status = "Reference"
                    ResourceType = $_.Groups[1].Value
                    ResourceName = $_.Groups[2].Value
                    File = $file.Name
                }
            }
        }

        $rgResult.Status = "Success"
        $rgResult.ResourceCount = ($rgManagedCount + $rgReferenceCount)
        $rgResult.ManagedCount = $rgManagedCount
        $rgResult.ReferenceCount = $rgReferenceCount
        
        Write-Host ""
        Write-Host "  [OK] EXPORT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Export Details:" -ForegroundColor Cyan
        Write-Host "    Resource Group: $rg" -ForegroundColor White
        Write-Host "    Managed Resources: $rgManagedCount" -ForegroundColor White
        Write-Host "    Referenced Resources: $rgReferenceCount" -ForegroundColor White
        Write-Host "    Output Directory: $exportDir" -ForegroundColor White
        Write-Host ""
        Write-Host "  [OK] Azure resources have been successfully exported to Terraform!" -ForegroundColor Green
        Write-Host ""

    }
    catch {
        $msg = $_.Exception.Message
        Write-Host "Failed: $msg" -ForegroundColor Red
        
        $rgResult.Status = "Failed"
        $rgResult.ErrorMessage = $msg
        
        # Categorize Error
        if ($msg -match "not found") { $rgResult.ErrorCategory = "Azure (Not Found)" }
        elseif ($msg -match "permission|authorization") { $rgResult.ErrorCategory = "Permission" }
        elseif ($msg -match "aztfexport") { $rgResult.ErrorCategory = "Tool (aztfexport)" }
        elseif ($msg -match "network") { $rgResult.ErrorCategory = "Network" }
        else { $rgResult.ErrorCategory = "Technical/Other" }
    }

    $globalReportData.Results += $rgResult
}

# ==============================================================================
# DISPLAY SUMMARY ON CONSOLE
# ==============================================================================

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "EXPORT SUMMARY - RESOURCE GROUP BREAKDOWN" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host ""

foreach ($result in $globalReportData.Results) {
    if ($result.Status -eq "Success") {
        Write-Host "  [$($result.ResourceGroup)]" -ForegroundColor Cyan -NoNewline
        Write-Host " - Status: " -NoNewline
        Write-Host "SUCCESS" -ForegroundColor Green -NoNewline
        Write-Host " | Managed: " -NoNewline
        Write-Host "$($result.ManagedCount)" -ForegroundColor Yellow -NoNewline
        Write-Host " | Referenced: " -NoNewline
        Write-Host "$($result.ReferenceCount)" -ForegroundColor Cyan
    }
    else {
        Write-Host "  [$($result.ResourceGroup)]" -ForegroundColor Cyan -NoNewline
        Write-Host " - Status: " -NoNewline
        Write-Host "FAILED" -ForegroundColor Red -NoNewline
        Write-Host " | Category: " -NoNewline
        Write-Host "$($result.ErrorCategory)" -ForegroundColor Magenta
        Write-Host "    Error: $($result.ErrorMessage)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "TOTALS FOR SUBSCRIPTION: $subscriptionName" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green

$totalSuccessRGs = @($globalReportData.Results | Where-Object Status -eq "Success").Count
$totalFailedRGs = @($globalReportData.Results | Where-Object Status -eq "Failed").Count
$totalManagedAll = ($globalReportData.Results | Measure-Object -Property ManagedCount -Sum).Sum
$totalReferenceAll = ($globalReportData.Results | Measure-Object -Property ReferenceCount -Sum).Sum

Write-Host "  Total Resource Groups Processed: " -NoNewline
Write-Host "$($globalReportData.Results.Count)" -ForegroundColor White
Write-Host "  Successful Exports: " -NoNewline
Write-Host "$totalSuccessRGs" -ForegroundColor Green
Write-Host "  Failed Exports: " -NoNewline
Write-Host "$totalFailedRGs" -ForegroundColor Red
Write-Host ""
Write-Host "  Total Managed Resources (Exported): " -NoNewline
Write-Host "$totalManagedAll" -ForegroundColor Yellow
Write-Host "  Total Referenced Resources (Data Sources): " -NoNewline
Write-Host "$totalReferenceAll" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host ""

# ==============================================================================
# REPORT GENERATION (EXCEL)
# ==============================================================================

if ($useExcel) {
    try {
        Write-Host ""
        Write-Host "Generating Professional Excel Report..." -ForegroundColor Cyan

        $exportEndDate = Get-Date -Format "yyyy-MM-dd"
        $exportEndTime = Get-Date -Format "HH:mm:ss"
        $duration = (New-TimeSpan -Start $exportStartDateTime -End (Get-Date)).ToString("hh\:mm\:ss")
        $reportFileName = "Multi-Export-Report-$SubscriptionId-$timestamp.xlsx"
        $reportPath = Join-Path $baseExportDir $reportFileName

        # Calculate aggregated metrics
        $measureManaged = $globalReportData.Results | Measure-Object -Property ManagedCount -Sum
        $totalManaged = if ($measureManaged) { $measureManaged.Sum } else { 0 }
        
        $measureRef = $globalReportData.Results | Measure-Object -Property ReferenceCount -Sum
        $totalRef = if ($measureRef) { $measureRef.Sum } else { 0 }
        
        $totalFailed = @($globalReportData.Results | Where-Object Status -eq "Failed").Count
        $totalSuccess = @($globalReportData.Results | Where-Object Status -eq "Success").Count

        # ==================================================================
        # BUILD SUMMARY DATA ARRAY
        # ==================================================================
        $summaryData = @()
        
        # Section 1: Export Information
        $summaryData += [PSCustomObject]@{ Section='HEADER'; Metric=''; Value='' }
        $summaryData += [PSCustomObject]@{ Section='EXPORT INFORMATION'; Metric=''; Value='' }
        $summaryData += [PSCustomObject]@{ Section='INFO'; Metric='Subscription ID'; Value=$SubscriptionId }
        $summaryData += [PSCustomObject]@{ Section='INFO'; Metric='Subscription Name'; Value=$subscriptionName }
        $summaryData += [PSCustomObject]@{ Section='INFO'; Metric='Resource Groups'; Value=($ResourceGroups -join ", ") }
        $summaryData += [PSCustomObject]@{ Section='INFO'; Metric='Export Date'; Value=$exportStartDate }
        $summaryData += [PSCustomObject]@{ Section='INFO'; Metric='Export Start Time'; Value=$exportStartTime }
        $summaryData += [PSCustomObject]@{ Section='INFO'; Metric='Export End Time'; Value=$exportEndTime }
        $summaryData += [PSCustomObject]@{ Section='INFO'; Metric='Duration'; Value=$duration }
        $summaryData += [PSCustomObject]@{ Section='INFO'; Metric='Total RGs Processed'; Value=$globalReportData.Results.Count }
        $summaryData += [PSCustomObject]@{ Section='SEPARATOR'; Metric=''; Value='' }
        
        # Section 2: Resource Summary
        $summaryData += [PSCustomObject]@{ Section='RESOURCE SUMMARY'; Metric=''; Value='' }
        $summaryData += [PSCustomObject]@{ Section='SUMMARY'; Metric='Managed Resources (Exported)'; Value=$totalManaged }
        $summaryData += [PSCustomObject]@{ Section='SUMMARY'; Metric='Referenced Resources (Data Sources)'; Value=$totalRef }
        $summaryData += [PSCustomObject]@{ Section='SUMMARY'; Metric='Successful Migrations'; Value=$totalSuccess }
        $summaryData += [PSCustomObject]@{ Section='SUMMARY'; Metric='Failed Migrations'; Value=$totalFailed }
        $summaryData += [PSCustomObject]@{ Section='SEPARATOR'; Metric=''; Value='' }
        
        # Section 3: Resource Group Status
        $summaryData += [PSCustomObject]@{ Section='RG STATUS'; Metric='Resource Group'; Value='Status | Managed | Referenced | Error' }
        foreach ($res in $globalReportData.Results) {
            if ($res.Status -eq "Success") {
                $statusLine = "[OK] SUCCESS | $($res.ManagedCount) | $($res.ReferenceCount) | N/A"
            } else {
                $statusLine = "[FAILED] N/A | N/A | N/A | $($res.ErrorCategory): $($res.ErrorMessage)"
            }
            $summaryData += [PSCustomObject]@{ Section='RG_DETAIL'; Metric=$res.ResourceGroup; Value=$statusLine }
        }
        
        # Export Summary Data - Create file first
        Write-Host "  Creating Summary worksheet..." -ForegroundColor Yellow
        $summaryData | Export-Excel -Path $reportPath -WorksheetName "Summary" -TableStyle Medium2 -AutoSize
        
        # ==================================================================
        # BUILD DETAILS DATA ARRAY
        # ==================================================================
        $detailData = @()
        
        # MANAGED RESOURCES SECTION
        $detailData += [PSCustomObject]@{ Section='HEADER'; ResourceGroup=''; DetailType=''; ResourceName=''; ResourceType=''; File='' }
        $detailData += [PSCustomObject]@{ Section='MANAGED'; ResourceGroup='MANAGED RESOURCES (EXPORTED TO TERRAFORM)'; DetailType=''; ResourceName=''; ResourceType=''; File='' }
        $detailData += [PSCustomObject]@{ Section='HEADER_ROW'; ResourceGroup='Resource Group'; DetailType='Status'; ResourceName='Resource Name'; ResourceType='Type'; File='File' }
        
        # Add Managed Resources
        if ($globalReportData.AllDetailedResources -and $globalReportData.AllDetailedResources.Count -gt 0) {
            foreach ($item in $globalReportData.AllDetailedResources) {
                $detailData += [PSCustomObject]@{
                    Section='MANAGED_DATA'
                    ResourceGroup=$item.ResourceGroup
                    DetailType=$item.Status
                    ResourceName=$item.ResourceName
                    ResourceType=$item.ResourceType
                    File=$item.File
                }
            }
        }
        
        # Separator row
        $detailData += [PSCustomObject]@{ Section='SEPARATOR'; ResourceGroup=''; DetailType=''; ResourceName=''; ResourceType=''; File='' }
        
        # REFERENCED RESOURCES SECTION
        $detailData += [PSCustomObject]@{ Section='REFERENCED'; ResourceGroup='REFERENCED RESOURCES (DATA SOURCES - READ ONLY)'; DetailType=''; ResourceName=''; ResourceType=''; File='' }
        $detailData += [PSCustomObject]@{ Section='HEADER_ROW'; ResourceGroup='Resource Group'; DetailType='Status'; ResourceName='Resource Name'; ResourceType='Type'; File='File' }
        
        # Add Referenced Resources
        if ($globalReportData.AllImportedResources -and $globalReportData.AllImportedResources.Count -gt 0) {
            foreach ($item in $globalReportData.AllImportedResources) {
                $detailData += [PSCustomObject]@{
                    Section='REFERENCED_DATA'
                    ResourceGroup=$item.ResourceGroup
                    DetailType=$item.Status
                    ResourceName=$item.ResourceName
                    ResourceType=$item.ResourceType
                    File=$item.File
                }
            }
        }
        
        # Separator row
        $detailData += [PSCustomObject]@{ Section='SEPARATOR'; ResourceGroup=''; DetailType=''; ResourceName=''; ResourceType=''; File='' }
        
        # FAILURE SECTION
        $detailData += [PSCustomObject]@{ Section='FAILURE'; ResourceGroup='FAILURE RESOURCE GROUPS'; DetailType=''; ResourceName=''; ResourceType=''; File='' }
        $detailData += [PSCustomObject]@{ Section='FAILURE_HEADER'; ResourceGroup='Resource Group Name'; DetailType='Failure Cause'; ResourceName='Resolution Steps'; ResourceType=''; File='' }
        
        foreach ($res in ($globalReportData.Results | Where-Object Status -eq 'Failed')) {
            # Generate error-specific resolution steps
            $errorMsg = $res.ErrorMessage.ToLower()
            $resolution = ""
            
            # Parse specific error messages for targeted resolution
            if ($errorMsg -match "permission|unauthorized|forbidden|access denied|not authorized") {
                $resolution = "Verify Azure RBAC permissions for resource group '$($res.ResourceGroup)' using: az role assignment list --resource-group $($res.ResourceGroup)"
            }
            elseif ($errorMsg -match "not found|does not exist|cannot be found") {
                $resolution = "Resource group '$($res.ResourceGroup)' not found. Verify it exists: az group show --name $($res.ResourceGroup) --subscription $SubscriptionId"
            }
            elseif ($errorMsg -match "initializing provider|provider.*error|terraform") {
                $resolution = "Terraform provider initialization failed. Check provider version compatibility and run 'terraform init' in the export directory."
            }
            elseif ($errorMsg -match "network|connection|timeout|unreachable") {
                $resolution = "Network connectivity issue. Test Azure connection: Test-NetConnection management.azure.com -Port 443"
            }
            elseif ($errorMsg -match "authentication|login|token|credential") {
                $resolution = "Azure authentication expired or invalid. Re-authenticate using: az login"
            }
            elseif ($errorMsg -match "quota|limit|exceeded") {
                $resolution = "Azure quota or rate limit exceeded. Wait and retry, or request quota increase for subscription."
            }
            elseif ($errorMsg -match "lock|locked") {
                $resolution = "Resource group is locked. Check and remove locks: az lock list --resource-group $($res.ResourceGroup)"
            }
            elseif ($errorMsg -match "subscription") {
                $resolution = "Subscription access issue. Verify subscription is active and accessible: az account show --subscription $SubscriptionId"
            }
            else {
                # Extract key phrases from error for custom message
                $resolution = "Error: $($res.ErrorMessage). Review the error details and check aztfexport logs in the terminal output."
            }
            
            $detailData += [PSCustomObject]@{
                Section='FAILURE_DATA'
                ResourceGroup=$res.ResourceGroup
                DetailType="$($res.ErrorCategory): $($res.ErrorMessage)"
                ResourceName=$resolution
                ResourceType=''
                File=''
            }
        }
        
        # Export Details Data - Add to existing file
        Write-Host "  Creating Details worksheet..." -ForegroundColor Yellow
        $detailData | Export-Excel -Path $reportPath -WorksheetName "Details" -TableStyle Medium2 -AutoSize
        
        # Verify file was created
        if (Test-Path $reportPath) {
            Write-Host "  Report successfully saved: $reportPath" -ForegroundColor Green
            
            # Now open for formatting (optional - if this fails, report is still saved)
            Write-Host "  Applying formatting..." -ForegroundColor Yellow
            try {
                $excel = Open-ExcelPackage -Path $reportPath
                
                if ($excel -and $excel.Workbook) {
                    # Format Summary worksheet
                    if ($excel.Workbook.Worksheets["Summary"]) {
                        $ws = $excel.Workbook.Worksheets["Summary"]
                        
                        # Format section headers
                        $ws.Cells["A2"].Style.Font.Bold = $true
                        $ws.Cells["A2"].Style.Font.Size = 14
                        $ws.Cells["A2"].Style.Font.Color.SetColor([System.Drawing.Color]::DarkBlue)
                        
                        $ws.Cells["A13"].Style.Font.Bold = $true
                        $ws.Cells["A13"].Style.Font.Size = 14
                        $ws.Cells["A13"].Style.Font.Color.SetColor([System.Drawing.Color]::DarkBlue)
                        
                        $ws.Cells["A19"].Style.Font.Bold = $true
                        $ws.Cells["A19"].Style.Font.Size = 14
                        $ws.Cells["A19"].Style.Font.Color.SetColor([System.Drawing.Color]::DarkBlue)
                        
                        # Apply dark blue background to SEPARATOR rows
                        for ($row = 1; $row -le $ws.Dimension.End.Row; $row++) {
                            if ($ws.Cells[$row, 1].Value -eq 'SEPARATOR') {
                                $ws.Row($row).Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                                $ws.Row($row).Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::DarkBlue)
                                $ws.Row($row).Height = 5
                            }
                        }
                        
                        $ws.Column(1).Width = 25
                        $ws.Column(2).Width = 35
                        $ws.Column(3).Width = 80
                        
                        # Add Resource Count Bar Chart
                        try {
                            # Add hidden data for chart (starting at row 3, column E)
                            $chartDataRow = 3
                            $ws.Cells["E$chartDataRow"].Value = "Category"
                            $ws.Cells["F$chartDataRow"].Value = "Count"
                            $chartDataRow++
                            
                            $ws.Cells["E$chartDataRow"].Value = "Managed Resources"
                            $ws.Cells["F$chartDataRow"].Value = $totalManaged
                            $chartDataRow++
                            
                            $ws.Cells["E$chartDataRow"].Value = "Referenced Resources"
                            $ws.Cells["F$chartDataRow"].Value = $totalRef
                            $chartDataRow++
                            
                            $ws.Cells["E$chartDataRow"].Value = "Successful RGs"
                            $ws.Cells["F$chartDataRow"].Value = $totalSuccess
                            $chartDataRow++
                            
                            $ws.Cells["E$chartDataRow"].Value = "Failed RGs"
                            $ws.Cells["F$chartDataRow"].Value = $totalFailed
                            
                            # Create bar chart
                            $chart = $ws.Drawings.AddChart("ResourceOverview", [OfficeOpenXml.Drawing.Chart.eChartType]::ColumnClustered)
                            $chart.Title.Text = "Multi-RG Export Overview"
                            $chart.SetPosition(2, 0, 4, 0)  # Position at row 3, column E
                            $chart.SetSize(450, 320)
                            $chart.Series.Add("F4:F7", "E4:E7")
                            $chart.Legend.Remove()
                            $chart.YAxis.Title.Text = "Count"
                            $chart.XAxis.Title.Text = ""
                            
                            # Hide chart data columns
                            $ws.Column(5).Hidden = $true
                            $ws.Column(6).Hidden = $true
                        }
                        catch {
                            Write-Host "  Note: Could not create overview chart" -ForegroundColor Yellow
                        }
                    }
                    
                    # Format Details worksheet
                    if ($excel.Workbook.Worksheets["Details"]) {
                        $wsDetail = $excel.Workbook.Worksheets["Details"]
                        
                        $wsDetail.Cells["A2"].Style.Font.Bold = $true
                        $wsDetail.Cells["A2"].Style.Font.Size = 14
                        $wsDetail.Cells["A2"].Style.Font.Color.SetColor([System.Drawing.Color]::DarkBlue)
                        
                        # Apply dark blue background to SEPARATOR rows
                        for ($row = 1; $row -le $wsDetail.Dimension.End.Row; $row++) {
                            if ($wsDetail.Cells[$row, 1].Value -eq 'SEPARATOR') {
                                $wsDetail.Row($row).Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                                $wsDetail.Row($row).Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::DarkBlue)
                                $wsDetail.Row($row).Height = 5
                            }
                        }
                        
                        $wsDetail.Column(1).Width = 30
                        $wsDetail.Column(2).Width = 25
                        $wsDetail.Column(3).Width = 80
                        $wsDetail.Column(4).Width = 45
                        $wsDetail.Column(5).Width = 25
                    }
                    
                    # Save and close
                    $excel.Save()
                    $excel.Dispose()
                    Write-Host "  Formatting applied successfully" -ForegroundColor Green
                }
            } catch {
                Write-Host "  Note: Formatting could not be applied (report still usable)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Warning: Report file was not created at: $reportPath" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "  WARNING: Failed to generate Excel report." -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  The export data is still available in the console output above." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Completed." -ForegroundColor Green