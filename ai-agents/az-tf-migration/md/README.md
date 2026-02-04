# Azure Terraform Migration MCP Server

**Version:** 1.0.0  
**Runtime:** Node.js  
**Protocol:** Model Context Protocol (MCP)

Enterprise-grade MCP server for Azure-to-Terraform migration workflows with AI agent orchestration.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running Locally](#running-locally)
- [Tools](#tools)
- [Security](#security)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)

---

## Overview

This MCP server provides three core tools for Azure-to-Terraform migration:

1. **assess** - Azure subscription/resource group assessment and compliance reporting
2. **export** - Export Azure resources to Terraform code using aztfexport
3. **refactor** - Refactor Terraform code with Azure naming standards and best practices

The server supports both **stdio** (recommended for Claude Desktop) and **HTTP/SSE** (for MCP Inspector) transports.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    MCP Server (index.js)                        │
├─────────────────────────────────────────────────────────────────┤
│  Transport Layer:                                               │
│  ├─ StdioServerTransport (Primary - Claude Desktop)            │
│  └─ SSEServerTransport (Secondary - MCP Inspector)             │
├─────────────────────────────────────────────────────────────────┤
│  Tools:                                                         │
│  ├─ assessment.js    → PowerShell scripts                      │
│  ├─ aztfexport.js    → aztfexport CLI + PowerShell             │
│  └─ code-refactor.js → Python refactoring engine               │
├─────────────────────────────────────────────────────────────────┤
│  Infrastructure:                                                │
│  ├─ Job Management (async tracking)                            │
│  ├─ Progress Streaming (real-time updates)                     │
│  ├─ Azure Blob Storage (report uploads)                        │
│  ├─ GitHub Integration (code versioning)                       │
│  └─ Structured Logging (JSON + correlation IDs)                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Features

### Core Capabilities
- ✅ **Dual Transport Support**: stdio (primary) and HTTP/SSE (debugging)
- ✅ **Long-Running Operations**: Async job execution with timeout=0
- ✅ **Real-Time Progress**: Streaming updates via SSE or polling
- ✅ **Structured Logging**: JSON format with correlation ID tracking
- ✅ **Security Hardened**: Input validation, sanitization, secret detection
- ✅ **Blob Storage Integration**: Upload reports to Azure Storage
- ✅ **GitHub Integration**: Push refactored code to repositories
- ✅ **Container Ready**: Dockerfile for Azure Container Apps deployment

### Advanced Features
- Automatic job cleanup (24-hour retention)
- Managed Identity support for Azure authentication
- Multi-resource group export in single operation
- PowerShell + Python script orchestration
- Comprehensive error handling and diagnostics

---

## Prerequisites

### Required

| Component | Version | Purpose |
|-----------|---------|---------|
| **Node.js** | 18.x+ | Runtime environment |
| **Azure CLI** | 2.50+ | Azure authentication |
| **PowerShell** | 7.3+ | Assessment & export scripts |
| **Python** | 3.10+ | Code refactoring |
| **aztfexport** | 0.13+ | Terraform export tool |

### Optional
| Component | Purpose |
|-----------|---------|
| **Azure Storage Account** | Report uploads |
| **GitHub PAT** | Code versioning |
| **Docker** | Containerization |

---

## Installation

### 1. Clone Repository
```bash
git clone <repository-url>
cd apps-mcp-server
```

### 2. Install Dependencies
```bash
npm install
```

### 3. Install Azure CLI & Login
```bash
# Windows
winget install Microsoft.AzureCLI

# Mac
brew install azure-cli

# Login
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 4. Install PowerShell (if needed)
```bash
# Windows: Built-in
# Mac/Linux
brew install powershell/tap/powershell
```

### 5. Install Python Dependencies
```bash
cd python
pip install -r requirements.txt
cd ..
```

### 6. Install aztfexport
```bash
# Windows (PowerShell)
Invoke-WebRequest -Uri "https://github.com/Azure/aztfexport/releases/latest/download/aztfexport_windows_amd64.zip" -OutFile aztfexport.zip
Expand-Archive aztfexport.zip -DestinationPath ./ps
Remove-Item aztfexport.zip

# Mac
brew install aztfexport

# Linux
wget https://github.com/Azure/aztfexport/releases/latest/download/aztfexport_linux_amd64.tar.gz
tar -xzf aztfexport_linux_amd64.tar.gz -C ./ps
```

---

## Configuration

### Environment Variables (.env)

```bash
# Server Configuration
PORT=3000
LOG_LEVEL=info
LOG_FORMAT=json
ENABLE_CORRELATION_ID=true

# Azure Configuration (Optional - uses Managed Identity by default)
# AZURE_SUBSCRIPTION_ID=your-subscription-id
# AZURE_TENANT_ID=your-tenant-id

# Azure Storage Account (Optional)
storageAccountRG=rg-mcp-servers
storageAccount=samcpstorage

# GitHub Configuration (Optional)
GITHUB_TOKEN=ghp_your_token_here
GITHUB_OWNER=your-org
GITHUB_REPO=refactored-terraform
GITHUB_BRANCH=main

# Output Destination
OUTPUT_DESTINATION=both  # Options: azure, github, both

# Script Paths
POWERSHELL_SCRIPT_PATH=./ps/assessment-AzSubscription.ps1
EXPORT_SCRIPT_PATH=./ps/Export-AzToTerraform.ps1
REFACTOR_SCRIPT_PATH=./python/refactor.py
```

### Security Configuration

The server implements multiple security layers per spec:

```javascript
// Input Validation
validateInput(subscriptionId, { 
  required: true, 
  pattern: /^[a-f0-9-]{36}$/ 
});

// Script Parameter Sanitization
const safe = sanitizeScriptParams(userInput);
// Removes: ; & | ` $ ( ) { } [ ] < >

// Secret Detection
blockHardcodedSecrets(codeContent);
// Detects: API keys, tokens, base64 secrets
```

---

## Running Locally

### Option 1: Stdio Mode (Recommended - Claude Desktop)

**1. Configure Claude Desktop**

File location: `%APPDATA%\Claude\claude_desktop_config.json` (Windows) or `~/Library/Application Support/Claude/claude_desktop_config.json` (Mac)

```json
{
  "mcpServers": {
    "azure-terraform": {
      "command": "node",
      "args": [
        "C:\\path\\to\\apps-mcp-server\\index.js",
        "--stdio"
      ],
      "env": {
        "GITHUB_TOKEN": "ghp_your_token_here"
      }
    }
  }
}
```

**2. Restart Claude Desktop**

Tools should appear in the tools panel.

**3. Test Tools**
```
Please assess Azure subscription abc123...
Export resource group rg-prod from subscription abc123...
Refactor the Terraform code in ./terraform/exports
```

---

### Option 2: HTTP Mode (MCP Inspector)

**1. Start Server**
```bash
# Using run script
./mcpserver-run.ps1

# Or directly
node index.js
```

**2. Open MCP Inspector**
```bash
# In browser
https://inspector.modelcontextprotocol.io/

# Or local proxy
npx @modelcontextprotocol/inspector node index.js --stdio
```

**3. Connect**
- URL: `http://localhost:3000/sse`
- Click "Connect"

**⚠️ Known Issue:** HTTP/SSE mode has connection persistence issues with current MCP SDK. Stdio mode is recommended.

---

## Tools

### 1. assess - Azure Subscription Assessment

**Description:** Analyzes Azure subscription/resource group for Terraform migration readiness.

**Parameters:**
```typescript
{
  subscriptionId: string;  // Required: Azure subscription GUID
  resourceGroup?: string;  // Optional: Specific resource group
}
```

**Example:**
```typescript
await mcpClient.callTool("assess", {
  subscriptionId: "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
  resourceGroup: "rg-production"
});
```

**Output:**
- HTML assessment report with compliance status
- Resource inventory
- Migration recommendations
- Blob Storage URL (if configured)

---

### 2. export - Export to Terraform

**Description:** Exports Azure resource groups to Terraform code using aztfexport.

**Parameters:**
```typescript
{
  subscriptionId: string;      // Required: Azure subscription GUID
  resourceGroups: string[];    // Required: Array of resource group names
  outputDirectory: string;     // Required: Local output path
}
```

**Example:**
```typescript
await mcpClient.callTool("export", {
  subscriptionId: "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
  resourceGroups: ["rg-prod", "rg-dev"],
  outputDirectory: "./terraform/exports"
});
```

**Output:**
- Terraform .tf files
- terraform.tfvars
- Provider configuration
- Resource dependencies

---

### 3. refactor - Refactor Terraform Code

**Description:** Refactors Terraform code with Azure naming standards and best practices.

**Parameters:**
```typescript
{
  terraformDirectory: string;  // Required: Path to Terraform files
  namingPrefix?: string;       // Optional: Naming convention prefix
  outputDirectory?: string;    // Optional: Custom output path
}
```

**Example:**
```typescript
await mcpClient.callTool("refactor", {
  terraformDirectory: "./terraform/exports",
  namingPrefix: "az-prod",
  outputDirectory: "./terraform/refactored"
});
```

**Output:**
- Refactored .tf files with:
  - Standardized resource names
  - Azure naming conventions
  - Best practice configurations
  - Module structure (if applicable)
- GitHub PR (if configured)
- Blob Storage upload (if configured)

---

## Security

### Input Validation

All tool inputs are validated per spec:

```javascript
// Subscription ID validation
validateInput(subscriptionId, {
  required: true,
  pattern: /^[a-f0-9-]{36}$/,
  maxLength: 36
});

// Resource group validation
validateInput(resourceGroup, {
  pattern: /^[a-zA-Z0-9-_()]+$/,
  maxLength: 90
});

// Path validation
validateInput(outputDirectory, {
  required: true,
  pattern: /^[a-zA-Z0-9-_./\\]+$/
});
```

### Script Sanitization

PowerShell and Python parameters are sanitized:

```javascript
// Remove shell injection characters
const sanitized = sanitizeScriptParams({
  subscriptionId: userInput,
  resourceGroup: userInput
});
// Strips: ; & | ` $ ( ) { } [ ] < >
```

### Secret Detection

Blocks hardcoded secrets in code:

```javascript
// Detects common secret patterns
blockHardcodedSecrets(terraformCode);
// Patterns: sk-..., ghp_..., base64==
```

### Managed Identity

Supports Azure Managed Identity for authentication:

```javascript
import { DefaultAzureCredential } from '@azure/identity';
const credential = new DefaultAzureCredential();
```

---

## Deployment

### Azure Container Apps

**1. Build Docker Image**
```bash
docker build -t azurecr.io/mcp/aztf-migration:latest .
```

**2. Push to ACR**
```bash
az acr login --name azurecr
docker push azurecr.io/mcp/aztf-migration:latest
```

**3. Deploy Container App**
```bash
az containerapp create \
  --name aztf-mcp-server \
  --resource-group rg-mcp \
  --image azurecr.io/mcp/aztf-migration:latest \
  --target-port 3000 \
  --ingress external \
  --cpu 1.0 \
  --memory 2.0Gi \
  --env-vars \
    PORT=3000 \
    storageAccount=secretref:storageAccount \
    GITHUB_TOKEN=secretref:githubToken
```

**4. Configure Secrets**
```bash
az containerapp secret set \
  --name aztf-mcp-server \
  --resource-group rg-mcp \
  --secrets \
    storageAccount=samcpstorage \
    githubToken=ghp_...
```

### Environment-Specific Settings

| Environment | Port | Timeout | Logging |
|-------------|------|---------|---------|
| **Development** | 3000 | 0 | debug |
| **Staging** | 3000 | 0 | info |
| **Production** | 3000 | 0 | warn |

---

## Troubleshooting

### Issue: Tools Not Appearing in Claude Desktop

**Solution:**
1. Check Claude Desktop logs: `%APPDATA%\Claude\logs\`
2. Verify absolute paths in config
3. Ensure Node.js is in PATH
4. Restart Claude Desktop after config changes

---

### Issue: HTTP 400 / Connection Closed (MCP Inspector)

**Root Cause:** MCP SDK SSE implementation issue

**Solution:**
Use stdio mode instead:
```bash
npx @modelcontextprotocol/inspector node index.js --stdio
```

---

### Issue: Azure Authentication Error

**Solution:**
```bash
# Re-authenticate
az login
az account show

# Check subscription access
az account list --output table
```

---

### Issue: Blob Storage Disabled

**Error:** `storageAccount env var missing`

**Solution:**
1. Set `storageAccount=your-account-name` in `.env`
2. Ensure Managed Identity has `Storage Blob Data Contributor` role
3. Or provide `AZURE_STORAGE_CONNECTION_STRING`

---

### Issue: Export Tool Fails

**Solution:**
1. Verify aztfexport is in PATH: `aztfexport version`
2. Check Azure CLI authentication: `az account show`
3. Ensure resource groups exist
4. Check PowerShell execution policy:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```

---

## API Reference

### REST Endpoints (HTTP Mode)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Health check + server info |
| `/sse` | GET | SSE connection for MCP |
| `/messages` | POST | JSON-RPC message handling |
| `/jobs` | GET | List all jobs |
| `/jobs/:id` | GET | Get job status |
| `/jobs/:id/progress` | GET | SSE progress stream |
| `/reports` | GET | Static report files |

### Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-Correlation-ID` | No | Request tracking ID (auto-generated if missing) |
| `Content-Type` | Yes | `application/json` |

### Correlation ID

All requests include correlation ID for tracing:

```javascript
// Request
POST /messages
X-Correlation-ID: 123e4567-e89b-12d3-a456-426614174000

// Response
X-Correlation-ID: 123e4567-e89b-12d3-a456-426614174000

// Logs
{"timestamp":"2026-02-04T10:00:00.000Z","level":"info","message":"POST message received","correlationId":"123e4567-e89b-12d3-a456-426614174000"}
```

---

## Logging

### Structured JSON Logging

All logs are JSON-formatted with correlation IDs:

```json
{
  "timestamp": "2026-02-04T10:00:00.000Z",
  "level": "info",
  "message": "MCP Server started successfully",
  "correlationId": "system",
  "mode": "http",
  "port": 3000,
  "version": "1.0.0",
  "tools": ["assess", "export", "refactor"]
}
```

### Log Levels

| Level | Purpose | Example |
|-------|---------|---------|
| **debug** | Detailed diagnostics | Function entry/exit |
| **info** | General information | Server started, tool called |
| **warn** | Non-critical issues | Blob storage disabled |
| **error** | Errors requiring attention | Tool execution failed |

### Configuration

```bash
# .env
LOG_LEVEL=info          # debug, info, warn, error
LOG_FORMAT=json         # json or text
ENABLE_CORRELATION_ID=true
```

---

## Performance

### Specifications

| Metric | Value |
|--------|-------|
| **Max Request Size** | 50 MB |
| **Socket Timeout** | 0 (disabled) |
| **Keep-Alive Timeout** | 0 (disabled) |
| **Job Retention** | 24 hours |
| **Concurrent Jobs** | Unlimited (memory-bound) |
| **Assessment Time** | 2-10 minutes |
| **Export Time** | 5-30 minutes (per RG) |
| **Refactor Time** | 1-5 minutes |

---

## Compliance

### Requirements Met

✅ **Server Config**
- Port: 3000 (default)
- Timeout: 0
- KeepAliveTimeout: 0
- Streaming: Enabled

✅ **Logging**
- Format: JSON
- Correlation ID: Enabled
- Structured: Yes

✅ **Security**
- Input validation: ✅
- Script sanitization: ✅
- Secret detection: ✅
- Managed Identity: ✅

✅ **Tools**
- Assessment: PowerShell + long-running ✅
- Export: PowerShell + long-running ✅
- Refactor: Python ✅

✅ **Deployment**
- Container: Dockerfile ✅
- Azure Container Apps: Ready ✅
- Environment: Configurable ✅

---

## Support

### Resources
- MCP Protocol: https://modelcontextprotocol.io
- MCP SDK: https://github.com/modelcontextprotocol/sdk
- Azure CLI: https://learn.microsoft.com/cli/azure/
- aztfexport: https://github.com/Azure/aztfexport

### Common Questions

**Q: Why stdio over HTTP?**  
A: Stdio transport is more reliable with current MCP SDK. HTTP/SSE has connection persistence issues.

**Q: Can I use this without Azure Storage?**  
A: Yes, reports save locally to `./ps/report` directory.

**Q: How do I scale this?**  
A: Deploy to Azure Container Apps with horizontal scaling enabled. Consider Redis for job storage in multi-instance scenarios.

**Q: Is this production-ready?**  
A: Yes, with stdio mode. HTTP mode recommended for debugging only until SDK issues resolved.

---

## License

[Your License Here]

## Contributors

[Your Team Here]

---

**Last Updated:** February 4, 2026  
**Version:** 1.0.0
