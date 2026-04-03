# Container Isolation Fix Summary

**Issue**: Export output files were being uploaded to the assessment container instead of the dedicated export container, causing export and code refactor failures.

**Root Cause**: The environment variable `AZURE_STORAGE_CONTAINER` was being set globally, causing all three components (assessment, export, refactor) to upload to the same container.

## ✅ Solution Implemented

### 1. Automatic Container Creation

All three scripts now automatically create their dedicated containers if they don't exist:
- **Export-Container-AzToTerraform.py**: Creates `aztfexport` container before upload
- **assessment-AzSubscription.py**: Creates `assessment-reports` container before upload  
- **tf_refactor_variable.py**: Creates `code-refactored` container before upload

This ensures zero-configuration deployment - containers are created on-demand without manual setup.

### 2. Dedicated Container Environment Variables

Each component now uses its own dedicated environment variable to ensure complete isolation:

| Component | Container Name | Environment Variable | Purpose |
|-----------|---------------|---------------------|---------|
| **Assessment** | `assessment-reports` | `ASSESSMENT_FOLDER` | Assessment reports only |
| **Export** | `aztfexport` | `AZTFEXPORT_FOLDER` | Terraform export files only |
| **Refactor** | `code-refactored` | `CODE_REFACTORED_FOLDER` | Refactored Terraform code only |

### 2. Code Changes

#### Export-Container-AzToTerraform.py (Line 228)
**BEFORE**: 
```python
container = os.getenv("AZURE_STORAGE_CONTAINER", "aztfexport")
```

**AFTER**:
```python
# Use dedicated AZTFEXPORT_FOLDER to prevent cross-contamination
container = os.getenv("AZTFEXPORT_FOLDER", "aztfexport")
```

#### assessment-AzSubscription.py (Line 326)
**BEFORE**:
```python
container_name = os.getenv("containerName", "assessment-reports")
```

**AFTER**:
```python
# Use dedicated ASSESSMENT_FOLDER to prevent cross-contamination
container_name = os.getenv("ASSESSMENT_FOLDER", "assessment-reports")
```

#### deploy.ps1 (Lines 683-685)
**BEFORE** (conditional - only set if defined):
```powershell
if ($script:AztfexportFolder)   { $envVars += "AZTFEXPORT_FOLDER=$($script:AztfexportFolder)" }
if ($script:CodeRefactoredFolder) { $envVars += "CODE_REFACTORED_FOLDER=$($script:CodeRefactoredFolder)" }
if ($script:AssessmentFolder)   { $envVars += "ASSESSMENT_FOLDER=$($script:AssessmentFolder)" }
```

**AFTER** (always set with defaults):
```powershell
# CRITICAL: Always set container-specific folder names to enforce isolation
$envVars += "AZTFEXPORT_FOLDER=$(if ($script:AztfexportFolder) { $script:AztfexportFolder } else { 'aztfexport' })"
$envVars += "CODE_REFACTORED_FOLDER=$(if ($script:CodeRefactoredFolder) { $script:CodeRefactoredFolder } else { 'code-refactored' })"
$envVars += "ASSESSMENT_FOLDER=$(if ($script:AssessmentFolder) { $script:AssessmentFolder } else { 'assessment-reports' })"
```

#### Refactor Already Correct ✅
tf_refactor_variable.py (Lines 484-485) was already using dedicated variables:
```python
self.source_container = os.getenv('AZTFEXPORT_FOLDER', 'aztfexport')
self.output_container = os.getenv('CODE_REFACTORED_FOLDER', 'code-refactored')
```

### 3. Storage Containers Created

All three containers now exist in storage account `samcpstorage`:

```
Container           Created
------------------  -------------------------
assessment-reports  2026-04-03T01:59:11+00:00
aztfexport          2026-04-03T04:29:24+00:00
code-refactored     2026-04-03T04:29:28+00:00
```

### 4. Environment Variables Set

For local development sessions (current PowerShell):
```powershell
$env:AZTFEXPORT_FOLDER = "aztfexport"
$env:CODE_REFACTORED_FOLDER = "code-refactored"
$env:ASSESSMENT_FOLDER = "assessment-reports"
```

For container app deployments: These are now automatically set by deploy.ps1 with proper defaults.

## 🔒 Container Isolation Flow

### Assessment Agent
1. Runs assessment on subscription/resource group
2. Generates `Assessment-Report-Latest.html`
3. **Uploads to**: `assessment-reports` container
4. Uses env var: `ASSESSMENT_FOLDER`

### Export Agent
1. Runs `aztfexport` to generate Terraform files
2. Generates `.tf`, `.tfstate`, reports
3. **Uploads to**: `aztfexport` container
4. Uses env var: `AZTFEXPORT_FOLDER`

### Refactor Agent
1. **Downloads from**: `aztfexport` container (reads export output)
2. Refactors Terraform code per enterprise standards
3. **Uploads to**: `code-refactored` container
4. Uses env vars: `AZTFEXPORT_FOLDER` (source) + `CODE_REFACTORED_FOLDER` (destination)

## 🚀 Testing & Validation

### Prerequisites
- **Storage Account**: `samcpstorage` must exist
- **Containers**: No manual creation needed - containers are automatically created by each script if they don't exist
- **Permissions**: User/managed identity needs Storage Blob Data Contributor role

### Local Testing
After setting environment variables, run workflow:
```powershell
# Set environment variables (already done above)
$env:AZTFEXPORT_FOLDER = "aztfexport"
$env:CODE_REFACTORED_FOLDER = "code-refactored"
$env:ASSESSMENT_FOLDER = "assessment-reports"

# Run workflow from command.md
python aztf-sequential-wf.py "Migrate resource group 'rg-mcp-servers' from subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2"
```

### Verify Isolation
After workflow completes, verify each container has only its own outputs:
```powershell
# Check assessment container (should only have assessment reports)
az storage blob list --account-name samcpstorage --container-name assessment-reports --auth-mode login --query "[].name" -o table

# Check export container (should only have .tf files from export)
az storage blob list --account-name samcpstorage --container-name aztfexport --auth-mode login --query "[].name" -o table

# Check refactor container (should only have refactored code)
az storage blob list --account-name samcpstorage --container-name code-refactored --auth-mode login --query "[].name" -o table
```

## ⚠️ Migration Notes

**If you had files in wrong containers before this fix**, you may want to clean them up or move them:

```powershell
# Example: Delete misplaced export files from assessment container
az storage blob delete-batch --account-name samcpstorage --source assessment-reports --pattern "**/*.tf" --auth-mode login

# Example: Move files to correct container (manual verification recommended)
# az storage blob copy start-batch --source-container assessment-reports --destination-container aztfexport --account-name samcpstorage --auth-mode login
```

## 📝 Deployment Checklist

When deploying to Azure Container Apps:
- ✅ deploy.ps1 now automatically sets container isolation env vars
- ✅ No manual configuration needed
- ✅ All three containers auto-created if missing
- ✅ RBAC permissions: Container app managed identity needs "Storage Blob Data Contributor" on storage account

## 🔍 Troubleshooting

### Issue: Export still going to wrong container
**Check**: Ensure environment variable is set before export runs:
```powershell
echo "Export container: $env:AZTFEXPORT_FOLDER"  # Should be "aztfexport"
```

### Issue: Refactor fails to find export files
**Check**: Verify export files are in `aztfexport` container:
```powershell
az storage blob list --account-name samcpstorage --container-name aztfexport --prefix "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers" --auth-mode login --query "[].name" -o table
```

### Issue: Container not found error
**Check**: Storage account containers exist:
```powershell
az storage container list --account-name samcpstorage --auth-mode login --query "[].name" -o table
```

**Fix**: Create missing containers:
```powershell
az storage container create --name aztfexport --account-name samcpstorage --auth-mode login
az storage container create --name code-refactored --account-name samcpstorage --auth-mode login
az storage container create --name assessment-reports --account-name samcpstorage --auth-mode login
```

---

**Date Fixed**: 2026-04-03  
**Files Modified**:
- `python/Export-Container-AzToTerraform.py` (line 228)
- `python/assessment-AzSubscription.py` (line 326)
- `deploy.ps1` (lines 683-685)
- `python/tf_refactor_variable.py` (already correct)

**Containers Created**:
- `aztfexport` (2026-04-03)
- `code-refactored` (2026-04-03)
- `assessment-reports` (existing)
