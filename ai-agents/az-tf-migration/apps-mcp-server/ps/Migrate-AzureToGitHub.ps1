# Migrate Azure Storage content to GitHub using Git CLI
param(
    [string]$StorageAccount = "samcpstorage",
    [string]$GitHubOwner = "sundeepm-git",
    [string]$GitHubRepo = "refactored-terraform",
    [string]$GitHubBranch = "main"
)

$ErrorActionPreference = "Stop"

# Load GitHub token from .env
$envPath = Join-Path $PSScriptRoot "..\.env"
$githubToken = ""

if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^\s*GITHUB_TOKEN\s*=\s*"?([^"]+)"?') {
            $githubToken = $matches[1].Trim()
        }
    }
}

if (-not $githubToken) {
    Write-Host "ERROR: GITHUB_TOKEN not found in .env file" -ForegroundColor Red
    exit 1
}

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "Azure Storage to GitHub Migration using Git CLI" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# Create temp directory
$tempDir = Join-Path $env:TEMP "azure_to_github_$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Write-Host "1. Created temporary directory: $tempDir" -ForegroundColor Green
    Write-Host ""
    
    # Clone repository or initialize new one
    Write-Host "2. Setting up GitHub repository..." -ForegroundColor Yellow
    $repoDir = Join-Path $tempDir "repo"
    
    $cloneUrl = "https://${githubToken}@github.com/${GitHubOwner}/${GitHubRepo}.git"
    
    git clone $cloneUrl $repoDir 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   OK - Cloned existing repository" -ForegroundColor Green
    }
    else {
        Write-Host "   Repository does not exist - creating new one..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
        Push-Location $repoDir
        git init
        git remote add origin $cloneUrl
        "# Azure Terraform Migration" | Out-File -FilePath "README.md" -Encoding UTF8
        git add README.md
        git commit -m "Initial commit"
        git branch -M $GitHubBranch
        git push -u origin $GitHubBranch
        Pop-Location
        Write-Host "   OK - Created new repository" -ForegroundColor Green
    }
    
    Push-Location $repoDir
    Write-Host ""
    
    # Containers to migrate
    $containers = @("assessment-reports", "aztfexport", "code-refactored")
    
    $totalFiles = 0
    
    foreach ($container in $containers) {
        Write-Host "=== Migrating Container: $container ===" -ForegroundColor Cyan
        
        # Create folder in repo
        $containerPath = Join-Path $repoDir $container
        New-Item -ItemType Directory -Path $containerPath -Force | Out-Null
        
        # Download from Azure
        Write-Host "   Downloading from Azure Storage..." -ForegroundColor Yellow
        
        az storage blob download-batch `
            --account-name $StorageAccount `
            --source $container `
            --destination $containerPath `
            --auth-mode login 2>&1 | Out-Null
        
        # Count files
        $files = Get-ChildItem -Path $containerPath -File -Recurse
        $fileCount = $files.Count
        
        if ($fileCount -gt 0) {
            Write-Host "   OK - Downloaded $fileCount files" -ForegroundColor Green
            $totalFiles += $fileCount
            
            # Stage files for git
            git add $container
        }
        else {
            Write-Host "   WARNING - No files found in container" -ForegroundColor Yellow
        }
        
        Write-Host ""
    }
    
    # Commit and push
    if ($totalFiles -gt 0) {
        Write-Host "3. Committing and pushing to GitHub..." -ForegroundColor Yellow
        
        git config user.name "Azure Terraform Migration"
        git config user.email "migration@azure.local"
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $commitMsg = "Migrate from Azure Storage - $totalFiles files - $timestamp"
        
        git commit -m $commitMsg
        git push origin $GitHubBranch
        
        Write-Host ""
        Write-Host "=====================================================================" -ForegroundColor Green
        Write-Host "Migration Complete!" -ForegroundColor Green
        Write-Host "=====================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Total files migrated: $totalFiles" -ForegroundColor White
        Write-Host ""
        Write-Host "View on GitHub:" -ForegroundColor Cyan
        Write-Host "https://github.com/${GitHubOwner}/${GitHubRepo}" -ForegroundColor Yellow
        Write-Host ""
    }
    else {
        Write-Host "WARNING - No files to migrate" -ForegroundColor Yellow
    }
    
    Pop-Location
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    # Cleanup
    Write-Host "4. Cleaning up temporary files..." -ForegroundColor Yellow
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "   OK - Cleanup complete" -ForegroundColor Green
}
