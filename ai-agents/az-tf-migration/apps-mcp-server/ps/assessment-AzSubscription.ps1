<#
Azure Subscription Assessment - KUDU HEADLESS EDITION
UPDATES: 
- Added "Report Outcome" decision table for aztfexport suitability.
- Commented out .log file generation (Console output only).
- Retained strict UI suppression to prevent Kudu crashes.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$SubscriptionId,
    [Parameter(Mandatory = $false)] [string[]]$ResourceGroupName
)

# ---------------------------------------------------------
# 1. NUCLEAR OPTION: SUPPRESS ALL UI
# ---------------------------------------------------------
$ProgressPreference    = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'

# Override Write-Host globally
function Write-Host {
    param([Parameter(ValueFromRemainingArguments)]$msg) 
    Write-Output "$msg"
}

# Neutralize Progress bars
function Write-Progress { return }
function Disable-ProgressBar { return }
function Set-OverallProgress { return }

# Kudu-safe logging (File logging commented out)
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format "HH:mm:ss"
    
    # Standard Output to Console (Safe)
    Write-Output "[$ts] [$Level] $Message"
    
    # [COMMENTED OUT LOG FILE GENERATION]
    # $logLine = "[$ts] [$Level] $Message"
    # $logLine | Out-File -FilePath $script:LogFilePath -Append -Encoding UTF8
}

try {
    # ---------------------------------------------------------
    # 2. PATHS
    # ---------------------------------------------------------
    # Container Apps & Local development - use script directory
    $RepoRoot = if ($PSScriptRoot) {
        $PSScriptRoot
    } else {
        # Fallback to current directory
        Get-Location | Select-Object -ExpandProperty Path
    }
    
    $ReportDir = Join-Path $RepoRoot "report"
    if (!(Test-Path $ReportDir)) { 
        Write-Output "[INFO] Creating report directory: $ReportDir"
        New-Item $ReportDir -ItemType Directory -Force | Out-Null 
    }
    
    Write-Output "[INFO] Report directory set to: $ReportDir"
    
    # [COMMENTED OUT]
    # $script:LogFilePath = Join-Path $ReportDir "Assessment.log"

    # ---------------------------------------------------------
    # 3. SILENT MODULE LOADING
    # ---------------------------------------------------------
    Write-Log "Checking required PowerShell modules..."
    
    # Check and load Az.Accounts
    if (!(Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Log "ERROR: Az.Accounts module not found. Install with: Install-Module -Name Az.Accounts -Force" "ERROR"
        throw "Required module Az.Accounts is not installed"
    }
    Write-Log "Loading Az.Accounts (Silent Mode)..."
    Import-Module Az.Accounts -Force -ErrorAction Stop -WarningAction SilentlyContinue
    
    # Check and load Az.Resources
    if (!(Get-Module -ListAvailable -Name Az.Resources)) {
        Write-Log "ERROR: Az.Resources module not found. Install with: Install-Module -Name Az.Resources -Force" "ERROR"
        throw "Required module Az.Resources is not installed"
    }
    Write-Log "Loading Az.Resources (Silent Mode)..."
    Import-Module Az.Resources -Force -ErrorAction Stop -WarningAction SilentlyContinue

    # ---------------------------------------------------------
    # 4. AUTHENTICATION (Managed Identity)
    # ---------------------------------------------------------
    Write-Log "Authenticating via Managed Identity..."
    if (-not (Get-AzContext)) {
        Connect-AzAccount -Identity -Subscription $SubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    } else {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }
    Write-Log "Authentication Successful."

    # ---------------------------------------------------------
    # 5. CORE LOGIC: Managed vs Reference (Exclusion Based)
    # ---------------------------------------------------------
    # Load Exclusion List
    $ExclusionFile = Join-Path $RepoRoot "exclusion.json"
    $ExcludedResources = @()
    $ExcludedTypes = @()

    if (Test-Path $ExclusionFile) {
        try {
            $json = Get-Content $ExclusionFile -Raw | ConvertFrom-Json
            if ($json.excludedResources) { $ExcludedResources = $json.excludedResources }
            if ($json.excludedResourceTypes) { $ExcludedTypes = $json.excludedResourceTypes | ForEach-Object { $_.ToLower() } }
            Write-Log "Loaded exclusion configuration from $ExclusionFile"
        } catch {
            Write-Log "WARNING: Failed to read exclusion.json: $_"
        }
    } else {
        Write-Log "WARNING: Exclusion file not found at $ExclusionFile"
    }

    $ManagedItems = New-Object System.Collections.Generic.List[object]
    $ReferenceItems = New-Object System.Collections.Generic.List[object]

    Write-Log "Discovering Resources..."
    Write-Log "Using exclusion.json as single source of truth for Reference resources"
    $groups = if ($ResourceGroupName) { $ResourceGroupName | ForEach-Object { Get-AzResourceGroup -Name $_ } } else { Get-AzResourceGroup }

    foreach ($rg in $groups) {
        Write-Log "Scanning RG: $($rg.ResourceGroupName)"
        $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
        
        foreach ($res in $resources) {
            $type = $res.ResourceType
            $typeLower = $type.ToLower()
            $name = $res.Name

            $item = [PSCustomObject]@{
                RG   = $rg.ResourceGroupName
                Name = $res.Name
                Type = $res.ResourceType
            }

            # Simplified Decision Logic (exclusion.json is the single source of truth):
            # 1. If resource name is in ExcludedResources list -> Reference (Platform/Infrastructure)
            # 2. If resource type is in ExcludedTypes list -> Reference (Platform/Infrastructure)
            # 3. Otherwise -> Managed (Workload resources to be migrated)
            
            if ($ExcludedResources -contains $name -or $ExcludedTypes -contains $typeLower) {
                $ReferenceItems.Add($item)
                Write-Log "  [Reference] $($res.Name) ($($res.ResourceType))" "DEBUG"
            } else {
                $ManagedItems.Add($item)
                Write-Log "  [Managed] $($res.Name) ($($res.ResourceType))" "DEBUG"
            }
        }
    }

    # ---------------------------------------------------------
    # 6. DECISION LOGIC (For aztfexport)
    # ---------------------------------------------------------
    $CountManaged   = $ManagedItems.Count
    $CountReference = $ReferenceItems.Count
    $TotalCount     = $CountManaged + $CountReference

    $Decision = "Undetermined"
    $Recommendation = "N/A"
    $ColorClass = "neutral"

    if ($TotalCount -eq 0) {
        $Decision = "Not Applicable"
        $Recommendation = "No resources found to export."
        $ColorClass = "neutral"
    } elseif ($CountManaged -gt 0) {
        $Decision = "Strong Candidate"
        $Recommendation = "Contains $CountManaged supported workload resources. Use 'aztfexport' to codify."
        $ColorClass = "success"
    } elseif ($CountReference -gt 0) {
        $Decision = "Review Required"
        $Recommendation = "Mostly platform resources. Verify if these are already managed by another state file before importing."
        $ColorClass = "warning"
    }

    $OutcomeTable = [PSCustomObject]@{
        'Total Resources' = $TotalCount
        'Managed Items'   = $CountManaged
        'Reference Items' = $CountReference
        'Decision'        = $Decision
        'Recommendation'  = $Recommendation
    }
    
    # Output outcome table as JSON for programmatic consumption
    Write-Log \"Assessment Decision\" \"INFO\"
    Write-Log \"$(($OutcomeTable | ConvertTo-Json -Compress))\" \"RESULT\"

    # ---------------------------------------------------------
    # 7. REPORT GENERATION
    # ---------------------------------------------------------
    $rgName = if ($ResourceGroupName -and $ResourceGroupName.Count -gt 0) { $ResourceGroupName[0] } else { "all" }
    # Use consistent filename (without timestamp) to ensure only latest report is kept
    $htmlPath = Join-Path $ReportDir "Assessment-Report-Latest.html"
    
    $style = @"
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #F5F5F5; color: #333; line-height: 1.6; }
    .container { max-width: 1400px; margin: 0 auto; background: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px 30px; text-align: center; }
    .header h1 { font-size: 32px; margin-bottom: 10px; font-weight: 600; }
    .header p { font-size: 16px; opacity: 0.9; }
    .content { padding: 30px; }
    .section { margin-bottom: 40px; background: white; border-radius: 8px; }
    .section-title { background: #F8F9FA; padding: 15px 20px; font-size: 20px; font-weight: bold; color: #2E5090; border-left: 5px solid #4472C4; margin-bottom: 20px; border-radius: 4px; }
    .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; margin-bottom: 20px; }
    .info-item { background: #F8F9FA; padding: 15px; border-radius: 5px; border-left: 3px solid #4472C4; }
    .info-label { font-weight: bold; color: #2E5090; font-size: 14px; margin-bottom: 5px; }
    .info-value { color: #333; font-size: 16px; }
    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
    .stat-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; box-shadow: 0 4px 15px rgba(0,0,0,0.1); transition: transform 0.3s; }
    .stat-card:hover { transform: translateY(-5px); }
    .stat-number { font-size: 36px; font-weight: bold; margin-bottom: 5px; }
    .stat-label { font-size: 14px; opacity: 0.9; }
    table { width: 100%; border-collapse: collapse; margin-top: 15px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); border-radius: 8px; overflow: hidden; }
    table thead { background: #4472C4; color: white; }
    table th { padding: 12px; text-align: left; font-weight: 600; font-size: 14px; }
    table tbody tr { border-bottom: 1px solid #E0E0E0; transition: background 0.2s; }
    table tbody tr:hover { background: #F5F5F5; }
    table tbody tr:last-child { border-bottom: none; }
    table td { padding: 12px; font-size: 13px; }
    .status-managed { background: #28A745; color: white; padding: 4px 12px; border-radius: 4px; font-size: 11px; font-weight: bold; display: inline-block; }
    .status-reference { background: #FFC107; color: #333; padding: 4px 12px; border-radius: 4px; font-size: 11px; font-weight: bold; display: inline-block; }
    .success { background-color: #dff6dd; color: #107c10; font-weight: bold; padding: 8px; }
    .warning { background-color: #fff4ce; color: #795e00; font-weight: bold; padding: 8px; }
    .neutral { background-color: #f3f2f1; color: #323130; padding: 8px; }
    .type-count { display: flex; justify-content: space-between; padding: 10px 15px; background: #F8F9FA; margin-bottom: 5px; border-radius: 3px; border-left: 3px solid #4472C4; }
    .type-name { font-weight: 500; color: #333; }
    .type-number { font-weight: bold; color: #4472C4; background: white; padding: 2px 8px; border-radius: 3px; }
    .footer { background: #F8F9FA; padding: 20px 30px; text-align: center; color: #666; font-size: 14px; border-top: 2px solid #E0E0E0; }
    .highlight-box { background: #E3F2FD; border-left: 4px solid #2196F3; padding: 15px; margin: 15px 0; border-radius: 4px; }
</style>
"@

    # Group resources by type for summary
    $managedByType = $ManagedItems | Group-Object -Property Type | Select-Object @{Name='ResourceType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
    $referenceByType = $ReferenceItems | Group-Object -Property Type | Select-Object @{Name='ResourceType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending
    
    $currentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure Subscription Assessment Report</title>
    $style
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Azure Subscription Assessment Report</h1>
            <p>Subscription: $SubscriptionId</p>
        </div>
        
        <div class="content">
            <!-- Assessment Summary -->
            <div class="section">
                <div class="section-title">Assessment Summary</div>
                <div class="stats-grid">
                    <div class="stat-card">
                        <div class="stat-number">$TotalCount</div>
                        <div class="stat-label">Total Resources</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">$CountManaged</div>
                        <div class="stat-label">Managed Resources</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">$CountReference</div>
                        <div class="stat-label">Reference Resources</div>
                    </div>
                </div>
            </div>
            
            <!-- Report Outcome -->
            <div class="section">
                <div class="section-title">Report Outcome: aztfexport Suitability</div>
                <table>
                    <thead>
                        <tr><th>Metric</th><th>Value</th></tr>
                    </thead>
                    <tbody>
                        <tr><td>Total Resources</td><td><strong>$TotalCount</strong></td></tr>
                        <tr><td>Managed (Workload)</td><td><span class="status-managed">$CountManaged</span></td></tr>
                        <tr><td>Reference (Platform)</td><td><span class="status-reference">$CountReference</span></td></tr>
                        <tr class='$ColorClass'><td><strong>Decision</strong></td><td><strong>$Decision</strong></td></tr>
                        <tr><td>Recommendation</td><td>$Recommendation</td></tr>
                    </tbody>
                </table>
            </div>
            
            <!-- Managed Resources by Type -->
            <div class="section">
                <div class="section-title">Managed Resources by Type</div>
"@
    
    if ($managedByType.Count -gt 0) {
        foreach ($type in $managedByType) {
            $htmlContent += @"
                <div class="type-count">
                    <span class="type-name">$($type.ResourceType)</span>
                    <span class="type-number">$($type.Count)</span>
                </div>
"@
        }
    } else {
        $htmlContent += '<p style="color: #666; font-style: italic; padding: 10px;">No managed resources found.</p>'
    }
    
    $htmlContent += @"
            </div>
            
            <!-- Reference Resources by Type -->
            <div class="section">
                <div class="section-title">Reference Resources by Type</div>
"@
    
    if ($referenceByType.Count -gt 0) {
        foreach ($type in $referenceByType) {
            $htmlContent += @"
                <div class="type-count">
                    <span class="type-name">$($type.ResourceType)</span>
                    <span class="type-number">$($type.Count)</span>
                </div>
"@
        }
    } else {
        $htmlContent += '<p style="color: #666; font-style: italic; padding: 10px;">No reference resources found.</p>'
    }
    
    $htmlContent += @"
            </div>
            
            <!-- Managed Resources Detail -->
            <div class="section">
                <div class="section-title">Managed Resources - Detailed Listing</div>
"@
    
    if ($ManagedItems.Count -gt 0) {
        $htmlContent += @"
                <table>
                    <thead>
                        <tr>
                            <th>Resource Group</th>
                            <th>Resource Name</th>
                            <th>Resource Type</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
"@
        foreach ($item in $ManagedItems) {
            $htmlContent += @"
                        <tr>
                            <td>$($item.RG)</td>
                            <td>$($item.Name)</td>
                            <td>$($item.Type)</td>
                            <td><span class="status-managed">Managed</span></td>
                        </tr>
"@
        }
        $htmlContent += @"
                    </tbody>
                </table>
"@
    } else {
        $htmlContent += '<p style="color: #666; font-style: italic; padding: 10px;">No managed resources found.</p>'
    }
    
    $htmlContent += @"
            </div>
            
            <!-- Reference Resources Detail -->
            <div class="section">
                <div class="section-title">Reference Resources - Detailed Listing</div>
"@
    
    if ($ReferenceItems.Count -gt 0) {
        $htmlContent += @"
                <table>
                    <thead>
                        <tr>
                            <th>Resource Group</th>
                            <th>Resource Name</th>
                            <th>Resource Type</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
"@
        foreach ($item in $ReferenceItems) {
            $htmlContent += @"
                        <tr>
                            <td>$($item.RG)</td>
                            <td>$($item.Name)</td>
                            <td>$($item.Type)</td>
                            <td><span class="status-reference">Reference</span></td>
                        </tr>
"@
        }
        $htmlContent += @"
                    </tbody>
                </table>
"@
    } else {
        $htmlContent += '<p style="color: #666; font-style: italic; padding: 10px;">No reference resources found.</p>'
    }
    
    $htmlContent += @"
            </div>
        </div>
        
        <div class="footer">
            <p>Report Generated: $currentDate</p>
            <p>Azure Subscription Assessment Tool</p>
        </div>
    </div>
</body>
</html>
"@
    
    $htmlContent | Out-File $htmlPath -Encoding UTF8

    Write-Log "SUCCESS: Report generated at $htmlPath"
    
    # Load .env configuration
    $envFilePath = Join-Path $PSScriptRoot "..\.env"
    if (Test-Path $envFilePath) {
        $envConfig = @{}
        Get-Content $envFilePath | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim().Trim('"')
                $envConfig[$key] = $value
            }
        }
        
        $outputDest = $envConfig["OUTPUT_DESTINATION"]
        $storageAccount = $envConfig["storageAccount"]
        $assessmentFolder = $envConfig["ASSESSMENT_FOLDER"]
        
        # Upload to Azure Blob Storage (for "azure" or "both")
        if ($outputDest -eq "azure" -or $outputDest -eq "both") {
            Write-Log "Uploading assessment report to Azure Blob Storage..."
            
            # Determine blob path based on resource group scope
            if ($ResourceGroupName -and $ResourceGroupName.Count -gt 0) {
                # Single or multiple resource groups - store under subscription/resourcegroup
                $blobPath = "$SubscriptionId/$rgName"
            } else {
                # All resource groups - store under subscription/all
                $blobPath = "$SubscriptionId/all"
            }
            $blobName = "$blobPath/Assessment-Report-Latest.html"
            
            try {
                # Check if container exists, create if not
                $containerExists = az storage container exists --account-name $storageAccount --name $assessmentFolder --auth-mode login --query "exists" --output tsv
                if ($containerExists -eq "false") {
                    Write-Log "Creating container: $assessmentFolder"
                    az storage container create --account-name $storageAccount --name $assessmentFolder --auth-mode login | Out-Null
                }
                
                # Clean up old HTML reports from this specific path (keep only the latest)
                Write-Log "Cleaning up old HTML reports from blob storage path: $blobPath/"
                try {
                    $existingBlobs = az storage blob list --account-name $storageAccount --container-name $assessmentFolder --prefix "$blobPath/" --auth-mode login --query "[?contains(name, '.html')].name" -o json 2>&1 | ConvertFrom-Json
                    
                    if ($existingBlobs -and $existingBlobs.Count -gt 0) {
                        Write-Log "Found $($existingBlobs.Count) existing HTML report(s) - deleting..."
                        foreach ($oldBlob in $existingBlobs) {
                            Write-Log "  Deleting old report: $oldBlob"
                            az storage blob delete --account-name $storageAccount --container-name $assessmentFolder --name $oldBlob --auth-mode login 2>&1 | Out-Null
                        }
                    } else {
                        Write-Log "No old HTML reports found"
                    }
                } catch {
                    Write-Log "WARNING: Could not clean up old reports: $_"
                }
                
                # Upload the new file
                az storage blob upload `
                    --account-name $storageAccount `
                    --container-name $assessmentFolder `
                    --name $blobName `
                    --file $htmlPath `
                    --auth-mode login `
                    --overwrite true | Out-Null
                
                Write-Log "SUCCESS: Assessment report uploaded to Azure Blob Storage"
                Write-Log "Storage URL: https://$storageAccount.blob.core.windows.net/$assessmentFolder/$blobName"
            } catch {
                Write-Log "WARNING: Failed to upload assessment report to Azure Blob Storage: $_"
            }
        }
        
        # Upload to GitHub (for "github" or "both")
        if ($outputDest -eq "github" -or $outputDest -eq "both") {
            Write-Log "Uploading assessment report to GitHub..."
            
            Import-Module "$PSScriptRoot\GitHubHelper.psm1" -Force
            
            $remotePath = "$($envConfig['ASSESSMENT_FOLDER'])/$SubscriptionId/$(Split-Path $htmlPath -Leaf)"
            
            $uploadResult = Upload-FileToGitHub `
                -LocalFilePath $htmlPath `
                -RemotePath $remotePath `
                -Token $envConfig["GITHUB_TOKEN"] `
                -Owner $envConfig["GITHUB_OWNER"] `
                -Repo $envConfig["GITHUB_REPO"] `
                -Branch $envConfig["GITHUB_BRANCH"] `
                -CommitMessage "Add assessment report for subscription $SubscriptionId"
            
            if ($uploadResult) {
                Write-Log "SUCCESS: Assessment report uploaded to GitHub"
                Write-Log "GitHub URL: https://github.com/$($envConfig['GITHUB_OWNER'])/$($envConfig['GITHUB_REPO'])/blob/$($envConfig['GITHUB_BRANCH'])/$remotePath"
            } else {
                Write-Log "WARNING: Failed to upload assessment report to GitHub"
            }
        }
    }

} catch {
    Write-Output "!! FATAL ERROR: $($_.Exception.Message)"
    exit 1
}