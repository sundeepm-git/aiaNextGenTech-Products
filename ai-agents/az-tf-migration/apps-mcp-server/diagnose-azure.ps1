#!/usr/bin/env pwsh
# Azure Container Apps Diagnostic Script

param(
    [string]$ResourceGroup = "rg-mcp-servers",
    [string]$AppName = "aztf-mcp-app"
)

Write-Host "=== Azure Container Apps Diagnostics ===" -ForegroundColor Cyan
Write-Host ""

# Get app URL
Write-Host "[1/5] Retrieving app information..." -ForegroundColor Yellow
$appInfo = az containerapp show --name $AppName --resource-group $ResourceGroup --output json | ConvertFrom-Json

if (-not $appInfo) {
    Write-Host "❌ Could not find Container App: $AppName" -ForegroundColor Red
    exit 1
}

$fqdn = $appInfo.properties.configuration.ingress.fqdn
Write-Host "✅ App FQDN: $fqdn" -ForegroundColor Green
Write-Host "   Provisioning State: $($appInfo.properties.provisioningState)" -ForegroundColor Gray
Write-Host "   Running Status: $($appInfo.properties.runningStatus)" -ForegroundColor Gray

# Test endpoints
Write-Host ""
Write-Host "[2/5] Testing /health endpoint..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "https://$fqdn/health" -TimeoutSec 15
    Write-Host "✅ Health Response:" -ForegroundColor Green
    $health | ConvertTo-Json -Depth 3 | Write-Host
} catch {
    Write-Host "❌ Health check failed: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "[3/5] Testing /tools endpoint..." -ForegroundColor Yellow
try {
    $tools = Invoke-RestMethod -Uri "https://$fqdn/tools" -TimeoutSec 15
    
    $toolCount = $tools.registered_tools.Count
    Write-Host "✅ Found $toolCount registered tools:" -ForegroundColor Green
    
    foreach ($tool in $tools.registered_tools) {
        Write-Host "  • $($tool.name)" -ForegroundColor Cyan
        Write-Host "    $($tool.description)" -ForegroundColor Gray
    }
    
    if ($toolCount -ne 3) {
        Write-Host "⚠️  Expected 3 tools, found $toolCount" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Blob Storage: $($tools.blob_storage)" -ForegroundColor Gray
    Write-Host "Report Dir: $($tools.local_report_dir)" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Filesystem Check:" -ForegroundColor Gray
    $tools.filesystem_check | Format-Table -AutoSize
    
    Write-Host ""
    Write-Host "Environment:" -ForegroundColor Gray
    $tools.environment | Format-Table -AutoSize
    
} catch {
    Write-Host "❌ Tools check failed: $_" -ForegroundColor Red
}

# Get recent logs
Write-Host ""
Write-Host "[4/5] Fetching recent container logs..." -ForegroundColor Yellow
Write-Host "(Last 50 lines)" -ForegroundColor Gray
Write-Host ""

az containerapp logs show `
    --name $AppName `
    --resource-group $ResourceGroup `
    --tail 50 `
    --output table

# Check replica status
Write-Host ""
Write-Host "[5/5] Checking replica status..." -ForegroundColor Yellow
$replicas = az containerapp replica list `
    --name $AppName `
    --resource-group $ResourceGroup `
    --output json | ConvertFrom-Json

Write-Host "Active Replicas: $($replicas.Count)" -ForegroundColor Gray
foreach ($replica in $replicas) {
    $status = if ($replica.properties.runningState -eq "Running") { "Green" } else { "Yellow" }
    Write-Host "  • $($replica.name)" -ForegroundColor $status
    Write-Host "    State: $($replica.properties.runningState)" -ForegroundColor Gray
    Write-Host "    Created: $($replica.properties.createdTime)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Diagnostics Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  Follow logs:     az containerapp logs show --name $AppName --resource-group $ResourceGroup --follow" -ForegroundColor Gray
Write-Host "  Exec into pod:   az containerapp exec --name $AppName --resource-group $ResourceGroup --command /bin/bash" -ForegroundColor Gray
Write-Host "  List files:      az containerapp exec --name $AppName --resource-group $ResourceGroup --command 'ls -R /app/ps'" -ForegroundColor Gray
Write-Host "  Test tools:      curl https://$fqdn/tools" -ForegroundColor Gray
