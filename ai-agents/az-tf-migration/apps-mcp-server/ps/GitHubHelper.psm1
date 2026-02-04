<#
.SYNOPSIS
    Helper functions for uploading files to GitHub repository

.DESCRIPTION
    Provides functions to upload files and directories to GitHub using Git CLI
    Used as alternative to Azure Blob Storage for assessment reports, aztfexport, and refactored code

.NOTES
    Requires: git CLI installed and configured
    Authentication: Uses GITHUB_TOKEN from environment or .env file
#>

function Get-EnvConfig {
    <#
    .SYNOPSIS
        Load configuration from .env file
    #>
    param(
        [string]$EnvFilePath = "$PSScriptRoot\..\.env"
    )
    
    $config = @{}
    
    if (Test-Path $EnvFilePath) {
        Get-Content $EnvFilePath | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $config[$key] = $value
            }
        }
    }
    
    return $config
}

function Test-GitHubAccess {
    <#
    .SYNOPSIS
        Test GitHub access with provided credentials
    #>
    param(
        [string]$Token,
        [string]$Owner,
        [string]$Repo
    )
    
    try {
        $headers = @{
            "Authorization" = "token $Token"
            "Accept" = "application/vnd.github.v3+json"
        }
        
        $url = "https://api.github.com/repos/$Owner/$Repo"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        
        Write-Output "[INFO] Connected to GitHub repo: $($response.full_name)"
        return $true
    }
    catch {
        Write-Output "[ERROR] Cannot access GitHub repository: $_"
        return $false
    }
}

function Upload-FileToGitHub {
    <#
    .SYNOPSIS
        Upload a single file to GitHub repository using GitHub API
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$LocalFilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$RemotePath,
        
        [Parameter(Mandatory=$true)]
        [string]$Token,
        
        [Parameter(Mandatory=$true)]
        [string]$Owner,
        
        [Parameter(Mandatory=$true)]
        [string]$Repo,
        
        [string]$Branch = "main",
        
        [string]$CommitMessage
    )
    
    try {
        # Read file content and encode to base64
        $fileBytes = [System.IO.File]::ReadAllBytes($LocalFilePath)
        $base64Content = [System.Convert]::ToBase64String($fileBytes)
        
        # Check if file exists to get SHA
        $headers = @{
            "Authorization" = "token $Token"
            "Accept" = "application/vnd.github.v3+json"
        }
        
        $getUrl = "https://api.github.com/repos/$Owner/$Repo/contents/$RemotePath"
        $sha = $null
        
        try {
            $existing = Invoke-RestMethod -Uri "$getUrl`?ref=$Branch" -Headers $headers -Method Get
            $sha = $existing.sha
        }
        catch {
            # File doesn't exist, that's okay
        }
        
        # Prepare commit message
        if (-not $CommitMessage) {
            $action = if ($sha) { "Update" } else { "Add" }
            $CommitMessage = "$action $RemotePath"
        }
        
        # Prepare request body
        $body = @{
            message = $CommitMessage
            content = $base64Content
            branch = $Branch
        }
        
        if ($sha) {
            $body.sha = $sha
        }
        
        $jsonBody = $body | ConvertTo-Json
        
        # Upload file
        $response = Invoke-RestMethod -Uri $getUrl -Headers $headers -Method Put -Body $jsonBody -ContentType "application/json"
        
        Write-Output "  ✓ Uploaded: $RemotePath"
        return $true
    }
    catch {
        Write-Output "  ✗ Failed: $RemotePath - $_"
        return $false
    }
}

function Upload-DirectoryToGitHub {
    <#
    .SYNOPSIS
        Upload all files in a directory to GitHub repository
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$LocalDirectory,
        
        [Parameter(Mandatory=$true)]
        [string]$RemoteBasePath,
        
        [Parameter(Mandatory=$true)]
        [string]$Token,
        
        [Parameter(Mandatory=$true)]
        [string]$Owner,
        
        [Parameter(Mandatory=$true)]
        [string]$Repo,
        
        [string]$Branch = "main",
        
        [string]$CommitMessagePrefix
    )
    
    if (-not (Test-Path $LocalDirectory)) {
        Write-Output "[ERROR] Directory does not exist: $LocalDirectory"
        return @{}
    }
    
    # Get all files but exclude .terraform directory and other unnecessary files
    $files = Get-ChildItem -Path $LocalDirectory -File -Recurse | Where-Object {
        $_.FullName -notlike "*\.terraform\*" -and
        $_.Name -ne ".DS_Store" -and
        $_.Name -ne "Thumbs.db"
    }
    
    $results = @{}
    
    Write-Output "[INFO] Uploading $($files.Count) files to GitHub..."
    
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($LocalDirectory.Length).TrimStart('\', '/')
        $remotePath = "$RemoteBasePath/$relativePath" -replace '\\', '/'
        
        $commitMsg = if ($CommitMessagePrefix) { 
            "$CommitMessagePrefix`: $relativePath" 
        } else { 
            $null 
        }
        
        try {
            $success = Upload-FileToGitHub `
                -LocalFilePath $file.FullName `
                -RemotePath $remotePath `
                -Token $Token `
                -Owner $Owner `
                -Repo $Repo `
                -Branch $Branch `
                -CommitMessage $commitMsg
            
            $results[$relativePath] = $success
        }
        catch {
            Write-Output "  ✗ Failed: $relativePath - $_"
            $results[$relativePath] = $false
        }
    }
    
    return $results
}

# Export functions
Export-ModuleMember -Function Get-EnvConfig, Test-GitHubAccess, Upload-FileToGitHub, Upload-DirectoryToGitHub
