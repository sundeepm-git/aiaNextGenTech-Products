# Timeout Configuration Guide

This document explains the timeout settings across the entire stack to prevent premature termination of long-running export jobs.

## Environment Variables

Add these to your `.env.local` file to customize timeout behavior:

```bash
# UI Configuration (.env.local - for local development)
NEXT_PUBLIC_API_TIMEOUT=600000                    # 10 minutes - HTTP POST timeout for starting jobs
NEXT_PUBLIC_RETRY_ATTEMPTS=3                      # Number of retry attempts for failed API calls
NEXT_PUBLIC_RETRY_DELAY=5000                      # 5 seconds - delay between retry attempts
NEXT_PUBLIC_RECONNECT_DELAY=5000                  # 5 seconds - delay before SSE reconnection
NEXT_PUBLIC_SSE_HEARTBEAT=30000                   # 30 seconds - max time between SSE events before warning
NEXT_PUBLIC_LONG_JOB_THRESHOLD=300000             # 5 minutes - threshold for "long-running" job classification
```

## Timeout Hierarchy

### 1. **Initial Job Start (HTTP POST)**
- **Timeout**: 10 minutes (600,000ms)
- **Purpose**: Allows time for job creation and initial setup
- **Configured in**: `config.ts` → `mcpServer.timeout`
- **Environment Variable**: `NEXT_PUBLIC_API_TIMEOUT`

### 2. **SSE Connection Heartbeat**
- **Interval**: 10 seconds (API sends status updates)
- **Timeout Warning**: 30 seconds (UI warns if no events received)
- **Purpose**: Keep connection alive and detect stale connections
- **Configured in**: 
  - API: `api_server.py` → `wait_for_event(job_id, 10.0)`
  - UI: `config.ts` → `ui.sseHeartbeatInterval`
- **Environment Variable**: `NEXT_PUBLIC_SSE_HEARTBEAT`

### 3. **SSE Reconnection**
- **Delay**: 5 seconds
- **Auto-reconnect**: Enabled by default
- **Purpose**: Recover from network glitches or temporary disconnections
- **Configured in**: `config.ts` → `ui.reconnectDelay`
- **Environment Variable**: `NEXT_PUBLIC_RECONNECT_DELAY`

### 4. **Export Job Execution** 
- **No Hard Timeout**: Export jobs run until completion (can take 5-15 minutes for large resource groups)
- **Progress Tracking**: Real-time via SSE stream with 10-second heartbeat
- **Status Updates**: Python script emits stdout/stderr continuously

## How It Works

### Export Job Lifecycle

```
1. User clicks "Start Export"
   ↓
2. UI sends HTTP POST to /api/workflow/start (10-minute timeout)
   ↓
3. API creates job, starts Python script, returns job ID (< 5 seconds)
   ↓
4. UI connects to SSE endpoint /api/jobs/{jobId}/progress
   ↓
5. API streams events every 10 seconds:
   - "status" events with progress %
   - "log" events with stdout/stderr
   - "complete" event when finished
   ↓
6. UI displays real-time logs and updates progress bar
   ↓
7. If SSE disconnects: auto-reconnect after 5 seconds
   ↓
8. When job completes: "complete" event closes SSE connection
```

### Heartbeat Monitoring

The UI tracks the last SSE event time and warns if:
- No events received for > 30 seconds
- Connection is stale but job still running

This helps diagnose:
- Network issues
- API server problems
- Python script hangs

## Troubleshooting

### Symptom: Progress bar shows "completed" but export still running

**Cause**: UI received a premature "complete" event or SSE reconnected after timeout

**Fix**:
1. Check browser console for SSE errors
2. Verify API server logs show continuous output
3. Increase `NEXT_PUBLIC_SSE_HEARTBEAT` to 60000ms (1 minute)
4. Check Azure Container App logs for Python script output

### Symptom: "Request timeout after 30000ms" when starting export

**Cause**: Default timeout too short for job initialization

**Fix**:
1. Increase `NEXT_PUBLIC_API_TIMEOUT` to 600000ms (10 minutes) ✅ ALREADY DONE
2. Restart Next.js dev server: `npm run dev`

### Symptom: "Connection lost. Attempting to reconnect..." repeated messages  

**Cause**: Network instability or API server restart

**Fix**:
1. Wait for auto-reconnect (5 seconds)
2. If persists, check API server health: `http://localhost:8000/health`
3. Check Azure Container App status: `az containerapp show --name aztf-mcp-app --resource-group rg-mcp-servers`

### Symptom: "No updates for 45s - connection may be stale"

**Cause**: Python script running but not emitting output

**Status**: This is a **warning, not an error**. Export is still running.

**What it means**:
- Azure CLI is enumerating resources (slow for large RGs)
- aztfexport tool is processing resources silently
- Network latency between container and blob storage

**Action**: Wait for next update. If exceeds 2 minutes, check:
```bash
# View container logs
az containerapp logs show --name aztf-mcp-app --resource-group rg-mcp-servers --tail 50

# Check if Python process is running
az containerapp exec --name aztf-mcp-app --resource-group rg-mcp-servers --command "ps aux | grep python"
```

## Production Deployment

When deploying with `deploy.ps1`, timeouts are automatically configured:

1. **API Server**: No timeout on Python script execution
2. **Container Apps**: 
   - Request timeout: 240 seconds (Azure default)
   - Health probe timeout: 30 seconds
3. **Blob Storage**: No timeout on upload operations
4. **Managed Identity**: Token refresh every 24 hours

## Performance Optimization

For faster exports:

1. **Parallel Processing**: Future enhancement - split large RGs into batches
2. **Incremental Export**: Cache resource metadata, only export changes
3. **Resource Filtering**: Export specific resource types only
4. **Compression**: Enable gzip for blob uploads

## Configuration Best Practices

### Local Development
```bash
NEXT_PUBLIC_API_TIMEOUT=600000        # 10 minutes
NEXT_PUBLIC_SSE_HEARTBEAT=30000       # 30 seconds  
NEXT_PUBLIC_RECONNECT_DELAY=5000      # 5 seconds
```

### Production (Azure)
```bash
NEXT_PUBLIC_API_TIMEOUT=900000        # 15 minutes (larger RGs)
NEXT_PUBLIC_SSE_HEARTBEAT=60000       # 1 minute (higher latency)
NEXT_PUBLIC_RECONNECT_DELAY=10000     # 10 seconds (network stability)
```

## Monitoring

Track timeout-related metrics in Observability page:

- **Agent Duration**: How long each agent ran
- **Retry Count**: Number of reconnection attempts
- **Throughput**: Jobs completed per hour
- **Error Rate**: % of jobs failing due to timeout

## Related Files

- **UI Config**: `ai-aztfexport-ui/app/services/config.ts`
- **UI Hook**: `ai-aztfexport-ui/app/hooks/useExportProgress.ts`
- **API Server**: `ai-agents/az-tf-migration/apps-mcp-server/python/api/api_server.py`
- **Workflow**: `ai-agents/az-tf-migration/apps-mcp-server/python/az-fndry-workflow/aztf-sequential-wf.py`

---

**Last Updated**: 2026-04-03  
**Version**: 1.0  
**Author**: System Configuration Team
