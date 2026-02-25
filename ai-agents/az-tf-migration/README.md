---

## 🔑 Agent Workflow, Deployment, and Secret Management (2024 Update)

### Agent Workflow

1. **Assessment Agent**: Scans Azure resources and generates a detailed assessment report (JSON/YAML). Implemented in `assessment.py` and invoked by the Node.js MCP server.
2. **Export Agent**: Converts the assessment output into Terraform code using `Export-Container-AzToTerraform.py` (Python) and PowerShell wrappers. Handles authentication and uploads results to Azure Blob or GitHub.
3. **Refactor Agent**: Optimizes and enforces standards on exported Terraform code using `code-refactor.py` and `tf_refactor_variable.py`.
4. **Deployment**: The orchestrator (Node.js/PowerShell) deploys the generated code to the target environment.

### Python Code Implementation

- `assessment.py`: Performs Azure resource assessment and outputs a report.
- `Export-Container-AzToTerraform.py`: Exports resources to Terraform HCL and tfstate.
- `code-refactor.py`: Refactors Terraform code for best practices and compliance.

All scripts are orchestrated by the Node.js server and PowerShell scripts, with configuration via `.env`.

### Deployment Steps

1. **Prepare Environment**: Ensure Azure CLI, Docker, and required permissions are available. Populate `.env` with all required values (see below).
2. **Run Deployment Script**: Execute `./apps-mcp-server/deploy.ps1` to build, push, and deploy the container app. The script:
  - Builds the Docker image with all agent scripts
  - Pushes the image to Azure Container Registry (ACR)
  - Deploys or updates the Azure Container App
  - Configures environment variables and secrets
3. **Wait for Readiness**: The script waits for the container app to become ready and outputs the public FQDN.
4. **Check Logs**: Use `az containerapp logs show --name <app-name> --resource-group <rg> --follow` to view logs.

### Secret Management

- **Client secrets** (e.g., `AZURE_CLIENT_SECRET`) are securely managed using Azure Container App secrets.
- The deployment script adds the client secret as a secret named `azure-client-secret` using `--secrets` (on create) or `--set-secrets` (on update).
- Environment variables such as `AZURE_CLIENT_SECRET` and `ARM_CLIENT_SECRET` are mapped to `secretref:azure-client-secret`.
- Secrets are never exposed in logs or code. The script ensures all sensitive values are referenced via `secretref`.

**Example (from deploy.ps1):**

```powershell
$envVars += "AZURE_CLIENT_SECRET=secretref:azure-client-secret"
$azArgs += '--secrets'
$azArgs += "azure-client-secret=$ClientSecret"
```

### .env File Example

```
RESOURCE_GROUP=your-rg
ACR_NAME=youracr
CONTAINER_APP_ENV=your-env
CONTAINER_APP_NAME=your-app
LOG_ANALYTICS_WORKSPACE=your-law
SUBSCRIPTION_ID=xxxx-xxxx-xxxx-xxxx
TENANT_ID=xxxx-xxxx-xxxx-xxxx
CLIENT_ID=xxxx-xxxx-xxxx-xxxx
CLIENT_SECRET=your-client-secret
STORAGE_ACCOUNT=yourstorage
STORAGE_CONTAINER=yourcontainer
```

### Troubleshooting

- Ensure all required secrets and environment variables are set in `.env`.
- If you see `SecretRef 'azure-client-secret' not found`, ensure the secret is set at creation or update time (the script handles this automatically).
- Use the provided log commands to debug deployment issues.

---
# 📚 Table of Contents
1. [System Architecture](#1-system-architecture)
2. [Agents & Workflow Details](#2-agents--workflow-details)
3. [Configuration & Output Destinations](#3-configuration--output-destinations)
4. [Installation & Local Setup](#4-installation--local-setup)
5. [Real-Time Progress Streaming](#5-real-time-progress-streaming)
6. [GitHub Integration](#6-github-integration)
7. [Deployment Guide](#7-deployment-guide)
8. [Development & Modularization](#8-development--modularization)
9. [Troubleshooting & Fixes](#9-troubleshooting--fixes)

---

# Azure Terraform Migration & MCP Server

**Version:** 2.0.1  
**Runtime:** Node.js, PowerShell, Python  
**Protocol:** Model Context Protocol (MCP)

This is a production-grade, modular MCP server designed to orchestrate the migration of Azure resources to Terraform. it uses a chain of AI agents and specialized tools to assess, export, and refactor infrastructure code.

This README consolidates all project documentation into a single source of truth.

---

## 1. System Architecture

The system supports dual output destinations (Azure Blob Storage and GitHub) and is configured via the `.env` file. The architecture includes Python, PowerShell, and Node.js entry points.

### System Overview
```
┌─────────────────────────────────────────────────────────────────────┐
│                         .env Configuration File                      │
│  OUTPUT_DESTINATION = "azure" | "github"                            │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    refactor.py (Main Entry Point)                    │
│  • Loads .env                                                       │
│  • Initializes TerraformRefactorEngine                              │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│              TerraformRefactorEngine (tf_refactor_variable.py)      │
│  If OUTPUT_DESTINATION == "azure":                                  │
│    • Use Azure Blob Storage (containers: aztfexport, code-refactored)│
│  If OUTPUT_DESTINATION == "github":                                 │
│    • Use GitHub Repo (folders: aztfexport/, code-refactored/)       │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Stack
*   **MCP Server (Node.js)**: Handles API requests, job management, and SSE streaming.
*   **PowerShell Scripts**: Execute Azure assessment and `aztfexport` logic.
*   **Python Engine**: Performs intelligent code refactoring and GitHub/Azure integration.

---

## 2. Agents & Workflow Details

The solution uses a chain of specialized agents/tools.

### 1. Migration Orchestrator Agent
**Purpose:** Extracts and validates user migration requirements from natural language.
*   **Input**: User prompt (e.g., "Migrate rg-app from sub-123").
*   **Details**: Validates subscription ID format and resource group existence.
*   **Output**:
    ```json
    {
      "subscriptionId": "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2",
      "resourceGroups": ["rg-app-dev", "rg-data-dev"],
      "outPath": "/assessment"
    }
    ```

### 2. Assessment Agent (`infraAzTfAssessmentAgent-v1`)
**Purpose:** Performs managed-only Azure resource assessment.
*   **Details**: Calls `assess_azure_environment` tool. Generates HTML/PDF reports.
*   **Output**: 
    ```json
    {
      "status": "completed",
      "subscriptionId": "<sub-guid>",
      "outPath": "/assessment",
      "artifacts": {
        "xlsx": "https://<storage>.blob.core.windows.net/.../report.xlsx",
        "pdf": "https://<storage>.blob.core.windows.net/.../report.pdf"
      }
    }
    ```

### 3. Export Tool (`AztfExportPS-Tool`)
**Purpose:** Exports Azure resources to Terraform HCL and tfstate.
*   **Details**: Runs `aztfexport` via PowerShell. Handles authentication and temp file management.
*   **Output**: Raw Terraform files (`main.tf`, `provider.tf`, `terraform.tfstate`) uploaded to `aztfexport` container/folder.

### 4. Refactor Agent (`TerraformRefactor-Agent`)
**Purpose:** Refactors exported code using naming standards and tagging rules.
*   **Details**: Runs `refactor.py`.
    *   Do NOT add remote backend (preserve local state).
    *   Enforce tags (owner, businessUnit, etc.).
    *   Apply naming conventions from `naming-standard.json`.
*   **Output**: Refactored `.tf` files in `code-refactored` container/folder.

---

## 3. Configuration & Output Destinations

All configuration is managed through the `.env` file in the root directory.

### Environment Variables (.env)

```bash
# Server Configuration
PORT=8080
LOG_LEVEL=info

# Output Destination Configuration
# Options: "azure" or "github" or "both"
OUTPUT_DESTINATION=both

# Azure Storage Configuration (Required if destination is azure or both)
storageAccountRG=rg-mcp-servers
storageAccount=samcpstorage
# Note: Azure Auth uses CLI login or Managed Identity

# GitHub Configuration (Required if destination is github or both)
GITHUB_TOKEN=ghp_your_token_here
GITHUB_OWNER=your-org
GITHUB_REPO=your-repo
GITHUB_BRANCH=main

# Script Paths
POWERSHELL_SCRIPT_PATH=./ps/assessment-AzSubscription.ps1
EXPORT_SCRIPT_PATH=./ps/Export-AzToTerraform.ps1
REFACTOR_SCRIPT_PATH=./python/refactor.py
```

### Output Folder Names
*   **Assessment Reports**: `assessment-reports/{subscription_id}/`
*   **Export Output**: `aztfexport/{subscription_id}/{rg_name}/`
*   **Refactored Code**: `code-refactored/{subscription_id}/{rg_name}/`

---

## 4. Installation & Local Setup


### Prerequisites
*   **Node.js**: 18+
*   **PowerShell**: 7.x
*   **Azure CLI**: Latest
*   **Python**: 3.8+ with `pip install requests python-dotenv azure-storage-blob azure-identity`
*   **aztfexport**: Installed and in PATH

#### Azure Authentication (Required for Automation/Production)

For all automation, CI/CD, and production scenarios, you **must** use a Service Principal (SPN) for Azure CLI authentication. This ensures secure, non-interactive access.

1. **Create a Service Principal:**
  ```bash
  az ad sp create-for-rbac --name <sp-name> --role Contributor --scopes /subscriptions/<subscription-id>
  ```
  Note the `appId`, `password`, and `tenant` from the output.

2. **Set the following environment variables before running any scripts:**
  ```bash
  export AZURE_CLIENT_ID=<appId>
  export AZURE_CLIENT_SECRET=<password>
  export AZURE_TENANT_ID=<tenant>
  ```
  On Windows (PowerShell):
  ```powershell
  $env:AZURE_CLIENT_ID = "<appId>"
  $env:AZURE_CLIENT_SECRET = "<password>"
  $env:AZURE_TENANT_ID = "<tenant>"
  ```

3. **The script will automatically attempt SPN login if these variables are set.**

4. For local development, you may use `az login` interactively, but using SPN is recommended for consistency.

5. Example SPN login command (for reference):
  ```bash
  az login --service-principal -u <appId> -p <password> --tenant <tenant>
  ```

### Server Modes

#### Mode 1: Stdio (Recommended for Claude/Clients)
Add to your `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "azure-terraform": {
      "command": "node",
      "args": ["C:/path/to/apps-mcp-server/index.js", "--stdio"],
      "env": {
        "storageAccount": "samcpstorage",
        "GITHUB_TOKEN": "your-token"
      }
    }
  }
}
```

#### Mode 2: HTTP/SSE (For Debugging/Inspector)
Start the server:
```bash
cd apps-mcp-server
npm install
npm start
# Server runs on port 8080
```

---

## 5. Real-Time Progress Streaming

The server supports real-time progress streaming for jobs using Server-Sent Events (SSE).

### API Endpoints

#### 1. Start Job
**POST** `/messages`
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "export_azure_to_terraform",
    "arguments": {
      "subscriptionId": "d0f1884d-...",
      "resourceGroup": "rg-mcp-servers"
    }
  }
}
```
**Response**: `Job ID: 550e8400-e29b-...`

#### 2. Stream Progress
**GET** `/jobs/{jobId}/progress`

**Event Types**:
*   `connected`: Connection established.
*   `stdout`: Real-time log output from PowerShell/Python.
*   `stderr`: Error/Warning output.
*   `complete`: Job finished.

### Example Usage (JavaScript)
```javascript
const source = new EventSource('http://localhost:8080/jobs/{id}/progress');
source.onmessage = (e) => {
  const data = JSON.parse(e.data);
  if (data.type === 'stdout') console.log(data.message);
  if (data.type === 'complete') source.close();
};
```

---

## 6. GitHub Integration

The system includes a dedicated Python helper `github_helper.py` and PowerShell module `GitHubHelper.psm1` to handle direct uploads to GitHub.

### Setup
1.  Generate a GitHub Personal Access Token (PAT) with `repo` scope.
2.  Update `.env` with `GITHUB_TOKEN`, `GITHUB_OWNER`, and `GITHUB_REPO`.
3.  Set `OUTPUT_DESTINATION=github` or `both`.

### Security Features
*   **Branch Protection**: Uploads to specified branch.
*   **.gitignore Generation**: The refactor engine automatically creates a `.gitignore` in the target folder to exclude:
    *   `terraform.tfstate`
    *   `main.tf` (if likely to contain secrets)
    *   `.terraform/`
*   **SHA Checking**: Checks existing file SHA before upload to avoid unnecessary commits.

---

## 7. Deployment Guide

### Azure Container Apps Deployment (`deploy.ps1`)

The included `deploy.ps1` script provides end-to-end automation for deploying the MCP server to Azure Container Apps. It handles prerequisites, Docker build, ACR push, and Container App deployment with Managed Identity.

**Usage Syntax:**
```powershell
.\apps-mcp-server\deploy.ps1 -ResourceGroup <name> -Location <region> [options]
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ResourceGroup` | string | `rg-aztf-mcp-prod` | Name of the Azure Resource Group. |
| `Location` | string | `eastus` | Azure region for resources. |
| `AcrName` | string | | Name of the Azure Container Registry. |
| `SubscriptionId` | string | | Azure Subscription ID. |
| `ContainerAppEnv` | string | | Name of the Container App Environment. |
| `ContainerAppName` | string | | Name of the Container App. |
| `LogAnalyticsWorkspace`| string | | Name of the Log Analytics Workspace. |
| `ImageTag` | string | `latest` | Tag for the Docker image. |
| `Port` | int | `8080` | Port for the application. |
| `Cpu` | string | `1.0` | CPU cores allocation. |
| `Memory` | string | `2.0Gi` | Memory allocation. |
| `MinReplicas` | int | `1` | Minimum container replicas. |
| `MaxReplicas` | int | `3` | Maximum container replicas. |
| `LogLevel` | string | `info` | Logging verbosity level. |
| `NodeEnv` | string | `production` | Node.js environment mode. |
| `SkipBuild` | switch | `false` | Skip Docker build step (deploy only). |
| `SkipTests` | switch | `false` | Skip post-deployment verification tests. |

**Script to RUN:**
```powershell
 .\deploy.ps1 -ResourceGroupName "rg-mcp-servers" -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" -TenantId "a0e1f124-d84e-4ef7-bf4b-926b60443fb9" -ClientId "4a7f6b45-8322-4cfe-bd16-008afdcc1221" -StorageAccountName "samcpstorage" -ContainerName "aztfexport" -ContainerAppName "aztf-mcp-app" -LogAnalyticsWorkspace "workspace-rgmcpserversIh7a" -AcrName "aztfmcpacr" -ImageTag "v2.3" -Port 3000 -MinReplicas 0 -MaxReplicas 1 -Cpu 0.25 -Memory "0.5Gi" -NoCache
```

### Update Secret
Go to the container app and update the secret their copy from .env file and update

## Command for MCP Inspector
npx @modelcontextprotocol/inspector

## Command to STOP the port-MCP
netstat -ano | findstr :6274
taskkill /PID 18568 /F

### Local Development Runner (`mcpserver-run.ps1`)

The `mcpserver-run.ps1` script validates prerequisites and starts the MCP server locally for development and testing. It ensures Node.js dependencies, Azure auth, and `.env` configuration are present.

**Usage Syntax:**
```powershell
.\md\mcpserver-run.ps1 [options]
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Port` | int | `8080` | Port number for the server to listen on. |
| `SkipChecks` | switch | `false` | Skip prerequisite validation checks. |
| `ShowDetails` | switch | `false` | Display detailed diagnostic information. |

**Example:**
```powershell
# Run with default checks on port 8080
.\md\mcpserver-run.ps1

# Run with detailed diagnostics
.\md\mcpserver-run.ps1 -ShowDetails

# Skip checks and use custom port
.\md\mcpserver-run.ps1 -Port 3000 -SkipChecks
```

### Manual Permissions (Managed Identity)
The Container App needs **System-Assigned Managed Identity** enabled and assigned the **Storage Blob Data Contributor** role on the target Storage Account.

```bash
az role assignment create \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/.../storageAccounts/samcpstorage
```

---

## 8. Development & Modularization

The codebase has been refactored for maintainability.

### Directory Structure
```
apps-mcp-server/
├── index.js                    # Main server entry & SSE logic
├── tools/                      # Tool definitions
│   ├── assessment.js          # Assessment logic
│   ├── aztfexport.js          # Export logic wrapper
│   └── code-refactor.js       # Refactor logic wrapper
├── ps/                        # PowerShell Scripts
│   ├── assessment-AzSubscription.ps1
│   ├── Export-AzToTerraform.ps1
│   └── GitHubHelper.psm1
├── python/                    # Python Engines
│   ├── refactor.py            # Main refactor entry point
│   ├── tf_refactor_variable.py # Refactoring logic
│   └── github_helper.py       # GitHub API integration
└── package.json
```

---

## 9. Testing with MCP Inspector

The project supports interactive testing using the official [MCP Inspector](https://github.com/modelcontextprotocol/inspector).

### Prerequisites
Node.js installed.
```bash
npx @modelcontextprotocol/inspector --version
```

### 1. Local Testing
To test the server running locally:

**Step 1: Start the Server**
```powershell
# In one terminal
.\md\mcpserver-run.ps1
```

**Step 2: Run Inspector**
```powershell
# In a second terminal
npx @modelcontextprotocol/inspector http://localhost:8080/sse
```

**Step 3: Execute Tools**
*   Open the browser window launched by Inspector.
*   Select `assess_azure_environment`.
*   Input JSON arguments: `{"subscriptionId": "...", "resourceGroup": "..."}`.
*   Click **Run Tool** and look for the returned `Job ID`.

### 2. Container Testing
To test the deployed Azure Container App:

**Step 1: Get Endpoint**
```powershell
$URL = az containerapp show --name aztf-mcp-app --resource-group rg-mcp-servers --query properties.configuration.ingress.fqdn -o tsv
# Endpoint format: https://<URL>/sse
```

**Step 2: Run Inspector**
```powershell
npx @modelcontextprotocol/inspector https://$URL/sse
```
*(Replace `$URL` with the actual variable value or string)*

---

## 10. Troubleshooting & Fixes

### Common Issues

#### 1. "StorageAccount parameter is required" or Upload Fails
*   **Cause**: Environment variables not passed to spawned PowerShell process.
*   **Status**: **FIXED** in v2.0.1.
*   **Fix**: Ensure `tools/aztfexport.js` spawn call includes `env: { ...process.env, storageAccount }`.

#### 2. Invalid JobId Parameter
*   **Cause**: Older version of PowerShell script expected `-JobId`.
*   **Status**: **FIXED**. Script now uses `{SubscriptionId}/{ResourceGroup}` path structure.
*   **Fix**: Ensure `tools/aztfexport.js` does NOT pass `-JobId` to PowerShell.

#### 3. SSE Disconnects
*   **Cause**: MCP SDK or Proxy issues.
*   **Workaround**: Use Stdio mode for production/stable clients. For HTTP, ensure client handles auto-reconnect.

#### 4. GitHub Upload 403/404
*   **Cause**: Token scope or Repo name.
*   **Fix**: Verify PAT has `repo` scope. Check `GITHUB_OWNER` spelling.

### Logs
Check logs via:
```bash
# Azure
az containerapp logs show --name aztf-mcp-app --resource-group rg-mcp-servers --follow

# Local
# Output appears in terminal where node index.js is running
```

### Foundry References 
JSON RESPONSE - https://github.com/microsoft/agent-framework/blob/main/workflow-samples/CustomerSupport.yaml#L29
https://learn.microsoft.com/en-us/power-platform/power-fx/working-with-json
https://github.com/orgs/microsoft-foundry/discussions/218

---
**Maintainer**: Sundeep K Maheshwari  
**License**: MIT

