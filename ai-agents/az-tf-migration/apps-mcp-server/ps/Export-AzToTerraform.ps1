<#
.SYNOPSIS
    Wrapper script that routes to the appropriate Azure Terraform export script based on execution mode.

.DESCRIPTION
    This script reads the EXECUTION_MODE from .env file and routes to either:
    - Export-Local-AzToTerraform.ps1 (for local development)
    - Export-Container-AzToTerraform.ps1 (for container/production)
    
    Shows colored console messages indicating which mode is being executed.

.PARAMETER SubscriptionId
    The subscription GUID or name that contains the target resource group.

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group to export.

.PARAMETER StorageContainer
    Azure Storage container name (default: aztfexport).

.EXAMPLE
    .\Export-AzToTerraform.ps1 -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" -ResourceGroupName "rg-mcp-servers"
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

# Get script directory
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Check if EXECUTION_MODE is already set (e.g., in container environment)
$executionMode = [System.Environment]::GetEnvironmentVariable('EXECUTION_MODE', 'Process')
if ([string]::IsNullOrWhiteSpace($executionMode)) {
    $executionMode = $env:EXECUTION_MODE
}

# Debug: Show what we detected
Write-Host "[DEBUG] EXECUTION_MODE environment variable: '$executionMode'" -ForegroundColor DarkGray

# If not set via environment variable, try to load from .env file
if ([string]::IsNullOrWhiteSpace($executionMode)) {
    $envFile = Join-Path (Split-Path $scriptDir -Parent) ".env"

    if (Test-Path $envFile) {
        # Load .env file
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                # Handle inline comments
                if ($value -match '^(.*?)\s*#.*$') {
                    $value = $matches[1].Trim()
                }
                # Set environment variable (only if not already set)
                if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($name, 'Process'))) {
                    [System.Environment]::SetEnvironmentVariable($name, $value, 'Process')
                    Set-Item -Path "env:$name" -Value $value
                }
            }
        }
        # Get execution mode from environment
        $executionMode = $env:EXECUTION_MODE
    } else {
        # .env file doesn't exist - this is expected in container environments
        Write-Host ""
        Write-Host ('=' * 80) -ForegroundColor Yellow
        Write-Host "  INFO: .env file not found (expected in container)" -ForegroundColor Yellow
        Write-Host ('=' * 80) -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Expected location: $envFile" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  For local development, copy .env.example to .env and configure:" -ForegroundColor Cyan
        Write-Host "    Copy-Item .env.example .env" -ForegroundColor Gray
        Write-Host ""
        # Only default to LOCAL if executionMode is still empty
        if ([string]::IsNullOrWhiteSpace($executionMode)) {
            Write-Host "  Defaulting to LOCAL execution mode..." -ForegroundColor Yellow
            Write-Host ""
            $executionMode = "LOCAL"
        }
    }
}

Write-Host "[DEBUG] Final EXECUTION_MODE: '$executionMode'" -ForegroundColor DarkGray

# Display execution mode banner
Write-Host ""
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "  AZURE TERRAFORM EXPORT" -ForegroundColor White
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ""

# Route to appropriate script based on execution mode
switch ($executionMode.ToUpper()) {
    "LOCAL" {
        Write-Host "  🖥️  EXECUTION MODE: " -NoNewline -ForegroundColor White
        Write-Host "LOCAL DEVELOPMENT" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Running Export-Local-AzToTerraform.ps1..." -ForegroundColor Cyan
        Write-Host ('=' * 80) -ForegroundColor Cyan
        Write-Host ""
        
        $localScript = Join-Path $scriptDir "Export-Local-AzToTerraform.ps1"
        if (-not (Test-Path $localScript)) {
            throw "Local export script not found: $localScript"
        }
        
        & $localScript -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -StorageContainer $StorageContainer
    }
    "CONTAINER" {
        Write-Host "  🐳 EXECUTION MODE: " -NoNewline -ForegroundColor White
        Write-Host "CONTAINER/PRODUCTION" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  Running Export-Container-AzToTerraform.ps1..." -ForegroundColor Cyan
        Write-Host ('=' * 80) -ForegroundColor Cyan
        Write-Host ""
        
        $containerScript = Join-Path $scriptDir "Export-Container-AzToTerraform.ps1"
        if (-not (Test-Path $containerScript)) {
            throw "Container export script not found: $containerScript"
        }
        
        & $containerScript -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -StorageContainer $StorageContainer
    }
    default {
        Write-Host ""
        Write-Host ('=' * 80) -ForegroundColor Red
        Write-Host "  ERROR: Invalid EXECUTION_MODE" -ForegroundColor Red
        Write-Host ('=' * 80) -ForegroundColor Red
        Write-Host ""
        Write-Host "  Current value: $executionMode" -ForegroundColor White
        Write-Host ""
        Write-Host "  Valid values:" -ForegroundColor Yellow
        Write-Host "    - LOCAL      (for local development)" -ForegroundColor Gray
        Write-Host "    - CONTAINER  (for container/production)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Set in .env file:" -ForegroundColor Cyan
        Write-Host "    EXECUTION_MODE=LOCAL" -ForegroundColor Gray
        Write-Host ""
        Write-Host ('=' * 80) -ForegroundColor Red
        exit 1
    }
}

