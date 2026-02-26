# Use Case: Auto‑Fix Azure Security Misconfigurations in Real Time

## 1. Create the Azure AI Foundry Project
**Steps:**
- Open Azure AI Foundry
- Create project Name: `fndry-cybersecurity-automation`
- Select:
  - Azure AI Hub
  - Resource Group - `rg-cybersecurity-ai-automation`
  - Region
  
This becomes the workspace for all three agents and workflows.

---

## 2. Build the Detection Agent
This agent receives Defender alerts and classifies the misconfiguration.

### 2.1 Create the Agent
- Go to **Agents → Create Agent**
- Name: `az-cspm-audit-v1`
- Model: GPT‑4o or Phi‑4
- Mode: Reasoning + Tool Use (no tools yet)

### 2.1.0 Creating MCP Server Tool

### 2.2 Add System Prompt
```
You are the Detection Agent.
Your job:
1. Read Microsoft Defender for Cloud alerts.
2. Extract resourceId, issueType, severity, and alertId.
3. Output a clean JSON object with these fields.
4. Do not fix anything. Only classify and extract.
```




### 2.3 Save Agent

---

## 3. Build the Remediation Agent
This agent analyzes the violation and calls your MCP tool to fix it.

### 3.1 Create the Agent
- Go to **Agents → Create Agent**
- Name: `az-cspm-remediation-v1`
- Model: GPT‑4o or Phi‑4
- Mode: Reasoning + Tool Use

### 3.2 Connect MCP Server
- Go to **Tools → Add Tool → Connect MCP Server**
- Enter your MCP endpoint (Azure Container Apps)
- Foundry auto-discovers your tool(s)

Your MCP tool must expose something like:
`fix_azure_misconfiguration`

### 3.3 Add System Prompt
```
You are the Remediation Agent.
Your job:
1. Read the misconfiguration details from the Detection Agent.
2. Determine the correct secure configuration.
3. Call the MCP tool fix_azure_misconfiguration with:
   - resourceId
   - issueType
   - alertId
4. Never guess. Only act on validated misconfigurations.
```

### 3.4 Enable Tool Use
- In the agent → Tools → enable `fix_azure_misconfiguration`

---

## 4. Build the Audit Agent
This agent logs the remediation action to Log Analytics.

### 4.1 Create the Agent
- Go to **Agents → Create Agent**
- Name: `az-cspm-detect-v1`
- Model: GPT‑4o or Phi‑4

### 4.2 Add System Prompt
```
You are the Audit Agent.
Your job:
1. Receive remediation results from the Remediation Agent.
2. Format a log entry for Azure Log Analytics.
3. Send the log entry to the Log Analytics ingestion endpoint using the HTTP node.
```

### 4.3 No tools needed
The workflow will send logs via HTTP.

---

## 5. Create the End‑to‑End Workflow in Foundry
This is where everything comes together.

### 5.1 Create Workflow
- Go to **Workflows → Create Workflow**
- Name: `AutoFixSecurityMisconfigurations`

### 5.2 Add Nodes
- **Node 1 — REST Input Node**
  - This becomes the webhook endpoint for Defender alerts.
- **Node 2 — Detection Agent Node**
  - Connect REST Input → Detection Agent
  - Map incoming alert JSON to agent input
- **Node 3 — Remediation Agent Node**
  - Connect Detection Agent → Remediation Agent
  - Pass the extracted fields:
    - resourceId
    - issueType
    - alertId
- **Node 4 — Audit Agent Node**
  - Connect Remediation Agent → Audit Agent
- **Node 5 — HTTP Node (Log Analytics)**
  - Connect Audit Agent → HTTP Node
  - Configure:
    - Workspace ID
    - Shared Key
    - Custom Log Type (e.g., SecurityAutoFix_CL)
    - POST to Log Analytics ingestion endpoint

---

## 6. Publish the Workflow
- Click **Publish**
- Foundry gives you a public HTTPS endpoint
  - This is the endpoint Defender alerts will hit.

---

## 7. Connect Microsoft Defender for Cloud

### 7.1 Enable Continuous Export
- Go to **Defender for Cloud → Environment Settings**
- Enable:
  - Security Alerts
  - Recommendations

### 7.2 Export to Event Grid
- Choose **Event Grid** as export target

### 7.3 Create Event Grid Subscription
- Endpoint Type: Webhook
- URL: Foundry Workflow Endpoint

Now every misconfiguration alert flows into your workflow.

---

## 8. End‑to‑End Flow
Here’s what happens automatically:

**Step 1 — Detection**
> Defender → Event Grid → Foundry Workflow
> Detection Agent extracts:
> - resourceId
> - issueType
> - alertId

**Step 2 — Remediation**
> Remediation Agent:
> - Analyzes misconfiguration
> - Calls MCP tool
> - MCP server executes ARM API fix

**Step 3 — Audit**
> Audit Agent:
> - Formats log entry
> - Sends to Log Analytics via HTTP node

---

## 9. You Now Have Three Fully Implemented Agents

| Detection Agent | Remediation Agent | Audit Agent |
|-----------------|------------------|-------------|
| Classifies alerts | Fixes misconfigurations | Logs actions to Log Analytics |

---

## Next Steps
If you want, I can now generate:

✔ The exact Foundry workflow JSON  
✔ The MCP tool schema  
✔ The ARM remediation backend code (Python or PowerShell)  
✔ A Zero‑Trust executive diagram (Azure‑blue, rounded‑card style)  
✔ A multi‑agent escalation version (approval workflow)  

Just tell me which one you want next.
