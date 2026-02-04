# Aztra - Azure Migration Neural Interface

Modern Generative AI User Interface for Azure-to-Terraform Migration with **Real-time Progress Streaming** via Server-Sent Events (SSE).

Built with **Next.js 14**, **React 18**, **TypeScript**, **TailwindCSS**, and **Framer Motion**.

---

## 🎯 Key Features

### 🔴 **Real-time Migration Progress** (NEW!)
- **Live SSE streaming** from MCP server
- Terminal-style log viewer with color-coded output
- Connection status indicators (Connecting, Connected, Completed, Error)
- Auto-reconnect on connection loss
- Job ID tracking for each export

### 🤖 **Sequential Agent Visualization**
- Watch Assessment, Migration, and Refactoring agents work in sequence
- Visual pipeline showing active agent stage
- Agent status indicators (idle, processing, success, failed)

### 💻 **Live Terminal Emulation**
- Real-time log streaming with timestamps
- Color-coded output (stdout, stderr, info, success, error)
- Auto-scrolling to latest messages
- Clear logs functionality

### 🧠 **Foundry Command Center**
- Natural language input to trigger migrations
- Structured input for Subscription ID and Resource Group
- Context-aware export orchestration

### 📊 **Storage Insights**
- Azure Blob Storage visualization
- Storage path display: `aztfExport/{subscriptionId}/{resourceGroup}/`
- Export completion status with file inventory

---

## 📋 Prerequisites

- **Node.js 18+** installed
- **MCP Server** running on port 8080 (default)
- **Azure CLI** authenticated (`az login`)
- **aztfexport** tool installed
- **PowerShell 7+** (for backend scripting)

---

## 🚀 Quick Start

### 1. Install Dependencies
```bash
cd ai-aztfexport-ui
npm install
```

### 2. Configure Backend
Create `.env.local`:
```env
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
```

### 3. Start MCP Server (Required for Real SSE)
```bash
cd ../ai-agents/az-tf-migration/apps-mcp-server
npm install  # First time only
npm start
```

Expected output:
```
MCP Server v2.0.0 running on http://localhost:8080
SSE endpoint available at /jobs/:id/progress
```

### 4. Run Development Server
```bash
cd ai-aztfexport-ui
npm run dev
```

### 5. Open in Browser
Navigate to [http://localhost:3000](http://localhost:3000)

Click **"Migration"** in the sidebar to access the real-time export interface.

---

## 🏗️ Architecture

```
┌───────────────────────────────────┐
│     MigrationPage Component       │
│  (Real-time SSE Integration)      │
└───────────┬───────────────────────┘
            │
            │ uses
            ▼
┌───────────────────────────────────┐
│    useExportProgress Hook         │
│  (EventSource SSE Connection)     │
└───────────┬───────────────────────┘
            │
            │ SSE Stream
            ▼
┌───────────────────────────────────┐
│       MCP Server (Node.js)        │
│  POST /messages                   │
│  GET /jobs/:id/progress (SSE)     │
└───────────┬───────────────────────┘
            │
            │ spawns
            ▼
┌───────────────────────────────────┐
│    PowerShell Script              │
│  Export-AzToTerraform.ps1         │
└───────────┬───────────────────────┘
            │
            │ executes
            ▼
┌───────────────────────────────────┐
│      aztfexport CLI               │
│  (Azure → Terraform)              │
└───────────────────────────────────┘
```

---

## 📂 Key Files

### Frontend
```
ai-aztfexport-ui/
├── app/
│   ├── hooks/
│   │   ├── useExportProgress.ts     # NEW: Real SSE hook
│   │   └── useAgentStream.ts        # Simulation framework
│   └── components/
│       └── pages/
│           └── MigrationPage.tsx    # UPDATED: Real SSE integration
│
├── .env.local                       # MCP server URL config
├── SSE-INTEGRATION-GUIDE.md         # Detailed technical docs
├── QUICK-START.md                   # User getting started guide
├── ARCHITECTURE-DIAGRAM.md          # Visual architecture
└── INTEGRATION-COMPLETE.md          # Implementation summary
```

### Backend (MCP Server)
```
ai-agents/az-tf-migration/apps-mcp-server/
├── index.js                         # SSE endpoint
├── tools/aztfexport.js              # Progress callbacks
├── ps/Export-AzToTerraform.ps1      # PowerShell script
└── REALTIME-PROGRESS.md             # Backend SSE docs
```

---

## 🎨 UI Components

### Migration Page Sections

1. **Input Form**
   - Subscription ID (required)
   - Resource Group (required)
   - Additional Context (optional)
   - Start Export button

2. **Status Bar**
   - Connection status badge (color-coded)
   - Job ID display
   - Clear logs button
   - Reconnect button (when disconnected)

3. **Real-time Logs**
   - Dark terminal-style display
   - Color-coded messages:
     - 🔵 Cyan: stdout (normal output)
     - 🔴 Red: stderr (error output)
     - 🔵 Blue: info (system messages)
     - 🟢 Green: success (completion)
   - Timestamps for each entry
   - Auto-scroll to latest

4. **Completion Message**
   - Success card with storage path
   - File inventory
   - Resource count

---

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEXT_PUBLIC_MCP_SERVER_URL` | `http://localhost:8080` | MCP server base URL |

### MCP Server Requirements

✅ SSE endpoint: `GET /jobs/:id/progress`  
✅ Export endpoint: `POST /messages`  
✅ Progress callbacks in `aztfexport.js`  

---

## 🧪 Testing

### Manual Test Flow

1. **Start both servers**
   ```bash
   # Terminal 1: MCP Server
   cd ai-agents/az-tf-migration/apps-mcp-server
   npm start

   # Terminal 2: UI
   cd ai-aztfexport-ui
   npm run dev
   ```

2. **Navigate to Migration page**
   - Open `http://localhost:3000`
   - Click "Migration" in sidebar

3. **Run export**
   - Enter Subscription ID: `d0f1884d-1f98-4bf1-9e15-e2986fc1bca2`
   - Enter Resource Group: `rg-mcp-servers`
   - Click "Start Export"

4. **Watch real-time logs**
   - Verify connection status: 🟢 Connected
   - See logs streaming in real-time
   - Check auto-scroll behavior

5. **Verify completion**
   - Status changes to: 🔵 Completed
   - Completion message displays
   - Storage path shown correctly

---

## 🐛 Troubleshooting

### Connection Error
**Issue:** Cannot connect to MCP server

**Solution:**
```bash
# Check MCP server is running
curl http://localhost:8080

# Restart if needed
cd ai-agents/az-tf-migration/apps-mcp-server
npm start
```

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


