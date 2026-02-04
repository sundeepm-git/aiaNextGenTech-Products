# Quick Start Guide - SSE Real-time Migration

## Prerequisites

- Node.js 18+ installed
- PowerShell 7+ installed
- Azure CLI installed and authenticated (`az login`)
- aztfexport tool installed
- MCP server running

## Setup Steps

### 1. Configure Environment

Create `.env.local` in `ai-aztfexport-ui/`:

```env
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
```

### 2. Start MCP Server

```powershell
cd ai-agents/az-tf-migration/apps-mcp-server
npm install  # First time only
npm start
```

Expected output:
```
MCP Server v2.0.0 running on http://localhost:8080
SSE endpoint available at /jobs/:id/progress
```

### 3. Start UI Application

```powershell
cd ai-aztfexport-ui
npm install  # First time only
npm run dev
```

Expected output:
```
ready - started server on 0.0.0.0:3000, url: http://localhost:3000
```

### 4. Navigate to Migration Page

Open browser: `http://localhost:3000`

Click **"Migration"** in the sidebar (Agent Context: MIGRATION)

## Using the Migration Interface

### Input Fields

1. **Subscription ID** (required)
   - Your Azure subscription GUID
   - Example: `d0f1884d-1f98-4bf1-9e15-e2986fc1bca2`
   - Find with: `az account show --query id -o tsv`

2. **Resource Group** (required)
   - Name of the resource group to export
   - Example: `rg-production`
   - List with: `az group list --query "[].name" -o tsv`

3. **Additional Context** (optional)
   - Any additional instructions or context
   - Currently not processed by backend

### Start Export

1. Fill in Subscription ID and Resource Group
2. Click **"Start Export"** button
3. Watch real-time logs appear in terminal viewer
4. Wait for completion message

### Progress Indicators

**Status Badge Colors:**
- 🟢 **Green (pulsing)**: Connected - receiving updates
- 🟡 **Yellow (pulsing)**: Connecting - establishing connection
- 🔵 **Blue**: Completed - export finished
- 🔴 **Red**: Error - something went wrong
- ⚪ **Gray**: Idle or Disconnected

**Log Colors:**
- 🔵 **Cyan**: Standard output (stdout)
- 🔴 **Red**: Error output (stderr)
- 🔵 **Blue**: System info messages
- 🟢 **Green**: Success messages
- 🔴 **Bold Red**: Critical errors

## Sample Export Flow

### Step 1: Initial Connection
```
10:30:00 [INFO] Starting export for subscription: d0f1884d-..., resource group: rg-production
10:30:01 [SUCCESS] Export job created with ID: a1b2c3d4-5678-90ab-cdef-1234567890ab
10:30:02 [INFO] Connected to export progress stream
```

### Step 2: Export Process
```
10:30:05 [STDOUT] Initializing aztfexport...
10:30:07 [STDOUT] Connecting to Azure subscription d0f1884d-...
10:30:10 [STDOUT] Found 15 resources in resource group rg-production
10:30:12 [STDOUT] Importing /subscriptions/.../Microsoft.Storage/storageAccounts/mystorage
10:30:15 [STDOUT] Importing /subscriptions/.../Microsoft.Web/sites/mywebapp
10:30:18 [STDOUT] Generating Terraform configuration files...
10:30:20 [STDOUT] Creating main.tf...
10:30:22 [STDOUT] Creating variables.tf...
10:30:24 [STDOUT] Creating terraform.tfstate...
```

### Step 3: Completion
```
10:30:30 [STDOUT] Generating HTML report...
10:30:32 [STDOUT] Uploading files to Azure Storage...
10:30:35 [SUCCESS] Export completed successfully
```

## Troubleshooting

### MCP Server Not Running

**Symptom:** Connection error immediately after clicking "Start Export"

**Solution:**
```powershell
cd ai-agents/az-tf-migration/apps-mcp-server
npm start
```

---

### Azure CLI Not Authenticated

**Symptom:** Error message: "No subscriptions found" or "Authentication failed"

**Solution:**
```powershell
az login
az account set --subscription "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2"
```

---

### aztfexport Not Installed

**Symptom:** Error: "aztfexport command not found"

**Solution:**
```powershell
# Windows
winget install aztfexport

# Or download from GitHub releases
# https://github.com/Azure/aztfexport/releases
```

---

### Connection Disconnects

**Symptom:** Status shows "Disconnected" with message "Connection lost..."

**Solution:**
1. Check MCP server is still running
2. Click **"Reconnect"** button
3. If that fails, restart export from beginning

---

### No Logs Appearing

**Symptom:** Status shows "Connected" but no logs appear

**Solution:**
1. Check PowerShell script uses direct execution (`& aztfexport`)
2. Verify Azure CLI connection: `az account show`
3. Check MCP server console for errors
4. Ensure subscription ID and resource group are correct

## Storage Structure

After successful export, files are stored in Azure Storage:

```
Container: aztfexport-storage
Path: aztfExport/{subscriptionId}/{resourceGroupName}/

Files:
  ├── main.tf                    # Main Terraform configuration
  ├── variables.tf               # Variable definitions
  ├── providers.tf               # Provider configuration
  ├── terraform.tfstate          # State file
  ├── import.log                 # Import process log
  └── html-report/
      └── migration-report.html  # Detailed HTML report
```

## Next Steps

After successful export:

1. **Review Terraform Files**
   - Download from Azure Storage
   - Review `main.tf` for accuracy
   - Check `terraform.tfstate` for imported resources

2. **Test Terraform Plan**
   ```bash
   terraform init
   terraform plan
   ```

3. **Review HTML Report**
   - Open `migration-report.html` in browser
   - Check compatibility scores
   - Review warnings and recommendations

4. **Refactor Code** (if needed)
   - Use the Refactoring agent
   - Apply best practices
   - Modularize large configurations

## Tips

- **Use specific resource group names** - Avoid exporting entire subscriptions
- **Check Azure permissions** - Ensure you have Reader access to all resources
- **Monitor logs closely** - Watch for warnings about unsupported resources
- **Keep browser tab open** - SSE connection requires active tab
- **Clear logs between runs** - Click "Clear Logs" before starting new export

## Support

For issues or questions:
- Check [SSE-INTEGRATION-GUIDE.md](./SSE-INTEGRATION-GUIDE.md) for detailed documentation
- Review [REALTIME-PROGRESS.md](../ai-agents/az-tf-migration/apps-mcp-server/REALTIME-PROGRESS.md) for backend details
- Open issue in project repository

## Summary

You now have a complete real-time migration interface that:
- ✅ Connects directly to MCP server
- ✅ Streams live progress updates
- ✅ Displays detailed logs with timestamps
- ✅ Handles connection failures gracefully
- ✅ Shows completion status with storage path
- ✅ Provides professional user experience

Start migrating your Azure resources to Terraform with full visibility into the process!
