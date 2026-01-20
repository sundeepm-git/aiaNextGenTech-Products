#### MCP Server Implementation (Remote/Local Integration)

##### Why this approach
The New Foundry agent service can connect to remote MCP servers and let agents invoke tools exposed by those servers, with approval workflows and multiple authentication modes. You point Foundry to your local/self-hosted MCP endpoint, enable your custom tool, paste its schemas, and call it from the agent. Save after edits in Agents/Workflows (Foundry does not auto-save).

Auth options for MCP tools: key-based, Agent Managed Identity, Project Managed Identity, or OAuth passthrough (pick per RBAC model).
  - All downstream references use the full output variable and dot notation to access subfields.

---

Below is the **minimum** code to host a **local MCP server** that exposes a single tool named **`execute_powershell_assessment`**, calls your PowerShell script, and returns the required JSON with `.xlsx` and `.pdf` artifact paths.

You’ll create **two files** (plus your existing PowerShell script):

*   `package.json`
*   `server.js`
*   *(Your script)* `./scripts/run-assessment.ps1` (already written by you)

***

## 1) `package.json`

```json
{
  "name": "mcp-assessment-minimal",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.19.2"
  }
}
```

***

## 2) `server.js` (minimal MCP server)

```js
import express from "express";
import { spawn } from "child_process";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(express.json({ limit: "1mb" }));

// ---- MCP discovery: what tools we expose ----
app.get("/.well-known/mcp", (req, res) => {
  res.json({
    tools: [
      {
        name: "execute_powershell_assessment",
        inputSchema: {
          type: "object",
          required: ["subscriptionId", "resourceGroups", "outPath"],
          properties: {
            subscriptionId: { type: "string" },
            resourceGroups: {
              type: "array",
              items: { type: "string" },
              minItems: 1
            },
            outPath: { type: "string" }
          },
          additionalProperties: false
        },
        outputSchema: {
          type: "object",
          required: ["status", "artifacts"],
          properties: {
            status: { type: "string", enum: ["completed", "failed"] },
            subscriptionId: { type: "string" },
            outPath: { type: "string" },
            artifacts: {
              type: "object",
              required: ["xlsx", "pdf"],
              properties: {
                xlsx: { type: "string" },
                pdf: { type: "string" }
              },
              additionalProperties: false
            },
            message: { type: "string" }
          },
          additionalProperties: false
        }
      }
    ]
  });
});

// ---- MCP tool invocation ----
app.post("/tools/execute_powershell_assessment", (req, res) => {
  const body = req.body || {};
  const subscriptionId = (body.subscriptionId || "").trim();
  const resourceGroups = Array.isArray(body.resourceGroups) ? body.resourceGroups : [];
  const outPath = (body.outPath || "/assessment").trim();

  if (!subscriptionId || resourceGroups.length === 0) {
    return res.status(400).json({
      status: "failed",
      message: "subscriptionId (string) and resourceGroups (non-empty array) are required"
    });
  }

  // Build PowerShell call:
  //   ./scripts/run-assessment.ps1 -SubscriptionId <id> -ResourceGroups <rg1,rg2> -OutPath <dir>
  const scriptPath = path.resolve(__dirname, "scripts", "run-assessment.ps1");
  const rgCsv = resourceGroups.join(",");

  const ps = spawn("pwsh", [
    "-NoLogo",
    "-NonInteractive",
    "-File", scriptPath,
    "-SubscriptionId", subscriptionId,
    "-ResourceGroups", rgCsv,
    "-OutPath", outPath
  ], { stdio: ["ignore", "pipe", "pipe"] });

  let stderr = "";
  ps.stderr.on("data", d => { stderr += String(d); });

  ps.on("close", (code) => {
    if (code !== 0) {
      return res.json({
        status: "failed",
        message: (stderr || "Assessment failed").slice(0, 1000)
      });
    }
    // Return artifact paths expected by your Foundry agent/workflow
    return res.json({
      status: "completed",
      subscriptionId,
      outPath,
      artifacts: {
        xlsx: `${outPath}/AzTfExport_Managed_RG_Report.xlsx`,
        pdf:  `${outPath}/AzTfExport_Managed_RG_Report.pdf`
      }
    });
  });
});

// Basic liveness
app.get("/healthz", (_req, res) => res.json({ status: "ok" }));

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`MCP server listening on http://localhost:${PORT}`);
});
```

> **That’s it.** This is the smallest workable server:
>
> *   **`GET /.well-known/mcp`** advertises one tool with your **exact schemas**.
> *   **`POST /tools/execute_powershell_assessment`** runs PowerShell and returns the **required JSON**.

***

## 3) Your PowerShell script location

Place your existing script here:

    ./scripts/run-assessment.ps1

**It must accept**:

    -SubscriptionId <guid> -ResourceGroups <commaSeparated> -OutPath <folder>

…and **write both**:

    <OutPath>/AzTfExport_Managed_RG_Report.xlsx
    <OutPath>/AzTfExport_Managed_RG_Report.pdf

***

## 4) Run locally

```bash
# from the mcp-assessment-minimal folder:
#### 2) Prerequisites on your MCP host
  - PowerShell 7+ (pwsh)
# server -> http://localhost:8080/assessment-ps/mcp
```

Quick test (optional):

```bash
curl -s http://localhost:8080/.well-known/mcp | jq
curl -s -X POST http://localhost:8080/tools/execute_powershell_assessment \
  -H "Content-Type: application/json" \
  -d '{"subscriptionId":"00000000-0000-0000-0000-000000000123","resourceGroups":["rg-app-dev","rg-data-dev"],"outPath":"/assessment"}' | jq
```

You should receive a `completed` JSON with the two artifact paths—or a `failed` message if the script errored.

***

## 5) Connect it to Microsoft Foundry (agent → Custom MCP tool)

1.  **Build → Agents →** open your agent (e.g., `infraAzTfAssessmentAgent‑v1`)
2.  **Tools → Add tool → Custom → Add Model Context Protocol tool**
    *   **Name:** `assessment_ps_runner`
    *   **Remote MCP Server endpoint:** `http://localhost:8080/assessment-ps/mcp` *(use HTTPS if exposing beyond local)*
    *   **Authentication:**
        *   For local dev, use **Key-based** and add something like `x-dev-key : my-local-key` (and optionally check it in your server).
        *   For prod, prefer **Agent/Project Managed Identity** and secure your endpoint.
3.  **Connect** → Foundry lists tools → enable **`execute_powershell_assessment`**
4.  Paste the **same Input/Output schemas** (from above) → **Save**
5.  In your agent **Instructions**, tell it to call:
    ```json
    {
      "subscriptionId": "<id>",
      "resourceGroups": ["<rg1>","<rg2>"],
      "outPath": "/assessment"
    }
    ```
6.  Test in the agent playground, then add the agent to a **Sequential** workflow.

***

### Want a minimal **Python** version instead of Node?

Say **“Python minimal MCP server”** and I’ll give you the equivalent `FastAPI` server in ~60 lines.
  - Az PowerShell modules, ImportExcel, wkhtmltopdf (for PDF)
  - ./run-assessment.ps1
  - ./ManagedResourcePolicy.json

#### 3) Implement the MCP server (minimal skeleton)
Expose a tool named execute_powershell_assessment with your Input/Output JSON Schemas, execute pwsh, and return JSON.

**Node.js (Express-like pseudo-server):**
```js
// server.js (illustrative pseudo-code)
import express from "express";
import bodyParser from "body-parser";
import { spawn } from "child_process";
const app = express();
app.use(bodyParser.json());
app.get("/.well-known/mcp", (_req, res) => {
  res.json({
    tools: [{
      name: "execute_powershell_assessment",
      inputSchema: { ... },
      outputSchema: { ... }
    }]
  });
});
app.post("/tools/execute_powershell_assessment", async (req, res) => {
  // Validate, run pwsh, return JSON as in previous example
});
app.listen(8080);
```

**Python (FastAPI-like pseudo-server):**
```python
# server.py (illustrative pseudo-code)
from fastapi import FastAPI
from pydantic import BaseModel
import subprocess
app = FastAPI()
class ExecInput(BaseModel):
    subscriptionId: str
    resourceGroups: list[str]
    outPath: str | None = "/assessment"
@app.get("/.well-known/mcp")
def capabilities():
    return { ... }  # Advertise tool and schemas
@app.post("/tools/execute_powershell_assessment")
def run_tool(inp: ExecInput):
    # Validate, run pwsh, return JSON as in previous example
```

The exact MCP protocol surface (well-known path, handshake) depends on your chosen SDK; see Microsoft’s MCP + Foundry guidance and community samples for concrete server templates and tool registration helpers.

#### 4) (Optional) Add auth to your MCP server
Pick one model to authenticate Foundry → your MCP server:

#### 5) Connect your local server in Foundry → Agent → Add tool → Custom
In your agent (infraAzTfAssessmentAgent-v1):
  - Name: assessment_ps_runner
  - Remote MCP Server endpoint: https://<YOUR_HOST>:8080
  - Authentication: Key-based (add headers) or Agent/Project Managed Identity

#### 6) Update the agent’s Instructions to call the tool
Add this block to the agent:
Call the MCP tool "execute_powershell_assessment" with:
{
  "subscriptionId": "<subscriptionId>",
  "resourceGroups": ["<rg1>", "<rg2>", ...],
  "outPath": "<outPath>"
}
Wait for the tool result and return JSON only with:
{
  "status":"AssessmentInitiated",
  "subscriptionId":"<subscriptionId>",
  "outPath":"<outPath>",
  "artifacts":{"xlsx":"<path>","pdf":"<path>"}
}
If the tool fails, return {"status":"failed","message":"<brief>"} only.

#### 7) Test the agent, then add to a Workflow
Agent test: Use the agent playground → provide subscriptionId, resourceGroups[], optional outPath → run. Approve the tool call if prompted. Should return JSON with .xlsx + .pdf. (If RBAC errors, grant Reader to the identity in Azure.)
Workflow: Build → Workflows → Create → Sequential → Save. Add:

---

### Node 1 — MigrationOrchestrator-Agent (Input Extraction & Routing)
**Purpose:**
Extracts and validates user migration requirements from a natural language prompt or structured input. Parses subscription, resource group(s), and output path, then sets these as workflow variables for downstream nodes.

**Details:**
- Receives user input (NLP or form-based)
- Extracts: subscriptionId, resourceGroups[], outPath
- Validates required fields and formats
- Saves output as `Local.orchestratorOutput` for use by subsequent nodes
- Example output:
  ```json
  {
    "subscriptionId": "<sub-guid>",
    "resourceGroups": ["rg-app-dev", "rg-data-dev"],
    "outPath": "/assessment"
  }
  ```

---

### Node 2 — Assessment Agent (infraAzTfAssessmentAgent-v1, MCP-Connected)
**Purpose:**
Performs a managed-only Azure resource assessment for the specified subscription and resource groups, using a remote/local MCP server. Generates .xlsx and .pdf reports for downstream processing.

**Details:**
- Receives variables from Node 1: `subscriptionId`, `resourceGroups`, `outPath`
- Calls the MCP tool `execute_powershell_assessment` (see implementation below)
- Waits for tool completion and returns JSON with artifact paths
- Saves output as `Local.assessmentOutput` for downstream use
- Example output:
  ```json
  {
    "status": "completed",
    "subscriptionId": "<sub-guid>",
    "outPath": "/assessment",
    "artifacts": {
      "xlsx": "/assessment/AzTfExport_Managed_RG_Report.xlsx",
      "pdf": "/assessment/AzTfExport_Managed_RG_Report.pdf"
    }
  }
  ```
- Downstream nodes (export, refactor, etc.) reference these artifact paths

---

Click Run Workflow. (Designer creation/saving/running per New Foundry docs.)

#### 8) Troubleshooting

#### 9) (Optional) Publish the agent for your UI
Publish the agent to get an OpenAI-compatible Responses API for your UI to call (POST /responses), governed by RBAC.


---

### 1.3 Node 3 — **aztF Export Node (AztfExportPS-Tool)**
**Add**: **+ Add Node → Tool** → select **AztfExportPS-Tool**.  
**Purpose**: Exports Azure resources to Terraform HCL and local tfstate using aztfexport.

---

### 1.4 Node 4 — **Code Refactor Node (TerraformRefactor-Agent)**
**Add**: **+ Add Node → Agent** → select **TerraformRefactor-Agent**.  
**Purpose**: Refactors exported Terraform code using naming standards and tagging rules.

---

### 1.5 Node 5 — **GitHub Pipeline Update (GitOps-Tool & PipelineGenerator-Tool)**
**Add**: **+ Add Node → Tool** → select **GitOps-Tool** and **PipelineGenerator-Tool**.  
**Purpose**: Commits refactored code, opens PR in GitHub, and writes subscription-level GitHub workflow for CI/CD.

---

### 1.6 Optional — **ReviewAssistant-Agent** (advice)
You can insert **ReviewAssistant-Agent** before/after PR creation to auto‑summarize the diff or suggest fixes. citeturn8search3

---

### 1.7 Save & Run
1) Click **Save** (required; no auto‑save). citeturn8search3  
2) Click **Run Workflow**. Interact via chat and provide an NLP instruction, e.g.:  
  _“Export RG `rg-app-dev` from subscription `0000-...-0000`, apply naming profile JSON `std-v2`, and open a PR.”_  
3) The workflow executes sequentially; you can add human‑in‑the‑loop approvals if needed. citeturn8search3turn8search5

---

## 5) Inputs & Outputs (Workflow Contract)
**Inputs** (from Agent to Workflow): `subscriptionId`, `tenantId`, `scope` (subscription|resourceGroup), `resourceGroups` (list), `namingStandardJson`, `repoUrl`, `branch`, `approvers`.  
**Outputs**: `/assessment/assessment.json`, `/export/` (HCL + local `.tfstate`), `/refactored/` (HCL, `refactor_report.md`, `naming-standard.json`), PR URL, pipeline YAML path.

---

## 6) Local State Policy (Initial Phase)
- Keep Terraform state **local** at export time:
  ```
  /run/artifacts/export/<timestamp>/terraform.tfstate
  ```
- **No backend block** is added during refactor; remote backend migration is deferred.

---

## 7) Custom JSON Naming Standard (Input to Refactor)
Example `naming-standard.json`:
```json
{
  "globalPrefix": "hca",
  "environmentCodes": {"Development": "dev", "Test": "tst", "Production": "prd"},
  "resourceAbbreviations": {"virtualNetwork": "vnet", "subnet": "snet", "networkSecurityGroup": "nsg", "publicIp": "pip", "storageAccount": "st"},
  "nameTemplates": {"virtualNetwork": "{prefix}-{app}-{env}-vnet-{seq}", "subnet": "{prefix}-{app}-{env}-snet-{seq}"},
  "requiredTags": {"owner": "required", "businessUnit": "required", "env": "inherit", "dataClassification": "default:internal"}
}
```

---

## 8) Refactor Agent — Prompt & Report
**System prompt (excerpt)**
```
You are a senior Terraform engineer. Transform exported Azure HCL using the provided naming-standard.json.
- Do NOT add a remote backend. Preserve local state.
- Enforce tags {owner, businessUnit, env, dataClassification}.
- Prefer approved modules; keep identities stable; generate refactor_report.md with decisions & follow-ups.
```
**Report sample**
```
# Terraform Refactor Report
Generated: <timestamp>
- azurerm_virtual_network.vnet1 → module.network["hca-app-dev-vnet-01"]
- azurerm_subnet.s1 → module.network["hca-app-dev-snet-01"]
Tags enforced: owner, businessUnit; env inherited: dev
Backend: local state preserved
Manual: 2 resources need module mapping decisions
```

---

## 9) PowerShell Tools (Execution Contracts)
- **Assessment**: `./scripts/run-assessment.ps1 -SubscriptionId <id> -TenantId <id> -OutPath <folder>` → emits `assessment.json`. citeturn8search3  
- **Export (aztfexport)**:  
  - Subscription: `./scripts/run-aztfexport.ps1 -SubscriptionId <id> -TenantId <id> -OutPath <folder>`  
  - RG subset: `./scripts/run-aztfexport.ps1 -SubscriptionId <id> -TenantId <id> -ResourceGroups <rg1,rg2> -OutPath <folder>`  
  → emits `export/` with HCL + local `.tfstate`. citeturn8search3

---

## 10) Publish Agent as API (for UI NLP)
- In Foundry, **Publish Agent** to obtain **API endpoints**.  
- **Responses API (OpenAI‑compatible)** for UI calls:  
  `https://{account}.services.ai.azure.com/api/projects/{project}/applications/{app}/protocols/openai`  
  Only **POST `/responses`** is available; client stores conversation as needed.  
  Caller requires **Azure RBAC** permission `/applications/invoke/action` (Azure AI User role). citeturn8search8  
- This matches the new Agent Service statement: **deployable agents can be exposed as endpoints**. citeturn8search4

---

## 11) UI Integration (NLP → Workflow)
**UI → Agent (Responses API) example request**
```http
POST /responses
Content-Type: application/json
{
  "input": [
    {"role": "user", "content": "Migrate subscription 0000, export RG rg-app-dev, use naming profile std-v2."}
  ]
}
```
Agent parses NLP → emits structured params → workflow runs nodes sequentially.  
Workflows support agent nodes, variables, and conditional logic. citeturn8search3turn8search5

---

## 12) GitHub Pipeline (Subscription‑wise, RG parameter)
```yaml
name: Terraform (${SUBSCRIPTION})

on:
  workflow_dispatch:
    inputs:
      resource_group:
        description: "Target Resource Group"
        required: true
        type: string
      action:
        description: "plan or apply"
        required: true
        default: plan
        type: choice
        options: [plan, apply]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - name: Init + Workspace
        run: |
          terraform -chdir=infra init
          terraform -chdir=infra workspace select ${{ github.event.inputs.resource_group }} || terraform -chdir=infra workspace new ${{ github.event.inputs.resource_group }}
      - name: Plan or Apply
        run: |
          if [ "${{ github.event.inputs.action }}" = "apply" ]; then
            terraform -chdir=infra apply -auto-approve
          else
            terraform -chdir=infra plan
          fi
```

---

## 13) Security & Ops
- **Identity**: Prefer Managed Identity for workflow runtime; secrets in **Key Vault**.  
- **RBAC**: Reader (assess/export); Contributor (repo/pipelines); **Azure AI User** to invoke published agent. citeturn8search8  
- **Script Security**: Sign PowerShell; `AllSigned`.  
- **Observability**: JSONL logs to Log Analytics; Teams notifications on failed runs.  

---

## 14) Operational Runbook
1. **UI prompt** → user enters NLP instruction.  
2. **MigrationOrchestrator-Agent** parses → sets `Local.*` variables.  
3. **AssessmentPS-Tool** & **AztfExportPS-Tool** run sequentially, produce artifacts.  
4. **TerraformRefactor-Agent** applies naming JSON; emits `/refactored` + `refactor_report.md`.  
5. **GitOps-Tool** opens PR; reviewers (or **ReviewAssistant-Agent**, optional) approve.  
6. **PipelineGenerator-Tool** writes subscription YAML.  
7. Trigger GitHub workflow (RG parameter) to plan/apply.

Rollback: revert PR; remove generated workflow file; retain export artifacts for audit.

---

## 15) Future Enhancements
- Remote backend migration (Azure Storage + locking).  
- Drift detection; scheduled re‑export.  
- Cost/size heuristics in assessment; SARIF policy outputs.  

---

*End of Document.*
