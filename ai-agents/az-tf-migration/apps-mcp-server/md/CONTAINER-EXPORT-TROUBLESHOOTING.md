# Container Export Troubleshooting Guide

## Issue Summary

### Problem Discovered
Container execution created files in a `container/` subdirectory with malformed content:
- **Location**: `azure-export/Enterprise-Enrollment-Subscription/rg-mcp-servers/container/`
- **Files**: `main(7).tf`, `variables(1).tf`, `data-sources.tf`
- **Issue**: Files contained orphaned Terraform fragments (provider config without wrappers, terraform blocks without parent blocks)

### Root Cause Analysis

1. **Parameter Mismatch**: The PowerShell script received `-ResourceGroupName "container"` instead of `-ResourceGroupName "rg-mcp-servers"`
2. **Merge Logic Failure**: The regex-based cleanup in the sandbox consolidation removed opening blocks, leaving orphaned content
3. **Windows File Naming**: Numbered suffixes like `(7)` indicate duplicate file conflicts during copy operations

## Diagnostic Information

### Expected Flow
```
SubscriptionId: "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2"
ResourceGroupName: "rg-mcp-servers"
SubscriptionName (from Azure): "Enterprise-Enrollment-Subscription"

Directory Structure:
azure-export/
├── Enterprise-Enrollment-Subscription/  ← $subscriptionName
│   └── rg-mcp-servers/                  ← $ResourceGroupName
│       ├── main.tf
│       ├── provider.tf
│       ├── terraform.tf
│       ├── data-sources.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfstate
│       └── Export-Report-Latest.html
```

### What Went Wrong
```
If ResourceGroupName = "container":

azure-export/
├── Enterprise-Enrollment-Subscription/
│   └── container/                        ← WRONG!
│       ├── main(7).tf (malformed)
│       ├── variables(1).tf (malformed)
│       └── data-sources.tf
```

## Fixes Implemented

### 1. Parameter Validation (Lines ~75-102)
```powershell
# Validates ResourceGroupName for:
- Invalid filesystem characters
- Suspicious values like 'container', 'test', 'temp', 'tmp', 'sandbox'
- Warns user if parameter looks incorrect
```

### 2. Debug Logging (Lines ~410-422)
```powershell
# Shows complete directory structure for verification:
- Script Directory
- Repo Root
- Export Root
- Subscription Directory
- Target Export Directory (final output location)
```

## Testing Instructions

### 1. Clean Up Existing Files
```powershell
# Remove the problematic container subdirectory
$containerDir = "C:\Users\sunsu\OneDrive\Desktop\Sundeep\AI-Projects\ai-Repository\Generative-AI-Projects\aiaNextGen-Products\ai-agents\az-tf-migration\apps-mcp-server\azure-export\Enterprise-Enrollment-Subscription\rg-mcp-servers\container"
if (Test-Path $containerDir) {
    Remove-Item -Path $containerDir -Recurse -Force
    Write-Host "Removed problematic container directory" -ForegroundColor Green
}
```

### 2. Test Local Execution
```powershell
cd "C:\Users\sunsu\OneDrive\Desktop\Sundeep\AI-Projects\ai-Repository\Generative-AI-Projects\aiaNextGen-Products\ai-agents\az-tf-migration\apps-mcp-server\ps"

.\Export-Container-AzToTerraform.ps1 `
    -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" `
    -ResourceGroupName "rg-mcp-servers"
```

**Expected Output:**
- Parameter validation banner showing correct values
- Directory structure showing correct paths
- No warnings about suspicious ResourceGroupName
- Files created in `.../rg-mcp-servers/` (NOT in a subdirectory)

### 3. Verify MCP Server Configuration

Check how the MCP tool is being invoked:

**File**: `tools/aztfexport.js` (Lines 40-52)

Ensure parameters are passed correctly:
```javascript
let psArgs = [
  '-NoProfile', 
  '-ExecutionPolicy', 
  'Bypass', 
  '-File', 
  resolvedScript, 
  '-SubscriptionId', 
  job.subscriptionId,        // Must be valid subscription GUID
  '-ResourceGroupName',
  job.resourceGroup          // Must be actual Azure RG name, NOT 'container'
];
```

### 4. Test Container Execution

**Deploy updated script:**
```powershell
# Build and push updated image
docker build --no-cache -t aztf-mcp-server .
docker tag aztf-mcp-server:latest <your-acr>.azurecr.io/aztf-mcp-server:latest
docker push <your-acr>.azurecr.io/aztf-mcp-server:latest
```

**Invoke MCP tool with CORRECT parameters:**
```json
{
  "tool": "export_azure_to_terraform",
  "parameters": {
    "subscriptionId": "d0f1884d-1-9e15-e2986fc1bca2",
    "resourceGroup": "rg-mcp-servers"  // ← Use actual Azure RG name!
  }
}
```

### 5. Verify Container Output

**Check container logs:**
```powershell
az containerapp logs show `
    --name aztf-mcp-app `
    --resource-group rg-aztf-mcp `
    --follow
```

**Look for:**
- ✅ Parameter Validation banner showing correct values
- ✅ Directory Structure showing `.../rg-mcp-servers/` (not `.../container/`)
- ✅ No warnings about suspicious ResourceGroupName
- ✅ "Standards enforcement completed"
- ✅ "Generating HTML export report"
- ✅ Files uploaded to Azure Storage

## Validation Checklist

After container run, verify:

- [ ] No `container/` subdirectory created
- [ ] main.tf contains properly formatted resources (not fragments)
- [ ] provider.tf exists with complete `provider "azurerm" { ... }` block
- [ ] terraform.tf exists with complete `terraform { ... }` block
- [ ] data-sources.tf, variables.tf, outputs.tf all exist
- [ ] terraform.tfstate exists
- [ ] Export-Report-Latest.html exists and contains resource summary
- [ ] All files uploaded to Azure Storage

## Common Mistakes to Avoid

### ❌ Incorrect Parameters
```powershell
# DON'T pass execution mode as resource group
-ResourceGroupName "container"    # WRONG!
-ResourceGroupName "test"         # WRONG!
-ResourceGroupName "sandbox"      # WRONG!
```

### ✅ Correct Parameters
```powershell
# DO pass actual Azure Resource Group name
-ResourceGroupName "rg-mcp-servers"           # Correct
-ResourceGroupName "rg-production-eastus2"    # Correct
-ResourceGroupName "my-app-infrastructure"    # Correct
```

### ❌ Don't Confuse These Concepts
- **EXECUTION_MODE** environment variable (value: "CONTAINER" or "LOCAL") ← Used by router script
- **ResourceGroupName** parameter (value: actual Azure RG name) ← Used by export script
- **StorageContainer** parameter (value: "aztfexport") ← Azure Storage container name

## File Structure Reference

### Correct Structure (Local Run)
```
azure-export/
└── Enterprise-Enrollment-Subscription/
    └── rg-mcp-servers/
        ├── main.tf (1,500+ lines, properly formatted resources)
        ├── provider.tf (complete provider block)
        ├── terraform.tf (complete terraform block)
        ├── data-sources.tf (reference data sources)
        ├── variables.tf (input variables)
        ├── outputs.tf (output values)
        ├── terraform.tfstate (state file from aztfexport)
        └── Export-Report-Latest.html (HTML report)
```

### Incorrect Structure (Container Run with Wrong Parameter)
```
azure-export/
└── Enterprise-Enrollment-Subscription/
    └── rg-mcp-servers/
        └── container/  ← WRONG: Created because ResourceGroupName was "container"
            ├── main(7).tf (orphaned fragments, malformed)
            ├── variables(1).tf (orphaned fragments, malformed)
            └── data-sources.tf
```

## Additional Resources

- [Export-Container-AzToTerraform.ps1](../ps/Export-Container-AzToTerraform.ps1) - Main export script
- [Export-AzToTerraform.ps1](../ps/Export-AzToTerraform.ps1) - Router script
- [aztfexport.js](../tools/aztfexport.js) - MCP tool implementation
- [Dockerfile](../Dockerfile) - Container configuration

## Support

If issues persist:

1. Check container logs for parameter values in "PARAMETER VALIDATION" section
2. Verify directory structure in "DIRECTORY STRUCTURE" section
3. Ensure no warnings about suspicious ResourceGroupName
4. Confirm MCP tool passes correct `job.resourceGroup` value
5. Validate Azure Resource Group actually exists and is accessible

---

**Last Updated**: 2025-02-10
**Script Version**: Export-Container-AzToTerraform.ps1 v2.1 (with parameter validation)
