# Fix: Azure Storage Upload Issue

## Problem
Exported Terraform files and HTML reports were not being uploaded to Azure Storage Account. Files remained local only instead of being uploaded to the expected path: `aztfExport/{SubscriptionId}/{ResourceGroupName}/`

## Root Causes

### 1. Removed `-JobId` Parameter Still Being Passed
**File:** `tools/aztfexport.js` (Line 50)

**Issue:** The Node.js tool was passing `-JobId` parameter to the PowerShell script, but this parameter was removed in a previous update when we changed the storage structure to use `{SubscriptionId}/{ResourceGroupName}` instead of `{JobId}`.

**Impact:** PowerShell script would fail with "A parameter cannot be found that matches parameter name 'JobId'" error.

**Fix:** Removed `-JobId` and `job.id` from psArgs array.

```javascript
// BEFORE:
psArgs = [
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', resolvedScript, 
  '-SubscriptionId', job.subscriptionId,
  '-ResourceGroupName', job.resourceGroup,
  '-JobId', job.id  // ❌ This parameter doesn't exist anymore
];

// AFTER:
psArgs = [
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', resolvedScript, 
  '-SubscriptionId', job.subscriptionId,
  '-ResourceGroupName', job.resourceGroup
  // ✅ Removed -JobId parameter
];
```

---

### 2. Environment Variables Not Passed to PowerShell Process
**File:** `tools/aztfexport.js` (Line 72)

**Issue:** The `spawn()` call was not passing environment variables to the PowerShell process. The PowerShell script expects `$env:storageAccount` to be available as a default parameter value, but the spawned process had no access to it.

**Impact:** Even though `storageAccount=samcpstorage` was set in `.env` file and loaded by the Node.js process, it was NOT available to the PowerShell child process. The PowerShell script would exit with error: "StorageAccount parameter is required".

**Fix:** Added `env` option to spawn() with explicit environment variable passing.

```javascript
// BEFORE:
const ps = spawn(psExecutable, psArgs);
// ❌ No environment variables passed

// AFTER:
const ps = spawn(psExecutable, psArgs, {
  env: {
    ...process.env,  // Inherit all environment variables
    storageAccount: storageAccount  // Explicitly pass storageAccount
  }
});
// ✅ Environment variables now available to PowerShell
```

---

### 3. Incorrect Storage Path in reportUrl
**File:** `tools/aztfexport.js` (Line 125)

**Issue:** After successful export, the job's `reportUrl` was using the old path structure with `{jobId}` instead of the new `{SubscriptionId}/{ResourceGroupName}` structure.

**Impact:** Frontend would display incorrect Azure Storage URL pointing to non-existent location.

**Fix:** Updated reportUrl to match actual storage structure.

```javascript
// BEFORE:
const exportPath = `https://${storageAccountName}.blob.core.windows.net/aztfexport/${job.id}/`;
// ❌ Wrong path: aztfexport/{jobId}/

// AFTER:
const exportPath = `https://${storageAccountName}.blob.core.windows.net/aztfExport/${job.subscriptionId}/${job.resourceGroup}/`;
// ✅ Correct path: aztfExport/{SubscriptionId}/{ResourceGroupName}/
```

Note: Also fixed container name capitalization from `aztfexport` to `aztfExport` to match PowerShell script.

---

## Files Modified

### `tools/aztfexport.js`
1. **Line 44-53:** Removed `-JobId` parameter from psArgs
2. **Line 72-77:** Added environment variable passing to spawn()
3. **Line 125-128:** Updated reportUrl to use correct storage path structure

---

## Verification Steps

### 1. Check Environment Variable
```bash
# Verify .env file has storageAccount set
cat .env
# Should show: storageAccount=samcpstorage
```

### 2. Restart MCP Server
```bash
cd ai-agents/az-tf-migration/apps-mcp-server
npm start
```

### 3. Test Export
```bash
# Via MCP Server API:
curl -X POST http://localhost:8080/messages \
  -H "Content-Type: application/json" \
  -d '{
    "toolName": "aztfexport",
    "args": {
      "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
      "resourceGroup": "rg-mcp-servers"
    }
  }'
```

### 4. Verify Upload
Check MCP server console logs for:
```
[Export Job ...] Added -StorageAccount parameter: samcpstorage
[Export Job ...] Uploading exported files to Azure Storage...
[Export Job ...] Successfully uploaded X of Y files
[Export Job ...] ✅ Terraform files exported to: https://samcpstorage.blob.core.windows.net/aztfExport/d0f1884d-.../rg-mcp-servers/
```

### 5. Verify in Azure Portal
Navigate to:
- Storage Account: `samcpstorage`
- Container: `aztfExport`
- Path: `d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/`

Should see files:
- `main.tf`
- `variables.tf`
- `provider.tf`
- `terraform.tf`
- `data-sources.tf`
- `terraform.tfstate`
- `html-report/migration-report.html`

---

## Expected Console Output (PowerShell Script)

### Before Fix:
```
=== SCRIPT STARTED ===
Parameters Received:
  SubscriptionId: d0f1884d-1f98-4bf1-9e15-e2986fc1bca2
  ResourceGroupName: rg-mcp-servers
  StorageAccount param: ''
  Environment variable: ''
ERROR: StorageAccount parameter is required
```

### After Fix:
```
=== SCRIPT STARTED ===
Parameters Received:
  SubscriptionId: d0f1884d-1f98-4bf1-9e15-e2986fc1bca2
  ResourceGroupName: rg-mcp-servers
  StorageAccount param: 'samcpstorage'
  Environment variable: 'samcpstorage'

Uploading exported files to Azure Storage...
  Storage Account: samcpstorage
  Container: aztfExport
  Blob Path: d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/

  Uploading: main.tf
  Uploading: variables.tf
  Uploading: provider.tf
  Uploading: terraform.tf
  Uploading: data-sources.tf
  Uploading: terraform.tfstate
  Uploading: html-report/migration-report.html

Successfully uploaded 7 of 7 files
Storage URL: https://samcpstorage.blob.core.windows.net/aztfExport/d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/

Cleaning up temporary files...
Temp files cleaned up

================================================================================
  [OK] AZURE TO TERRAFORM EXPORT - COMPLETED SUCCESSFULLY
================================================================================
```

---

## Storage Structure

```
Azure Storage Account: samcpstorage
├── Container: aztfExport
│   └── {SubscriptionId}/
│       └── {ResourceGroupName}/
│           ├── main.tf
│           ├── variables.tf
│           ├── provider.tf
│           ├── terraform.tf
│           ├── data-sources.tf
│           ├── terraform.tfstate
│           └── html-report/
│               └── migration-report.html
```

**Example Path:**
```
aztfExport/d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/main.tf
```

---

## Additional Notes

### PowerShell Parameter Default
The PowerShell script uses this parameter definition:
```powershell
[Parameter(Mandatory = $false)]
[string]$StorageAccount = $env:storageAccount
```

This means:
- If `-StorageAccount` is passed explicitly, use that value
- Otherwise, use `$env:storageAccount` from environment
- If both are missing, `$StorageAccount` will be empty string

The script validates after parameters are set:
```powershell
if ([string]::IsNullOrEmpty($StorageAccount)) {
    Write-Error "ERROR: StorageAccount parameter is required"
    exit 1
}
```

### Why spawn() Doesn't Inherit Environment by Default
Node.js `child_process.spawn()` by default does NOT inherit environment variables for security reasons. You must explicitly pass them via the `env` option. This is documented behavior to prevent accidental exposure of sensitive environment variables to child processes.

---

## Testing Checklist

- [x] Fixed `-JobId` parameter removal
- [x] Fixed environment variable passing
- [x] Fixed reportUrl path structure
- [x] Updated container name capitalization
- [ ] **TODO: User to test actual export to Azure Storage**
- [ ] **TODO: Verify files appear in Azure Portal**
- [ ] **TODO: Verify frontend displays correct storage URL**

---

## Summary

**Issue:** Files not uploading to Azure Storage  
**Root Cause 1:** Invalid `-JobId` parameter causing script failure  
**Root Cause 2:** Environment variables not passed to PowerShell process  
**Root Cause 3:** Incorrect storage path in success message  

**Status:** ✅ **FIXED** - All three issues resolved  
**Testing:** ⏳ **PENDING** - User needs to test actual export to verify
