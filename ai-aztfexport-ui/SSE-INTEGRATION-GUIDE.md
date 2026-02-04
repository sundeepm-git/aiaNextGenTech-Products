
# SSE Integration Guide - Migration Page

## Overview

The MigrationPage component has been fully integrated with the MCP Server's Server-Sent Events (SSE) endpoint to display real-time progress of Azure-to-Terraform export operations.

## Architecture

```
┌─────────────────┐
│  MigrationPage  │
│   (React/TSX)   │
└────────┬────────┘
         │
         │ useExportProgress()
         │
    ┌────▼───────────────┐
    │ useExportProgress  │
    │   (React Hook)     │
    └────┬───────────────┘
         │
         │ EventSource
         │
    ┌────▼───────────────┐
    │   MCP Server       │
    │ SSE Endpoint:      │
    │ /jobs/:id/progress │
    └────┬───────────────┘
         │
         │ Progress Callbacks
         │
    ┌────▼───────────────┐
    │ aztfexport.js      │
    │ (PowerShell spawn) │
    └────┬───────────────┘
         │
         │ stdout/stderr
         │
    ┌────▼───────────────┐
    │ PowerShell Script  │
    │ Export-AzToTerraform│
    └────────────────────┘
```

## Files Modified/Created

### 1. **useExportProgress.ts** (New Hook)
**Location:** `ai-aztfexport-ui/app/hooks/useExportProgress.ts`

Custom React hook that manages SSE connection and export state.

**Features:**
- Establishes EventSource connection to MCP server
- Handles connection states (idle, connecting, connected, completed, error, disconnected)
- Auto-reconnect on connection loss (3-second delay)
- Real-time log streaming with timestamps
- Job ID extraction from MCP server response
- Cleanup on component unmount

**API:**
```typescript
interface UseExportProgressReturn {
  jobId: string | null;
  status: 'idle' | 'connecting' | 'connected' | 'completed' | 'error' | 'disconnected';
  logs: ProgressLog[];
  isRunning: boolean;
  error: string | null;
  startExport: (subscriptionId: string, resourceGroup: string, prompt?: string) => Promise<void>;
  clearLogs: () => void;
  reconnect: () => void;
}
```

**Usage:**
```typescript
const {
  jobId,
  status,
  logs,
  isRunning,
  error,
  startExport,
  clearLogs,
  reconnect,
} = useExportProgress();

// Start export
await startExport('subscription-id', 'resource-group-name', 'optional context');
```

### 2. **MigrationPage.tsx** (Updated Component)
**Location:** `ai-aztfexport-ui/app/components/pages/MigrationPage.tsx`

Complete overhaul from mock simulation to real SSE integration.

**Key Changes:**
- ✅ Removed mock folder tree structure
- ✅ Added subscription ID and resource group input fields
- ✅ Integrated `useExportProgress` hook
- ✅ Real-time log display with color coding
- ✅ Connection status badge (idle, connecting, connected, completed, error, disconnected)
- ✅ Auto-scrolling log viewer
- ✅ Reconnect button for disconnected state
- ✅ Clear logs functionality
- ✅ Completion message with storage path info

**UI Components:**

1. **Input Form:**
   - Subscription ID (required)
   - Resource Group (required)
   - Additional Context (optional)
   - Start Export button (disabled when running or missing required fields)

2. **Status Bar:**
   - Current job status with colored badge
   - Job ID display
   - Clear logs button

3. **Real-time Logs:**
   - Dark terminal-style display
   - Color-coded messages:
     - `stdout`: Cyan (normal output)
     - `stderr`: Red (error output)
     - `info`: Blue (system messages)
     - `success`: Green (completion)
     - `error`: Bold red (critical errors)
   - Timestamp for each log entry
   - Auto-scroll to latest message

4. **Completion Message:**
   - Success card with storage path
   - Resource count (from logs)
   - File list information

## Configuration

### Environment Variables

Set the MCP server URL in `.env.local`:

```env
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
```

**Default:** `http://localhost:8080` (if not set)

### MCP Server Requirements

Ensure the MCP server is running with:
- ✅ SSE endpoint: `GET /jobs/:id/progress`
- ✅ Export endpoint: `POST /messages` with `toolName: 'aztfexport'`
- ✅ Progress callbacks in `aztfexport.js`

## Event Flow

### 1. User Initiates Export
```typescript
// User clicks "Start Export"
await startExport('d0f1884d-1f98-4bf1-9e15-e2986fc1bca2', 'rg-production');
```

### 2. Hook Calls MCP Server
```http
POST /messages HTTP/1.1
Content-Type: application/json

{
  "toolName": "aztfexport",
  "args": {
    "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
    "resourceGroup": "rg-production"
  }
}
```

### 3. Extract Job ID
```typescript
// Response: "Export started. Job ID: a1b2c3d4-..."
const jobIdMatch = result.match(/Job ID: ([a-f0-9-]+)/i);
const jobId = jobIdMatch[1]; // "a1b2c3d4-..."
```

### 4. Connect to SSE Endpoint
```typescript
const eventSource = new EventSource(
  `http://localhost:8080/jobs/${jobId}/progress`
);
```

### 5. Receive Real-time Events

**Connected Event:**
```json
event: connected
data: {"message":"Connected to export progress","timestamp":"2024-01-15T10:30:00.000Z"}
```

**Stdout Event:**
```json
event: stdout
data: {"message":"Importing resource: azurerm_storage_account...","timestamp":"2024-01-15T10:30:15.123Z"}
```

**Stderr Event:**
```json
event: stderr
data: {"message":"Warning: Resource type may not be fully supported","timestamp":"2024-01-15T10:30:20.456Z"}
```

**Complete Event:**
```json
event: complete
data: {"message":"Export completed successfully","timestamp":"2024-01-15T10:35:00.789Z"}
```

### 6. Display in UI
Each event is converted to a `ProgressLog` and rendered in the terminal-style viewer.

## Status States

| Status | Description | Badge Color | User Action |
|--------|-------------|-------------|-------------|
| `idle` | No export running | Gray | Can start export |
| `connecting` | Establishing SSE connection | Yellow (pulsing) | Wait |
| `connected` | Receiving real-time updates | Green (pulsing) | View logs |
| `completed` | Export finished successfully | Blue | View results |
| `error` | Export failed | Red | Retry |
| `disconnected` | Connection lost | Gray | Reconnect |

## Error Handling

### Connection Errors
If SSE connection fails:
1. Status changes to `disconnected`
2. Error log displayed: "Connection lost. Attempting to reconnect in 3 seconds..."
3. Auto-reconnect after 3 seconds
4. Manual reconnect button available

### Export Errors
If MCP server returns error:
1. Status changes to `error`
2. Error message displayed in red alert box
3. User can retry with new inputs

## Testing

### 1. Start MCP Server
```bash
cd ai-agents/az-tf-migration/apps-mcp-server
npm start
# Server runs on http://localhost:8080
```

### 2. Start Next.js App
```bash
cd ai-aztfexport-ui
npm run dev
# App runs on http://localhost:3000
```

### 3. Test Export Flow
1. Navigate to "Migration" page
2. Enter subscription ID: `d0f1884d-1f98-4bf1-9e15-e2986fc1bca2`
3. Enter resource group: `rg-mcp-servers`
4. Click "Start Export"
5. Watch real-time logs appear
6. Verify completion message with storage path

### 4. Test Reconnection
1. Stop MCP server during export
2. Verify "Disconnected" status appears
3. Restart MCP server
4. Click "Reconnect" button
5. Verify logs resume streaming

## Comparison: Before vs After

### Before (Mock Implementation)
- ❌ Simulated 3-second delay with `setTimeout`
- ❌ Hardcoded fake folder tree structure
- ❌ No real backend communication
- ❌ No progress visibility during export
- ❌ Generic "Migration" prompt

### After (Real SSE Integration)
- ✅ Real-time communication with MCP server
- ✅ Live progress logs from PowerShell script
- ✅ Actual export job tracking with Job ID
- ✅ Connection state management
- ✅ Auto-reconnect on connection loss
- ✅ Specific subscription ID and resource group inputs
- ✅ Completion message with actual storage path

## Performance Considerations

### Log Buffering
- Logs are accumulated in React state
- Consider limiting to last 1000 logs for long-running exports
- Clear logs button available to free memory

### Connection Management
- EventSource automatically handles HTTP/2 multiplexing
- Single connection per export job
- Proper cleanup on component unmount prevents memory leaks

### Auto-scroll Optimization
- Uses `scrollIntoView` with smooth behavior
- Triggered only when new logs arrive
- Ref-based scrolling avoids re-renders

## Future Enhancements

### Planned Features
1. **Download Logs**: Export logs to `.txt` file
2. **Progress Bar**: Calculate percentage based on resource count
3. **Multi-job Dashboard**: Track multiple exports simultaneously
4. **Log Filtering**: Filter by log type (stdout, stderr, info, etc.)
5. **Job History**: Store completed jobs in local storage
6. **Export Metrics**: Display total resources, time taken, success rate

### Backend Enhancements
1. **File Preview**: Stream generated Terraform files to UI
2. **HTML Report Link**: Open HTML report in new tab
3. **Storage Explorer**: Browse exported files directly from UI
4. **Diff Viewer**: Compare exported code with previous versions

## Troubleshooting

### Issue: "Connection lost. Attempting to reconnect..."

**Causes:**
- MCP server stopped or crashed
- Network interruption
- Server restart

**Solutions:**
1. Check MCP server is running: `curl http://localhost:8080`
2. Check network connectivity
3. Click "Reconnect" button
4. Restart MCP server if necessary

---

### Issue: "Could not extract job ID from response"

**Causes:**
- MCP server returned unexpected response format
- Export tool crashed before returning job ID

**Solutions:**
1. Check MCP server logs for errors
2. Verify `aztfexport` tool is installed
3. Check PowerShell script permissions
4. Test MCP endpoint directly:
   ```bash
   curl -X POST http://localhost:8080/messages \
     -H "Content-Type: application/json" \
     -d '{"toolName":"aztfexport","args":{"subscriptionId":"...","resourceGroup":"..."}}'
   ```

---

### Issue: No logs appearing after "Connected"

**Causes:**
- PowerShell script not outputting to stdout
- Progress callbacks not configured
- Azure CLI authentication issues

**Solutions:**
1. Verify `Export-AzToTerraform.ps1` uses `& aztfexport` (not `Start-Process -RedirectStandardOutput`)
2. Check `aztfexport.js` has progress callbacks implemented
3. Test Azure CLI: `az account show`
4. Check PowerShell execution policy: `Get-ExecutionPolicy`

---

### Issue: SSE connection immediately disconnects

**Causes:**
- CORS issues if MCP server and UI on different domains
- Reverse proxy buffering SSE responses
- MCP server not sending SSE headers

**Solutions:**
1. Verify MCP server CORS settings allow SSE
2. Check SSE headers in network tab:
   ```
   Content-Type: text/event-stream
   Cache-Control: no-cache
   Connection: keep-alive
   ```
3. Test SSE endpoint directly:
   ```bash
   curl -N http://localhost:8080/jobs/{jobId}/progress
   ```

## Related Documentation

- [REALTIME-PROGRESS.md](../ai-agents/az-tf-migration/apps-mcp-server/REALTIME-PROGRESS.md) - Backend SSE implementation
- [example-frontend-progress.html](../ai-agents/az-tf-migration/apps-mcp-server/example-frontend-progress.html) - Standalone SSE demo
- [Export-AzToTerraform.ps1](../ai-agents/az-tf-migration/apps-mcp-server/ps/Export-AzToTerraform.ps1) - PowerShell export script

## Summary

The MigrationPage component now provides a production-ready interface for Azure-to-Terraform export operations with:
- Real-time progress visibility
- Robust connection management
- User-friendly status indicators
- Professional terminal-style log display
- Comprehensive error handling

Users can now monitor their exports in real-time, see exactly what's happening during the process, and get immediate feedback on success or failure.
