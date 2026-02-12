#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automated deployment script for Azure Terraform MCP Server to Azure Container Apps

.DESCRIPTION
    This script performs a complete deployment by:
    1. Checking and creating Azure resources if they don't exist
    2. Deleting all existing container app revisions (optional)
    3. Building a fresh Docker image with --no-cache
    4. Pushing to Azure Container Registry
    5. Creating or updating container app deployment
    6. Verifying all tools are registered

.PARAMETER ResourceGroup
    Azure Resource Group name

.PARAMETER SubscriptionId
    Azure Subscription ID

.PARAMETER AcrName
    Azure Container Registry name

.PARAMETER Location
    Azure region where resources will be deployed (default: centralus)

.PARAMETER ContainerAppName
    Container App name (default: aztf-mcp-app)

.PARAMETER ContainerAppEnv
    Container Apps Environment name (default: mcp-aca-env)

.PARAMETER LogAnalyticsWorkspace
    Log Analytics Workspace name (default: workspace-mcp-servers)

.PARAMETER ImageTag
    Docker image tag (default: timestamp-based)

.PARAMETER KeepOldRevisions
    Keep old revisions instead of deactivating them

.EXAMPLE
    .\deploy.ps1 -SubscriptionId "your-sub-id" -TenantId "your-tenant-id" -ClientId "your-client-id" -ClientSecret "your-secret"
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-aztf-mcp",
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerName,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "centralus",
    
    [Parameter(Mandatory=$false)]
    [string]$AppName = "aztf-mcp-app",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "production",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageName = "aztf-mcp-server",
    
    [Parameter(Mandatory=$false)]
    [string]$Tag,
    
    [Parameter(Mandatory=$false)]
    [string]$AcrName,
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerAppName = "aztf-mcp-app",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerAppEnv = "mcp-aca-env",
    
    [Parameter(Mandatory=$false)]
    [string]$LogAnalyticsWorkspace = "workspace-mcp-servers",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageTag,
    
    [Parameter(Mandatory=$false)]
    [switch]$KeepOldRevisions,
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 3000,
    
    [Parameter(Mandatory=$false)]
    [string]$Cpu = "1.0",
    
    [Parameter(Mandatory=$false)]
    [string]$Memory = "2.0Gi",
    
    [Parameter(Mandatory=$false)]
    [int]$MinReplicas = 1,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxReplicas = 3,
    
    [Parameter(Mandatory=$false)]
    [string]$LogLevel = "info",
    
    [Parameter(Mandatory=$false)]
    [string]$NodeEnv = "production",
    
    [Parameter(Mandatory=$false)]
    [switch]$NoCache
)

$ErrorActionPreference = "Stop"

# Map parameter names for backward compatibility
$ResourceGroup = $ResourceGroupName

# Helper Functions
function Write-Status {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    $prefix = switch ($Type) {
        "Error"   { "[ERROR]" }
        "Warning" { "[WARNING]" }
        "Success" { "[SUCCESS]" }
        "Step"    { "[STEP]" }
        default   { "[INFO]" }
    }
    Write-Host "$prefix $Message"
}

function Write-Step {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "`n===> $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Get-UniqueAcrName {
    <#
    .SYNOPSIS
        Generates a unique Azure Container Registry name
    .DESCRIPTION
        ACR names must be globally unique. This function appends a random
        4-digit suffix to ensure uniqueness across Azure.
    #>
    param([string]$BaseName = "acraztfmcp")
    $randomSuffix = Get-Random -Minimum 1000 -Maximum 9999
    return "$BaseName$randomSuffix"
}

function Wait-ForDeployment {
    <#
    .SYNOPSIS
        Displays a countdown timer for deployment wait periods
    .DESCRIPTION
        Shows a progress indicator while waiting for Azure resources
        to initialize or become ready
    #>
    param(
        [string]$Message,
        [int]$Seconds = 15
    )
    
    Write-Info "$Message (waiting $Seconds seconds)"
    for ($i = $Seconds; $i -gt 0; $i--) {
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ""
}

# Generate ACR name if not provided
if (-not $AcrName) {
    $AcrName = Get-UniqueAcrName
}

Write-Host "DEBUG: Using ACR: $AcrName"

# ===========================
# START DEPLOYMENT
# ===========================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Azure Terraform MCP Server Deployment" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Generate timestamp-based tag if not provided
if (-not $ImageTag) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $ImageTag = "v-$timestamp"
}

$IMAGE_NAME = "aztf-mcp-server"
$IMAGE_FULL = "${AcrName}.azurecr.io/${IMAGE_NAME}:${ImageTag}"

Write-Info "Resource Group:    $ResourceGroup"
Write-Info "Location:          $Location"
Write-Info "Subscription:      $SubscriptionId"
Write-Info "ACR:               $AcrName"

Write-Info "Container App:     $ContainerAppName"
Write-Info "Environment:       $ContainerAppEnv"
Write-Info "Log Analytics:     $LogAnalyticsWorkspace"
Write-Info "Image Tag:         $ImageTag"
Write-Info "Port:              $Port"
Write-Info "CPU:               $Cpu"
Write-Info "Memory:            $Memory"
Write-Info "Min Replicas:      $MinReplicas"
Write-Info "Max Replicas:      $MaxReplicas"
Write-Info "Log Level:         $LogLevel"
Write-Info "Node Env:          $NodeEnv"
Write-Host ""

$confirm = Read-Host "Continue with deployment? (Y/N)"
if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Warning "Deployment cancelled"
    exit 0
}

# ===========================
# STEP 1: SET AZURE CONTEXT
# ===========================

Write-Step "Setting Azure subscription context" "Magenta"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Failed to set subscription"
    exit 1
}
Write-Success "Subscription context set"

# ===========================
# STEP 2: ENSURE AZURE RESOURCES EXIST
# ===========================

Write-Step "Checking and creating Azure resources if needed" "Magenta"

# Check/Create Resource Group
Write-Info "Checking Resource Group: $ResourceGroup"
$rgExists = az group show --name $ResourceGroup --query "name" -o tsv 2>$null

if (-not $rgExists) {
    Write-Info "Creating Resource Group: $ResourceGroup in $Location"
    az group create --name $ResourceGroup --location $Location --output none
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Resource Group created"
    } else {
        Write-Fail "Failed to create Resource Group"
        exit 1
    }
} else {
    Write-Success "Resource Group exists"
}

# Check/Create Log Analytics Workspace (required for Container Apps Environment)
Write-Info "Checking Log Analytics Workspace: $LogAnalyticsWorkspace"
$lawExists = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $LogAnalyticsWorkspace `
    --query "name" -o tsv 2>$null

if (-not $lawExists) {
    Write-Info "Creating Log Analytics Workspace: $LogAnalyticsWorkspace"
    az monitor log-analytics workspace create `
        --resource-group $ResourceGroup `
        --workspace-name $LogAnalyticsWorkspace `
        --location $Location `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Log Analytics Workspace created"
    } else {
        Write-Fail "Failed to create Log Analytics Workspace"
        exit 1
    }
} else {
    Write-Success "Log Analytics Workspace exists"
}

# Get Log Analytics Workspace ID
$LAW_ID = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $LogAnalyticsWorkspace `
    --query "customerId" -o tsv

$LAW_KEY = az monitor log-analytics workspace get-shared-keys `
    --resource-group $ResourceGroup `
    --workspace-name $LogAnalyticsWorkspace `
    --query "primarySharedKey" -o tsv

# Check/Create Azure Container Registry
Write-Info "Checking Azure Container Registry: $AcrName"
$acrExists = az acr show --name $AcrName --resource-group $ResourceGroup --query "name" -o tsv 2>$null

if (-not $acrExists) {
    Write-Info "Creating Azure Container Registry: $AcrName"
    az acr create `
        --resource-group $ResourceGroup `
        --name $AcrName `
        --sku Basic `
        --location $Location `
        --admin-enabled true `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Azure Container Registry created"
    } else {
        Write-Fail "Failed to create Azure Container Registry"
        exit 1
    }
} else {
    Write-Success "Azure Container Registry exists"
}

# Check/Create Container Apps Environment
Write-Info "Checking Container Apps Environment: $ContainerAppEnv"
$envExists = az containerapp env show `
    --name $ContainerAppEnv `
    --resource-group $ResourceGroup `
    --query "name" -o tsv 2>$null

if (-not $envExists) {
    Write-Info "Creating Container Apps Environment: $ContainerAppEnv"
    az containerapp env create `
        --name $ContainerAppEnv `
        --resource-group $ResourceGroup `
        --location $Location `
        --logs-workspace-id $LAW_ID `
        --logs-workspace-key $LAW_KEY `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Container Apps Environment created"
    } else {
        Write-Fail "Failed to create Container Apps Environment"
        exit 1
    }
} else {
    Write-Success "Container Apps Environment exists"
}

Write-Success "All Azure resources are ready"

# ===========================
# STEP 3: DELETE OLD REVISIONS
# ===========================

Write-Step "Cleaning up old container app revisions" "Magenta"

# Check if container app exists
$appExists = az containerapp show --name $ContainerAppName --resource-group $ResourceGroup --query "name" -o tsv 2>$null

if ($appExists) {
    if (-not $KeepOldRevisions) {
        Write-Info "Deactivating all revisions..."
        
        $revisions = az containerapp revision list `
            --name $ContainerAppName `
            --resource-group $ResourceGroup `
            --query "[].name" `
            --output tsv
        
        if ($revisions) {
            foreach ($revision in $revisions -split "`n") {
                if ($revision.Trim()) {
                    Write-Info "  Deactivating revision: $revision"
                    az containerapp revision deactivate `
                        --name $ContainerAppName `
                        --resource-group $ResourceGroup `
                        --revision $revision `
                        --output none 2>$null
                }
            }
        }
        
        Write-Success "Old revisions deactivated"
    } else {
        Write-Warning "Keeping old revisions as requested"
    }
} else {
    Write-Info "Container app does not exist - will create new"
}

# ===========================
# STEP 4: CLEAN LOCAL DOCKER
# ===========================

Write-Step "Cleaning local Docker images" "Magenta"

# Remove old local images
Write-Info "Removing old local images..."
docker rmi "${IMAGE_NAME}:${ImageTag}" -f 2>$null | Out-Null
docker rmi "${IMAGE_NAME}:latest" -f 2>$null | Out-Null
docker rmi $IMAGE_FULL -f 2>$null | Out-Null

Write-Success "Local images cleaned"

# ===========================
# STEP 5: BUILD FRESH IMAGE
# ===========================

Write-Step "Building fresh Docker image with --no-cache" "Magenta"

$buildStart = Get-Date

docker build --no-cache -t "${IMAGE_NAME}:${ImageTag}" .

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Docker build failed"
    exit 1
}

$buildDuration = ((Get-Date) - $buildStart).TotalSeconds
Write-Success "Image built in $([math]::Round($buildDuration, 1)) seconds"

# Verify image contents
Write-Info "Verifying image contents..."
$verification = docker run --rm "${IMAGE_NAME}:${ImageTag}" sh -c "ls /app/tools/ 2>/dev/null && grep -c '/tools' /app/index.js 2>/dev/null || echo 0"

if ($verification -match "assessment.js" -and $verification -match "aztfexport.js" -and $verification -match "code-refactor.js") {
    Write-Success "All tool files verified in image"
} else {
    Write-Warning "Some tool files may be missing - deployment will continue"
}

# ===========================
# STEP 6: PUSH TO ACR
# ===========================

Write-Step "Pushing image to Azure Container Registry" "Magenta"

# Get ACR credentials
$ACR_LOGIN_SERVER = az acr show --name $AcrName --resource-group $ResourceGroup --query loginServer --output tsv
$ACR_USERNAME = az acr credential show --name $AcrName --resource-group $ResourceGroup --query username -o tsv
$ACR_PASSWORD = az acr credential show --name $AcrName --resource-group $ResourceGroup --query "passwords[0].value" -o tsv

Write-Info "Logging into ACR: $ACR_LOGIN_SERVER"
echo $ACR_PASSWORD | docker login $ACR_LOGIN_SERVER --username $ACR_USERNAME --password-stdin | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Fail "ACR login failed"
    exit 1
}

Write-Info "Tagging image..."
docker tag "${IMAGE_NAME}:${ImageTag}" $IMAGE_FULL

Write-Info "Pushing image..."
$pushStart = Get-Date
docker push $IMAGE_FULL

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Image push failed"
    exit 1
}

$pushDuration = ((Get-Date) - $pushStart).TotalSeconds
Write-Success "Image pushed in $([math]::Round($pushDuration, 1)) seconds"

# ===========================
# STEP 7: DEPLOY CONTAINER APP
# ===========================

Write-Step "Deploying Container App" "Magenta"

# Build environment variables array
$envVars = @(
    "PORT=$Port"
    "LOG_LEVEL=$LogLevel"
    "NODE_ENV=$NodeEnv"
)

# Add storage account if provided
if ($StorageAccountName) {
    $envVars += "AZURE_STORAGE_ACCOUNT=$StorageAccountName"
    $envVars += "storageAccount=$StorageAccountName"
}

# Add storage container if provided
if ($ContainerName) {
    $envVars += "AZURE_STORAGE_CONTAINER=$ContainerName"
}

# Add SPN credentials if provided (REQUIRED for automation)
if ($SubscriptionId) {
    $envVars += "AZURE_SUBSCRIPTION_ID=$SubscriptionId"
    $envVars += "ARM_SUBSCRIPTION_ID=$SubscriptionId" # ADD THIS
}

if ($TenantId) {
    $envVars += "AZURE_TENANT_ID=$TenantId"
    $envVars += "ARM_TENANT_ID=$TenantId"           # ADD THIS
}

if ($ClientId) {
    $envVars += "AZURE_CLIENT_ID=$ClientId"
    $envVars += "ARM_CLIENT_ID=$ClientId"           # ADD THIS
}

if ($ClientSecret) {
    $envVars += "AZURE_CLIENT_SECRET=$ClientSecret"
    $envVars += "ARM_CLIENT_SECRET=$ClientSecret"   # ADD THIS
}

Write-Info "Configured environment variables:"
foreach ($envVar in $envVars) {
    $varName = $envVar.Split('=')[0]
    if ($varName -like "*SECRET*" -or $varName -like "*PASSWORD*") {
        Write-Info "  $varName=***"
    } else {
        Write-Info "  $envVar"
    }
}

if ($appExists) {
    Write-Info "Updating existing container app..."
    
    # Set registry credentials FIRST (before update attempts to pull image)
    Write-Info "Updating registry credentials..."
    az containerapp registry set `
        --name $ContainerAppName `
        --resource-group $ResourceGroup `
        --server $ACR_LOGIN_SERVER `
        --username $ACR_USERNAME `
        --password $ACR_PASSWORD `
        --output none
    
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to set registry credentials"
        exit 1
    }
    
    # Build the az command with environment variables as separate arguments
    $azArgs = @(
        'containerapp', 'update',
        '--name', $ContainerAppName,
        '--resource-group', $ResourceGroup,
        '--image', $IMAGE_FULL,
        '--revision-suffix', "r$(Get-Date -Format 'HHmmss')",
        '--cpu', $Cpu,
        '--memory', $Memory,
        '--min-replicas', $MinReplicas,
        '--max-replicas', $MaxReplicas,
        '--set-env-vars'
    )
    
    # Add each environment variable as a separate argument
    foreach ($envVar in $envVars) {
        $azArgs += $envVar
    }
    
    $azArgs += '--output'
    $azArgs += 'none'
    
    # Execute the command
    & az @azArgs
} else {
    Write-Info "Creating new container app..."
    
    # Build the az command with environment variables as separate arguments
    $azArgs = @(
        'containerapp', 'create',
        '--name', $ContainerAppName,
        '--resource-group', $ResourceGroup,
        '--environment', $ContainerAppEnv,
        '--image', $IMAGE_FULL,
        '--target-port', $Port,
        '--ingress', 'external',
        '--registry-server', $ACR_LOGIN_SERVER,
        '--registry-username', $ACR_USERNAME,
        '--registry-password', $ACR_PASSWORD,
        '--cpu', $Cpu,
        '--memory', $Memory,
        '--min-replicas', $MinReplicas,
        '--max-replicas', $MaxReplicas,
        '--system-assigned',
        '--env-vars'
    )
    
    # Add each environment variable as a separate argument
    foreach ($envVar in $envVars) {
        $azArgs += $envVar
    }
    
    $azArgs += '--output'
    $azArgs += 'none'
    
    # Execute the command
    & az @azArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Container app deployment failed"
    exit 1
}

Write-Success "Container app deployed"

# ===========================
# STEP 8: WAIT FOR READY
# ===========================

Write-Step "Waiting for container to become ready" "Magenta"

$maxWait = 60
$waited = 0
$isReady = $false

while ($waited -lt $maxWait -and -not $isReady) {
    Start-Sleep -Seconds 5
    $waited += 5
    
    $latestReady = az containerapp show `
        --name $ContainerAppName `
        --resource-group $ResourceGroup `
        --query "properties.latestReadyRevisionName" `
        --output tsv 2>$null
    
    if ($latestReady) {
        $isReady = $true
        Write-Success "Container ready: $latestReady"
    } else {
        Write-Info "Waiting... ($waited seconds)"
    }
}

if (-not $isReady) {
    Write-Warning "Container did not become ready within $maxWait seconds"
    Write-Info "Check logs: az containerapp logs show --name $ContainerAppName --resource-group $ResourceGroup --follow"
}

# ===========================
# STEP 9: VERIFY DEPLOYMENT
# ===========================

Write-Step "Verifying deployment" "Magenta"

$APP_URL = az containerapp show `
    --name $ContainerAppName `
    --resource-group $ResourceGroup `
    --query properties.configuration.ingress.fqdn `
    --output tsv

Write-Info "App URL: https://$APP_URL"
Write-Host ""

# Check current container status and logs
Write-Info "Checking container status..."
$revisionStatus = az containerapp revision show `
    --name $ContainerAppName `
    --resource-group $ResourceGroup `
    --revision $latestReady `
    --query "properties.provisioningState" `
    --output tsv 2>$null

Write-Info "Revision provisioning state: $revisionStatus"

# Wait for app to fully start (increased from 15 to 45 seconds)
Write-Info "Waiting 45 seconds for application to initialize..."
Start-Sleep -Seconds 45

# Test health endpoint
Write-Info "Testing /health endpoint..."
try {
    $health = Invoke-RestMethod -Uri "https://$APP_URL/health" -TimeoutSec 60
    
    Write-Success "Health check passed"
    Write-Info "  Version: $($health.version)"
    Write-Info "  Status: $($health.status)"
    Write-Info "  Blob Storage: $($health.blobStorage.available)"
    
    if ($health.version -eq "2.1.0") {
        Write-Success "✓ Running latest version (2.1.0)"
    } else {
        Write-Warning "Version mismatch - expected 2.1.0, got $($health.version)"
    }
} catch {
    Write-Fail "Health check failed: $_"
    
    Write-Info "Fetching recent container logs..."
    az containerapp logs show `
        --name $ContainerAppName `
        --resource-group $ResourceGroup `
        --tail 50 `
        --output table 2>$null
}

Write-Host ""

# Test tools endpoint with retries
Write-Info "Testing /tools endpoint (with retries)..."
$toolsSuccess = $false
$maxRetries = 5

for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        $tools = Invoke-RestMethod -Uri "https://$APP_URL/tools" -TimeoutSec 60
        $toolCount = $tools.registered_tools.Count
        
        Write-Success "Found $toolCount registered tools:"
        foreach ($tool in $tools.registered_tools) {
            Write-Info "  • $($tool.name)"
        }
        
        if ($toolCount -eq 3) {
            Write-Success "✓ All 3 tools registered successfully!"
            $toolsSuccess = $true
            break
        } else {
            Write-Warning "Expected 3 tools, found $toolCount (attempt $i/$maxRetries)"
        }
    } catch {
        Write-Warning "Tools endpoint failed (attempt $i/$maxRetries): $_"
    }
    
    if ($i -lt $maxRetries) {
        Write-Info "Retrying in 10 seconds..."
        Start-Sleep -Seconds 10
    }
}

if (-not $toolsSuccess) {
    Write-Fail "Tools endpoint verification failed after $maxRetries attempts"
    Write-Info "Fetching detailed container logs..."
    Write-Host ""
    Write-Host "===== CONTAINER LOGS (Last 100 lines) =====" -ForegroundColor Yellow
    az containerapp logs show `
        --name $ContainerAppName `
        --resource-group $ResourceGroup `
        --tail 100 `
        --output table
    Write-Host "============================================" -ForegroundColor Yellow
    Write-Host ""
}

# ===========================
# SUMMARY
# ===========================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "   DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "App URL:      https://$APP_URL" -ForegroundColor Cyan
Write-Host "Health:       https://$APP_URL/health" -ForegroundColor Cyan
Write-Host "Tools:        https://$APP_URL/tools" -ForegroundColor Cyan
Write-Host "SSE:          https://$APP_URL/sse" -ForegroundColor Cyan
Write-Host ""
Write-Host "Image:        $IMAGE_FULL" -ForegroundColor Yellow
Write-Host ""

if ($toolsSuccess) {
    Write-Host "✓ All systems operational!" -ForegroundColor Green
} else {
    Write-Host "⚠ Deployment completed but verification had issues" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Debug commands:" -ForegroundColor Yellow
    Write-Host "  # Follow live logs:" -ForegroundColor Gray
    Write-Host "  az containerapp logs show --name $ContainerAppName --resource-group $ResourceGroup --follow" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  # List revisions:" -ForegroundColor Gray
    Write-Host "  az containerapp revision list --name $ContainerAppName --resource-group $ResourceGroup --output table" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  # Restart container:" -ForegroundColor Gray
    Write-Host "  az containerapp revision restart --name $ContainerAppName --resource-group $ResourceGroup --revision $latestReady" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  # Check container details:" -ForegroundColor Gray
    Write-Host "  az containerapp show --name $ContainerAppName --resource-group $ResourceGroup" -ForegroundColor Cyan
}
