# Alternative GitHub Upload using Git CLI
# Use this if GitHub token has permission issues

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup
)

# Load .env configuration
$envFilePath = Join-Path $PSScriptRoot "..\.env"
$envConfig = @{}
Get-Content $envFilePath | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim().Trim('"')
        $envConfig[$key] = $value
    }
}

$owner = $envConfig["GITHUB_OWNER"]
$repo = $envConfig["GITHUB_REPO"]
$token = $envConfig["GITHUB_TOKEN"]
$branch = $envConfig["GITHUB_BRANCH"]

# Create temp directory for git operations
$tempDir = Join-Path $env:TEMP "github-upload-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Write-Host "Cloning repository..." -ForegroundColor Cyan
    $repoUrl = "https://$($token)@github.com/$owner/$repo.git"
    git clone --depth 1 --branch $branch $repoUrl $tempDir 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Repository doesn't exist or cannot be accessed. Creating new repository..." -ForegroundColor Yellow
        # Initialize new repo
        Set-Location $tempDir
        git init
        git checkout -b $branch
    } else {
        Set-Location $tempDir
    }
    
    # Copy assessment reports
    $reportDir = Join-Path $PSScriptRoot "report"
    if (Test-Path $reportDir) {
        $targetDir = Join-Path $tempDir "assessment-reports\$SubscriptionId"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        
        $reportFiles = Get-ChildItem $reportDir -Filter "*.html" | Where-Object {
            $_.Name -like "*$SubscriptionId*"
        }
        
        foreach ($file in $reportFiles) {
            Copy-Item $file.FullName -Destination $targetDir -Force
            Write-Host "  Copied: $($file.Name)" -ForegroundColor Green
        }
    }
    
    # Commit and push
    git config user.name "Azure Terraform Migration"
    git config user.email "automation@azuretf.local"
    git add .
    
    $changes = git status --porcelain
    if ($changes) {
        git commit -m "Upload assessment reports for subscription $SubscriptionId"
        git push -u origin $branch
        
        Write-Host "`nSuccessfully uploaded to GitHub!" -ForegroundColor Green
        Write-Host "URL: https://github.com/$owner/$repo/tree/$branch/assessment-reports/$SubscriptionId" -ForegroundColor Cyan
    } else {
        Write-Host "No changes to commit" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
finally {
    # Cleanup
    Set-Location $PSScriptRoot
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
