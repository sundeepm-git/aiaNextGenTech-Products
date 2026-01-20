# agent-2-infraAzTfAssessmentAgent-v1 (Assessment Agent)

## Purpose
Performs a managed-only Azure resource assessment for the specified subscription and resource groups, using a remote/local MCP server. Generates .xlsx and .pdf reports for downstream processing.

## Details
- Receives variables from MigrationOrchestrator-Agent: `subscriptionId`, `resourceGroups`, `outPath`
- Calls the MCP tool `execute_powershell_assessment` (see implementation in workflow doc)
- Waits for tool completion and returns JSON with artifact paths
- Saves output as `Local.assessmentOutput` for downstream use

## Example Output
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
