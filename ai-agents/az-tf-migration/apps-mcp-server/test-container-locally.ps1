#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test the MCP server container locally before deploying to Azure

.DESCRIPTION
    This script:
    1. Builds the Docker image
    2. Runs it locally with proper environment variables
    3. Tests the endpoints
    4. Shows logs for debugging

.PARAMETER BuildNoCache
    Build image with --no-cache flag (recommended for testing fixes)

.PARAMETER SkipBuild
    Skip building and use existing image

.EXAMPLE
    .\test-container-locally.ps1 -BuildNoCache
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$BuildNoCache,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccount = "samcpstorage"
)

$ErrorActionPreference = "Stop"

$IMAGE_NAME = "aztf-mcp-server"
$IMAGE_TAG = "test"
$CONTAINER_NAME = "aztf-mcp-test"

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Local Container Test" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Load .env file if credentials not provided
if (-not $SubscriptionId -or -not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Host "Loading credentials from .env file..." -ForegroundColor Yellow
    
    if (Test-Path ".env") {
        Get-Content ".env" | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                # Handle inline comments
                if ($value -match '^(.*?)\s*#.*$') {
                    $value = $matches[1].Trim()
                }
                
                # Set credentials from .env
                if ($name -eq "AZURE_SUBSCRIPTION_ID" -and -not $SubscriptionId) { $SubscriptionId = $value }
                if ($name -eq "AZURE_TENANT_ID" -and -not $TenantId) { $TenantId = $value }
                if ($name -eq "AZURE_CLIENT_ID" -and -not $ClientId) { $ClientId = $value }
                if ($name -eq "AZURE_CLIENT_SECRET" -and -not $ClientSecret) { $ClientSecret = $value }
                if ($name -eq "storageAccount" -and $StorageAccount -eq "samcpstorage") { $StorageAccount = $value }
            }
        }
        Write-Host "✓ Credentials loaded from .env" -ForegroundColor Green
    } else {
        Write-Host "ERROR: .env file not found and credentials not provided" -ForegroundColor Red
        Write-Host ""
        Write-Host "Either:" -ForegroundColor Yellow
        Write-Host "  1. Create .env file with credentials (copy from .env.example)" -ForegroundColor Gray
        Write-Host "  2. Pass credentials as parameters:" -ForegroundColor Gray
        Write-Host "       -SubscriptionId, -TenantId, -ClientId, -ClientSecret" -ForegroundColor Gray
        exit 1
    }
}

# Validate credentials
if (-not $SubscriptionId) { Write-Host "ERROR: SubscriptionId required" -ForegroundColor Red; exit 1 }
if (-not $TenantId) { Write-Host "ERROR: TenantId required" -ForegroundColor Red; exit 1 }
if (-not $ClientId) { Write-Host "ERROR: ClientId required" -ForegroundColor Red; exit 1 }
if (-not $ClientSecret) { Write-Host "ERROR: ClientSecret required" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "  Tenant:       $TenantId" -ForegroundColor Gray
Write-Host "  Client ID:    $ClientId" -ForegroundColor Gray
Write-Host "  Client Secret: ***" -ForegroundColor Gray
Write-Host "  Storage:      $StorageAccount" -ForegroundColor Gray
Write-Host ""

# STEP 1: BUILD IMAGE
if (-not $SkipBuild) {
    Write-Host "STEP 1: Building Docker image..." -ForegroundColor Magenta
    Write-Host ""
    
    # Stop and remove old container if exists
    docker stop $CONTAINER_NAME 2>$null | Out-Null
    docker rm $CONTAINER_NAME 2>$null | Out-Null
    
    # Remove old image
    docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" -f 2>$null | Out-Null
    
    if ($BuildNoCache) {
        Write-Host "Building with --no-cache..." -ForegroundColor Yellow
        docker build --no-cache -t "${IMAGE_NAME}:${IMAGE_TAG}" .
    } else {
        docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Build failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ Image built successfully" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "STEP 1: Skipping build (using existing image)" -ForegroundColor Yellow
    Write-Host ""
}

# STEP 2: RUN CONTAINER
Write-Host "STEP 2: Starting container..." -ForegroundColor Magenta
Write-Host ""

# Stop and remove old container if exists
docker stop $CONTAINER_NAME 2>$null | Out-Null
docker rm $CONTAINER_NAME 2>$null | Out-Null

# Run container with proper environment variables
docker run -d `
    --name $CONTAINER_NAME `
    -p 8080:8080 `
    -e "PORT=8080" `
    -e "NODE_ENV=production" `
    -e "EXECUTION_MODE=CONTAINER" `
    -e "STDIO_MODE=false" `
    -e "RUNNING_IN_CONTAINER=true" `
    -e "NO_COLOR=1" `
    -e "TERM=dumb" `
    -e "AZURE_EXTENSION_QUIET=true" `
    -e "AZURE_CORE_NO_COLOR=true" `
    -e "AZURE_CORE_OUTPUT=json" `
    -e "AZURE_SUBSCRIPTION_ID=$SubscriptionId" `
    -e "ARM_SUBSCRIPTION_ID=$SubscriptionId" `
    -e "AZURE_TENANT_ID=$TenantId" `
    -e "ARM_TENANT_ID=$TenantId" `
    -e "AZURE_CLIENT_ID=$ClientId" `
    -e "ARM_CLIENT_ID=$ClientId" `
    -e "AZURE_CLIENT_SECRET=$ClientSecret" `
    -e "ARM_CLIENT_SECRET=$ClientSecret" `
    -e "storageAccount=$StorageAccount" `
    -e "AZURE_STORAGE_ACCOUNT=$StorageAccount" `
    -e "AZURE_STORAGE_CONTAINER=aztfexport" `
    "${IMAGE_NAME}:${IMAGE_TAG}"

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to start container" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Container started: $CONTAINER_NAME" -ForegroundColor Green
Write-Host ""

# STEP 3: WAIT FOR STARTUP
Write-Host "STEP 3: Waiting for application to start (15 seconds)..." -ForegroundColor Magenta
Start-Sleep -Seconds 15

# STEP 4: TEST ENDPOINTS
Write-Host ""
Write-Host "STEP 4: Testing endpoints..." -ForegroundColor Magenta
Write-Host ""

# Test health endpoint
Write-Host "Testing /health endpoint..." -ForegroundColor Cyan
try {
    $health = Invoke-RestMethod -Uri "http://localhost:8080/health" -TimeoutSec 10
    Write-Host "✓ Health check passed" -ForegroundColor Green
    Write-Host "  Status: $($health.status)" -ForegroundColor Gray
    Write-Host "  Version: $($health.version)" -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "✗ Health check failed: $_" -ForegroundColor Red
    Write-Host ""
}

# Test tools endpoint
Write-Host "Testing /tools endpoint..." -ForegroundColor Cyan
try {
    $tools = Invoke-RestMethod -Uri "http://localhost:8080/tools" -TimeoutSec 10
    $toolCount = $tools.registered_tools.Count
    
    Write-Host "✓ Found $toolCount registered tools:" -ForegroundColor Green
    foreach ($tool in $tools.registered_tools) {
        Write-Host "  • $($tool.name)" -ForegroundColor Gray
    }
    Write-Host ""
} catch {
    Write-Host "✗ Tools check failed: $_" -ForegroundColor Red
    Write-Host ""
}

# STEP 5: SHOW LOGS
Write-Host "STEP 5: Container logs (last 50 lines)..." -ForegroundColor Magenta
Write-Host ""
docker logs --tail 50 $CONTAINER_NAME
Write-Host ""

# STEP 6: INSTRUCTIONS
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Green
Write-Host "   Container Running" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "Access the container:" -ForegroundColor Cyan
Write-Host "  Health:  http://localhost:8080/health" -ForegroundColor Gray
Write-Host "  Tools:   http://localhost:8080/tools" -ForegroundColor Gray
Write-Host "  SSE:     http://localhost:8080/sse" -ForegroundColor Gray
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  View logs:     docker logs -f $CONTAINER_NAME" -ForegroundColor Gray
Write-Host "  Stop container: docker stop $CONTAINER_NAME" -ForegroundColor Gray
Write-Host "  Remove:        docker rm $CONTAINER_NAME" -ForegroundColor Gray
Write-Host "  Shell access:  docker exec -it $CONTAINER_NAME sh" -ForegroundColor Gray
Write-Host ""
Write-Host "Test the export tool:" -ForegroundColor Cyan
Write-Host "  Use your MCP client to call: export_azure_to_terraform" -ForegroundColor Gray
Write-Host "  With parameters:" -ForegroundColor Gray
Write-Host "    subscriptionId: $SubscriptionId" -ForegroundColor Gray
Write-Host "    resourceGroup: rg-mcp-servers" -ForegroundColor Gray
Write-Host ""
Write-Host "Press Enter to stop and cleanup, or Ctrl+C to keep running..." -ForegroundColor Yellow
Read-Host

# Cleanup
Write-Host ""
Write-Host "Cleaning up..." -ForegroundColor Yellow
docker stop $CONTAINER_NAME
docker rm $CONTAINER_NAME
Write-Host "✓ Container stopped and removed" -ForegroundColor Green
