# Export Functionality Integration - Runtime Progress Display

## Status: ✅ FULLY INTEGRATED

The Azure-to-Terraform export functionality with **real-time runtime progress** is fully integrated and ready to use in the Migration area of the UI.

---

## Integration Overview

### Architecture Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    USER INTERFACE (React)                    │
│                                                              │
│  Navigation: Sidebar → Click "Migration"                    │
│  Component: MigrationPage.tsx                               │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  User Inputs:                                       │    │
│  │  • Subscription ID (required)                      │    │
│  │  • Resource Group (required)                       │    │
│  │  • Context (optional)                              │    │
│  │  [Start Export] Button                             │    │
│  └────────────────────────────────────────────────────┘    │
│                         │                                    │
│                         │ calls startExport()                │
│                         ▼                                    │
│  ┌────────────────────────────────────────────────────┐    │
│  │  useExportProgress Hook                            │    │
│  │  • POST /messages to MCP server                    │    │
│  │  • Extract Job ID from response                    │    │
│  │  • Open EventSource SSE connection                 │    │
│  │  • Stream real-time logs                           │    │
│  │  • Manage connection state                         │    │
│  └────────────────────────────────────────────────────┘    │
│                         │                                    │
└─────────────────────────┼────────────────────────────────────┘
                          │ SSE Stream
                          │
┌─────────────────────────▼────────────────────────────────────┐
│              MCP SERVER (Node.js/Express)                    │
│                                                              │
│  POST /messages Endpoint:                                   │
│  • Receives export request                                  │
│  • Creates Job ID                                           │
│  • Spawns PowerShell process with env vars                  │
│  • Returns Job ID to frontend                               │
│                                                              │
│  GET /jobs/:id/progress Endpoint (SSE):                     │
│  • Streams real-time progress                               │
│  • Events: connected, stdout, stderr, complete              │
│                                                              │
│  PowerShell Spawn (tools/aztfexport.js):                   │
│  ✅ Passes environment variables (storageAccount)           │
│  ✅ Removed invalid -JobId parameter                        │
│  ✅ Correct storage path structure                          │
│                                                              │
└─────────────────────────┬────────────────────────────────────┘
                          │
┌─────────────────────────▼────────────────────────────────────┐
│         POWERSHELL SCRIPT (Export-AzToTerraform.ps1)        │
│                                                              │
│  • Validates StorageAccount parameter                       │
│  • Runs aztfexport CLI                                      │
│  • Generates Terraform files                                │
│  • Creates HTML report                                      │
│  • Uploads to Azure Storage:                                │
│    aztfExport/{SubscriptionId}/{ResourceGroupName}/         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Integration Points

### 1. Frontend Components

#### MigrationPage.tsx
**Location:** `ai-aztfexport-ui/app/components/pages/MigrationPage.tsx`

**Status:** ✅ Fully Integrated

**Features:**
- ✅ Subscription ID input field
- ✅ Resource Group input field  
- ✅ Optional context textarea
- ✅ Start Export button with loading state
- ✅ Real-time log viewer (terminal style)
- ✅ Connection status badge
- ✅ Auto-scroll to latest logs
- ✅ Clear logs functionality
- ✅ Reconnect button on disconnect
- ✅ Completion message with storage path
- ✅ Error handling and display

**Usage:**
1. Navigate to app via sidebar: Click **"Migration"**
2. Enter Azure Subscription ID
3. Enter Resource Group name
4. Click **"Start Export"**
5. Watch real-time progress logs
6. See completion message with storage URL

---

#### useExportProgress Hook
**Location:** `ai-aztfexport-ui/app/hooks/useExportProgress.ts`

**Status:** ✅ Fully Implemented

**Capabilities:**
- ✅ POST request to MCP server `/messages` endpoint
- ✅ Job ID extraction from response
- ✅ EventSource SSE connection management
- ✅ Real-time log accumulation
- ✅ Connection state tracking (idle, connecting, connected, completed, error, disconnected)
- ✅ Auto-reconnect on connection loss (3-second delay)
- ✅ Manual reconnect function
- ✅ Clear logs function
- ✅ Proper cleanup on unmount

---

### 2. Backend MCP Server

#### index.js
**Location:** `ai-agents/az-tf-migration/apps-mcp-server/index.js`

**Status:** ✅ Operational

**Endpoints:**
- ✅ `POST /messages` - Accepts export requests
- ✅ `GET /jobs/:id/progress` - SSE streaming endpoint

---

#### tools/aztfexport.js
**Location:** `ai-agents/az-tf-migration/apps-mcp-server/tools/aztfexport.js`

**Status:** ✅ Fixed and Ready

**Recent Fixes:**
1. ✅ **Removed `-JobId` parameter** (no longer exists in PowerShell script)
2. ✅ **Added environment variable passing** to spawn()
   ```javascript
   spawn(psExecutable, psArgs, {
     env: {
       ...process.env,
       storageAccount: storageAccount
     }
   });
   ```
3. ✅ **Updated reportUrl** to match storage structure:
   ```javascript
   aztfExport/${job.subscriptionId}/${job.resourceGroup}/
   ```

---

### 3. PowerShell Script

#### Export-AzToTerraform.ps1
**Location:** `ai-agents/az-tf-migration/apps-mcp-server/ps/Export-AzToTerraform.ps1`

**Status:** ✅ Working

**Features:**
- ✅ Validates StorageAccount parameter
- ✅ Uses `$env:storageAccount` as default
- ✅ Runs aztfexport with real-time output
- ✅ Generates HTML report
- ✅ Uploads all files to Azure Storage
- ✅ Storage path: `aztfExport/{SubscriptionId}/{ResourceGroupName}/`

---

### 4. Environment Configuration

#### MCP Server .env
**Location:** `ai-agents/az-tf-migration/apps-mcp-server/.env`

**Status:** ✅ Configured

```env
storageAccount=samcpstorage
PORT=8080
```

---

#### UI .env.local
**Location:** `ai-aztfexport-ui/.env.local`

**Status:** ✅ Configured

```env
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
```

---

## User Journey - Step by Step

### 1. Start Services

```bash
# Terminal 1: Start MCP Server
cd ai-agents/az-tf-migration/apps-mcp-server
npm start
# Server runs on http://localhost:8080

# Terminal 2: Start UI
cd ai-aztfexport-ui
npm run dev
# UI runs on http://localhost:3000
```

---

### 2. Navigate to Migration Page

1. Open browser: `http://localhost:3000`
2. Click **"Migration"** in left sidebar
3. See the Migration interface:
   - Subscription ID input
   - Resource Group input
   - Optional context field
   - Start Export button

---

### 3. Start Export

**Input Example:**
- **Subscription ID:** `d0f1884d-1f98-4bf1-9e15-e2986fc1bca2`
- **Resource Group:** `rg-mcp-servers`
- **Context:** (optional) Leave blank or add notes

Click **"Start Export"** button

---

### 4. Watch Real-time Progress

**Connection Status Changes:**
```
🟡 Connecting... → 🟢 Connected → 🔵 Completed
```

**Real-time Logs Appear:**
```
10:30:00 [INFO] Starting export for subscription: d0f1884d-...
10:30:01 [SUCCESS] Export job created with ID: a1b2c3d4-...
10:30:02 [INFO] Connected to export progress stream
10:30:05 [STDOUT] Initializing aztfexport...
10:30:07 [STDOUT] Connecting to Azure subscription...
10:30:10 [STDOUT] Found 15 resources in rg-mcp-servers
10:30:12 [STDOUT] Importing /subscriptions/.../Microsoft.Storage/storageAccounts/mystorage
10:30:15 [STDOUT] Importing /subscriptions/.../Microsoft.Web/sites/mywebapp
10:30:18 [STDOUT] Generating Terraform configuration files...
10:30:20 [STDOUT] Creating main.tf...
10:30:22 [STDOUT] Creating variables.tf...
10:30:24 [STDOUT] Creating terraform.tfstate...
10:30:26 [STDOUT] Generating HTML report...
10:30:28 [STDOUT] Uploading exported files to Azure Storage...
10:30:30 [STDOUT]   Uploading: main.tf
10:30:31 [STDOUT]   Uploading: variables.tf
10:30:32 [STDOUT]   Uploading: provider.tf
10:30:33 [STDOUT]   Uploading: terraform.tfstate
10:30:34 [STDOUT]   Uploading: html-report/migration-report.html
10:30:35 [STDOUT] Successfully uploaded 7 of 7 files
10:30:36 [SUCCESS] Export completed successfully ✅
```

---

### 5. View Results

**Completion Message Displays:**
```
✅ Export Completed Successfully!

✅ Azure resources have been successfully exported to Terraform configuration

Storage Path:
aztfExport/d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/

Files include: main.tf, variables.tf, providers.tf, terraform.tfstate, and HTML report
```

---

### 6. Verify in Azure Portal

Navigate to:
- **Storage Account:** `samcpstorage`
- **Container:** `aztfExport`
- **Path:** `d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/`

**Files Present:**
- ✅ `main.tf`
- ✅ `variables.tf`
- ✅ `provider.tf`
- ✅ `terraform.tf`
- ✅ `data-sources.tf`
- ✅ `terraform.tfstate`
- ✅ `html-report/migration-report.html`

---

## UI Features - Detailed Breakdown

### Input Section
```tsx
┌─────────────────────────────────────────────────────┐
│  Subscription ID *                                  │
│  [d0f1884d-1f98-4bf1-9e15-e2986fc1bca2_________]   │
│                                                     │
│  Resource Group *                                   │
│  [rg-mcp-servers_______________________________]   │
│                                                     │
│  Additional Context (Optional)                      │
│  [_______________________________________________]  │
│  [_______________________________________________]  │
│                                                     │
│  [▶ Start Export]                                  │
└─────────────────────────────────────────────────────┘
```

### Status Bar
```tsx
┌─────────────────────────────────────────────────────┐
│  Job Status: [🟢 Connected]                        │
│  Job ID: a1b2c3d4-5678-90ab-cdef-1234567890ab      │
│                                   [Clear Logs]      │
└─────────────────────────────────────────────────────┘
```

### Real-time Logs (Terminal Style)
```tsx
┌─────────────────────────────────────────────────────┐
│  📟 Export Progress                                │
│ ┌─────────────────────────────────────────────────┐ │
│ │ 10:30:05  Initializing aztfexport...           │ │
│ │ 10:30:07  Connecting to Azure...               │ │
│ │ 10:30:10  Found 15 resources...                │ │
│ │ 10:30:12  Importing storage account...         │ │
│ │ 10:30:15  Importing web app...                 │ │
│ │ 10:30:18  Generating Terraform files...        │ │
│ │ 10:30:30  Uploading to Azure Storage...        │ │
│ │ 10:30:35  Export completed successfully ✅     │ │
│ │ ▼ (auto-scroll)                                │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### Completion Card
```tsx
┌─────────────────────────────────────────────────────┐
│  ✅ Export Completed Successfully!                 │
│                                                     │
│  ✅ Azure resources have been successfully         │
│     exported to Terraform configuration            │
│                                                     │
│  Storage Path:                                      │
│  aztfExport/d0f1884d-.../rg-mcp-servers/          │
│                                                     │
│  Files include: main.tf, variables.tf, providers.tf│
│  terraform.tfstate, and HTML report                │
└─────────────────────────────────────────────────────┘
```

---

## Color Coding

### Log Message Types

| Type | Color | Example |
|------|-------|---------|
| **stdout** | 🔵 Cyan | Normal output from PowerShell/aztfexport |
| **stderr** | 🔴 Red | Error messages and warnings |
| **info** | 🔵 Blue | System messages (connecting, job created) |
| **success** | 🟢 Green | Completion messages |
| **error** | 🔴 Bold Red | Critical errors |

### Status Badges

| Status | Badge | Description |
|--------|-------|-------------|
| **idle** | ⚪ Gray | No export running |
| **connecting** | 🟡 Yellow (pulsing) | Establishing SSE connection |
| **connected** | 🟢 Green (pulsing) | Receiving real-time updates |
| **completed** | 🔵 Blue | Export finished successfully |
| **error** | 🔴 Red | Export failed |
| **disconnected** | ⚪ Gray | Connection lost |

---

## Error Handling

### Scenario 1: Missing Required Fields
- **Symptom:** Start Export button is disabled
- **Solution:** Fill in Subscription ID and Resource Group

### Scenario 2: Connection Failed
- **Display:** Red alert box with error message
- **Action:** Verify MCP server is running, check network

### Scenario 3: SSE Disconnect
- **Display:** Status changes to "Disconnected"
- **Action:** Auto-reconnect in 3 seconds, or click "Reconnect" button

### Scenario 4: PowerShell Error
- **Display:** Error logs appear in red in terminal
- **Storage:** Files remain local (not uploaded)
- **Action:** Review error, fix issue, retry

---

## Testing Checklist

- [x] MigrationPage component integrated
- [x] useExportProgress hook implemented
- [x] SSE connection working
- [x] Real-time logs streaming
- [x] Auto-scroll functioning
- [x] Status badges updating correctly
- [x] Clear logs working
- [x] Reconnect button working
- [x] Completion message displaying
- [x] Storage path correct
- [x] Environment variables configured
- [x] MCP server endpoints operational
- [x] PowerShell script fixed
- [x] File upload to Azure Storage working

---

## Summary

### ✅ Integration Status: **COMPLETE**

All components are properly wired together:

1. **Frontend** (React/Next.js)
   - MigrationPage with real input fields
   - useExportProgress hook managing SSE
   - Real-time log display
   - Connection state management

2. **Backend** (MCP Server)
   - POST /messages endpoint accepting requests
   - GET /jobs/:id/progress SSE streaming
   - Environment variables properly passed
   - Correct storage path structure

3. **PowerShell Script**
   - Validates and uses StorageAccount
   - Real-time output via direct execution
   - Uploads files to Azure Storage
   - Correct folder structure

4. **Configuration**
   - .env files properly set
   - Server URLs configured
   - Storage account specified

### 🎯 Ready to Use

Users can now:
- Navigate to Migration page
- Enter Azure credentials
- Start export with one click
- Watch real-time progress
- See completion status
- Verify files in Azure Storage

### 📚 Documentation

- [SSE-INTEGRATION-GUIDE.md](../ai-aztfexport-ui/SSE-INTEGRATION-GUIDE.md) - Technical details
- [QUICK-START.md](../ai-aztfexport-ui/QUICK-START.md) - User guide
- [FIX-STORAGE-UPLOAD.md](./FIX-STORAGE-UPLOAD.md) - Recent fixes
- [INTEGRATION-COMPLETE.md](../ai-aztfexport-ui/INTEGRATION-COMPLETE.md) - Full summary

---

**The export functionality with runtime progress is fully integrated and ready for production use!** 🚀
