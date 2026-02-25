#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automated local deployment and testing script for Azure Terraform MCP Server.

.DESCRIPTION
    This script performs a local deployment by:
    1. Verifying the .env file exists for SPN credentials
    2. Building a fresh Docker image locally
    3. Cleaning up previous running instances
    4. Starting a new container with port mapping and env vars
    5. Running health and tool verification checks locally
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$ImageName = "aztf-mcp-server-local",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerName = "aztf-mcp-local-instance",
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 3000
)

$ErrorActionPreference = "Stop"

# ===========================
# HELPER FUNCTIONS
# ===========================
function Write-Step { param([string]$Message, [string]$Color = "Cyan") Write-Host "`n===> $Message" -ForegroundColor $Color }
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Fail { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "  $Message" -ForegroundColor Gray }
function Write-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Local MCP Server Deployment & Test" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ===========================
# STEP 1: CHECK ENVIRONMENT
# ===========================
Write-Step "Checking for .env file" "Magenta"
if (-not (Test-Path ".env")) {
    Write-Fail "No .env file found. Local testing requires a .env file with SPN credentials."
    exit 1
}
Write-Success "Found .env file"

# ===========================
# STEP 2: BUILD IMAGE
# ===========================
Write-Step "Building local Docker image" "Magenta"
Write-Info "Running: docker build -t $ImageName ."

$buildStart = Get-Date
docker build -t $ImageName .

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Docker build failed. Check the output above for errors."
    exit 1
}
$buildDuration = ((Get-Date) - $buildStart).TotalSeconds
Write-Success "Image built in $([math]::Round($buildDuration, 1)) seconds"

# ===========================
# STEP 3: CLEANUP OLD CONTAINERS
# ===========================
Write-Step "Cleaning up old containers" "Magenta"
$existingContainer = docker ps -aq -f name="^${ContainerName}$"

if ($existingContainer) {
    Write-Info "Stopping and removing existing container: $ContainerName"
    docker stop $ContainerName | Out-Null
    docker rm $ContainerName | Out-Null
    Write-Success "Old container removed"
} else {
    Write-Info "No existing container found to clean up"
}

# ===========================
# STEP 4: START LOCAL CONTAINER
# ===========================
Write-Step "Starting local container" "Magenta"
Write-Info "Mapping Port $Port to Container Port $Port"

# Run container in detached mode (-d), inject .env file, map ports
docker run -d -p "$($Port):$($Port)" --env-file .env --name $ContainerName $ImageName

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Failed to start Docker container."
    exit 1
}
Write-Success "Container successfully started"

# ===========================
# STEP 5: VERIFY ENDPOINTS
# ===========================
Write-Step "Verifying local deployment" "Magenta"
Write-Info "Waiting 5 seconds for Node.js server to initialize..."
Start-Sleep -Seconds 5

$LOCAL_URL = "http://localhost:$Port"
$toolsSuccess = $false

try {
    Write-Info "Testing $LOCAL_URL/health"
    $health = Invoke-RestMethod -Uri "$LOCAL_URL/health" -TimeoutSec 10
    Write-Success "Health check passed (Status: $($health.status))"

    Write-Info "Testing $LOCAL_URL/tools"
    $tools = Invoke-RestMethod -Uri "$LOCAL_URL/tools" -TimeoutSec 10
    $toolCount = $tools.registered_tools.Count
    
    Write-Success "Found $toolCount registered tools:"
    foreach ($tool in $tools.registered_tools) {
        Write-Info "  • $($tool.name)"
    }
    $toolsSuccess = $true

} catch {
    Write-Fail "Endpoint verification failed: $_"
}

# ===========================
# SUMMARY
# ===========================
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "   LOCAL DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

if (-not $toolsSuccess) {
    Write-Host "⚠ Server started, but endpoints didn't respond correctly." -ForegroundColor Yellow
    Write-Host "Printing recent logs to debug..." -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------------" -ForegroundColor Gray
    docker logs --tail 20 $ContainerName
    Write-Host "---------------------------------------------------------------" -ForegroundColor Gray
} else {
    Write-Host "✓ Your local MCP server is running and ready to test!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Connection URLs for your MCP Client/Inspector:" -ForegroundColor Cyan
    Write-Host "  SSE Endpoint:  $LOCAL_URL/sse" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Helpful Commands:" -ForegroundColor Yellow
    Write-Host "  View live logs: docker logs -f $ContainerName" -ForegroundColor Gray
    Write-Host "  Stop server:    docker stop $ContainerName" -ForegroundColor Gray
}
Write-Host ""