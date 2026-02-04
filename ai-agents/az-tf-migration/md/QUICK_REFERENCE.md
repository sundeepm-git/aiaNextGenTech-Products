# MCP Server - Quick Reference Guide

## 🎯 Three Main Tools

### 1. **assess_azure_environment**
Assess Azure resources for Terraform migration readiness.

```javascript
{
  "name": "assess_azure_environment",
  "arguments": {
    "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
    "resourceGroup": "rg-mcp-servers"
  }
}
```

**Output**: HTML assessment report in Azure Blob Storage  
**Container**: `assessment-reports/{subscriptionId}/`

---

### 2. **export_azure_to_terraform**
Export Azure resources to Terraform configuration files.

```javascript
{
  "name": "export_azure_to_terraform",
  "arguments": {
    "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
    "resourceGroup": "rg-mcp-servers"
  }
}
```

**Output**: Terraform files (.tf, .tfstate, etc.)  
**Container**: `aztfexport/{subscriptionId}/{resourceGroup}/`

---

### 3. **refactor_terraform_code** ⭐ NEWLY IMPLEMENTED
Refactor exported Terraform code to follow best practices.

```javascript
{
  "name": "refactor_terraform_code",
  "arguments": {
    "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
    "resourceGroup": "rg-mcp-servers",
    "refactorOptions": {
      "verbose": true,
      "dryRun": false,
      "variableOptimization": true,
      "securityHardening": true
    }
  }
}
```

**Output**: Refactored Terraform files  
**Container**: `code-refactored/{subscriptionId}/{resourceGroup}/`  
**Files**: `variables.tf`, `terraform.tfvars`, `outputs.tf`, `providers.tf`, etc.

---

## 🔄 Complete Workflow

```
1. ASSESS    → Generate assessment report
2. EXPORT    → Export resources to Terraform
3. REFACTOR  → Optimize and secure Terraform code
```

**Example:**
```javascript
// Step 1: Assess
await assess_azure_environment({
  subscriptionId: "xxx",
  resourceGroup: "my-rg"
});

// Step 2: Export
await export_azure_to_terraform({
  subscriptionId: "xxx",
  resourceGroup: "my-rg"
});

// Step 3: Refactor
await refactor_terraform_code({
  subscriptionId: "xxx",
  resourceGroup: "my-rg",
  refactorOptions: { variableOptimization: true }
});
```

---

## 📍 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Server info & tools list |
| `/health` | GET | Health check + storage status |
| `/sse` | GET | MCP SSE connection |
| `/messages` | POST | MCP messages endpoint |
| `/jobs` | GET | List all jobs |
| `/jobs/:id` | GET | Get job status |
| `/jobs/:id/progress` | GET | Real-time progress (SSE) |
| `/reports/:filename` | GET | Download reports |

---

## 🔍 Job Status Tracking

### Check Job Status:
```bash
curl http://localhost:8080/jobs/{jobId}
```

### Watch Real-Time Progress:
```bash
curl -N http://localhost:8080/jobs/{jobId}/progress
```

### Response Example:
```json
{
  "id": "abc-123",
  "status": "completed",
  "reportUrl": "https://samcpstorage.blob.core.windows.net/...",
  "message": {
    "status": "SUCCESS",
    "summary": "Refactoring completed successfully",
    "instructions": "✓ Files uploaded to Azure Storage"
  }
}
```

---

## ⚙️ Server Configuration

### Required Environment Variables:
```bash
# Azure Storage
storageAccount=samcpstorage
storageAccountRG=rg-mcp-servers

# Output Destination
OUTPUT_DESTINATION=both  # azure | github | both

# GitHub (optional)
GITHUB_TOKEN=ghp_xxx
GITHUB_OWNER=sundeepm-git
GITHUB_REPO=refactored-terraform

# Script Paths
POWERSHELL_SCRIPT_PATH=./ps/assessment-AzSubscription.ps1
EXPORT_SCRIPT_PATH=./ps/Export-AzToTerraform.ps1
REFACTOR_SCRIPT_PATH=./python/refactor.py
```

---

## 🧹 Automatic Maintenance

### Job Cleanup:
- **Frequency**: Every 60 minutes
- **Retention**: 24 hours
- **What's cleaned**: Completed/failed jobs older than 24 hours
- **Logs**: `[Job Cleanup] Removed X old job(s)`

### Progress Callback Cleanup:
- Automatically removed when job completes
- Prevents memory leaks from SSE connections

---

## 🚀 Starting the Server

### Local Development:
```bash
npm install
npm start
```

### Docker:
```bash
docker build -t aztf-mcp-server .
docker run -p 8080:8080 --env-file .env aztf-mcp-server
```

### Azure Container Apps:
```bash
az containerapp up \
  --name aztf-mcp-app \
  --resource-group rg-mcp-servers \
  --location centralus \
  --image sundeepm/aztf-mcp-server:latest \
  --env-vars $(cat .env | xargs)
```

---

## 🔧 Troubleshooting

### Issue: Python not found
**Error**: `Python is not installed or not in PATH`  
**Fix**: Install Python 3.8+ and add to PATH

### Issue: aztfexport not found
**Error**: `Required tool 'aztfexport' is not installed`  
**Fix**: 
- Windows: `winget install aztfexport`
- macOS: `brew install aztfexport`
- Linux: Download from GitHub releases

### Issue: Blob Storage upload fails
**Error**: `Blob Storage: Failed to initialize`  
**Fix**: Check `storageAccount` env var and Managed Identity permissions

### Issue: GitHub upload fails
**Error**: `GitHub upload: 403 Forbidden`  
**Fix**: Verify `GITHUB_TOKEN` has `repo` scope permissions

---

## 📊 Monitoring

### Health Check:
```bash
curl http://localhost:8080/health
```

**Response:**
```json
{
  "status": "healthy",
  "serverVersion": "2.0.1",
  "blobStorage": {
    "available": true,
    "accountName": "samcpstorage",
    "containerName": "assessment-reports"
  },
  "activeJobs": 3
}
```

### View Active Jobs:
```bash
curl http://localhost:8080/jobs
```

### Check Server Logs:
```bash
# Look for these log patterns:
[Job xyz] Starting...
[Job xyz] Python still running (60s)
[Job xyz] ✅ Completed
[Job Cleanup] Removed 2 old job(s)
```

---

## 🎨 Example Use Cases

### Use Case 1: Migrate Single Resource Group
```javascript
// 1. Assess first
const assessJob = await assess_azure_environment({
  subscriptionId: "xxx",
  resourceGroup: "my-app-rg"
});

// 2. Review assessment report
// 3. Export to Terraform
const exportJob = await export_azure_to_terraform({
  subscriptionId: "xxx",
  resourceGroup: "my-app-rg"
});

// 4. Refactor for best practices
const refactorJob = await refactor_terraform_code({
  subscriptionId: "xxx",
  resourceGroup: "my-app-rg",
  refactorOptions: {
    variableOptimization: true,
    securityHardening: true
  }
});
```

### Use Case 2: Batch Migration
```javascript
const resourceGroups = ["rg-app1", "rg-app2", "rg-app3"];

for (const rg of resourceGroups) {
  // Assess
  await assess_azure_environment({ subscriptionId: "xxx", resourceGroup: rg });
  
  // Export
  await export_azure_to_terraform({ subscriptionId: "xxx", resourceGroup: rg });
  
  // Refactor
  await refactor_terraform_code({ 
    subscriptionId: "xxx", 
    resourceGroup: rg,
    refactorOptions: { variableOptimization: true }
  });
}
```

---

## 📚 Additional Resources

- **Documentation**: See `IMPROVEMENTS_IMPLEMENTED.md`
- **Architecture**: See `tools/README.md`
- **Deployment**: See `COMPLETE_DEPLOYMENT_GUIDE.md`
- **GitHub Repo**: https://github.com/sundeepm-git/refactored-terraform

---

**Version**: 2.0.1  
**Last Updated**: February 3, 2026  
**Status**: ✅ Production Ready
