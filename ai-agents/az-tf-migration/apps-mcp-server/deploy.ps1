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
    .\deploy.ps1 -SubscriptionId "your-sub-id" -TenantId "your-tenant-id" -ClientId "your-client-id"
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

function Wait-ForContainerAppReady {
    <#
    .SYNOPSIS
        Waits until a container app has no active provisioning operations.
    .DESCRIPTION
        Polls the container app provisioningState until it is 'Succeeded'
        (or a terminal state) before returning, so the next mutating
        command will not hit ContainerAppOperationInProgress.
    #>
    param(
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string]$RG,
        [int]$MaxWaitSeconds = 120,
        [int]$PollIntervalSeconds = 10
    )

    $waited = 0
    while ($waited -lt $MaxWaitSeconds) {
        $state = az containerapp show --name $AppName --resource-group $RG `
            --query "properties.provisioningState" -o tsv 2>$null
        if ($state -eq "Succeeded" -or $state -eq "Failed" -or $state -eq "Canceled") {
            Write-Info "Container app '$AppName' provisioning state: $state"
            return
        }
        Write-Info "Waiting for '$AppName' provisioning to finish (state: $state, ${waited}s elapsed)..."
        Start-Sleep -Seconds $PollIntervalSeconds
        $waited += $PollIntervalSeconds
    }
    Write-Warning "Timed out waiting for '$AppName' provisioning after ${MaxWaitSeconds}s — proceeding anyway"
}

# ===========================
# LOAD .ENV VARIABLES
# ===========================
# Load ALL key variables from .env so deploy.ps1 works without passing every parameter
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Write-Info "Found .env file. Loading variables..."
    $envVarsLoaded = @()
    foreach ($line in Get-Content $envFile) {
        # Skip comments and empty lines
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Split on the first equals sign
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) {
            $envName = $parts[0].Trim()
            $envValue = $parts[1].Trim().Trim('"', "'").Trim()
            # Strip inline comments (e.g., "value # comment")
            if ($envValue -match '^([^#]+?)\s*#') { $envValue = $Matches[1].Trim() }

            switch ($envName) {
                "AZURE_CLIENT_SECRET"    { if (-not $ClientSecret)    { $ClientSecret    = $envValue; $envVarsLoaded += $envName } }
                "AZURE_CLIENT_ID"        { if (-not $ClientId)        { $ClientId        = $envValue; $envVarsLoaded += $envName } }
                "AZURE_TENANT_ID"        { if (-not $TenantId)        { $TenantId        = $envValue; $envVarsLoaded += $envName } }
                "AZURE_SUBSCRIPTION_ID"  { if (-not $SubscriptionId)  { $SubscriptionId  = $envValue; $envVarsLoaded += $envName } }
                "storageAccount"      { if (-not $StorageAccountName) { $StorageAccountName = $envValue; $envVarsLoaded += $envName } }
                "storageAccountRG"    { if (-not $ResourceGroupName -or $ResourceGroupName -eq "rg-aztf-mcp") { $ResourceGroupName = $envValue; $ResourceGroup = $envValue; $envVarsLoaded += $envName } }
                "containerName"       { if (-not $ContainerName) { $ContainerName = $envValue; $envVarsLoaded += $envName } }
                "OUTPUT_DESTINATION"  { $script:OutputDestination = $envValue; $envVarsLoaded += $envName }
                "GITHUB_TOKEN"        { $script:GitHubToken = $envValue; $envVarsLoaded += $envName }
                "GITHUB_OWNER"        { $script:GitHubOwner = $envValue; $envVarsLoaded += $envName }
                "GITHUB_REPO"         { $script:GitHubRepo  = $envValue; $envVarsLoaded += $envName }
                "GITHUB_BRANCH"       { $script:GitHubBranch = $envValue; $envVarsLoaded += $envName }
                "AZTFEXPORT_FOLDER"   { $script:AztfexportFolder = $envValue; $envVarsLoaded += $envName }
                "CODE_REFACTORED_FOLDER" { $script:CodeRefactoredFolder = $envValue; $envVarsLoaded += $envName }
                "ASSESSMENT_FOLDER"   { $script:AssessmentFolder = $envValue; $envVarsLoaded += $envName }
                "AZURE_AI_PROJECT_ENDPOINT" { $script:AzureAiProjectEndpoint = $envValue; $envVarsLoaded += $envName }
                "FOUNDRY_API_KEY"    { $script:FoundryApiKey = $envValue; $envVarsLoaded += $envName }
            }
        }
    }
    if ($envVarsLoaded.Count -gt 0) {
        Write-Success "Loaded $($envVarsLoaded.Count) variables from .env: $($envVarsLoaded -join ', ')"
    }
} else {
    Write-Info "No .env file found. Relying on script parameters."
}

# Resolve ACR name — use existing ACR in the resource group instead of generating a random one
if (-not $AcrName) {
    Write-Info "No ACR name provided — looking up existing ACR in resource group $ResourceGroup..."
    $existingAcr = az acr list --resource-group $ResourceGroup --query "[0].name" -o tsv 2>$null
    if ($existingAcr) {
        $AcrName = $existingAcr
        Write-Success "Found existing ACR: $AcrName"
    } else {
        $AcrName = "aztfmcpacr"
        Write-Warning "No existing ACR found — will create: $AcrName"
    }
}

Write-Info "Using ACR: $AcrName"

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

# Log in with Service Principal if ClientId and TenantId are provided
if ($TenantId -and $ClientId) {
    Write-Step "Logging in with Service Principal" "Magenta"

    # Resolve ClientSecret: use parameter, else fall back to AZURE_CLIENT_SECRET env var
    $resolvedSecret = $ClientSecret
    if (-not $resolvedSecret) {
        $resolvedSecret = $env:AZURE_CLIENT_SECRET
    }

    if (-not $resolvedSecret) {
        Write-Warning "No ClientSecret supplied and AZURE_CLIENT_SECRET is not set. Attempting existing login..."
    } else {
        az login --service-principal `
            --username $ClientId `
            --password $resolvedSecret `
            --tenant $TenantId `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Service principal login failed"
            exit 1
        }
        Write-Success "Logged in as service principal $ClientId"
    }
}

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

# Also check provisioning state — if it's being deleted or failed, we must recreate
$envState = ""
if ($envExists) {
    $envState = az containerapp env show `
        --name $ContainerAppEnv `
        --resource-group $ResourceGroup `
        --query "properties.provisioningState" -o tsv 2>$null
}

if (-not $envExists -or $envState -in @("ScheduledForDelete", "Failed", "Canceled")) {
    if ($envState -in @("ScheduledForDelete", "Failed", "Canceled")) {
        Write-Warning "Container Apps Environment is in '$envState' state. Waiting for cleanup before recreating..."
        $waitCount = 0
        while ($waitCount -lt 24) {
            Start-Sleep -Seconds 10
            $waitCount++
            $stillExists = az containerapp env show --name $ContainerAppEnv --resource-group $ResourceGroup --query "name" -o tsv 2>$null
            if (-not $stillExists) {
                Write-Success "Old environment removed"
                break
            }
            Write-Info "  Waiting for environment deletion... ($($waitCount * 10)s)"
        }
    }
    Write-Info "Creating Container Apps Environment: $ContainerAppEnv"
    $maxAttempts = 3
    $attempt = 1
    $created = $false
    while ($attempt -le $maxAttempts -and -not $created) {
        Write-Info "Attempt $attempt of $maxAttempts to create Container Apps Environment..."
        az containerapp env create `
            --name $ContainerAppEnv `
            --resource-group $ResourceGroup `
            --location $Location `
            --logs-workspace-id $LAW_ID `
            --logs-workspace-key $LAW_KEY `
            --output none
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Container Apps Environment created"
            $created = $true
        } else {
            Write-Warning "Attempt $attempt failed to create Container Apps Environment. Retrying in 20 seconds..."
            Start-Sleep -Seconds 20
            $attempt++
        }
    }
    if (-not $created) {
        Write-Fail "Failed to create Container Apps Environment after $maxAttempts attempts. Check Azure Portal for partial resources or try again later."
        exit 1
    }
} else {
    Write-Success "Container Apps Environment exists (state: $envState)"
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

# Build environment variables array — include ALL vars the container needs
$envVars = @(
    "PORT=$Port"
    "LOG_LEVEL=$LogLevel"
    "NODE_ENV=$NodeEnv"
    "PYTHONUNBUFFERED=1"
    "RUNNING_IN_CONTAINER=true"
)

# Azure Storage configuration
if ($StorageAccountName) {
    $envVars += "AZURE_STORAGE_ACCOUNT=$StorageAccountName"
    $envVars += "storageAccount=$StorageAccountName"
}
# NOTE: Do NOT set a single AZURE_STORAGE_CONTAINER — each process uses its own distinct container:
#   Assessment  -> ASSESSMENT_FOLDER     (default: assessment-reports)
#   Export      -> AZTFEXPORT_FOLDER     (default: aztfexport)
#   Refactor    -> CODE_REFACTORED_FOLDER (default: code-refactored)
$storageRG = if ($ResourceGroup) { $ResourceGroup } else { "rg-mcp-servers" }
$envVars += "storageAccountRG=$storageRG"

# Azure SPN credentials
if ($SubscriptionId) {
    $envVars += "AZURE_SUBSCRIPTION_ID=$SubscriptionId"
    $envVars += "ARM_SUBSCRIPTION_ID=$SubscriptionId"
}
if ($TenantId) {
    $envVars += "AZURE_TENANT_ID=$TenantId"
    $envVars += "ARM_TENANT_ID=$TenantId"
}
if ($ClientId) {
    $envVars += "AZURE_CLIENT_ID=$ClientId"
    $envVars += "ARM_CLIENT_ID=$ClientId"
}
if ($ClientSecret) {
    $envVars += "AZURE_CLIENT_SECRET=secretref:azure-client-secret"
    $envVars += "ARM_CLIENT_SECRET=secretref:azure-client-secret"
}

# GitHub configuration (for OUTPUT_DESTINATION=github or both)
if ($script:GitHubToken)  { $envVars += "GITHUB_TOKEN=$($script:GitHubToken)" }
if ($script:GitHubOwner)  { $envVars += "GITHUB_OWNER=$($script:GitHubOwner)" }
if ($script:GitHubRepo)   { $envVars += "GITHUB_REPO=$($script:GitHubRepo)" }
if ($script:GitHubBranch) { $envVars += "GITHUB_BRANCH=$($script:GitHubBranch)" }

# Output destination and folder configuration
if ($script:OutputDestination)  { $envVars += "OUTPUT_DESTINATION=$($script:OutputDestination)" }
# CRITICAL: Always set container-specific folder names to enforce isolation (prevent cross-contamination)
$envVars += "AZTFEXPORT_FOLDER=$(if ($script:AztfexportFolder) { $script:AztfexportFolder } else { 'aztfexport' })"
$envVars += "CODE_REFACTORED_FOLDER=$(if ($script:CodeRefactoredFolder) { $script:CodeRefactoredFolder } else { 'code-refactored' })"
$envVars += "ASSESSMENT_FOLDER=$(if ($script:AssessmentFolder) { $script:AssessmentFolder } else { 'assessment-reports' })"

# Script paths inside the container
$envVars += "REFACTOR_SCRIPT_PATH=./python/refactor.py"
$envVars += "EXPORT_SCRIPT_PATH=./python/Export-Container-AzToTerraform.py"
$envVars += "EXECUTION_MODE=container"

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
    
    # Set registry credentials FIRST
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

    # Wait for registry-set provisioning to finish before issuing next update
    Wait-ForContainerAppReady -AppName $ContainerAppName -RG $ResourceGroup

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

    # Wait for update provisioning to finish before setting secrets
    Wait-ForContainerAppReady -AppName $ContainerAppName -RG $ResourceGroup

    # Set secrets separately (az containerapp update does not support --set-secrets)
    if ($ClientSecret) {
        Write-Info "Setting container app secrets..."
        az containerapp secret set `
            --name $ContainerAppName `
            --resource-group $ResourceGroup `
            --secrets "azure-client-secret=$ClientSecret" `
            --output none 2>$null
    }
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

    # Add the secret at creation time if it exists
    if ($ClientSecret) {
        $azArgs += '--secrets'
        $azArgs += "azure-client-secret=$ClientSecret"
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
    Write-Success "Running version $($health.version)"
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
# SUMMARY — MCP Server
# ===========================

$MCP_URL = az containerapp show `
    --name $ContainerAppName `
    --resource-group $ResourceGroup `
    --query properties.configuration.ingress.fqdn `
    --output tsv

Write-Success "MCP Server deployed: https://$MCP_URL"

# ===========================
# STEP 10: DEPLOY API CONTAINER APP
# ===========================

Write-Step "Building & deploying FastAPI container app" "Cyan"

$API_APP_NAME = "aztf-api-app"
$API_IMAGE_NAME = "aztf-api-server"
$API_IMAGE_FULL = "${ACR_LOGIN_SERVER}/${API_IMAGE_NAME}:${ImageTag}"

# Build API image from Dockerfile.api (same build context = apps-mcp-server)
Write-Info "Building API image..."
docker build --no-cache -f Dockerfile.api -t "${API_IMAGE_NAME}:${ImageTag}" .

if ($LASTEXITCODE -ne 0) {
    Write-Fail "API Docker build failed"
    exit 1
}

Write-Info "Tagging & pushing API image..."
docker tag "${API_IMAGE_NAME}:${ImageTag}" $API_IMAGE_FULL
docker push $API_IMAGE_FULL

if ($LASTEXITCODE -ne 0) {
    Write-Fail "API image push failed"
    exit 1
}

# Build env vars for API container
$apiEnvVars = @(
    "PYTHONUNBUFFERED=1"
    "RUNNING_IN_CONTAINER=true"
)
if ($StorageAccountName) {
    $apiEnvVars += "AZURE_STORAGE_ACCOUNT=$StorageAccountName"
    $apiEnvVars += "storageAccount=$StorageAccountName"
}
# Per-process container names passed via ASSESSMENT_FOLDER, AZTFEXPORT_FOLDER, CODE_REFACTORED_FOLDER
$apiEnvVars += "storageAccountRG=$ResourceGroup"
if ($SubscriptionId) {
    $apiEnvVars += "AZURE_SUBSCRIPTION_ID=$SubscriptionId"
    $apiEnvVars += "ARM_SUBSCRIPTION_ID=$SubscriptionId"
}
if ($TenantId) {
    $apiEnvVars += "AZURE_TENANT_ID=$TenantId"
    $apiEnvVars += "ARM_TENANT_ID=$TenantId"
}
if ($ClientId) {
    $apiEnvVars += "AZURE_CLIENT_ID=$ClientId"
    $apiEnvVars += "ARM_CLIENT_ID=$ClientId"
}
if ($ClientSecret) {
    $apiEnvVars += "AZURE_CLIENT_SECRET=secretref:azure-client-secret"
    $apiEnvVars += "ARM_CLIENT_SECRET=secretref:azure-client-secret"
}
# MCP server URL so API can call it if needed
$apiEnvVars += "MCP_SERVER_URL=https://$MCP_URL"

# Azure AI Foundry endpoint — required by the sequential workflow (aztf-sequential-wf.py)
if ($script:AzureAiProjectEndpoint) {
    $apiEnvVars += "AZURE_AI_PROJECT_ENDPOINT=$($script:AzureAiProjectEndpoint)"
    Write-Info "Including AZURE_AI_PROJECT_ENDPOINT in API env vars"
}
if ($script:FoundryApiKey) {
    $apiEnvVars += "FOUNDRY_API_KEY=secretref:foundry-api-key"
}

# Check if API container app exists
$apiAppExists = az containerapp show --name $API_APP_NAME --resource-group $ResourceGroup --query "name" -o tsv 2>$null

if ($apiAppExists) {
    Write-Info "Updating existing API container app..."
    az containerapp registry set `
        --name $API_APP_NAME `
        --resource-group $ResourceGroup `
        --server $ACR_LOGIN_SERVER `
        --username $ACR_USERNAME `
        --password $ACR_PASSWORD `
        --output none

    # Wait for registry-set provisioning to finish before issuing next update
    Wait-ForContainerAppReady -AppName $API_APP_NAME -RG $ResourceGroup

    $azArgs = @(
        'containerapp', 'update',
        '--name', $API_APP_NAME,
        '--resource-group', $ResourceGroup,
        '--image', $API_IMAGE_FULL,
        '--revision-suffix', "r$(Get-Date -Format 'HHmmss')",
        '--cpu', '0.5',
        '--memory', '1.0Gi',
        '--min-replicas', '1',
        '--max-replicas', '3',
        '--set-env-vars'
    )
    foreach ($envVar in $apiEnvVars) { $azArgs += $envVar }
    $azArgs += '--output'; $azArgs += 'none'
    & az @azArgs

    # Wait for update provisioning to finish before setting secrets
    Wait-ForContainerAppReady -AppName $API_APP_NAME -RG $ResourceGroup

    # Set secrets separately (az containerapp update does not support --set-secrets)
    $apiSecrets = @()
    if ($ClientSecret)          { $apiSecrets += "azure-client-secret=$ClientSecret" }
    if ($script:FoundryApiKey)  { $apiSecrets += "foundry-api-key=$($script:FoundryApiKey)" }
    if ($apiSecrets.Count -gt 0) {
        Write-Info "Setting API container app secrets..."
        $secretArgs = @('containerapp', 'secret', 'set', '--name', $API_APP_NAME, '--resource-group', $ResourceGroup, '--secrets')
        foreach ($s in $apiSecrets) { $secretArgs += $s }
        $secretArgs += '--output'; $secretArgs += 'none'
        & az @secretArgs 2>$null
    }
} else {
    Write-Info "Creating new API container app..."
    $azArgs = @(
        'containerapp', 'create',
        '--name', $API_APP_NAME,
        '--resource-group', $ResourceGroup,
        '--environment', $ContainerAppEnv,
        '--image', $API_IMAGE_FULL,
        '--target-port', '8000',
        '--ingress', 'external',
        '--registry-server', $ACR_LOGIN_SERVER,
        '--registry-username', $ACR_USERNAME,
        '--registry-password', $ACR_PASSWORD,
        '--cpu', '0.5',
        '--memory', '1.0Gi',
        '--min-replicas', '1',
        '--max-replicas', '3',
        '--system-assigned',
        '--env-vars'
    )
    foreach ($envVar in $apiEnvVars) { $azArgs += $envVar }
    $createSecrets = @()
    if ($ClientSecret)          { $createSecrets += "azure-client-secret=$ClientSecret" }
    if ($script:FoundryApiKey)  { $createSecrets += "foundry-api-key=$($script:FoundryApiKey)" }
    if ($createSecrets.Count -gt 0) { $azArgs += '--secrets'; foreach ($s in $createSecrets) { $azArgs += $s } }
    $azArgs += '--output'; $azArgs += 'none'
    & az @azArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Fail "API container app deployment failed"
    exit 1
}

# Wait for API to be ready
Write-Info "Waiting for API container to become ready..."
$apiWait = 0
while ($apiWait -lt 60) {
    Start-Sleep -Seconds 5; $apiWait += 5
    $apiReady = az containerapp show --name $API_APP_NAME --resource-group $ResourceGroup `
        --query "properties.latestReadyRevisionName" --output tsv 2>$null
    if ($apiReady) { Write-Success "API container ready: $apiReady"; break }
    Write-Info "Waiting... ($apiWait seconds)"
}

$API_URL = az containerapp show --name $API_APP_NAME --resource-group $ResourceGroup `
    --query properties.configuration.ingress.fqdn --output tsv
Write-Success "API Server deployed: https://$API_URL"

# ===========================
# STEP 11: DEPLOY UI CONTAINER APP
# ===========================

Write-Step "Building & deploying Next.js UI container app" "Cyan"

$UI_APP_NAME = "aztf-ui-app"
$UI_IMAGE_NAME = "aztf-ui"
$UI_IMAGE_FULL = "${ACR_LOGIN_SERVER}/${UI_IMAGE_NAME}:${ImageTag}"

# Resolve path to UI source (outside apps-mcp-server)
$uiSourcePath = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\ai-aztfexport-ui")
Write-Info "UI source: $uiSourcePath"

# Build UI image — pass API and MCP URLs as build args so NEXT_PUBLIC_ vars are baked in
Write-Info "Building UI image with API_URL=https://$API_URL and MCP_URL=https://$MCP_URL..."
docker build --no-cache `
    --build-arg "NEXT_PUBLIC_WORKFLOW_API_URL=https://$API_URL" `
    --build-arg "NEXT_PUBLIC_MCP_SERVER_URL=https://$MCP_URL" `
    -t "${UI_IMAGE_NAME}:${ImageTag}" `
    "$uiSourcePath"

if ($LASTEXITCODE -ne 0) {
    Write-Fail "UI Docker build failed"
    exit 1
}

Write-Info "Tagging & pushing UI image..."
docker tag "${UI_IMAGE_NAME}:${ImageTag}" $UI_IMAGE_FULL
docker push $UI_IMAGE_FULL

if ($LASTEXITCODE -ne 0) {
    Write-Fail "UI image push failed"
    exit 1
}

# Check if UI container app exists
$uiAppExists = az containerapp show --name $UI_APP_NAME --resource-group $ResourceGroup --query "name" -o tsv 2>$null

if ($uiAppExists) {
    Write-Info "Updating existing UI container app..."
    az containerapp registry set `
        --name $UI_APP_NAME `
        --resource-group $ResourceGroup `
        --server $ACR_LOGIN_SERVER `
        --username $ACR_USERNAME `
        --password $ACR_PASSWORD `
        --output none

    $azArgs = @(
        'containerapp', 'update',
        '--name', $UI_APP_NAME,
        '--resource-group', $ResourceGroup,
        '--image', $UI_IMAGE_FULL,
        '--revision-suffix', "r$(Get-Date -Format 'HHmmss')",
        '--cpu', '0.5',
        '--memory', '1.0Gi',
        '--min-replicas', '1',
        '--max-replicas', '3',
        '--output', 'none'
    )
    & az @azArgs
} else {
    Write-Info "Creating new UI container app..."
    $azArgs = @(
        'containerapp', 'create',
        '--name', $UI_APP_NAME,
        '--resource-group', $ResourceGroup,
        '--environment', $ContainerAppEnv,
        '--image', $UI_IMAGE_FULL,
        '--target-port', '3000',
        '--ingress', 'external',
        '--registry-server', $ACR_LOGIN_SERVER,
        '--registry-username', $ACR_USERNAME,
        '--registry-password', $ACR_PASSWORD,
        '--cpu', '0.5',
        '--memory', '1.0Gi',
        '--min-replicas', '1',
        '--max-replicas', '3',
        '--output', 'none'
    )
    & az @azArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Fail "UI container app deployment failed"
    exit 1
}

# Wait for UI to be ready
Write-Info "Waiting for UI container to become ready..."
$uiWait = 0
while ($uiWait -lt 60) {
    Start-Sleep -Seconds 5; $uiWait += 5
    $uiReady = az containerapp show --name $UI_APP_NAME --resource-group $ResourceGroup `
        --query "properties.latestReadyRevisionName" --output tsv 2>$null
    if ($uiReady) { Write-Success "UI container ready: $uiReady"; break }
    Write-Info "Waiting... ($uiWait seconds)"
}

$UI_URL = az containerapp show --name $UI_APP_NAME --resource-group $ResourceGroup `
    --query properties.configuration.ingress.fqdn --output tsv
Write-Success "UI deployed: https://$UI_URL"

# ===========================
# FINAL SUMMARY — ALL THREE SERVICES
# ===========================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "   DEPLOYMENT COMPLETE — ALL 3 CONTAINER APPS" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  UI (React/Next.js)     : https://$UI_URL" -ForegroundColor Cyan
Write-Host "  API (FastAPI)          : https://$API_URL" -ForegroundColor Cyan
Write-Host "  MCP Server (Node.js)   : https://$MCP_URL" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Quick-Access Links:" -ForegroundColor Yellow
Write-Host "    UI Home              : https://$UI_URL" -ForegroundColor White
Write-Host "    API Health           : https://${API_URL}/health" -ForegroundColor White
Write-Host "    API Docs (Swagger)   : https://${API_URL}/docs" -ForegroundColor White
Write-Host "    MCP Health           : https://${MCP_URL}/health" -ForegroundColor White
Write-Host "    MCP Tools            : https://${MCP_URL}/tools" -ForegroundColor White
Write-Host "    MCP SSE              : https://${MCP_URL}/sse" -ForegroundColor White
Write-Host ""
Write-Host "  Images:" -ForegroundColor Yellow
Write-Host "    MCP : $IMAGE_FULL" -ForegroundColor Gray
Write-Host "    API : $API_IMAGE_FULL" -ForegroundColor Gray
Write-Host "    UI  : $UI_IMAGE_FULL" -ForegroundColor Gray
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green

if ($toolsSuccess) {
    Write-Host "✓ All systems operational!" -ForegroundColor Green
} else {
    Write-Host "⚠ MCP tool verification had issues — check logs" -ForegroundColor Yellow
    Write-Host "  az containerapp logs show --name $ContainerAppName --resource-group $ResourceGroup --follow" -ForegroundColor Cyan
}