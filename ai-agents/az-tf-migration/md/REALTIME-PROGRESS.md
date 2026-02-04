# Real-Time Progress Streaming

This MCP server now supports real-time progress streaming for Azure Terraform export jobs using Server-Sent Events (SSE).

## Features

✅ **Real-time Output** - See PowerShell script output as it happens  
✅ **Progress Updates** - Monitor aztfexport progress in real-time  
✅ **Multiple Clients** - Multiple frontends can connect to the same job  
✅ **Auto-Reconnect** - Automatic reconnection on connection loss  
✅ **Job Status** - Get current job status and existing output

## Architecture

```
┌──────────────┐      ┌──────────────┐      ┌──────────────────┐
│   Frontend   │─────▶│  MCP Server  │─────▶│ PowerShell Script│
│              │◀─SSE─│  (Node.js)   │◀─────│  (aztfexport)   │
└──────────────┘      └──────────────┘      └──────────────────┘
```

## API Endpoints

### 1. Start Export Job
**POST** `/messages`

Start an export job using MCP protocol:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "aztfexport",
    "arguments": {
      "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
      "resourceGroup": "rg-mcp-servers"
    }
  }
}
```

Response includes job ID:
```
Job ID: 550e8400-e29b-41d4-a716-446655440000
```

### 2. Real-Time Progress Stream
**GET** `/jobs/{jobId}/progress`

Connect to SSE stream for real-time updates:

```javascript
const eventSource = new EventSource('http://localhost:8080/jobs/{jobId}/progress');

eventSource.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log(data);
};
```

## Progress Event Types

### 1. Connected Event
Sent immediately when client connects:
```json
{
  "type": "connected",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "running",
  "message": "Connected to progress stream"
}
```

### 2. Standard Output (stdout)
Real-time output from PowerShell script:
```json
{
  "type": "stdout",
  "message": "Export started at: 10:24:54\n",
  "timestamp": "2026-02-03T10:24:54.123Z",
  "jobId": "550e8400-e29b-41d4-a716-446655440000"
}
```

### 3. Error Output (stderr)
Error messages and warnings:
```json
{
  "type": "stderr",
  "message": "Warning: Resource type excluded\n",
  "timestamp": "2026-02-03T10:25:01.456Z",
  "jobId": "550e8400-e29b-41d4-a716-446655440000"
}
```

### 4. Completion Event
Sent when job completes:
```json
{
  "type": "complete",
  "status": "completed",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-03T10:28:30.789Z",
  "completedAt": "2026-02-03T10:28:30.789Z",
  "error": null
}
```

## Frontend Implementation

### JavaScript Example

```javascript
// Start export job
async function startExport(subscriptionId, resourceGroup) {
  const response = await fetch('http://localhost:8080/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: {
        name: 'aztfexport',
        arguments: { subscriptionId, resourceGroup }
      }
    })
  });
  
  const data = await response.json();
  const jobIdMatch = data.result?.content?.[0]?.text.match(/Job ID: ([a-f0-9-]+)/i);
  
  return jobIdMatch ? jobIdMatch[1] : null;
}

// Connect to progress stream
function watchProgress(jobId) {
  const eventSource = new EventSource(`http://localhost:8080/jobs/${jobId}/progress`);
  
  eventSource.onmessage = (event) => {
    const data = JSON.parse(event.data);
    
    switch (data.type) {
      case 'connected':
        console.log('✓ Connected to progress stream');
        break;
        
      case 'stdout':
        console.log(data.message);
        break;
        
      case 'stderr':
        console.error(data.message);
        break;
        
      case 'complete':
        console.log(`✓ Export ${data.status}`);
        eventSource.close();
        break;
    }
  };
  
  eventSource.onerror = () => {
    console.error('Connection error');
  };
  
  return eventSource;
}

// Usage
const jobId = await startExport('sub-id', 'rg-name');
const stream = watchProgress(jobId);
```

### React Hook Example

```jsx
import { useState, useEffect } from 'react';

function useExportProgress(jobId) {
  const [logs, setLogs] = useState([]);
  const [status, setStatus] = useState('connecting');
  
  useEffect(() => {
    if (!jobId) return;
    
    const eventSource = new EventSource(
      `http://localhost:8080/jobs/${jobId}/progress`
    );
    
    eventSource.onopen = () => setStatus('connected');
    
    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      
      if (data.type === 'stdout' || data.type === 'stderr') {
        setLogs(prev => [...prev, {
          type: data.type,
          message: data.message,
          timestamp: data.timestamp
        }]);
      }
      
      if (data.type === 'complete') {
        setStatus(data.status);
        eventSource.close();
      }
    };
    
    eventSource.onerror = () => setStatus('disconnected');
    
    return () => eventSource.close();
  }, [jobId]);
  
  return { logs, status };
}

// Usage in component
function ExportMonitor({ jobId }) {
  const { logs, status } = useExportProgress(jobId);
  
  return (
    <div>
      <div>Status: {status}</div>
      <div className="logs">
        {logs.map((log, i) => (
          <div key={i} className={log.type}>
            [{new Date(log.timestamp).toLocaleTimeString()}] {log.message}
          </div>
        ))}
      </div>
    </div>
  );
}
```

## Testing

### 1. Test with Example HTML

Open `example-frontend-progress.html` in your browser:
```bash
# Open in default browser (Windows)
start example-frontend-progress.html

# Or serve with a simple HTTP server
npx serve .
```

### 2. Test with cURL

```bash
# Start export job
curl -X POST http://localhost:8080/messages \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "aztfexport",
      "arguments": {
        "subscriptionId": "your-sub-id",
        "resourceGroup": "your-rg-name"
      }
    }
  }'

# Connect to progress stream (replace JOB_ID)
curl -N http://localhost:8080/jobs/{JOB_ID}/progress
```

## Connection Management

### Heartbeat
Server sends heartbeat every 30 seconds to keep connection alive:
```
: heartbeat
```

### Reconnection
If connection is lost, frontend should reconnect automatically:

```javascript
eventSource.onerror = () => {
  setTimeout(() => {
    // Reconnect after 3 seconds
    connectToProgressStream(serverUrl, jobId);
  }, 3000);
};
```

### Multiple Clients
Multiple clients can connect to the same job progress stream simultaneously. Each client receives all progress updates independently.

## Storage Path Updates

Export files are now stored in the following hierarchy:
```
Container: aztfExport
├── {SubscriptionId}/
│   ├── {ResourceGroupName}/
│   │   ├── main.tf
│   │   ├── provider.tf
│   │   ├── data-sources.tf
│   │   ├── terraform.tfstate
│   │   └── Export-Report_{RG}_{timestamp}.html
```

Example:
```
aztfExport/
├── d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/
│   ├── rg-mcp-servers/
│   │   ├── main.tf
│   │   ├── provider.tf
│   │   └── Export-Report_rg-mcp-servers_20260203-102830.html
```

## Benefits

1. **User Experience** - Users see progress immediately instead of waiting
2. **Debugging** - Real-time visibility into what's happening
3. **Transparency** - Clear feedback on long-running operations
4. **Monitoring** - Track multiple exports simultaneously
5. **Resilience** - Automatic reconnection on network issues

## Browser Compatibility

✅ Chrome/Edge - Full support  
✅ Firefox - Full support  
✅ Safari - Full support  
✅ Mobile browsers - Full support  

SSE is widely supported in all modern browsers.
