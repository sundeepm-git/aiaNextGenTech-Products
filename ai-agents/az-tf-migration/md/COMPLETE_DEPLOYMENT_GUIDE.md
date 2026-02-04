# Azure Terraform MCP Server - Complete Deployment Guide

**Version**: 2.0 (Async Job Pattern with Azure Blob Storage)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Local Development Setup](#local-development-setup)
5. [Azure Resources Setup](#azure-resources-setup)
6. [Container App Deployment](#container-app-deployment)
7. [Azure Blob Storage Configuration](#azure-blob-storage-configuration)
8. [API Reference](#api-reference)
9. [Testing with MCP Inspector](#testing-with-mcp-inspector)
10. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
11. [Production Deployment Checklist](#production-deployment-checklist)

---

## Overview

The Azure Terraform MCP Server is a production-grade Model Context Protocol (MCP) server that provides AI agents with tools to assess Azure environments for Terraform migration readiness. 

### Key Features

- ✓ **Async Job Pattern**: Long-running assessments without timeout issues
- ✓ **Azure Blob Storage**: Persistent report storage with public URLs
- ✓ **Managed Identity**: Secure authentication without connection strings
- ✓ **Graceful Degradation**: Falls back to local storage if Blob unavailable
- ✓ **Production-Ready**: Comprehensive error handling, logging, and health checks
- ✓ **RESTful API**: Job status tracking and report retrieval endpoints

### What's New in v2.0

**Before (v1.x)**:
- Tool executed PowerShell synchronously
- Client waited 5-10 minutes for completion
- Frequent timeout errors (MCP error -32001)
- Reports stored locally only

**After (v2.0)**:
- Tool returns Job ID immediately
- Client polls `/jobs/:id` for status
- No timeout limits
- Reports uploaded to Azure Blob Storage

---

## Architecture

### Components

```
┌─────────────────┐
│   AI Agent      │
│  (Copilot/etc)  │
└────────┬────────┘
         │ SSE/MCP Protocol
         ↓
┌─────────────────────────────────┐
│  Azure Container App            │
│  ┌───────────────────────────┐  │
│  │  MCP Server (Node.js)     │  │
│  │  - Express + SSE          │  │
│  │  - Job Queue (in-memory)  │  │
│  │  - PowerShell Spawner     │  │
│  └───────────┬───────────────┘  │
│              │                   │
│  ┌───────────▼───────────────┐  │
│  │  PowerShell + Az Modules  │  │
│  │  - Assessment Script      │  │
│  └───────────┬───────────────┘  │
└──────────────┼───────────────────┘
               │
       ┌───────┴────────┐
       │                │
       ↓                ↓
┌─────────────┐  ┌──────────────┐
│ Azure Blob  │  │ Local Report │
│  Storage    │  │  Directory   │
│ (Primary)   │  │  (Fallback)  │
└─────────────┘  └──────────────┘
```

### Job Flow

```
1. Client → MCP Tool: assess_azure_environment
2. Server → Creates Job (UUID)
3. Server → Returns Job ID + Status URL (instant)
4. Server → Spawns PowerShell (async)
5. Client → Polls GET /jobs/:id
6. PowerShell → Completes assessment
7. Server → Uploads report to Blob Storage
8. Job Status → "completed" + Report URL
9. Client → Downloads report from Blob URL
```

---

## Prerequisites

### Required Software

- **Node.js**: 18+ (22 recommended)
- **PowerShell**: 7.x
- **Docker**: For building container images
- **Azure CLI**: Latest version

### Required Azure Resources

All resources must exist before deployment:

| Resource | Type | Purpose |
|----------|------|---------|
| Azure Container Registry | `Microsoft.ContainerRegistry` | Store Docker images |
| Container Apps Environment | `Microsoft.App/managedEnvironments` | Host container apps |
| Log Analytics Workspace | `Microsoft.OperationalInsights` | Centralized logging |
| Storage Account | `Microsoft.Storage` | Blob storage for reports |
| Resource Group | `Microsoft.Resources` | Logical container |

### Azure Permissions

- **Container App**: System-assigned Managed Identity enabled
- **Storage Account**: `Storage Blob Data Contributor` role assigned to Container App identity
- **Subscription**: Reader access for assessment

---

## Local Development Setup

### Part 1: Install Dependencies

```powershell
cd apps-mcp-server
npm install
```

**Expected output**:
```
added 176 packages
```

### Part 2: Configure Environment

Create or update `.env`:

```env
# PowerShell Script Paths
POWERSHELL_SCRIPT_PATH=./ps/assessment-AzSubscription.ps1
EXPORT_SCRIPT_PATH=./ps/Export-AzToTerraform.ps1

# Server Configuration
PORT=8080

# Azure Storage (for local testing, optional)
storageAccount=samcpstorage

# ABAC (If Attribure based Access Control- You can not assign role to system assignned identity) - Use Below command to assign
```pw
az role assignment create --assignee 582c42f7-98b2-44df-aeb2-ca8b2711b31a --role "Storage Blob Data Contributor" --scope /subscriptions/d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/resourceGroups/rg-mcp-servers/providers/Microsoft.Storage/storageAccounts/samcpstorage

# ASSIGNED TO Container APP Environmet
az role assignment create --assignee 1a02c2ea-86e0-49b5-b965-3c60a23c6154 --role "Storage Blob Data Contributor" --scope /subscriptions/d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/resourceGroups/rg-mcp-servers/providers/Microsoft.Storage/storageAccounts/samcpstorage

#Command to get your local M/C public IP address
 curl ifconfig.me
 value = 108.239.222.100

# ADD in storage Account firewall rules
az storage account network-rule add --resource-group rg-mcp-servers --account-name samcpstorage --ip-address 108.239.222.100

```
# RUN after ABAC - containerapp revision restart
```
az containerapp revision list --name aztf-mcp-app --resource-group rg-mcp-servers --query "[].name" -o tsv
az containerapp revision restart --name aztf-mcp-app --resource-group rg-mcp-servers --revision aztf-mcp-app--0000008


```

# Logging
LOG_LEVEL=info
NODE_ENV=development
```

### Part 3: Authenticate to Azure

```powershell
Connect-AzAccount
Set-AzContext -Subscription "your-subscription-id"
```

### Part 4: Run Local Server

**Option A: Using Helper Script**

```powershell
.\mcpserver-run.ps1
```

**Expected output**:
```
═══════════════════════════════════════════════════════════════
   Azure Terraform MCP Server - Local Runner
═══════════════════════════════════════════════════════════════

✓ All prerequisites satisfied!
✓ Port 8080 is available

[Blob Storage] Storage account name not configured (local mode)
[Local Report Dir] Using: C:\...\apps-mcp-server\ps\report
MCP Server started successfully. Listening on: 8080
Blob Storage: DISABLED
```

**Option B: Direct Node Command**

```powershell
node index.js
```

### Part 5: Test Locally

Open another terminal:

```powershell
# Test root endpoint
Invoke-RestMethod -Uri "http://localhost:8080/"

# Test health check
Invoke-RestMethod -Uri "http://localhost:8080/health" | ConvertTo-Json
```

**Expected health response**:
```json
{
  "status": "healthy",
  "serverVersion": "2.0.0",
  "blobStorage": {
    "available": false,
    "error": "Storage account name not configured..."
  },
  "localReportDir": "C:\\...\\ps\\report",
  "activeJobs": 0
}
```

---

## Azure Resources Setup

### Step 1: Enable Managed Identity

```powershell
az containerapp identity assign `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --system-assigned
```

**Verify**:
```powershell
$IDENTITY_ID = az containerapp show `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --query identity.principalId `
  --output tsv

Write-Host "Identity Principal ID: $IDENTITY_ID"
```

### Step 2: Assign Storage Permissions

```powershell
# Assign Storage Blob Data Contributor role
az role assignment create `
  --assignee $IDENTITY_ID `
  --role "Storage Blob Data Contributor" `
  --scope "/subscriptions/YOUR-SUB-ID/resourceGroups/rg-mcp-servers/providers/Microsoft.Storage/storageAccounts/samcpstorage"
```

**Verify**:
```powershell
az role assignment list `
  --assignee $IDENTITY_ID `
  --scope "/subscriptions/YOUR-SUB-ID/resourceGroups/rg-mcp-servers/providers/Microsoft.Storage/storageAccounts/samcpstorage" `
  --query "[].roleDefinitionName" `
  --output table
```

**Expected output**:
```
Result
----------------------------------
Storage Blob Data Contributor
```

### Step 3: Configure Storage Account (if restricted)

If storage account has network restrictions:

```powershell
# Allow Azure services
az storage account update `
  --name samcpstorage `
  --resource-group rg-mcp-servers `
  --bypass AzureServices `
  --default-action Allow
```

---

## Container App Deployment

### Option 1: Using deploy.ps1 Script (Recommended)

```powershell
./deploy.ps1 `
  -ResourceGroup "rg-mcp-servers" `
  -Location "eastus" `
  -AcrName "aztfmcpacr" `
  -SubscriptionId "YOUR-SUB-ID" `
  -ContainerAppEnv "mcp-aca-env" `
  -ContainerAppName "aztf-mcp-app" `
  -LogAnalyticsWorkspace "workspace-name" `
  -Port 8080 `
  -Cpu "1.0" `
  -Memory "2.0Gi" `
  -MinReplicas 1 `
  -MaxReplicas 3
```

**One-line version**:
```powershell
./deploy.ps1 -ResourceGroup "rg-mcp-servers" -Location "eastus" -AcrName "aztfmcpacr" -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" -ContainerAppEnv "mcp-aca-env" -ContainerAppName "aztf-mcp-app" -LogAnalyticsWorkspace "workspace-rgmcpserversIh7a" -ImageTag "v2.0" -Port 8080 -Cpu "1.0" -Memory "2.0Gi" -MinReplicas 1 -MaxReplicas 3 -LogLevel "info" -NodeEnv "production"

```

### Option 2: Manual Deployment

**Step 1: Build Docker Image**

```powershell
docker build -t aztfmcpacr.azurecr.io/aztf-mcp-app:v2 .
```

**Step 2: Push to ACR**

```powershell
az acr login --name aztfmcpacr
docker push aztfmcpacr.azurecr.io/aztf-mcp-app:v2
```

**Step 3: Deploy to Container App**

```powershell
az containerapp update `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --image aztfmcpacr.azurecr.io/aztf-mcp-app:v2 `
  --set-env-vars "storageAccount=samcpstorage" "PUBLIC_HOST=aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io"
```

### Step 4: Verify Deployment

```powershell
# Get Container App URL
$URL = az containerapp show `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --query properties.configuration.ingress.fqdn `
  --output tsv

# Test health endpoint
Invoke-RestMethod -Uri "https://$URL/health" | ConvertTo-Json -Depth 5
```

**Expected output**:
```json
{
  "status": "healthy",
  "serverVersion": "2.0.0",
  "blobStorage": {
    "available": true,
    "accountName": "samcpstorage",
    "containerName": "assessment-reports",
    "error": null
  },
  "localReportDir": "/app/ps/report",
  "activeJobs": 0
}
```

---

## Azure Blob Storage Configuration

### Container Creation

The container `assessment-reports` is auto-created on first run with public blob read access.

**Manual creation** (if needed):

```powershell
az storage container create `
  --name assessment-reports `
  --account-name samcpstorage `
  --auth-mode login `
  --public-access blob
```

### Report Structure

Reports are stored in Blob Storage with this path structure:

```
assessment-reports/
├── {job-id-1}/
│   └── Assessment-{subscription-id}.html
├── {job-id-2}/
│   └── Assessment-{subscription-id}.html
└── ...
```

### Blob URLs

Public URLs are returned in job status:

```
https://samcpstorage.blob.core.windows.net/assessment-reports/{job-id}/Assessment-{sub-id}.html
```

### Troubleshooting Storage Access

**Check container exists**:
```powershell
az storage container show `
  --name assessment-reports `
  --account-name samcpstorage `
  --auth-mode login
```

**List blobs in container**:
```powershell
az storage blob list `
  --container-name assessment-reports `
  --account-name samcpstorage `
  --auth-mode login `
  --query "[].name" `
  --output table
```

**Check RBAC propagation delay**:
```powershell
# Wait 60 seconds after role assignment
Start-Sleep -Seconds 60

# Restart container to refresh token
az containerapp revision restart `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --revision $(az containerapp revision list --name aztf-mcp-app --resource-group rg-mcp-servers --query "[?properties.active].name" -o tsv)
```

---

## API Reference

### Endpoints Overview

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Root endpoint with API info |
| GET | `/health` | Health check with Blob Storage status |
| GET | `/sse` | SSE endpoint for MCP protocol |
| POST | `/messages` | MCP message handler |
| GET | `/jobs` | List all jobs |
| GET | `/jobs/:id` | Get job status and report URL |
| GET | `/reports/:filename` | Serve local reports (fallback) |

### 1. Root Endpoint

**GET /**

**Response**:
```json
{
  "message": "Azure Terraform MCP Server",
  "version": "2.0.0",
  "endpoints": {
    "sse": "/sse",
    "messages": "/messages",
    "jobs": "/jobs",
    "jobStatus": "/jobs/:id",
    "reports": "/reports/:filename",
    "health": "/health"
  }
}
```

### 2. Health Check

**GET /health**

**Response**:
```json
{
  "status": "healthy",
  "serverVersion": "2.0.0",
  "timestamp": "2026-01-30T10:40:00.000Z",
  "blobStorage": {
    "available": true,
    "accountName": "samcpstorage",
    "containerName": "assessment-reports",
    "error": null
  },
  "localReportDir": "/app/ps/report",
  "activeJobs": 3
}
```

### 3. MCP Tool: assess_azure_environment

**Tool Name**: `assess_azure_environment`

**Input**:
```json
{
  "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
  "resourceGroup": "rg-genai-infra-0014"
}
```

**Response** (immediate):
```
Job started successfully!

Job ID: 550e8400-e29b-41d4-a716-446655440000
Status: pending
Status URL: http://localhost:8080/jobs/550e8400-e29b-41d4-a716-446655440000

Poll the status URL to check progress and retrieve the report when completed.

✓ Blob Storage: Reports will be uploaded to 'samcpstorage/assessment-reports'
```

### 4. Job Status

**GET /jobs/:id**

**Response** (pending/running):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
  "resourceGroup": "rg-genai-infra-0014",
  "status": "running",
  "createdAt": "2026-01-30T10:30:00.000Z",
  "startedAt": "2026-01-30T10:30:01.000Z",
  "completedAt": null,
  "error": null,
  "reportFileName": null,
  "reportUrl": null
}
```

**Response** (completed):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
  "resourceGroup": "rg-genai-infra-0014",
  "status": "completed",
  "createdAt": "2026-01-30T10:30:00.000Z",
  "startedAt": "2026-01-30T10:30:01.000Z",
  "completedAt": "2026-01-30T10:35:23.000Z",
  "error": null,
  "reportFileName": "Assessment-d0f1884d-1f98-4bf1-9e15-e2986fc1bca2.html",
  "reportUrl": "https://samcpstorage.blob.core.windows.net/assessment-reports/550e8400-e29b-41d4-a716-446655440000/Assessment-d0f1884d-1f98-4bf1-9e15-e2986fc1bca2.html"
}
```

**Job Status Values**:
- `pending`: Job created, waiting to start
- `running`: PowerShell script executing
- `completed`: Success, report available
- `failed`: Error occurred (check `error` field)

### 5. List All Jobs

**GET /jobs**

**Response**:
```json
{
  "jobs": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "status": "completed",
      "reportUrl": "https://...",
      ...
    },
    {
      "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "status": "running",
      ...
    }
  ],
  "count": 2
}
```

### 6. Download Report (Local Fallback)

**GET /reports/:filename**

**Example**:
```powershell
Invoke-WebRequest `
  -Uri "http://localhost:8080/reports/Assessment-d0f1884d.html" `
  -OutFile "report.html"
```

---

## Testing with MCP Inspector

### Step 1: Install Inspector

```powershell
npx @modelcontextprotocol/inspector
```

### Step 2: Connect to Server

**Local**:
```
http://localhost:8080/sse
```

**Azure**:
```
https://aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io/sse
```

### Step 3: Call Tool

1. Select tool: `assess_azure_environment`
2. Fill parameters:
   - `subscriptionId`: `d0f1884d-1f98-4bf1-9e15-e2986fc1bca2`
   - `resourceGroup`: `rg-genai-infra-0014`
3. Click **Call Tool**
4. Copy Job ID from response
5. Open Status URL in browser to poll job status

### Step 4: Retrieve Report

Once job status is `completed`, click the `reportUrl` to view the HTML assessment report.

---

## Monitoring and Troubleshooting

### Check Container Logs

```powershell
# Stream logs
az containerapp logs show `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --follow

# Last 50 lines
az containerapp logs show `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --tail 50
```

**Look for**:
- `[Blob Storage] Initialized successfully` ✓
- `[Blob Storage] Failed to initialize...` ✗
- `[Job xxx] Starting PowerShell...`
- `[Job xxx] PowerShell completed successfully`

### Common Issues

#### Issue 1: Blob Storage Unavailable

**Symptoms**:
```json
{
  "blobStorage": {
    "available": false,
    "error": "This request is not authorized..."
  }
}
```

**Causes**:
- Managed Identity not enabled
- Missing `Storage Blob Data Contributor` role
- RBAC assignment not propagated yet
- Storage account network restrictions

**Fix**:
```powershell
# 1. Verify identity exists
$IDENTITY_ID = az containerapp show --name aztf-mcp-app --resource-group rg-mcp-servers --query identity.principalId -o tsv
Write-Host $IDENTITY_ID

# 2. Check role assignment
az role assignment list --assignee $IDENTITY_ID --all --output table

# 3. Assign role if missing
az role assignment create `
  --assignee $IDENTITY_ID `
  --role "Storage Blob Data Contributor" `
  --scope "/subscriptions/YOUR-SUB-ID/resourceGroups/rg-mcp-servers/providers/Microsoft.Storage/storageAccounts/samcpstorage"

# 4. Wait and restart
Start-Sleep -Seconds 60
az containerapp revision restart --name aztf-mcp-app --resource-group rg-mcp-servers --revision $(az containerapp revision list --name aztf-mcp-app --resource-group rg-mcp-servers --query "[?properties.active].name" -o tsv)
```

#### Issue 2: MCP Timeout Errors (v1.x only)

**Symptoms**:
```
MCP error -32001: Request timed out
```

**Fix**: Upgrade to v2.0 (async job pattern) using this guide.

#### Issue 3: Job Stuck in "running"

**Check logs**:
```powershell
az containerapp logs show --name aztf-mcp-app --resource-group rg-mcp-servers --tail 100 | Select-String -Pattern "Job"
```

**Look for**:
- PowerShell spawn errors
- Azure authentication failures
- Script path resolution issues

#### Issue 4: Report URL Returns 404

**If Blob URL**:
```powershell
# Check container public access
az storage container show `
  --name assessment-reports `
  --account-name samcpstorage `
  --auth-mode login `
  --query "properties.publicAccess"
```

**Expected**: `blob` (not `null` or `none`)

**Fix**:
```powershell
az storage container set-permission `
  --name assessment-reports `
  --account-name samcpstorage `
  --public-access blob `
  --auth-mode login
```

### Restart Container

```powershell
# List revisions
az containerapp revision list `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --query "[?properties.active].name" `
  --output table

# Restart specific revision
az containerapp revision restart `
  --name aztf-mcp-app `
  --resource-group rg-mcp-servers `
  --revision aztf-mcp-app--0000006
```

---

## Production Deployment Checklist

### Pre-Deployment

- [ ] All Azure resources exist (ACR, Container App Env, Storage Account, etc.)
- [ ] System-assigned Managed Identity enabled on Container App
- [ ] `Storage Blob Data Contributor` role assigned to identity
- [ ] Storage account allows Azure services or Container App subnet
- [ ] Dependencies installed: `npm install`
- [ ] Environment variables configured (`.env` or Container App settings)
- [ ] Docker image built and tested locally

### Deployment

- [ ] Image pushed to ACR
- [ ] Container App updated with new image tag
- [ ] Environment variables set: `storageAccount`, `PUBLIC_HOST`
- [ ] Container App restarted to pick up changes

### Post-Deployment

- [ ] `/health` endpoint returns `status: "healthy"`
- [ ] `blobStorage.available` is `true`
- [ ] MCP tool returns Job ID successfully
- [ ] `/jobs/:id` returns status
- [ ] Job completes and report URL is accessible
- [ ] Container logs show no errors
- [ ] Test from MCP Inspector

### Monitoring

- [ ] Set up Azure Monitor alerts for Container App health
- [ ] Configure Log Analytics queries for job failures
- [ ] Monitor Blob Storage capacity and costs
- [ ] Track average job duration in logs

---

## Polling Best Practices

### JavaScript Example

```javascript
async function pollJob(jobId, baseUrl) {
  const maxAttempts = 60; // 10 minutes max
  const interval = 10000; // 10 seconds
  
  for (let i = 0; i < maxAttempts; i++) {
    const res = await fetch(`${baseUrl}/jobs/${jobId}`);
    const job = await res.json();
    
    if (job.status === 'completed') {
      console.log(`Report ready: ${job.reportUrl}`);
      return job;
    } else if (job.status === 'failed') {
      throw new Error(job.error);
    }
    
    console.log(`Job ${job.status}... (${i + 1}/${maxAttempts})`);
    await new Promise(r => setTimeout(r, interval));
  }
  
  throw new Error('Job timeout');
}

// Usage
const jobId = "550e8400-e29b-41d4-a716-446655440000";
const result = await pollJob(jobId, "https://aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io");
window.open(result.reportUrl);
```

### PowerShell Example

```powershell
function Wait-JobCompletion {
    param(
        [string]$JobId,
        [string]$BaseUrl,
        [int]$MaxAttempts = 60,
        [int]$IntervalSeconds = 10
    )
    
    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        $job = Invoke-RestMethod -Uri "$BaseUrl/jobs/$JobId"
        
        if ($job.status -eq "completed") {
            Write-Host "✓ Report ready: $($job.reportUrl)" -ForegroundColor Green
            return $job
        }
        elseif ($job.status -eq "failed") {
            throw "Job failed: $($job.error)"
        }
        
        Write-Host "Job $($job.status)... ($($i+1)/$MaxAttempts)" -ForegroundColor Yellow
        Start-Sleep -Seconds $IntervalSeconds
    }
    
    throw "Job timeout after $($MaxAttempts * $IntervalSeconds) seconds"
}

# Usage
$jobId = "550e8400-e29b-41d4-a716-446655440000"
$result = Wait-JobCompletion -JobId $jobId -BaseUrl "https://aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io"
Start-Process $result.reportUrl
```

---

## Environment Variables Reference

### Required

| Variable | Example | Description |
|----------|---------|-------------|
| `storageAccount` | `samcpstorage` | Azure Storage account name for Blob uploads |
| `PORT` | `8080` | HTTP server port |

### Optional

| Variable | Example | Description |
|----------|---------|-------------|
| `PUBLIC_HOST` | `aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io` | Public hostname for job status URLs |
| `POWERSHELL_SCRIPT_PATH` | `./ps/assessment-AzSubscription.ps1` | Path to assessment script |
| `LOG_LEVEL` | `info` | Logging verbosity |
| `NODE_ENV` | `production` | Node environment |

---

## Support and Resources

### Documentation

- **MCP Protocol**: https://modelcontextprotocol.io/
- **Azure Container Apps**: https://learn.microsoft.com/azure/container-apps/
- **Azure Blob Storage**: https://learn.microsoft.com/azure/storage/blobs/

### Troubleshooting Resources

- **Container Logs**: `az containerapp logs show`
- **Health Endpoint**: `/health` for real-time status
- **Job Status API**: `/jobs/:id` for detailed job info

### Common Commands Quick Reference

```powershell
# Get Container App URL
az containerapp show --name aztf-mcp-app --resource-group rg-mcp-servers --query properties.configuration.ingress.fqdn -o tsv

# View logs
az containerapp logs show --name aztf-mcp-app --resource-group rg-mcp-servers --follow

# Restart container
az containerapp revision restart --name aztf-mcp-app --resource-group rg-mcp-servers --revision $(az containerapp revision list --name aztf-mcp-app --resource-group rg-mcp-servers --query "[?properties.active].name" -o tsv)

# Check health
Invoke-RestMethod -Uri "https://YOUR-APP-URL/health" | ConvertTo-Json

# List jobs
Invoke-RestMethod -Uri "https://YOUR-APP-URL/jobs"

# Check job status
Invoke-RestMethod -Uri "https://YOUR-APP-URL/jobs/YOUR-JOB-ID"
```

---

**End of Guide** - Version 2.0 | Last Updated: January 30, 2026
