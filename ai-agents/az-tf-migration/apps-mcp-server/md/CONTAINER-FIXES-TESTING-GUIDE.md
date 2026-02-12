# Container Export Fixes - Testing & Deployment Guide

## Issues Fixed

### 1. **Environment Variables Not Inherited by aztfexport**
**Problem**: Set environment variables in PowerShell weren't being passed to aztfexport child process
**Fix**: Changed from `Invoke-Expression` to `System.Diagnostics.Process` with explicit environment hashtable

### 2. **Regex Cleanup Too Aggressive**
**Problem**: Regex patterns removed opening blocks, leaving orphaned content like:
```terraform
subscription_id = "..."  # No provider "azurerm" { wrapper
required_providers {     # No terraform { wrapper
```
**Fix**: 
- Improved regex patterns to match nested braces: `provider\s+"[^"]+"\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}`
- Added orphaned content detection and cleanup
-Better error handling for malformed content

### 3. **State File Not Generated**
**Problem**: `terraform.tfstate` wasn't being copied from sandbox
**Fix**: Added try/catch with better error messages and verification

### 4. **Empty main.tf After Cleanup**
**Problem**: Over-aggressive cleanup left main.tf with only headers
**Fix**: Validate content before writing, keep original if cleanup would result in empty file

### 5. **Missing Environment Variables in Container**
**Problem**: Container didn't have all required environment variables set
**Fix**: Updated Dockerfile to include `RUNNING_IN_CONTAINER`, `NO_COLOR`, `TERM`, `AZURE_EXTENSION_QUIET`, etc.

## Testing Steps

### Phase 1: Local Container Test

```powershell
cd c:\Users\sunsu\OneDrive\Desktop\Sundeep\AI-Projects\ai-Repository\Generative-AI-Projects\aiaNextGen-Products\ai-agents\az-tf-migration\apps-mcp-server

# Test container locally (builds with --no-cache and runs)
.\test-container-locally.ps1 -BuildNoCache
```

**Expected Results:**
- ✅ Health check passes
- ✅ 3 tools registered
- ✅ No errors in logs
- ✅ Container stays running

**What to Check:**
```powershell
# 1. View container logs
docker logs aztf-mcp-test

# 2. Shell into container
docker exec -it aztf-mcp-test sh

# 3. Inside container, check environment
env | grep -E "AZURE|ARM|NO_COLOR|TERM|RUNNING"

# 4. Inside container, verify PowerShell script exists
ls -la /app/ps/Export-Container-AzToTerraform.ps1

# 5. Inside container, test aztfexport
aztfexport --version
```

### Phase 2: Test Export from Container

**Using MCP Client (Claude Desktop, etc.):**

1. Configure MCP client to connect to `http://localhost:8080/sse`

2. Call the export tool:
```json
{
  "tool": "export_azure_to_terraform",
  "parameters": {
    "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
    "resourceGroup": "rg-mcp-servers"
  }
}
```

3. Monitor logs:
```powershell
docker logs -f aztf-mcp-test
```

**Expected Log Output:**
```
PARAMETER VALIDATION
  SubscriptionId: d0f1884d-1f98-4bf1-9e15-e2986fc1bca2
  ResourceGroupName: rg-mcp-servers
  StorageContainer: aztfexport

DIRECTORY STRUCTURE
  Script Directory: /app/ps
  Repo Root: /app
  Export Root: /app/azure-export
  Subscription Directory: /app/azure-export/Enterprise-Enrollment-Subscription
  Target Export Directory: /app/azure-export/Enterprise-Enrollment-Subscription/rg-mcp-servers

[1/3] Processing: samcpstorage
   ✓ Extracted provider block
   ✓ Merged
   ✓ Copied state file

Standards enforcement completed
  Created provider.tf with 1 provider(s)
  Updated main.tf (removed providers and sensitive values)
  Created terraform.tf
  Created data-sources.tf
  Created variables.tf
  Created outputs.tf

Generating HTML export report...
✓ HTML report generated: Export-Report-Latest.html

Uploading to Azure Storage...
✓ Successfully uploaded 8 files
```

### Phase 3: Validate Generated Files

**Access container filesystem:**
```powershell
docker exec -it aztf-mcp-test sh
cd /app/azure-export/Enterprise-Enrollment-Subscription/rg-mcp-servers
ls -la
```

**Expected Files:**
```
main.tf                    # Valid resource blocks
provider.tf                # Complete provider "azurerm" { ... }
terraform.tf               # Complete terraform { required_providers { ... } }
data-sources.tf            # Data sources or header
variables.tf               # Variable definitions
outputs.tf                 # Output definitions
terraform.tfstate          # State file from aztfexport
Export-Report-Latest.html  # HTML report
```

**Validate main.tf Structure:**
```bash
cat main.tf | head -50
```

Should see:
```terraform
# ==============================================================================
# FILE: main.tf
# ==============================================================================
# DESCRIPTION:
#   Main Terraform configuration...
# ==============================================================================

# --- Resource: samcpstorage ---
resource "azurerm_storage_account" "res_0" {
  account_replication_type = "LRS"
  account_tier             = "Standard"
  location                 = "centralus"
  name                     = "samcpstorage"
  resource_group_name      = "rg-mcp-servers"
  # ... more properties
}
```

**Validate provider.tf:**
```bash
cat provider.tf
```

Should see:
```terraform
provider "azurerm" {
  features {}
  subscription_id = "..."
  tenant_id       = "..."
  client_id       = "..."
  client_secret   = "***REMOVED***"
}
```

**Validate terraform.tf:**
```bash
cat terraform.tf
```

Should see:
```terraform
terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
```

### Phase 4: Validate Infrastructure Files

**Run Terraform validation:**
```bash
cd /app/azure-export/Enterprise-Enrollment-Subscription/rg-mcp-servers
terraform init
terraform validate
```

**Expected Output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/azurerm versions matching "~> 3.0"...
- Installing hashicorp/azurerm v3.x.x...

Terraform has been successfully initialized!

Success! The configuration is valid.
```

## Deployment to Azure Container Apps

Once local testing passes:

```powershell
# Navigate to deployment directory
cd c:\Users\sunsu\OneDrive\Desktop\Sundeep\AI-Projects\ai-Repository\Generative-AI-Projects\aiaNextGen-Products\ai-agents\az-tf-migration\apps-mcp-server

# Run deployment with your credentials
.\deploy.ps1 `
    -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" `
    -TenantId "your-tenant-id" `
    -ClientId "your-client-id" `
    -ClientSecret "your-client-secret" `
    -StorageAccountName "samcpstorage" `
    -NoCache
```

**Deployment will:**
1. Build image with --no-cache
2. Push to Azure Container Registry
3. Deploy to Azure Container Apps
4. Set all required environment variables
5. Verify health and tools endpoints

**Monitor Deployment:**
```powershell
# Check container app logs
az containerapp logs show `
    --name aztf-mcp-app `
    --resource-group rg-aztf-mcp `
    --follow
```

**Verify Deployment:**
```powershell
# Get app URL
$APP_URL = az containerapp show `
    --name aztf-mcp-app `
    --resource-group rg-aztf-mcp `
    --query properties.configuration.ingress.fqdn `
    --output tsv

# Test endpoints
Invoke-RestMethod -Uri "https://$APP_URL/health"
Invoke-RestMethod -Uri "https://$APP_URL/tools"
```

## Troubleshooting

### Issue: "No .tf files generated"
**Check:**
1. Container has network access to Azure
2. Service Principal has correct permissions on subscription
3. Resource Group exists and has resources
4. aztfexport binary is executable: `docker exec -it <container> aztfexport --version`

### Issue: "main.tf still malformed"
**Check:**
1. Container logs show "✓ Extracted provider block"
2. Container logs show "✓ Merged" for each resource
3. PWD inside container: `docker exec -it <container> pwd` should be `/app`
4. Script path: `docker exec -it <container> ls -la /app/ps/Export-Container-AzToTerraform.ps1`

### Issue: "terraform.tfstate missing"
**Check:**
1. Container logs show "✓ Copied state file"
2. Sandbox directories are being created: `docker exec -it <container> ls -la /app/azure-export/.../rg-name/`
3. aztfexport completed successfully (exit code 0)

### Issue: "Environment variables not set"
**Check:**
```bash
docker exec -it <container> env | grep -E "AZURE|ARM|NO_COLOR|TERM"
```

Should show all environment variables from Dockerfile + deploy.ps1.

### Issue: "/dev/tty errors"
**These are warnings only** - they appear because aztfexport tries to access TTY in headless mode. The `NO_COLOR`, `TERM=dumb`, and `AZURE_EXTENSION_QUIET` environment variables prevent these from causing failures.

## Validation Checklist

After container export completes:

- [ ] No "WARNING: ResourceGroupName looks suspicious" message
- [ ] Directory structure shows correct paths (not 'container' subdirectory)
- [ ] All resource processing shows "✓ Merged"
- [ ] "Standards enforcement completed" message appears
- [ ] "HTML report generated" message appears
- [ ] "Successfully uploaded X files" message appears
- [ ] main.tf contains valid resource blocks (not orphaned fragments)
- [ ] provider.tf contains complete `provider "azurerm" { }` block
- [ ] terraform.tf contains complete `terraform { }` block
- [ ] terraform.tfstate exists and is not empty
- [ ] Export-Report-Latest.html exists and shows resource summary
- [ ] `terraform validate` passes inside container

## Files Changed

1. **Export-Container-AzToTerraform.ps1**
   - Added parameter validation and debug logging
   - Fixed environment variable inheritance for aztfexport
   - Improved regex patterns for nested braces
   - Added orphaned content cleanup
   - Better error handling and validation

2. **Dockerfile**
   - Added `RUNNING_IN_CONTAINER=true`
   - Added headless execution environment variables
   - Added storage configuration defaults

3. **deploy.ps1**
   - Added default storage account value
   - Added storage container default value

4. **test-container-locally.ps1** (NEW)
   - Local container testing script
   - Automated build, run, and validation
   - Helpful debugging commands

## Support

If issues persist after following this guide:

1. **Check container logs** for specific error messages
2. **Verify environment variables** are set correctly
3. **Test locally first** using test-container-locally.ps1
4. **Validate credentials** have correct Azure permissions
5. **Check network connectivity** from container to Azure

---

**Version**: 3.0 (with container execution fixes)  
**Last Updated**: 2025-02-10  
**Tested On**: Docker Desktop, Azure Container Apps
