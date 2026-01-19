
# Azure → Terraform Migration (Agentic AI Workflow) — End‑to‑End Runbook

**File:** `az-tf-migration.md`  
**Owner:** Platform Engineering / Enterprise Architecture  
**Last updated:** 2026-01-19

> This runbook documents a production blueprint for migrating existing Azure resources to Terraform using **Microsoft Foundry (New)** workflow designer, publishable **Agents as APIs**, and a UI that triggers the workflow via **NLP prompts**. It incorporates: local Terraform state (initial phase), custom **JSON naming standards** for refactor, `aztfexport`-based export, subscription‑wise pipeline generation, and a detailed, step‑by‑step configuration guide for the Foundry Workflow nodes.

---

## 0) What’s New & References
- **Foundry (New) Workflow Designer** — build visual, declarative sequences; add agent/tool nodes; support sequential, human‑in‑loop, and group chat patterns. citeturn8search3
- **New Agent Service** — prompt/workflow/container agents; publishable as endpoints; enterprise features; migration path from classic Assistants API. citeturn8search4
- **Multi‑agent orchestration patterns & samples** (group chat, variables, approvals), including how to pass variables and gates. citeturn8search5
- **VS Code (low‑code) authoring** option for Foundry workflows/agents (optional). citeturn8search6
- **Published agent → Responses API (OpenAI‑compatible)** for programmatic UI integration; RBAC via Azure AI User role. citeturn8search8

---

## 1) Objectives & Scope
**Goals**
1. Assess Azure subscription(s).  
2. Export resources with **aztfexport** (subscription → single/multiple RG).  
3. **Refactor** exported HCL to org standards using **custom JSON naming standard**.  
4. Generate **subscription‑wise pipelines** parameterized by Resource Group.  
5. Orchestrate with **Foundry Workflow (New)** and expose an **Agent as an API** for UI‑driven NLP execution.  

**Out of Scope**
- Remote backend enablement (initially **local state only**).  
- App configuration/validation; shared infra provisioning.  

---

## 2) High‑Level Architecture
```mermaid
flowchart LR
  UI[Custom UI (NLP Prompt)] -->|POST /responses| AGENT[MigrationOrchestrator-Agent (Published API)]
  AGENT -->|Parameters| WF[Azure-Terraform-Migration-Workflow]
  subgraph Azure-Terraform-Migration-Workflow
    A[AssessmentPS-Tool]
    E[AztfExportPS-Tool]
    R[TerraformRefactor-Agent\n+ naming-standard.json]
    G[GitOps-Tool (PR)]
    P[PipelineGenerator-Tool]
  end
  WF --> A --> E --> R --> G --> P
  WF --> KV[(Key Vault / Secrets)]
  WF --> ST[(Artifacts & Local tfstate)]
```
**Designer & patterns** from Foundry (New) Workflows blade. citeturn8search3  
**Publishable agents** exposed as endpoints for external UI integration. citeturn8search4turn8search8

---

## 3) Prerequisites
- Azure subscription with **Foundry (New)** access; create/select a project in the portal. citeturn8search3turn8search7  
- Service principals with least privilege (Reader for assess/export; Contributor only for repo/pipeline ops).  
- Signed PowerShell scripts: `run-assessment.ps1`, `run-aztfexport.ps1`.
- GitHub repository connected for PRs and pipelines.

---

## 4) Foundry Workflow — Designer Steps (Sequential Pattern)
This section explains **exact names of agents/tools** and **how to configure** each node **step‑by‑step** in **Microsoft Foundry (New)**. The guidance aligns with the official workflow‑builder docs (create → assign agents → add nodes → save/run). citeturn8search3

### 4.1 Agent & Tool Names (use these exact names)
**Agents (LLM)**
- **MigrationOrchestrator-Agent** — Interprets NLP prompt from UI, extracts parameters for the workflow. (Prompt‑based Agent, **Published**) citeturn8search4  
- **TerraformRefactor-Agent** — Refactors exported HCL using `naming-standard.json`. (Prompt‑based Agent) citeturn8search3  
- *(Optional)* **ReviewAssistant-Agent** — Provides PR advisory comments. (Prompt‑based Agent)

**Tools**
- **AssessmentPS-Tool** — Executes `run-assessment.ps1` to produce `assessment.json`. citeturn8search3  
- **AztfExportPS-Tool** — Executes `run-aztfexport.ps1` to produce HCL + local `.tfstate`. citeturn8search3  
- **GitOps-Tool** — Commits refactored code, opens PR in GitHub. citeturn8search3  
- **PipelineGenerator-Tool** — Writes subscription‑level GitHub workflow (RG parameter). citeturn8search3

---

### 4.2 Create the Workflow (once)
1) In Foundry, go to **Build → Workflows** → **Create → Sequential**. citeturn8search3  
2) Name it: `Azure-Terraform-Migration-Workflow`.  
3) Click **Save** (Workflows **do not** auto‑save). citeturn8search3

---

### 4.3 Node 1 — **MigrationOrchestrator-Agent** (NLP → parameters)
**Add**: **+ Add Node → Agent** → select **MigrationOrchestrator-Agent**. citeturn8search3  
**Prompt** (example):
```
You extract subscriptionId, tenantId, scope (subscription|resourceGroup), resourceGroups (list),
namingJson, repoUrl, and branchName from user natural language input. Output a compact JSON
object with these fields for downstream nodes.
```
**Output variable mappings** (use Local.*):
- `Local.subscriptionId`
- `Local.tenantId`
- `Local.scope`
- `Local.resourceGroups`
- `Local.namingJson`
- `Local.repoUrl`
- `Local.branchName`

*Tip:* Foundry workflows support passing data via variables like `Local.*` and using logic nodes with conditions; this mirrors the variable usage patterns in official samples. citeturn8search5

---

### 4.4 Node 2 — **AssessmentPS-Tool** (PowerShell)
**Add**: **+ Add Node → Tool** → select **AssessmentPS-Tool**. citeturn8search3  
**Inputs**:
- `SubscriptionId = Local.subscriptionId`
- `TenantId = Local.tenantId`
- `OutPath = /assessment`
**Outputs**:
- `Local.assessmentOutput = /assessment/assessment.json`

---

### 4.5 Node 3 — **AztfExportPS-Tool** (PowerShell)
**Add**: **+ Add Node → Tool** → select **AztfExportPS-Tool**. citeturn8search3  
**Inputs**:
- `SubscriptionId = Local.subscriptionId`
- `TenantId = Local.tenantId`
- `ResourceGroups = Local.resourceGroups`
- `OutPath = /export`
**Outputs**:
- `Local.exportOutput = /export` (HCL + **local** `terraform.tfstate`)

---

### 4.6 Node 4 — **TerraformRefactor-Agent** (LLM)
**Add**: **+ Add Node → Agent** → select **TerraformRefactor-Agent**. citeturn8search3  
**Prompt** (summary):
```
Use Local.namingJson and Local.exportOutput to refactor the exported Terraform code.
Apply naming standards, tagging rules, and approved modules. Preserve local tfstate.
Generate refactor_report.md and a compilable structure under /refactored.
```
**Inputs**:
- `exportPath = Local.exportOutput`
- `namingJson = Local.namingJson`
**Outputs**:
- `Local.refactorOutput = /refactored`

---

### 4.7 Node 5 — **GitOps-Tool** (commit + PR)
**Add**: **+ Add Node → Tool** → select **GitOps-Tool**. citeturn8search3  
**Inputs**:
- `Repo = Local.repoUrl`
- `Branch = Local.branchName`
- `CommitPath = Local.refactorOutput`
**Outputs**:
- `Local.prUrl`

---

### 4.8 Node 6 — **PipelineGenerator-Tool** (write CI YAML)
**Add**: **+ Add Node → Tool** → select **PipelineGenerator-Tool**. citeturn8search3  
**Inputs**:
- `subscriptionId = Local.subscriptionId`
- `pipelineType = "github"`
- (optional) `rgParamEnabled = true`
**Outputs**:
- path to generated `.github/workflows/terraform-${subscriptionId}.yml`

---

### 4.9 Optional — **ReviewAssistant-Agent** (advice)
You can insert **ReviewAssistant-Agent** before/after PR creation to auto‑summarize the diff or suggest fixes. citeturn8search3

---

### 4.10 Save & Run
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
