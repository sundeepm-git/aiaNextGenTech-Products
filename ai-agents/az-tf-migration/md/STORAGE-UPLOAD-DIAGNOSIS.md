# Storage Upload Issue - Diagnosis and Fix

## Problem

Exported Terraform files are NOT being uploaded to Azure Storage account `samcpstorage`. Files remain local only in temp directory instead of being uploaded to:
```
Storage Path: aztfExport/{SubscriptionId}/{ResourceGroupName}/
Example: aztfExport/d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/
```

## Root Cause Analysis

Based on the FIX-STORAGE-UPLOAD.md document already in the repository, the issue has been identified and fixed:

### Issue 1: Invalid -JobId Parameter ✅ FIXED
**Problem:** The PowerShell script no longer accepts `-JobId` parameter, but `aztfexport.js` was still passing it.

**Location:** `tools/aztfexport.js` Line 44-53

**Fix Applied:** Removed `-JobId` parameter from psArgs array.

### Issue 2: Environment Variables Not Passed ✅ FIXED  
**Problem:** Node.js `spawn()` does NOT inherit environment variables by default. The `storageAccount` environment variable was not being passed to PowerShell, causing the upload to fail silently.

**Location:** `tools/aztfexport.js` Line 72-77

**Fix Applied:** Added `env` option to spawn:
```javascript
spawn(psExecutable, psArgs, {
  env: {
    ...process.env,
    storageAccount: storageAccount
  }
});
```

### Issue 3: Wrong Storage Path ✅ FIXED
**Problem:** The `reportUrl` was using obsolete `{jobId}` path instead of `{SubscriptionId}/{ResourceGroupName}`.

**Location:** `tools/aztfexport.js` Line 125-128

**Fix Applied:** Updated reportUrl to:
```javascript
aztfExport/${job.subscriptionId}/${job.resourceGroup}/
```

## Enhanced Upload Logic ✅ IMPROVED

The PowerShell script has been enhanced with:

1. **Azure CLI Authentication Check**
   - Verifies user is logged in to Azure
   - Shows authenticated user

2. **Storage Account Validation**
   - Checks if storage account exists
   - Verifies accessibility
   - Shows clear error messages

3. **Container Auto-Creation**
   - Checks if container exists
   - Creates container if missing
   - Handles permission errors

4. **Detailed Upload Logging**
   - DEBUG output for each step
   - Detailed error messages
   - Failed upload tracking
   - Success/failure count

5. **Conditional Cleanup**
   - Only deletes temp files if ALL uploads succeed
   - Keeps files locally if any upload fails
   - Shows temp directory location

## Verification Steps

### 1. Restart MCP Server (REQUIRED)
The environment variable fix requires restarting the MCP server:

```bash
cd ai-agents/az-tf-migration/apps-mcp-server
npm start
```

### 2. Run Export via UI or MCP Server

**Via UI:**
```
1. Navigate to Migration page
2. Enter:
   - Subscription ID: d0f1884d-1f98-4bf1-9e15-e2986fc1bca2
   - Resource Group: rg-mcp-servers
3. Click "Start Export"
4. Watch logs for "Uploading" messages
```

**Via MCP Server API:**
```bash
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

### 3. Monitor Logs

Look for these debug messages in the output:

```
DEBUG: Verifying Azure CLI authentication...
DEBUG: Azure CLI authenticated as: user@example.com
DEBUG: Checking storage account accessibility...
DEBUG: Storage account accessible
DEBUG: Checking if container 'aztfExport' exists...
DEBUG: Container exists (or created)
DEBUG: Found X files to upload
  Uploading: main.tf
DEBUG: Blob name: d0f1884d-.../rg-mcp-servers/main.tf
DEBUG: Upload successful
...
Successfully uploaded X of X files
Storage URL: https://samcpstorage.blob.core.windows.net/aztfExport/...
```

### 4. Verify in Azure Portal

1. Navigate to Azure Portal
2. Go to Storage Account: `samcpstorage`
3. Click "Containers"
4. Click "aztfExport"
5. Navigate to: `d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/`
6. Verify files are present:
   - main.tf
   - variables.tf
   - provider.tf
   - terraform.tf
   - data-sources.tf
   - terraform.tfstate
   - html-report/ (folder)

### 5. Check via Azure CLI

```bash
# List files in storage
az storage blob list \
  --account-name samcpstorage \
  --container-name aztfExport \
  --prefix "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/" \
  --auth-mode login \
  --output table
```

## Common Issues and Solutions

### Issue: "Not logged in to Azure CLI"

**Solution:**
```bash
az login
```

Then retry the export.

### Issue: "Cannot access storage account"

**Possible Causes:**
1. Storage account name is incorrect
2. Insufficient permissions
3. Storage account doesn't exist

**Solution:**
```bash
# Verify storage account exists
az storage account show --name samcpstorage

# Check your permissions
az role assignment list --assignee $(az account show --query user.name -o tsv) --scope /subscriptions/{subscriptionId}
```

You need at least "Storage Blob Data Contributor" role.

### Issue: "Failed to create container"

**Cause:** Insufficient permissions to create containers.

**Solution:**
Create container manually:
```bash
az storage container create \
  --account-name samcpstorage \
  --name aztfExport \
  --auth-mode login
```

### Issue: "Upload successful" but files not in storage

**Possible Causes:**
1. Looking in wrong subscription
2. Wrong storage account name
3. Files uploaded to different path

**Solution:**
Check the Storage URL shown in the output and navigate to it directly.

### Issue: Files still in temp directory after "successful" upload

**Cause:** Upload actually failed silently.

**Solution:** Check the enhanced error messages in the new version. The script now shows:
- How many files uploaded successfully
- List of failed uploads
- Keeps temp directory if any upload fails

## File Locations

### MCP Server Files (Already Fixed)
```
ai-agents/az-tf-migration/apps-mcp-server/
├── tools/
│   └── aztfexport.js           # FIXED: Lines 44-53, 72-77, 125-128
├── ps/
│   └── Export-AzToTerraform.ps1  # ENHANCED: Lines 1590-1700
└── .env                          # Must contain: storageAccount=samcpstorage
```

### Configuration
```
apps-mcp-server/.env:
  storageAccount=samcpstorage

ai-aztfexport-ui/.env.local:
  NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
  NEXT_PUBLIC_AZURE_STORAGE_ACCOUNT=samcpstorage
```

## Testing Checklist

- [ ] Restart MCP server to load fixes
- [ ] Verify .env file has storageAccount=samcpstorage
- [ ] Run export via UI or API
- [ ] Check console/logs for DEBUG messages
- [ ] Verify "Successfully uploaded X of X files" message
- [ ] Check Storage URL is displayed
- [ ] Verify files in Azure Portal
- [ ] Confirm temp directory is cleaned up (or kept if upload failed)

## Expected Output

When working correctly, you should see:

```
Uploading exported files to Azure Storage...
  Storage Account: samcpstorage
  Container: aztfExport
  Blob Path: d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/

DEBUG: Verifying Azure CLI authentication...
DEBUG: Azure CLI authenticated as: user@domain.com
DEBUG: Checking storage account accessibility...
DEBUG: Storage account accessible
DEBUG: Checking if container 'aztfExport' exists...
DEBUG: Container exists
DEBUG: Found 7 files to upload
  Uploading: main.tf
DEBUG: Blob name: d0f1884d-.../rg-mcp-servers/main.tf
DEBUG: Upload successful
  Uploading: variables.tf
DEBUG: Blob name: d0f1884d-.../rg-mcp-servers/variables.tf
DEBUG: Upload successful
  ... (more files) ...

Successfully uploaded 7 of 7 files
Storage URL: https://samcpstorage.blob.core.windows.net/aztfExport/d0f1884d-.../rg-mcp-servers/

Cleaning up temporary files...
Temp files cleaned up
```

## Summary

✅ **Fixes Applied:**
1. Removed invalid -JobId parameter from aztfexport.js
2. Added environment variable passing to PowerShell spawn
3. Fixed storage path structure in reportUrl
4. Enhanced upload section with detailed logging and error handling

⚠️ **Action Required:**
1. **Restart MCP server** to load environment variable fix
2. Test export and verify files appear in Azure Storage
3. Check debug output for any remaining issues

📝 **Documentation:**
- FIX-STORAGE-UPLOAD.md - Original fix documentation
- STORAGE-UPLOAD-DIAGNOSIS.md - This file (detailed diagnosis)
- Export-AzToTerraform.ps1 - Enhanced with debug logging

The storage upload should now work correctly when the MCP server is restarted! 🎉
