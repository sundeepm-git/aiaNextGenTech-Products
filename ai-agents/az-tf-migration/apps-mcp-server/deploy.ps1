#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automated deployment script for Azure Terraform MCP Server to Azure Container Apps

.DESCRIPTION
    This PowerShell script provides end-to-end automation for deploying the Azure Terraform
    Migration MCP Server to Azure Container Apps. It handles:
    
    - Prerequisites validation (Azure CLI, Docker, authentication)
    - Docker image build with Azure PowerShell modules
    - Azure Container Registry (ACR) provisioning and image push
    - Log Analytics workspace creation for monitoring
    - Container Apps environment setup
    - Application deployment with System-assigned Managed Identity
    - RBAC role assignment (Reader role on subscription)
    - Post-deployment health checks and verification
    
    The script is idempotent and can be safely re-run. It will detect existing resources
    and update them as needed.

.PARAMETER ResourceGroup
    Name of the Azure Resource Group to create or use.
    Default: rg-aztf-mcp-prod

.PARAMETER Location
    Azure region where resources will be deployed.
    Default: eastus
    Examples: westus2, eastus2, northeurope, westeurope

.PARAMETER SkipBuild
    When specified, skips the Docker image build step.
    Use this if you've already built the image and want to redeploy.

.PARAMETER SkipTests
    When specified, skips post-deployment verification tests.
    Useful for faster deployments when you don't need immediate validation.

.PARAMETER LocalTest
    When specified, runs a local Docker container test before pushing to Azure.
    Tests health and tools endpoints to verify all 3 tools are registered.

.PARAMETER NoCache
    When specified, forces Docker to build without using cache.
    Use this to ensure fresh builds with latest code changes.

.EXAMPLE
    .\deploy.ps1
    Runs full deployment with default settings (rg-aztf-mcp-prod in eastus)
    
.EXAMPLE
    .\deploy.ps1 -ResourceGroup "my-rg" -Location "westus2"
    Deploys to custom resource group in West US 2 region

.EXAMPLE
    .\deploy.ps1 -SkipBuild
    Redeploys without rebuilding the Docker image

.EXAMPLE
    .\deploy.ps1 -ResourceGroup "prod-rg" -SkipTests
    Deploys to production without running post-deployment tests

.NOTES
    Author: Azure Terraform Migration Team
    Version: 1.0.0
    Prerequisites:
        - Azure CLI (az) installed and configured
        - Docker Desktop running
        - Azure subscription with Contributor access
        - Authenticated to Azure (az login)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-aztf-mcp-prod",

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory = $false)]
    [string]$AcrName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ContainerAppEnv,

    [Parameter(Mandatory = $false)]
    [string]$ContainerAppName,

    [Parameter(Mandatory = $false)]
    [string]$LogAnalyticsWorkspace,

    [Parameter(Mandatory = $false)]
    [string]$ImageTag = "latest",

    [Parameter(Mandatory = $false)]
    [int]$Port = 8080,

    [Parameter(Mandatory = $false)]
    [string]$Cpu = "1.0",

    [Parameter(Mandatory = $false)]
    [string]$Memory = "2.0Gi",

    [Parameter(Mandatory = $false)]
    [int]$MinReplicas = 1,

    [Parameter(Mandatory = $false)]
    [int]$MaxReplicas = 3,

    [Parameter(Mandatory = $false)]
    [string]$LogLevel = "info",

    [Parameter(Mandatory = $false)]
    [string]$NodeEnv = "production",

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild,

    [Parameter(Mandatory = $false)]
    [switch]$SkipTests,

    [Parameter(Mandatory = $false)]
    [switch]$LocalTest,

    [Parameter(Mandatory = $false)]
    [switch]$NoCache
)

# Script configuration
$ErrorActionPreference = "Stop"           # Stop execution on any error
$ProgressPreference = "SilentlyContinue"  # Suppress progress bars for cleaner output

# Color scheme for status messages
$ColorInfo = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"

#region Helper Functions
# -----------------------------------------------------------------------------
# Helper functions for status reporting, prerequisites checking, and utilities
# -----------------------------------------------------------------------------

function Write-Status {
    <#
    .SYNOPSIS
        Writes formatted status messages with color coding
    .DESCRIPTION
        Outputs messages with consistent formatting and color-coded prefixes
        based on message type (Info, Success, Warning, Error, Step)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Success", "Warning", "Error", "Step")]
        [string]$Type = "Info"
    )
    
    $color = switch ($Type) {
        "Info" { $ColorInfo }
        "Success" { $ColorSuccess }
        "Warning" { $ColorWarning }
        "Error" { $ColorError }
        "Step" { "Magenta" }
    }
    
    $prefix = switch ($Type) {
        "Info" { "[INFO]" }
        "Success" { "[✓]" }
        "Warning" { "[!]" }
        "Error" { "[✗]" }
        "Step" { "==>" }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates all deployment prerequisites are met
    .DESCRIPTION
        Checks for:
        - Azure CLI installation and authentication
        - Docker Desktop installation and daemon status
        - Correct working directory (apps-mcp-server)
    #>
    Write-Status "Checking prerequisites..." -Type Step
    
    # Check Azure CLI
    try {
        $azVersion = az version --query '"azure-cli"' -o tsv 2>$null
        Write-Status "Azure CLI version: $azVersion" -Type Success
    }
    catch {
        Write-Status "Azure CLI not found. Install from: https://aka.ms/InstallAzureCLIDirect" -Type Error
        exit 1
    }
    
    # Check Docker
    try {
        $dockerVersion = docker --version 2>$null
        Write-Status "Docker: $dockerVersion" -Type Success
    }
    catch {
        Write-Status "Docker not found. Install Docker Desktop." -Type Error
        exit 1
    }
    
    # Check Docker is running
    try {
        docker ps > $null 2>&1
        Write-Status "Docker daemon is running" -Type Success
    }
    catch {
        Write-Status "Docker daemon is not running. Start Docker Desktop." -Type Error
        exit 1
    }
    
    # Check Azure login
    try {
        $account = az account show --query "name" -o tsv 2>$null
        Write-Status "Logged in to Azure: $account" -Type Success
    }
    catch {
        Write-Status "Not logged in to Azure. Running az login..." -Type Warning
        az login
    }
    
    # Check if in correct directory
    if (-not (Test-Path ".\package.json")) {
        Write-Status "Not in apps-mcp-server directory. Please run from project root." -Type Error
        exit 1
    }
    
    Write-Status "All prerequisites met!" -Type Success
    Write-Host ""
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
    
    Write-Status "$Message (waiting $Seconds seconds)" -Type Info
    for ($i = $Seconds; $i -gt 0; $i--) {
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ""
}

#endregion

#region Main Deployment
# -----------------------------------------------------------------------------
# Main deployment workflow - orchestrates all deployment steps
# -----------------------------------------------------------------------------

try {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   Azure Terraform MCP Server - Deployment Script" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Step 0a: Force Azure subscription context FIRST (before any az commands)
    if ($SubscriptionId) {
        Write-Status "Setting Azure subscription context to: $SubscriptionId" -Type Step
        az account set --subscription $SubscriptionId
        if ($LASTEXITCODE -ne 0) {
            Write-Status "Failed to set Azure subscription context" -Type Error
            exit 1
        }
        $currentSub = az account show --query id -o tsv
        if ($currentSub -ne $SubscriptionId) {
            Write-Status "Failed to set Azure subscription context. Current: $currentSub, Expected: $SubscriptionId" -Type Error
            exit 1
        }
        Write-Status "Azure subscription context set successfully to: $SubscriptionId" -Type Success
        Write-Host ""
    }
    
    # Step 0: Prerequisites
    Test-Prerequisites
    
    # Step 1: Configure deployment variables
    # Generate unique names and retrieve Azure subscription details
    Write-Status "Setting deployment variables..." -Type Step
    
    $ACR_NAME = if ($AcrName) { $AcrName } else { Get-UniqueAcrName }
    $SUBSCRIPTION_ID = if ($SubscriptionId) { $SubscriptionId } else { az account show --query id -o tsv }
    $CONTAINERAPPS_ENVIRONMENT = if ($ContainerAppEnv) { $ContainerAppEnv } else { "env-aztf-mcp" }
    $CONTAINER_APP_NAME = if ($ContainerAppName) { $ContainerAppName } else { "app-aztf-mcp-server" }
    $LOG_ANALYTICS_WORKSPACE = if ($LogAnalyticsWorkspace) { $LogAnalyticsWorkspace } else { "law-aztf-mcp" }
    $IMAGE_NAME = "aztf-mcp-server"
    # Auto-increment image tag if it already exists in ACR
    $IMAGE_TAG = $ImageTag
    if ($ACR_NAME -and $ACR_LOGIN_SERVER) {
        $existingTags = az acr repository show-tags --name $ACR_NAME --resource-group $ResourceGroup --repository $IMAGE_NAME --output tsv 2>$null
        if ($existingTags) {
            $versionPattern = '^v(\d+)$'
            $maxVersion = 0
            foreach ($tag in $existingTags -split '\s+') {
                if ($tag -match $versionPattern) {
                    $ver = [int]$Matches[1]
                    if ($ver -gt $maxVersion) { $maxVersion = $ver }
                }
            }
            $IMAGE_TAG = "v$($maxVersion + 1)"
            Write-Status "Auto-incremented image tag: $IMAGE_TAG" -Type Info
        }
    }
    
    Write-Host ""
    Write-Host "Deployment Configuration:" -ForegroundColor Yellow
    Write-Host "  Subscription ID: $SUBSCRIPTION_ID" -ForegroundColor White
    Write-Host "  Resource Group:  $ResourceGroup" -ForegroundColor White
    Write-Host "  Location:        $Location" -ForegroundColor White
    Write-Host "  ACR Name:        $ACR_NAME" -ForegroundColor White
    Write-Host "  Container App Env: $CONTAINERAPPS_ENVIRONMENT" -ForegroundColor White
    Write-Host "  Container App:   $CONTAINER_APP_NAME" -ForegroundColor White
    Write-Host "  Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE" -ForegroundColor White
    Write-Host "  Image Tag:       $IMAGE_TAG" -ForegroundColor White
    Write-Host "  Port:            $Port" -ForegroundColor White
    Write-Host "  CPU:             $Cpu" -ForegroundColor White
    Write-Host "  Memory:          $Memory" -ForegroundColor White
    Write-Host "  Min Replicas:    $MinReplicas" -ForegroundColor White
    Write-Host "  Max Replicas:    $MaxReplicas" -ForegroundColor White
    Write-Host "  Log Level:       $LogLevel" -ForegroundColor White
    Write-Host "  Node Env:        $NodeEnv" -ForegroundColor White
    Write-Host ""
    
    $confirmation = Read-Host "Proceed with deployment? (Y/N)"
    if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
        Write-Status "Deployment cancelled by user" -Type Warning
        exit 0
    }
    
    # Step 2: Build Docker image locally
    # Creates containerized application with Node.js, PowerShell 7, and Azure modules
    if (-not $SkipBuild) {
        Write-Status "Building Docker image..." -Type Step
        
        $buildArgs = @("-t", "${IMAGE_NAME}:${IMAGE_TAG}")
        if ($NoCache) {
            Write-Status "Building with --no-cache flag for clean build" -Type Info
            $buildArgs += "--no-cache"
        }
        $buildArgs += "."
        
        docker build @buildArgs
        
        if ($LASTEXITCODE -ne 0) {
            Write-Status "Docker build failed" -Type Error
            exit 1
        }
        Write-Status "Docker image built successfully" -Type Success
        Write-Host ""
        
        # Step 2.5: Local test (optional)
        if ($LocalTest) {
            Write-Status "Running local container test..." -Type Step
            Write-Host ""
            
            # Stop any existing test container
            docker stop aztf-mcp-test 2>$null
            docker rm aztf-mcp-test 2>$null
            
            Write-Status "Starting container on port 8080..." -Type Info
            docker run -d --name aztf-mcp-test -p 8080:8080 "${IMAGE_NAME}:${IMAGE_TAG}"
            
            Wait-ForDeployment "Waiting for container to start" 10
            
            # Test health endpoint
            Write-Status "Testing /health endpoint..." -Type Info
            try {
                $health = Invoke-RestMethod -Uri "http://localhost:8080/health" -TimeoutSec 15
                Write-Status "Health Response:" -Type Success
                $health | ConvertTo-Json -Depth 3 | Write-Host
                
                if ($health.status -ne "healthy") {
                    Write-Status "Health check failed - status: $($health.status)" -Type Error
                    docker logs aztf-mcp-test
                    docker stop aztf-mcp-test
                    docker rm aztf-mcp-test
                    exit 1
                }
            } catch {
                Write-Status "Health check failed: $_" -Type Error
                docker logs aztf-mcp-test
                docker stop aztf-mcp-test
                docker rm aztf-mcp-test
                exit 1
            }
            
            Write-Host ""
            
            # Test tools endpoint
            Write-Status "Testing /tools endpoint..." -Type Info
            try {
                $tools = Invoke-RestMethod -Uri "http://localhost:8080/tools" -TimeoutSec 15
                $toolCount = $tools.registered_tools.Count
                
                Write-Status "Found $toolCount registered tools:" -Type Success
                foreach ($tool in $tools.registered_tools) {
                    Write-Host "  • $($tool.name)" -ForegroundColor Cyan
                }
                
                if ($toolCount -ne 3) {
                    Write-Status "Expected 3 tools, found $toolCount" -Type Error
                    Write-Host ""
                    Write-Host "Filesystem check:" -ForegroundColor Yellow
                    $tools.filesystem_check | Format-Table -AutoSize
                    docker logs aztf-mcp-test
                    docker stop aztf-mcp-test
                    docker rm aztf-mcp-test
                    exit 1
                }
                
                Write-Host ""
                Write-Host "Filesystem verification:" -ForegroundColor Yellow
                $tools.filesystem_check | Format-Table -AutoSize
                
            } catch {
                Write-Status "Tools check failed: $_" -Type Error
                docker logs aztf-mcp-test
                docker stop aztf-mcp-test
                docker rm aztf-mcp-test
                exit 1
            }
            
            # Cleanup
            Write-Status "Cleaning up test container..." -Type Info
            docker stop aztf-mcp-test
            docker rm aztf-mcp-test
            Write-Status "Local test passed ✓" -Type Success
            Write-Host ""
        }
    }
    else {
        Write-Status "Skipping Docker build" -Type Warning
        Write-Host ""
    }
    
    # Step 3: Use existing Azure Resource Group
    Write-Status "Using existing resource group: $ResourceGroup" -Type Step
    $rgExists = az group exists --name $ResourceGroup
    if ($rgExists -ne "true") {
        Write-Status "Resource group '$ResourceGroup' does not exist. Please create it before running this script." -Type Error
        exit 1
    }
    Write-Host ""
    
    # Step 4: Use existing Azure Container Registry (ACR)
    Write-Status "Using existing Azure Container Registry: $ACR_NAME" -Type Step
    Write-Host "[DEBUG] az acr show --name $ACR_NAME --resource-group $ResourceGroup" -ForegroundColor Yellow
    $acrExists = az acr show --name $ACR_NAME --resource-group $ResourceGroup --query "name" -o tsv 2>$null
    if (-not $acrExists) {
        Write-Status "ACR '$ACR_NAME' does not exist in resource group '$ResourceGroup'. Please create it before running this script." -Type Error
        exit 1
    }
    Write-Host "[DEBUG] az acr show --name $ACR_NAME --resource-group $ResourceGroup --query loginServer --output tsv" -ForegroundColor Yellow
    $ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --resource-group $ResourceGroup --query loginServer --output tsv
    Write-Status "ACR Login Server: $ACR_LOGIN_SERVER" -Type Info
    Write-Host ""

    # Re-compute/auto-increment image tag now that we can query ACR
    try {
        $existingTags = az acr repository show-tags --name $ACR_NAME --resource-group $ResourceGroup --repository $IMAGE_NAME --output tsv 2>$null
    } catch {
        $existingTags = $null
    }

    if ($existingTags) {
        $versionPattern = '^v(\d+)$'
        $maxVersion = 0
        foreach ($tag in $existingTags -split '\s+') {
            if ($tag -match $versionPattern) {
                $ver = [int]$Matches[1]
                if ($ver -gt $maxVersion) { $maxVersion = $ver }
            }
        }
        $newTag = "v$($maxVersion + 1)"
        if ($newTag -ne $IMAGE_TAG) {
            Write-Status "Auto-incremented image tag: $newTag" -Type Info
            $IMAGE_TAG = $newTag
        }
    }

    
    # Step 5: Push Docker image to ACR
    # Authenticate, tag, and upload container image to private registry
    Write-Status "Pushing image to Azure Container Registry..." -Type Step
    
    # Verify subscription context before ACR login
    $currentSubBeforeLogin = az account show --query id -o tsv
    Write-Host "[DEBUG] Current subscription before ACR login: $currentSubBeforeLogin" -ForegroundColor Yellow
    Write-Host "[DEBUG] Expected subscription: $SUBSCRIPTION_ID" -ForegroundColor Yellow
    
    if ($currentSubBeforeLogin -ne $SUBSCRIPTION_ID) {
        Write-Status "Subscription context mismatch detected. Re-setting to: $SUBSCRIPTION_ID" -Type Warning
        az account set --subscription $SUBSCRIPTION_ID
        if ($LASTEXITCODE -ne 0) {
            Write-Status "Failed to re-set subscription context" -Type Error
            exit 1
        }
    }
    
    # Get ACR credentials and use docker login directly to avoid resource group lookup issues
    Write-Host "[DEBUG] Getting ACR credentials from resource group: $ResourceGroup" -ForegroundColor Yellow
    $ACR_USERNAME = az acr credential show --name $ACR_NAME --resource-group $ResourceGroup --query username -o tsv
    $ACR_PASSWORD = az acr credential show --name $ACR_NAME --resource-group $ResourceGroup --query "passwords[0].value" -o tsv
    
    if (-not $ACR_USERNAME -or -not $ACR_PASSWORD) {
        Write-Status "Failed to retrieve ACR credentials" -Type Error
        exit 1
    }
    
    Write-Host "[DEBUG] docker login $ACR_LOGIN_SERVER --username $ACR_USERNAME" -ForegroundColor Yellow
    echo $ACR_PASSWORD | docker login $ACR_LOGIN_SERVER --username $ACR_USERNAME --password-stdin
    
    # Ensure local image exists for the computed tag; if not, build or retag accordingly
    $localImageExists = (docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" > $null 2>&1) -eq $true
    if (-not $localImageExists) {
        Write-Status "Local image ${IMAGE_NAME}:${IMAGE_TAG} not found, attempting to retag from latest or rebuild" -Type Info
        $latestExists = (docker image inspect "${IMAGE_NAME}:latest" > $null 2>&1) -eq $true
        if ($latestExists) {
            docker tag "${IMAGE_NAME}:latest" "${IMAGE_NAME}:${IMAGE_TAG}"
        }
        else {
            Write-Status "Building local image with tag ${IMAGE_TAG}..." -Type Info
            docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
        }
    }

    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
    docker push "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Failed to push image to ACR" -Type Error
        exit 1
    }
    
    Write-Status "Image pushed successfully" -Type Success
    
    # Verify image
    Write-Host "[DEBUG] az acr repository show-tags --name $ACR_NAME --resource-group $ResourceGroup --repository $IMAGE_NAME --output tsv" -ForegroundColor Yellow
    $tags = az acr repository show-tags --name $ACR_NAME --resource-group $ResourceGroup --repository $IMAGE_NAME --output tsv
    Write-Status "Available tags: $tags" -Type Info
    Write-Host ""
    
    # Step 6: Use existing Log Analytics Workspace
    Write-Status "Using existing Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE" -Type Step
    $lawExists = az monitor log-analytics workspace show `
        --resource-group $ResourceGroup `
        --workspace-name $LOG_ANALYTICS_WORKSPACE `
        --query "name" -o tsv 2>$null
    if (-not $lawExists) {
        Write-Status "Log Analytics workspace '$LOG_ANALYTICS_WORKSPACE' does not exist in resource group '$ResourceGroup'. Please create it before running this script." -Type Error
        exit 1
    }
    $LOG_ANALYTICS_WORKSPACE_ID = az monitor log-analytics workspace show `
        --resource-group $ResourceGroup `
        --workspace-name $LOG_ANALYTICS_WORKSPACE `
        --query customerId -o tsv
    $LOG_ANALYTICS_KEY = az monitor log-analytics workspace get-shared-keys `
        --resource-group $ResourceGroup `
        --workspace-name $LOG_ANALYTICS_WORKSPACE `
        --query primarySharedKey -o tsv
    Write-Host ""
    
    # Step 7: Use existing Container Apps Environment
    Write-Status "Using existing Container Apps environment: $CONTAINERAPPS_ENVIRONMENT" -Type Step
    $envExists = az containerapp env show `
        --name $CONTAINERAPPS_ENVIRONMENT `
        --resource-group $ResourceGroup `
        --query "name" -o tsv 2>$null
    if (-not $envExists) {
        Write-Status "Container Apps environment '$CONTAINERAPPS_ENVIRONMENT' does not exist in resource group '$ResourceGroup'. Please create it before running this script." -Type Error
        exit 1
    }
    Write-Host ""
    
    # Step 8: Deploy MCP Server Container App
    # Deploys application with auto-scaling, external ingress, and system-assigned identity
    Write-Status "Deploying Container App with Managed Identity..." -Type Step
    
    $ACR_USERNAME = az acr credential show --name $ACR_NAME --resource-group $ResourceGroup --query username -o tsv
    $ACR_PASSWORD = az acr credential show --name $ACR_NAME --resource-group $ResourceGroup --query "passwords[0].value" -o tsv
    
    $appExists = az containerapp show `
        --name $CONTAINER_APP_NAME `
        --resource-group $ResourceGroup `
        --query "name" -o tsv 2>$null
    
    if ($appExists) {
        Write-Status "Container app already exists, updating..." -Type Warning
        
        az containerapp update `
            --name $CONTAINER_APP_NAME `
            --resource-group $ResourceGroup `
            --image "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" `
            --set-env-vars "storageAccount=samcpstorage" `
            --output none
        
        Write-Status "Container app updated" -Type Success
    }
    else {
        az containerapp create `
            --name $CONTAINER_APP_NAME `
            --resource-group $ResourceGroup `
            --environment $CONTAINERAPPS_ENVIRONMENT `
            --image "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" `
            --target-port 8080 `
            --ingress external `
            --registry-server $ACR_LOGIN_SERVER `
            --registry-username $ACR_USERNAME `
            --registry-password $ACR_PASSWORD `
            --cpu 1.0 `
            --memory 2.0Gi `
            --min-replicas 1 `
            --max-replicas 3 `
            --system-assigned `
            --env-vars "PORT=8080" "LOG_LEVEL=info" "NODE_ENV=production" "storageAccount=samcpstorage" `
            --output none
        
        Write-Status "Container app deployed successfully" -Type Success
    }
    
    Wait-ForDeployment "Waiting for container to initialize" 20
    Write-Host ""
    
    # Step 9: Configure RBAC for Managed Identity
    # Grants Reader role to allow resource assessment across subscription
    Write-Status "Configuring Managed Identity permissions..." -Type Step
    
    $IDENTITY_PRINCIPAL_ID = az containerapp show `
        --name $CONTAINER_APP_NAME `
        --resource-group $ResourceGroup `
        --query identity.principalId -o tsv
    
    if ($IDENTITY_PRINCIPAL_ID) {
        Write-Status "Managed Identity Principal ID: $IDENTITY_PRINCIPAL_ID" -Type Info
        
        # Check if role assignment already exists
        $roleExists = az role assignment list `
            --assignee $IDENTITY_PRINCIPAL_ID `
            --role "Reader" `
            --scope "/subscriptions/$SUBSCRIPTION_ID" `
            --query "[0].id" -o tsv 2>$null
        
        if ($roleExists) {
            Write-Status "Role assignment already exists" -Type Warning
        }
        else {
            az role assignment create `
                --assignee $IDENTITY_PRINCIPAL_ID `
                --role "Reader" `
                --scope "/subscriptions/$SUBSCRIPTION_ID" `
                --output none
            
            Write-Status "Reader role assigned to Managed Identity" -Type Success
        }
    }
    else {
        Write-Status "Could not retrieve Managed Identity" -Type Warning
    }
    Write-Host ""
    
    # Step 10: Retrieve application endpoints
    # Get the public FQDN for accessing the deployed MCP server
    Write-Status "Retrieving application details..." -Type Step
    
    $APP_URL = az containerapp show `
        --name $CONTAINER_APP_NAME `
        --resource-group $ResourceGroup `
        --query properties.configuration.ingress.fqdn -o tsv
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "   DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Application URL:     https://$APP_URL" -ForegroundColor Cyan
    Write-Host "Health Check:        https://$APP_URL/" -ForegroundColor Cyan
    Write-Host "SSE Endpoint:        https://$APP_URL/sse" -ForegroundColor Cyan
    Write-Host "Messages Endpoint:   https://$APP_URL/messages" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Resource Group:      $ResourceGroup" -ForegroundColor Yellow
    Write-Host "Container Registry:  $ACR_LOGIN_SERVER" -ForegroundColor Yellow
    Write-Host "Container App:       $CONTAINER_APP_NAME" -ForegroundColor Yellow
    Write-Host "Image Tag Used:      $IMAGE_TAG" -ForegroundColor Yellow
    Write-Host "Log Analytics:       $LOG_ANALYTICS_WORKSPACE" -ForegroundColor Yellow
    Write-Host "Container Apps Env:  $CONTAINERAPPS_ENVIRONMENT" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Resources updated or used in this deployment:" -ForegroundColor Green
    Write-Host "- Resource Group: $ResourceGroup (existing)" -ForegroundColor White
    Write-Host "- ACR: $ACR_NAME (existing)" -ForegroundColor White
    Write-Host "- Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE (existing)" -ForegroundColor White
    Write-Host "- Container Apps Environment: $CONTAINERAPPS_ENVIRONMENT (existing)" -ForegroundColor White
    Write-Host "- Container App: $CONTAINER_APP_NAME (created/updated)" -ForegroundColor White
    Write-Host "- Image Tag: $IMAGE_TAG (pushed)" -ForegroundColor White
    Write-Host ""
    
    # Step 11: Validate deployment success
    # Performs health checks and displays recent application logs
    if (-not $SkipTests) {
        Write-Status "Running post-deployment tests..." -Type Step
        Write-Host ""
        
        Wait-ForDeployment "Waiting for application to be fully ready" 10
        
        # Verify the application is responding correctly
        Write-Status "Testing health endpoint..." -Type Info
        try {
            $response = Invoke-RestMethod -Uri "https://$APP_URL/health" -Method Get -TimeoutSec 30
            if ($response.status -eq "healthy") {
                Write-Status "Health check PASSED ✓" -Type Success
                Write-Host "  Tools registered: $($response.toolsCount)" -ForegroundColor Gray
            }
            else {
                Write-Status "Health check returned unexpected response" -Type Warning
            }
        }
        catch {
            Write-Status "Health check failed: $($_.Exception.Message)" -Type Warning
            Write-Status "The application may still be starting up. Please check logs." -Type Info
        }
        
        Write-Host ""
        
        # Test tools endpoint
        Write-Status "Testing tools endpoint..." -Type Info
        try {
            $tools = Invoke-RestMethod -Uri "https://$APP_URL/tools" -Method Get -TimeoutSec 30
            $toolCount = $tools.registered_tools.Count
            
            Write-Status "Found $toolCount registered tools:" -Type Success
            foreach ($tool in $tools.registered_tools) {
                Write-Host "  • $($tool.name)" -ForegroundColor Cyan
            }
            
            if ($toolCount -ne 3) {
                Write-Status "Expected 3 tools, found $toolCount - checking filesystem..." -Type Warning
                Write-Host ""
                Write-Host "Filesystem check:" -ForegroundColor Yellow
                $tools.filesystem_check | Format-Table -AutoSize
            }
        }
        catch {
            Write-Status "Tools check failed: $($_.Exception.Message)" -Type Warning
        }
        
        Write-Host ""
        
        # Display last 20 log entries for verification
        Write-Status "Recent application logs:" -Type Info
        Write-Host ""
        az containerapp logs show `
            --name $CONTAINER_APP_NAME `
            --resource-group $ResourceGroup `
            --tail 20
        
        Write-Host ""
    }
    
    # Display comprehensive success summary and next steps
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Test health: curl https://$APP_URL/health" -ForegroundColor White
    Write-Host "  2. Test tools:  curl https://$APP_URL/tools" -ForegroundColor White
    Write-Host "  3. View logs:   az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $ResourceGroup --follow" -ForegroundColor White
    Write-Host "  4. Exec shell:  az containerapp exec --name $CONTAINER_APP_NAME --resource-group $ResourceGroup --command /bin/bash" -ForegroundColor White
    Write-Host "  5. List files:  az containerapp exec --name $CONTAINER_APP_NAME --resource-group $ResourceGroup --command 'ls -R /app/ps'" -ForegroundColor White
    Write-Host ""
    Write-Host "Diagnostics:" -ForegroundColor Yellow
    Write-Host "  Run: .\diagnose-azure.ps1 -ResourceGroup $ResourceGroup -AppName $CONTAINER_APP_NAME" -ForegroundColor White
    Write-Host ""
    Write-Host "To view all resources:" -ForegroundColor Yellow
    Write-Host "  az resource list --resource-group $ResourceGroup --output table" -ForegroundColor White
    Write-Host ""
    Write-Host "To delete all resources:" -ForegroundColor Yellow
    Write-Host "  az group delete --name $ResourceGroup --yes --no-wait" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
}
catch {
    Write-Host ""
    Write-Status "Deployment failed: $($_.Exception.Message)" -Type Error
    Write-Status "Stack trace: $($_.ScriptStackTrace)" -Type Error
    Write-Host ""
    exit 1
}

#endregion
