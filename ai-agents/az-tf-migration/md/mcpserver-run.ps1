#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Starts the Azure Terraform MCP Server locally for development and testing

.DESCRIPTION
    This script validates prerequisites and starts the MCP server on localhost.
    It performs the following checks before starting:
    
    - Node.js dependencies installed (npm install)
    - Azure PowerShell modules available (Az.Accounts, Az.Resources)
    - Azure authentication active (Connect-AzAccount)
    - .env configuration file exists
    - PowerShell scripts accessible
    
    Once validated, starts the Express server with MCP protocol support.

.PARAMETER Port
    Port number for the server to listen on.
    Default: 8080 (from .env file)

.PARAMETER SkipChecks
    Skip prerequisite validation checks.
    Use only if you're certain everything is configured correctly.

.PARAMETER ShowDetails
    Display detailed diagnostic information during startup.

.EXAMPLE
    .\mcpserver-run.ps1
    Validates prerequisites and starts server on default port (8080)

.EXAMPLE
    .\mcpserver-run.ps1 -Port 3000
    Starts server on custom port 3000

.EXAMPLE
    .\mcpserver-run.ps1 -SkipChecks
    Starts server without running prerequisite checks

.EXAMPLE
    .\mcpserver-run.ps1 -ShowDetails
    Starts server with detailed diagnostic output

.NOTES
    Author: Azure Terraform Migration Team
    Version: 1.0.0
    
    The server provides:
    - Health endpoint: http://localhost:8080/
    - SSE endpoint: http://localhost:8080/sse
    - Messages endpoint: http://localhost:8080/messages (POST)
    
    Press Ctrl+C to stop the server
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 8080,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipChecks,
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowDetails
)

# Script configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Color scheme
$ColorInfo = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"

#region Helper Functions
# -----------------------------------------------------------------------------
# Utility functions for status display and validation
# -----------------------------------------------------------------------------

function Write-Status {
    <#
    .SYNOPSIS
        Writes color-coded status messages
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Success", "Warning", "Error", "Header")]
        [string]$Type = "Info"
    )
    
    $color = switch ($Type) {
        "Info" { $ColorInfo }
        "Success" { $ColorSuccess }
        "Warning" { $ColorWarning }
        "Error" { $ColorError }
        "Header" { "Magenta" }
    }
    
    $prefix = switch ($Type) {
        "Info" { "[INFO]" }
        "Success" { "  ✓  " }
        "Warning" { "  !  " }
        "Error" { "  ✗  " }
        "Header" { "===>" }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates all runtime prerequisites
    #>
    Write-Status "Checking prerequisites..." -Type Header
    Write-Host ""
    
    $allChecksPassed = $true
    
    # Check 1: Node modules
    Write-Host "1. Node Dependencies:" -ForegroundColor Yellow
    if (Test-Path ".\node_modules") {
        Write-Status "node_modules installed" -Type Success
    }
    else {
        Write-Status "node_modules not found" -Type Error
        Write-Host "   Fix: Run 'npm install'" -ForegroundColor Gray
        $allChecksPassed = $false
    }
    Write-Host ""
    
    # Check 2: Azure PowerShell modules
    Write-Host "2. Azure PowerShell Modules:" -ForegroundColor Yellow
    
    $azAccounts = Get-Module -ListAvailable Az.Accounts -ErrorAction SilentlyContinue
    if ($azAccounts) {
        Write-Status "Az.Accounts module available" -Type Success
    }
    else {
        Write-Status "Az.Accounts module not found" -Type Error
        Write-Host "   Fix: Install-Module Az.Accounts -Force" -ForegroundColor Gray
        $allChecksPassed = $false
    }
    
    $azResources = Get-Module -ListAvailable Az.Resources -ErrorAction SilentlyContinue
    if ($azResources) {
        Write-Status "Az.Resources module available" -Type Success
    }
    else {
        Write-Status "Az.Resources module not found" -Type Error
        Write-Host "   Fix: Install-Module Az.Resources -Force" -ForegroundColor Gray
        $allChecksPassed = $false
    }
    Write-Host ""
    
    # Check 3: Azure authentication
    Write-Host "3. Azure Authentication:" -ForegroundColor Yellow
    try {
        $ctx = Get-AzContext -ErrorAction SilentlyContinue
        if ($ctx) {
            Write-Status "Authenticated as: $($ctx.Account.Id)" -Type Success
            Write-Status "Subscription: $($ctx.Subscription.Name)" -Type Info
        }
        else {
            Write-Status "Not authenticated to Azure" -Type Error
            Write-Host "   Fix: Run 'Connect-AzAccount'" -ForegroundColor Gray
            $allChecksPassed = $false
        }
    }
    catch {
        Write-Status "Not authenticated to Azure" -Type Error
        Write-Host "   Fix: Run 'Connect-AzAccount'" -ForegroundColor Gray
        $allChecksPassed = $false
    }
    Write-Host ""
    
    # Check 4: Configuration files
    Write-Host "4. Configuration Files:" -ForegroundColor Yellow
    
    if (Test-Path ".\.env") {
        Write-Status ".env file exists" -Type Success
    }
    else {
        Write-Status ".env file not found" -Type Warning
        Write-Host "   Note: Using default configuration" -ForegroundColor Gray
    }
    
    if (Test-Path ".\package.json") {
        Write-Status "package.json exists" -Type Success
    }
    else {
        Write-Status "package.json not found" -Type Error
        Write-Host "   Are you in the correct directory?" -ForegroundColor Gray
        $allChecksPassed = $false
    }
    Write-Host ""
    
    # Check 5: PowerShell scripts
    Write-Host "5. PowerShell Scripts:" -ForegroundColor Yellow
    
    if (Test-Path ".\ps\assessment-AzSubscription.ps1") {
        Write-Status "Assessment script found" -Type Success
    }
    else {
        Write-Status "Assessment script not found" -Type Error
        Write-Host "   Expected: .\ps\assessment-AzSubscription.ps1" -ForegroundColor Gray
        $allChecksPassed = $false
    }
    
    if (Test-Path ".\ps\Export-AzToTerraform.ps1") {
        Write-Status "Export script found" -Type Success
    }
    else {
        Write-Status "Export script not found" -Type Warning
        Write-Host "   Expected: .\ps\Export-AzToTerraform.ps1" -ForegroundColor Gray
    }
    Write-Host ""
    
    return $allChecksPassed
}

function Show-ServerInfo {
    <#
    .SYNOPSIS
        Displays server endpoints and usage information
    #>
    param([int]$ServerPort)
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "   MCP SERVER STARTED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Server Endpoints:" -ForegroundColor Yellow
    Write-Host "  Health Check:  http://localhost:$ServerPort/" -ForegroundColor Cyan
    Write-Host "  SSE Endpoint:  http://localhost:$ServerPort/sse" -ForegroundColor Cyan
    Write-Host "  Messages:      http://localhost:$ServerPort/messages" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Available MCP Tools:" -ForegroundColor Yellow
    Write-Host "  • assess_azure_environment - Assess Azure subscription for Terraform migration" -ForegroundColor White
    Write-Host ""
    Write-Host "Quick Test Commands:" -ForegroundColor Yellow
    Write-Host "  curl http://localhost:$ServerPort/" -ForegroundColor Gray
    Write-Host "  Invoke-RestMethod -Uri http://localhost:$ServerPort/ -Method Get" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Integration:" -ForegroundColor Yellow
    Write-Host "  • Use with Azure AI Foundry" -ForegroundColor White
    Write-Host "  • Use with MCP Inspector: npx @modelcontextprotocol/inspector" -ForegroundColor White
    Write-Host ""
    Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
}

function Test-PortAvailable {
    <#
    .SYNOPSIS
        Checks if a port is available for use
    #>
    param([int]$PortToTest)
    
    # Use Get-NetTCPConnection to check if port is in use
    $connection = Get-NetTCPConnection -LocalPort $PortToTest -ErrorAction SilentlyContinue
    return ($null -eq $connection)
}

function Get-ProcessOnPort {
    <#
    .SYNOPSIS
        Gets the process using a specific port
    #>
    param([int]$PortNumber)
    
    try {
        $connection = Get-NetTCPConnection -LocalPort $PortNumber -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($connection) {
            $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
            return $process
        }
    }
    catch {
        # Fallback to netstat on older systems
        $netstat = netstat -ano | Select-String ":$PortNumber\s" | Select-Object -First 1
        if ($netstat) {
            $processId = ($netstat -split "\s+")[-1]
            return Get-Process -Id $processId -ErrorAction SilentlyContinue
        }
    }
    return $null
}

#endregion

#region Main Execution
# -----------------------------------------------------------------------------
# Main script execution flow
# -----------------------------------------------------------------------------

try {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   Azure Terraform MCP Server - Local Runner" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Validate we're in the correct directory
    if (-not (Test-Path ".\package.json")) {
        Write-Status "Not in apps-mcp-server directory!" -Type Error
        Write-Host "Please navigate to the apps-mcp-server directory and try again." -ForegroundColor Gray
        exit 1
    }
    
    # Run prerequisite checks unless skipped
    if (-not $SkipChecks) {
        $checksPass = Test-Prerequisites
        
        if (-not $checksPass) {
            Write-Host ""
            Write-Status "Prerequisites check failed!" -Type Error
            Write-Host ""
            Write-Host "Please fix the issues above and try again." -ForegroundColor Gray
            Write-Host "Or run with -SkipChecks to bypass validation (not recommended)." -ForegroundColor Gray
            Write-Host ""
            exit 1
        }
        
        Write-Status "All prerequisites satisfied!" -Type Success
        Write-Host ""
    }
    else {
        Write-Status "Skipping prerequisite checks (as requested)" -Type Warning
        Write-Host ""
    }
    
    # Set port environment variable
    $env:PORT = $Port
    if ($Port -ne 8080) {
        Write-Status "Using custom port: $Port" -Type Info
    }
    
    # Check if port is available
    Write-Status "Checking port availability..." -Type Header
    $portAvailable = Test-PortAvailable -PortToTest $Port
    
    if (-not $portAvailable) {
        Write-Status "Port $Port is already in use!" -Type Error
        Write-Host ""
        
        # Try to identify the process
        $process = Get-ProcessOnPort -PortNumber $Port
        if ($process) {
            Write-Host "Process using port ${Port}:" -ForegroundColor Yellow
            Write-Host "  Name: $($process.ProcessName)" -ForegroundColor White
            Write-Host "  PID:  $($process.Id)" -ForegroundColor White
            Write-Host ""
            
            # Check if it's another instance of this server
            if ($process.ProcessName -eq "node") {
                Write-Host "This appears to be another Node.js process (possibly this MCP server)." -ForegroundColor Yellow
                Write-Host ""
                $response = Read-Host "Do you want to stop it and continue? (Y/N)"
                if ($response -eq 'Y' -or $response -eq 'y') {
                    try {
                        Stop-Process -Id $process.Id -Force
                        Write-Status "Process stopped successfully" -Type Success
                        Write-Status "Waiting for port to be released..." -Type Info
                        
                        # Wait for port to be released (up to 10 seconds)
                        $waited = 0
                        $maxWait = 10
                        while ($waited -lt $maxWait) {
                            Start-Sleep -Seconds 1
                            $waited++
                            if (Test-PortAvailable -PortToTest $Port) {
                                Write-Status "Port is now available" -Type Success
                                Write-Host ""
                                break
                            }
                        }
                        
                        # Final check
                        if (-not (Test-PortAvailable -PortToTest $Port)) {
                            Write-Status "Port is still in use after waiting ${waited} seconds" -Type Error
                            Write-Host ""
                            Write-Host "Please wait a moment and try again, or use a different port:" -ForegroundColor Yellow
                            Write-Host "  .\mcpserver-run.ps1 -Port 3000" -ForegroundColor Gray
                            Write-Host ""
                            exit 1
                        }
                    }
                    catch {
                        Write-Status "Failed to stop process: $($_.Exception.Message)" -Type Error
                        Write-Host ""
                        Write-Host "Solutions:" -ForegroundColor Yellow
                        Write-Host "  1. Manually stop the process: Stop-Process -Id $($process.Id) -Force" -ForegroundColor Gray
                        Write-Host "  2. Use a different port: .\mcpserver-run.ps1 -Port 3000" -ForegroundColor Gray
                        Write-Host ""
                        exit 1
                    }
                }
                else {
                    Write-Host ""
                    Write-Host "Solutions:" -ForegroundColor Yellow
                    Write-Host "  1. Stop the process manually: Stop-Process -Id $($process.Id) -Force" -ForegroundColor Gray
                    Write-Host "  2. Use a different port: .\mcpserver-run.ps1 -Port 3000" -ForegroundColor Gray
                    Write-Host ""
                    exit 1
                }
            }
            else {
                Write-Host "Solutions:" -ForegroundColor Yellow
                Write-Host "  1. Stop the process: Stop-Process -Id $($process.Id) -Force" -ForegroundColor Gray
                Write-Host "  2. Use a different port: .\mcpserver-run.ps1 -Port 3000" -ForegroundColor Gray
                Write-Host ""
                exit 1
            }
        }
        else {
            Write-Host "Could not identify the process using port $Port" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Solutions:" -ForegroundColor Yellow
            Write-Host "  1. Find and stop the process manually" -ForegroundColor Gray
            Write-Host "  2. Use a different port: .\mcpserver-run.ps1 -Port 3000" -ForegroundColor Gray
            Write-Host "  3. Wait a moment and try again" -ForegroundColor Gray
            Write-Host ""
            exit 1
        }
    }
    else {
        Write-Status "Port $Port is available" -Type Success
        Write-Host ""
    }
    
    # Display detailed info if requested
    if ($ShowDetails) {
        Write-Status "Detailed diagnostics enabled" -Type Info
        Write-Host ""
        Write-Host "Environment:" -ForegroundColor Yellow
        Write-Host "  Working Directory: $(Get-Location)" -ForegroundColor Gray
        Write-Host "  Node Version: $(node --version 2>$null)" -ForegroundColor Gray
        Write-Host "  npm Version: $(npm --version 2>$null)" -ForegroundColor Gray
        
        if (Test-Path ".\.env") {
            Write-Host "  .env file:" -ForegroundColor Gray
            Get-Content ".\.env" | Where-Object { $_ -notmatch "^#" -and $_ -notmatch "^\s*$" } | ForEach-Object {
                Write-Host "    $_" -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }
    
    # Start the server
    Write-Status "Starting MCP server..." -Type Header
    Write-Host ""
    
    # Get the directory of the script
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

    # Construct the full path to the .env file
    $EnvFile = Join-Path -Path $ScriptDir -ChildPath ".env"

    # Check if the .env file exists
    if (-not (Test-Path $EnvFile)) {
        Write-Error ".env file not found at $EnvFile. Please ensure it exists."
        exit 1
    }

    Write-Host "✅ Starting MCP server..."
    Write-Host "   Loading environment from: $EnvFile"
    Write-Host "   Press Ctrl+C to stop the server."

    # Run Node with the --env-file flag
    node --env-file=$EnvFile index.js
    
}
catch {
    Write-Host ""
    Write-Status "Failed to start server: $($_.Exception.Message)" -Type Error
    Write-Host ""
    Write-Host "Common Issues:" -ForegroundColor Yellow
    Write-Host "  1. Port $Port already in use - Try a different port with -Port parameter" -ForegroundColor Gray
    Write-Host "  2. Missing dependencies - Run 'npm install'" -ForegroundColor Gray
    Write-Host "  3. Configuration errors - Check .env file" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
finally {
    if ($env:PORT -and $Port -ne 8080) {
        Remove-Item Env:\PORT -ErrorAction SilentlyContinue
    }
}

#endregion
