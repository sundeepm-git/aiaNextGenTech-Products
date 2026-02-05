#!/usr/bin/env pwsh
# Quick deployment script - builds and pushes new image to Azure

$ErrorActionPreference = "Stop"

Write-Host "=== Quick Deployment ===" -ForegroundColor Cyan
Write-Host ""

# Configuration
$ACR_NAME = "aztfmcpacr"
$SUBSCRIPTION_ID = "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2"
$RESOURCE_GROUP = "rg-mcp-servers"
$CONTAINER_APP_NAME = "aztf-mcp-app"
$IMAGE_NAME = "aztf-mcp-server"
$IMAGE_TAG = "v2.1"

# Step 1: Set subscription context
Write-Host "[1/6] Setting subscription context..." -ForegroundColor Yellow
az account set --subscription $SUBSCRIPTION_ID

# Step 2: Build image with no cache
Write-Host "[2/6] Building Docker image with --no-cache..." -ForegroundColor Yellow
docker build --no-cache -t "${IMAGE_NAME}:${IMAGE_TAG}" .
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Image built" -ForegroundColor Green

# Step 3: Get ACR login server
Write-Host "[3/6] Getting ACR details..." -ForegroundColor Yellow
$ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv
Write-Host "  ACR: $ACR_LOGIN_SERVER" -ForegroundColor Gray

# Step 4: Login and push
Write-Host "[4/6] Pushing to ACR..." -ForegroundColor Yellow
$ACR_USERNAME = az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query username -o tsv
$ACR_PASSWORD = az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "passwords[0].value" -o tsv
echo $ACR_PASSWORD | docker login $ACR_LOGIN_SERVER --username $ACR_USERNAME --password-stdin

docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
docker push "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Push failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Image pushed" -ForegroundColor Green

# Step 5: Update Container App
Write-Host "[5/6] Updating Container App..." -ForegroundColor Yellow
az containerapp update `
    --name $CONTAINER_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --image "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Update failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Container App updated" -ForegroundColor Green

# Step 6: Wait and verify
Write-Host "[6/6] Waiting for deployment..." -ForegroundColor Yellow
Write-Host "  Waiting 30 seconds for new revision to start..." -ForegroundColor Gray
Start-Sleep -Seconds 30

$APP_URL = az containerapp show `
    --name $CONTAINER_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query properties.configuration.ingress.fqdn `
    --output tsv

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "App URL: https://$APP_URL" -ForegroundColor Cyan
Write-Host "Health:  https://$APP_URL/health" -ForegroundColor Cyan
Write-Host "SSE:     https://$APP_URL/sse" -ForegroundColor Cyan
Write-Host ""

# Test health endpoint
Write-Host "Testing health endpoint..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "https://$APP_URL/health" -TimeoutSec 15
    Write-Host "Status: $($health.status)" -ForegroundColor Green
    Write-Host "Blob Storage: $($health.blobStorage.available)" -ForegroundColor Gray
    Write-Host "Active Jobs: $($health.activeJobs)" -ForegroundColor Gray
} catch {
    Write-Host "⚠️  Health check failed: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✅ Done! Test with MCP Inspector at: https://$APP_URL/sse" -ForegroundColor Green
