# Storage Upload Fix - Export Not Uploading Files

## Problem Description

Export jobs were showing "completed ✅" status but files were not actually being uploaded to Azure Storage Account (`samcpstorage`). 

### Root Cause

The Python export script (`Export-Container-AzToTerraform.py`) had exception handling that **silently swallowed upload errors**:

```python
# OLD CODE - BAD ❌
try:
    res = subprocess.run([...upload command...], capture_output=True, text=True)
    if res.returncode == 0:
        print("SUCCESS: Files pushed to Storage Account")
    else:
        print("ERROR: Storage upload failed")  # Just prints, doesn't fail!
except Exception as e: 
    print(f"ERROR: Storage operation failed: {e}")  # Just prints, doesn't fail!

# Script exits with code 0 → Job marked as "completed" even though upload failed
```

The workflow saw:
1. Export script exits with code 0 (success)
2. Node.js MCP server marks job status as `completed`
3. User sees "✅ Export job finished — files uploaded to storage"
4. But files are NOT in storage account!

---

## What Was Fixed

### 1. Export Script Error Handling

**File:** `python/Export-Container-AzToTerraform.py`

**Changes:**
- Upload failures now call `sys.exit(1)` to fail the script
- Added detailed error output (stdout/stderr from `az` CLI)
- Script will now properly fail if upload fails
- GitHub push errors won't fail job if storage upload succeeded

```python
# NEW CODE - GOOD ✅
try:
    res = subprocess.run([...upload command...], capture_output=True, text=True)
    if res.returncode == 0:
        print("SUCCESS: Files pushed to Storage Account")
        upload_success = True
    else:
        print("ERROR: Storage upload failed")
        print(f"ERROR: stdout: {res.stdout}")
        print(f"ERROR: stderr: {res.stderr}")
        sys.exit(1)  # ← FAIL THE SCRIPT!
except Exception as e: 
    print(f"ERROR: Storage operation failed: {e}")
    sys.exit(1)  # ← FAIL THE SCRIPT!
```

### 2. Verification

The refactor script (`tf_refactor_variable.py`) already had correct error handling:
- Uses `check=True` in subprocess.run()
- Re-raises exceptions
- ✅ No changes needed

---

## How to Diagnose the Real Issue

The actual problem is likely **missing RBAC permissions** on the storage account. Run the diagnostic script:

```powershell
cd ai-agents/az-tf-migration/apps-mcp-server
./test-storage-permissions.ps1
```

This script will:
1. ✓ Verify Azure CLI login
2. ✓ Check if container exists
3. ✓ Attempt to upload a test file
4. ✓ Verify the uploaded file
5. ✓ Clean up test file

### Expected Errors

#### Error: "Failed to check container"
**Cause:** Storage account doesn't exist OR missing permissions

**Solution:**
```bash
# Verify storage account exists
az storage account show --name samcpstorage --resource-group rg-mcp-servers

# If it exists, you need RBAC role assignment
```

#### Error: "Upload failed"
**Cause:** Missing "Storage Blob Data Contributor" role

**Solution:**
```bash
# Get your user object ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Grant yourself Storage Blob Data Contributor role
az role assignment create \
  --assignee $USER_ID \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-mcp-servers/providers/Microsoft.Storage/storageAccounts/samcpstorage"
```

For Service Principal (if running in Container Apps):
```bash
# Get your Service Principal Object ID from .env
SP_OBJECT_ID="657d1054-065b-4d79-9628-402bc981f448"

az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-mcp-servers/providers/Microsoft.Storage/storageAccounts/samcpstorage"
```

---

## Testing the Fix

### 1. Run the permission diagnostic:
```powershell
./test-storage-permissions.ps1
```

### 2. Run a test export:
```powershell
cd python/az-fndry-workflow
python aztf-sequential-wf.py
```

### 3. Check the output:

**Before Fix:**
```
[EXPORT POLL]: Job xxx: status=completed (776s elapsed)
[EXPORT POLL]: Job xxx COMPLETED in 776s ✅
[EXPORT POLL]: Export job finished — files uploaded to storage ✅
# But files NOT in storage!
```

**After Fix (with permissions issue):**
```
[EXPORT POLL]: Job xxx: status=failed
ERROR: Storage upload failed. Check permissions for 'samcpstorage'.
ERROR: stderr: ERROR: You do not have the required permissions...
```

**After Fix (with permissions granted):**
```
[EXPORT POLL]: Job xxx: status=completed (776s elapsed)
[EXPORT POLL]: Job xxx COMPLETED in 776s ✅
[EXPORT POLL]: Export job finished — files uploaded to storage ✅
# Files ARE in storage! ✅
```

---

## Verify Files in Storage

### Using Azure Portal:
1. Go to Storage Account `samcpstorage`
2. Navigate to Containers → `aztfexport`
3. Look for path: `<subscription-id>/<resource-group-name>/`

### Using Azure CLI:
```bash
az storage blob list \
  --account-name samcpstorage \
  --container-name aztfexport \
  --prefix "<subscription-id>/<resource-group-name>/" \
  --auth-mode login \
  --output table
```

---

## Summary of Changes

| File | Change | Impact |
|------|--------|--------|
| `Export-Container-AzToTerraform.py` | Upload failures now call `sys.exit(1)` | Jobs will correctly fail if upload fails |
| `Export-Container-AzToTerraform.py` | Added detailed error logging | Easier to diagnose permission issues |
| `test-storage-permissions.ps1` | New diagnostic script | Quickly test storage permissions |

---

## Next Steps

1. ✅ Code changes applied
2. ⚠️ **Run permission diagnostic:** `./test-storage-permissions.ps1`
3. ⚠️ **Grant RBAC role** if diagnostic fails
4. ✅ Re-run export workflow
5. ✅ Verify files appear in storage account

---

## Related Configuration

**Storage Account Details** (from `.env`):
- `storageAccount=samcpstorage`
- `storageAccountRG=rg-mcp-servers`
- `AZURE_STORAGE_CONTAINER=aztfexport` (default)

**Authentication** (from `.env`):
- Service Principal: `4a7f6b45-8322-4cfe-bd16-008afdcc1221`
- Object ID: `657d1054-065b-4d79-9628-402bc981f448`
