# MCP Server Real-time Call Flow from UI

## Complete Call Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                          │
│                                                                 │
│  1. MigrationPage.tsx (Dedicated Migration Page)               │
│     OR                                                          │
│  2. page.tsx (Workflow Page with parsed commands)              │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  User Actions:                                            │ │
│  │  • MigrationPage: Click "Start Export" button            │ │
│  │  • Workflow: Submit command with Sub ID + RG             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                         │                                       │
│                         ▼                                       │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  Calls: startExport(subscriptionId, resourceGroup)        │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                  REACT HOOK LAYER                               │
│                                                                 │
│  useExportProgress.ts                                           │
│  Location: app/hooks/useExportProgress.ts                       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 1: POST Request to Start Export                    │  │
│  │  ─────────────────────────────────────────────────────   │  │
│  │  const response = await fetch(                           │  │
│  │    `${MCP_SERVER_URL}/messages`,                         │  │
│  │    {                                                      │  │
│  │      method: 'POST',                                     │  │
│  │      headers: { 'Content-Type': 'application/json' },    │  │
│  │      body: JSON.stringify({                              │  │
│  │        toolName: 'aztfexport',                           │  │
│  │        args: {                                           │  │
│  │          subscriptionId: subscriptionId,                 │  │
│  │          resourceGroup: resourceGroup                    │  │
│  │        }                                                  │  │
│  │      })                                                   │  │
│  │    }                                                      │  │
│  │  );                                                       │  │
│  │                                                           │  │
│  │  Environment Variable:                                   │  │
│  │  MCP_SERVER_URL = http://localhost:8080                  │  │
│  │  (from .env.local: NEXT_PUBLIC_MCP_SERVER_URL)           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 2: Extract Job ID from Response                    │  │
│  │  ─────────────────────────────────────────────────────   │  │
│  │  const result = await response.text();                   │  │
│  │  const jobIdMatch = result.match(/Job ID: ([a-f0-9-]+)/);│  │
│  │  const jobId = jobIdMatch[1];                            │  │
│  │                                                           │  │
│  │  Example Response:                                        │  │
│  │  "Export started. Job ID: a1b2c3d4-5678-90ab-cdef-..."   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 3: Open SSE Connection for Real-time Progress      │  │
│  │  ─────────────────────────────────────────────────────   │  │
│  │  const eventSource = new EventSource(                    │  │
│  │    `${MCP_SERVER_URL}/jobs/${jobId}/progress`           │  │
│  │  );                                                       │  │
│  │                                                           │  │
│  │  Full URL:                                                │  │
│  │  http://localhost:8080/jobs/a1b2c3d4-.../progress        │  │
│  │                                                           │  │
│  │  Connection Type: Server-Sent Events (SSE)               │  │
│  │  Protocol: HTTP with text/event-stream content type      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 4: Listen for SSE Events                           │  │
│  │  ─────────────────────────────────────────────────────   │  │
│  │                                                           │  │
│  │  eventSource.addEventListener('connected', (event) => {  │  │
│  │    const data = JSON.parse(event.data);                  │  │
│  │    addLog({ type: 'info', message: data.message });      │  │
│  │  });                                                      │  │
│  │                                                           │  │
│  │  eventSource.addEventListener('stdout', (event) => {     │  │
│  │    const data = JSON.parse(event.data);                  │  │
│  │    addLog({ type: 'stdout', message: data.message });    │  │
│  │  });                                                      │  │
│  │                                                           │  │
│  │  eventSource.addEventListener('stderr', (event) => {     │  │
│  │    const data = JSON.parse(event.data);                  │  │
│  │    addLog({ type: 'stderr', message: data.message });    │  │
│  │  });                                                      │  │
│  │                                                           │  │
│  │  eventSource.addEventListener('complete', (event) => {   │  │
│  │    const data = JSON.parse(event.data);                  │  │
│  │    addLog({ type: 'success', message: data.message });   │  │
│  │    setState({ status: 'completed', isRunning: false });  │  │
│  │    eventSource.close();                                   │  │
│  │  });                                                      │  │
│  │                                                           │  │
│  │  eventSource.onerror = (error) => {                      │  │
│  │    // Auto-reconnect after 3 seconds                     │  │
│  │    setTimeout(() => connectToProgress(jobId), 3000);     │  │
│  │  };                                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          │ HTTP POST & SSE Stream
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                      MCP SERVER                                 │
│                  (Node.js + Express)                            │
│                                                                 │
│  Location: ai-agents/az-tf-migration/apps-mcp-server/          │
│  Port: 8080                                                     │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Endpoint 1: POST /messages                              │  │
│  │  ────────────────────────────────────────────────────    │  │
│  │  • Receives: { toolName, args }                          │  │
│  │  • Creates Job ID (UUID)                                 │  │
│  │  • Calls: tools/aztfexport.js handler                    │  │
│  │  • Returns: "Job ID: xyz123"                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Endpoint 2: GET /jobs/:id/progress                      │  │
│  │  ────────────────────────────────────────────────────    │  │
│  │  • SSE Endpoint (text/event-stream)                      │  │
│  │  • Sends events:                                         │  │
│  │    - connected: Initial connection                       │  │
│  │    - stdout: PowerShell standard output                  │  │
│  │    - stderr: PowerShell error output                     │  │
│  │    - complete: Export finished                           │  │
│  │                                                           │  │
│  │  Event Format:                                           │  │
│  │  event: stdout                                           │  │
│  │  data: {                                                 │  │
│  │    "message": "Initializing aztfexport...",              │  │
│  │    "timestamp": "2026-02-03T10:30:05.000Z"               │  │
│  │  }                                                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Tool Handler: tools/aztfexport.js                       │  │
│  │  ────────────────────────────────────────────────────    │  │
│  │  • Spawns PowerShell child process                       │  │
│  │  • Passes environment variables (storageAccount)         │  │
│  │  • Streams stdout/stderr to SSE clients                  │  │
│  │  • Broadcasts to all connected clients                   │  │
│  │                                                           │  │
│  │  const ps = spawn(psExecutable, psArgs, {                │  │
│  │    env: { ...process.env, storageAccount: storageAccount }│  │
│  │  });                                                      │  │
│  │                                                           │  │
│  │  ps.stdout.on('data', (data) => {                        │  │
│  │    progressCallback({                                     │  │
│  │      type: 'stdout',                                     │  │
│  │      message: data.toString()                            │  │
│  │    });                                                    │  │
│  │  });                                                      │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                   POWERSHELL LAYER                              │
│                                                                 │
│  Script: ps/Export-AzToTerraform.ps1                            │
│                                                                 │
│  • Runs aztfexport CLI                                          │
│  • Generates Terraform files                                    │
│  • Uploads to Azure Storage                                     │
│  • Writes output to stdout (captured by Node.js)                │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Locations

### Frontend (UI)

**1. Hook: useExportProgress.ts**
```
Location: ai-aztfexport-ui/app/hooks/useExportProgress.ts
Lines: 1-257

Key Functions:
- startExport(subscriptionId, resourceGroup, prompt?)
- connectToProgress(jobId)
- reconnect()
- clearLogs()

MCP Server Calls:
- POST http://localhost:8080/messages (Line 173)
- EventSource http://localhost:8080/jobs/{jobId}/progress (Line 55)
```

**2. Component: MigrationPage.tsx**
```
Location: ai-aztfexport-ui/app/components/pages/MigrationPage.tsx
Lines: 1-295

Usage:
const { startExport, logs, status, isRunning } = useExportProgress();

Trigger:
handleMigrate() → startExport(subscriptionId, resourceGroup, prompt)
```

**3. Component: page.tsx (Workflow Integration)**
```
Location: ai-aztfexport-ui/app/page.tsx
Lines: 1-171

Usage:
const { 
  logs: migrationLogs,
  status: migrationStatus,
  startExport 
} = useExportProgress();

Trigger:
handleCommand(cmd) → Parse → startExport(subscriptionId, resourceGroup, cmd)
```

---

### Backend (MCP Server)

**4. Server Entry: index.js**
```
Location: ai-agents/az-tf-migration/apps-mcp-server/index.js

Endpoints:
- POST /messages → Accepts export request, returns Job ID
- GET /jobs/:id/progress → SSE endpoint for real-time progress
```

**5. Tool Handler: aztfexport.js**
```
Location: ai-agents/az-tf-migration/apps-mcp-server/tools/aztfexport.js

Key Function:
executeExportJob(job, __dirname, progressCallback)

Responsibilities:
- Spawn PowerShell process
- Pass environment variables
- Stream stdout/stderr via progressCallback
- Broadcast to all SSE clients
```

**6. PowerShell Script: Export-AzToTerraform.ps1**
```
Location: ai-agents/az-tf-migration/apps-mcp-server/ps/Export-AzToTerraform.ps1

Responsibilities:
- Run aztfexport CLI
- Generate Terraform files
- Upload to Azure Storage
- Write progress to stdout
```

---

## HTTP Request Details

### Request 1: Start Export Job

**Method:** POST  
**URL:** `http://localhost:8080/messages`  
**Headers:**
```json
{
  "Content-Type": "application/json"
}
```

**Body:**
```json
{
  "toolName": "aztfexport",
  "args": {
    "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
    "resourceGroup": "rg-mcp-servers"
  }
}
```

**Response:**
```
Export started. Job ID: a1b2c3d4-5678-90ab-cdef-1234567890ab
```

**Code Location:**
```typescript
// File: useExportProgress.ts, Lines 152-183
const response = await fetch(`${MCP_SERVER_URL}/messages`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    toolName: 'aztfexport',
    args: { subscriptionId, resourceGroup }
  }),
});

const result = await response.text();
const jobIdMatch = result.match(/Job ID: ([a-f0-9-]+)/i);
const jobId = jobIdMatch[1];
```

---

### Request 2: Subscribe to Progress Stream

**Method:** GET (SSE)  
**URL:** `http://localhost:8080/jobs/{jobId}/progress`  
**Headers:** (Set by EventSource automatically)
```
Accept: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
```

**Response Stream:**
```
event: connected
data: {"message":"Connected to export stream","timestamp":"2026-02-03T10:30:00.000Z"}

event: stdout
data: {"message":"Initializing aztfexport...","timestamp":"2026-02-03T10:30:05.000Z"}

event: stdout
data: {"message":"Found 15 resources","timestamp":"2026-02-03T10:30:10.000Z"}

event: stdout
data: {"message":"Uploading to Azure Storage...","timestamp":"2026-02-03T10:30:30.000Z"}

event: complete
data: {"message":"Export completed successfully","timestamp":"2026-02-03T10:30:35.000Z"}
```

**Code Location:**
```typescript
// File: useExportProgress.ts, Lines 44-142
const eventSource = new EventSource(`${MCP_SERVER_URL}/jobs/${jobId}/progress`);

eventSource.addEventListener('connected', (event) => {
  const data = JSON.parse(event.data);
  addLog({ type: 'info', message: data.message });
});

eventSource.addEventListener('stdout', (event) => {
  const data = JSON.parse(event.data);
  addLog({ type: 'stdout', message: data.message });
});

eventSource.addEventListener('stderr', (event) => {
  const data = JSON.parse(event.data);
  addLog({ type: 'stderr', message: data.message });
});

eventSource.addEventListener('complete', (event) => {
  const data = JSON.parse(event.data);
  addLog({ type: 'success', message: data.message });
  setState({ status: 'completed', isRunning: false });
  eventSource.close();
});
```

---

## State Management Flow

```typescript
// Initial State
{
  jobId: null,
  status: 'idle',
  logs: [],
  isRunning: false,
  error: null
}

// After startExport() called
{
  jobId: null,
  status: 'idle',
  logs: [],
  isRunning: true,    ← Set to true
  error: null
}

// After POST /messages response
{
  jobId: 'a1b2c3d4-...',  ← Job ID extracted
  status: 'idle',
  logs: [
    { type: 'info', message: 'Starting export...' }
  ],
  isRunning: true,
  error: null
}

// After SSE connection opens
{
  jobId: 'a1b2c3d4-...',
  status: 'connected',    ← Status updated
  logs: [
    { type: 'info', message: 'Starting export...' },
    { type: 'info', message: 'Connected to stream' }
  ],
  isRunning: true,
  error: null
}

// During execution (stdout events)
{
  jobId: 'a1b2c3d4-...',
  status: 'connected',
  logs: [
    { type: 'info', message: 'Starting export...' },
    { type: 'info', message: 'Connected to stream' },
    { type: 'stdout', message: 'Initializing...' },
    { type: 'stdout', message: 'Found 15 resources' },
    // ... more logs
  ],
  isRunning: true,
  error: null
}

// After completion
{
  jobId: 'a1b2c3d4-...',
  status: 'completed',    ← Status completed
  logs: [..., { type: 'success', message: 'Export complete' }],
  isRunning: false,       ← Set to false
  error: null
}
```

---

## Environment Configuration

### UI Environment (.env.local)

```bash
# Location: ai-aztfexport-ui/.env.local
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
```

**Usage in Code:**
```typescript
// File: useExportProgress.ts, Line 22
const MCP_SERVER_URL = process.env.NEXT_PUBLIC_MCP_SERVER_URL || 'http://localhost:8080';
```

### MCP Server Environment (.env)

```bash
# Location: ai-agents/az-tf-migration/apps-mcp-server/.env
storageAccount=samcpstorage
PORT=8080
```

---

## Error Handling

### Connection Errors

```typescript
// File: useExportProgress.ts, Lines 117-139
eventSource.onerror = (error) => {
  console.error('SSE connection error:', error);
  
  setState((prev) => ({
    ...prev,
    status: 'disconnected',
  }));

  addLog({
    type: 'error',
    message: 'Connection lost. Attempting to reconnect in 3 seconds...',
    timestamp: new Date().toISOString(),
  });

  // Auto-reconnect after 3 seconds
  reconnectTimeoutRef.current = setTimeout(() => {
    if (state.isRunning) {
      connectToProgress(jobId);
    }
  }, 3000);
};
```

### Export Start Errors

```typescript
// File: useExportProgress.ts, Lines 209-221
try {
  const response = await fetch(`${MCP_SERVER_URL}/messages`, {...});
  
  if (!response.ok) {
    throw new Error(`Failed to start export: ${response.statusText}`);
  }
  
  // ... process response
  
} catch (error) {
  setState({
    status: 'error',
    isRunning: false,
    error: error.message
  });
  
  addLog({
    type: 'error',
    message: error.message
  });
}
```

---

## Summary

### MCP Server Real-time Methods Called from UI:

1. **POST /messages** (Line 173 in useExportProgress.ts)
   - Purpose: Start export job
   - Returns: Job ID
   - Triggered by: `startExport()` function

2. **GET /jobs/:id/progress** (Line 55 in useExportProgress.ts)
   - Purpose: Stream real-time progress via SSE
   - Returns: Event stream (connected, stdout, stderr, complete)
   - Triggered by: `connectToProgress(jobId)` after receiving Job ID

### Used In:

1. **MigrationPage.tsx** - Dedicated migration page
2. **page.tsx** - Workflow page (when credentials detected in command)

### Key Hook:

- **useExportProgress.ts** - Handles all MCP server communication
  - HTTP POST to start job
  - SSE EventSource to stream progress
  - Auto-reconnect on connection loss
  - State management for logs and status
