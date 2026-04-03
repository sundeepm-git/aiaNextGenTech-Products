# UI API Layer README

This is the single source of truth for running the UI and API layer in sequence for Azure-to-Terraform workflow execution.

## Scope

This README covers:

1. Local prerequisites
2. Environment setup
3. Start order for MCP, API, and UI
4. End-to-end run flow
5. Progress and timeout behavior
6. Troubleshooting and recovery
7. Production deployment command

## Folder Structure

1. UI: ai-aztfexport-ui
2. API: ai-agents/az-tf-migration/apps-mcp-server/python/api
3. MCP Server: ai-agents/az-tf-migration/apps-mcp-server
4. Workflow Engine: ai-agents/az-tf-migration/apps-mcp-server/python/az-fndry-workflow

## Prerequisites

1. Windows PowerShell
2. Node.js 18+
3. Python virtual environment at repository root: .venv
4. Azure CLI installed and authenticated
5. Access to subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2
6. Storage account samcpstorage

## Step 1: Open Repository Root

Run from:

```powershell
cd c:\Users\sunsu\OneDrive\Desktop\Sundeep\AI-Projects\ai-Repository\Generative-AI-Projects\aiaNextGen-Products
```

## Step 2: Set PowerShell Execution Policy

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Step 3: Activate Python Virtual Environment

```powershell
.\.venv\Scripts\Activate.ps1
```

## Step 4: Configure UI Environment

File: ai-aztfexport-ui/.env.local

Use these values for local development:

```env
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
NEXT_PUBLIC_WORKFLOW_API_URL=http://localhost:8000
NEXT_PUBLIC_AZURE_STORAGE_ACCOUNT=samcpstorage
NEXT_PUBLIC_AZURE_CONTAINER=aztfExport

NEXT_PUBLIC_ENABLE_REAL_MIGRATION=true
NEXT_PUBLIC_ENABLE_SIMULATION=true
NEXT_PUBLIC_AUTO_RECONNECT=true

NEXT_PUBLIC_API_TIMEOUT=600000
NEXT_PUBLIC_RETRY_ATTEMPTS=3
NEXT_PUBLIC_RETRY_DELAY=5000
NEXT_PUBLIC_RECONNECT_DELAY=5000
NEXT_PUBLIC_SSE_HEARTBEAT=30000
NEXT_PUBLIC_LONG_JOB_THRESHOLD=300000
NEXT_PUBLIC_LOG_RETENTION=1000
```

Notes:

1. Keep localhost URLs in .env.local for local development.
2. deploy.ps1 builds production UI image with Azure URLs and does not overwrite local .env.local.

## Step 5: Start MCP Server (Terminal 1)

```powershell
cd ai-agents\az-tf-migration\apps-mcp-server
npm install
node index.js
```

Expected:

1. MCP process starts without crash
2. Port 8080 is listening

## Step 6: Start API Server (Terminal 2)

```powershell
cd ai-agents\az-tf-migration\apps-mcp-server\python\api
..\..\..\..\..\.venv\Scripts\python.exe -m uvicorn api_server:app --host 0.0.0.0 --port 8000 --reload
```

Health checks:

```powershell
Invoke-RestMethod -Uri "http://localhost:8000/health" -Method Get
```

Swagger:

1. http://localhost:8000/docs

## Step 7: Start UI (Terminal 3)

```powershell
cd ai-aztfexport-ui
npm install
npm run dev
```

Open:

1. http://localhost:3000

## Step 8: Run Workflow from UI

In Workflow page, use prompt:

```text
Migrate resource group 'rg-mcp-servers' from subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2
```

Execution sequence:

1. Orchestrator
2. Assessment
3. Export
4. Refactor

## Step 9: Verify Export Progress Behavior

Expected behavior:

1. Export can run several minutes without timeout.
2. UI keeps polling and reconnecting when needed.
3. Status heartbeat continues from API.
4. Job completes only when API emits complete status.

Technical settings currently applied:

1. UI request timeout: 600000 ms
2. SSE reconnect delay: 5000 ms
3. SSE heartbeat warning threshold: 30000 ms
4. API event wait interval: 10 seconds

## Step 10: Validate Output in Storage

Container and path:

1. Container: aztfexport
2. Prefix: subscriptionId/resourceGroup

Example check:

```powershell
az storage blob list --account-name samcpstorage --container-name aztfexport --prefix "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers" --auth-mode login --output table
```

## Step 11: Common Failure Recovery

If UI is up but API is down:

1. Restart API server first
2. Refresh UI page

If API is up but MCP is down:

1. Restart MCP server
2. Re-run workflow from UI

If export completed but verification is flaky:

1. Workflow now uses SDK-based storage verification path
2. Re-run only when status is failed, not when status is completed

If port conflict exists:

```powershell
Get-NetTCPConnection -LocalPort 3000,8000,8080 -ErrorAction SilentlyContinue | Select-Object LocalPort,State,OwningProcess
```

## Step 12: Production Deployment (Single Script)

Use only deploy.ps1:

```powershell
cd ai-agents\az-tf-migration\apps-mcp-server
.\deploy.ps1 -ResourceGroupName "rg-mcp-servers" -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" -TenantId "a0e1f124-d84e-4ef7-bf4b-926b60443fb9" -ClientId "4a7f6b45-8322-4cfe-bd16-008afdcc1221" -StorageAccountName "samcpstorage" -ContainerName "aztfexport" -ContainerAppName "aztf-mcp-app" -LogAnalyticsWorkspace "workspace-rgmcpserversIh7a" -AcrName "aztfmcpacr" -ImageTag "v2.5" -Port 3000 -MinReplicas 0 -MaxReplicas 1 -Cpu 0.25 -Memory "0.5Gi" -NoCache
```

This deploys in sequence:

1. MCP Server container app
2. API Server container app
3. UI container app

## Final Checklist

1. MCP running on 8080
2. API running on 8000
3. UI running on 3000
4. Workflow prompt accepted
5. Export progress remains active until complete
6. Refactor starts after export completion
7. Blob files present in storage

---

### No Logs Appearing
**Issue:** Status shows "Connected" but no logs

**Solution:**
1. Verify PowerShell script uses direct execution (`& aztfexport`)
2. Check Azure CLI: `az account show`
3. Verify subscription ID and resource group are correct
4. Check MCP server console for errors

---

### SSE Disconnects Immediately
**Issue:** Connection status flickers between connecting/disconnected

**Solution:**
1. Check browser console for CORS errors
2. Verify SSE headers in MCP server response
3. Test SSE endpoint directly:
   ```bash
   curl -N http://localhost:8080/jobs/{jobId}/progress
   ```

---

## 📚 Documentation

- **[SSE-INTEGRATION-GUIDE.md](./SSE-INTEGRATION-GUIDE.md)** - Detailed technical documentation
- **[QUICK-START.md](./QUICK-START.md)** - User-friendly getting started guide
- **[ARCHITECTURE-DIAGRAM.md](./ARCHITECTURE-DIAGRAM.md)** - Visual architecture diagrams
- **[INTEGRATION-COMPLETE.md](./INTEGRATION-COMPLETE.md)** - Implementation summary

---

## 🔄 Migration: Mock vs Real

### Before (Mock Implementation)
- ❌ Simulated 3-second delay
- ❌ Fake folder tree structure
- ❌ No backend communication
- ❌ No progress visibility

### After (Real SSE Integration)
- ✅ Real-time MCP server communication
- ✅ Live progress logs from PowerShell
- ✅ Actual Job ID tracking
- ✅ Connection state management
- ✅ Auto-reconnect on failure
- ✅ Actual storage paths displayed

---

## 🚀 Future Enhancements

### Planned Features
- [ ] Download logs as `.txt` file
- [ ] Progress bar with percentage
- [ ] Filter logs by type
- [ ] Multi-job dashboard
- [ ] Job history with replay
- [ ] File preview in UI
- [ ] HTML report viewer
- [ ] Export scheduling
- [ ] Email/Slack notifications

---

## 🎯 Success Criteria

✅ Real-time visibility into export progress  
✅ Professional terminal-style UI  
✅ Robust connection management  
✅ Clear status indicators  
✅ Comprehensive error handling  
✅ Clean React architecture  
✅ Full TypeScript typing  
✅ Complete documentation  

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

---

## 📄 License

This project is part of the aiaNextGen-Products suite.

---

## 🙏 Acknowledgments

- **Next.js** - React framework
- **TailwindCSS** - Utility-first CSS
- **Lucide Icons** - Beautiful icon set
- **EventSource API** - Browser-native SSE
- **aztfexport** - Azure to Terraform export tool
- **Azure CLI** - Azure command-line interface

---

## 📧 Support

For issues or questions:
- Review documentation in this repository
- Check backend docs in `apps-mcp-server/REALTIME-PROGRESS.md`
- Open issue in project repository

---

**The "Agent Context: MIGRATION" interface is now fully integrated with real-time progress streaming!** 🎉


