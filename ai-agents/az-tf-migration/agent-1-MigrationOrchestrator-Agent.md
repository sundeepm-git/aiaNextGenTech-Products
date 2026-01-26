# agent-1-MigrationOrchestrator-Agent

## Purpose
Extracts and validates user migration requirements from a natural language prompt or structured input. Parses subscription, resource group(s), and output path, then sets these as workflow variables for downstream nodes.

## Details
- Receives user input (NLP or form-based)
- Extracts: subscriptionId, resourceGroups[]
- Validates required fields and formats
- Saves output as `Local.orchestratorOutput` for use by subsequent nodes

## Example Output
```json
{
  "subscriptionId": "<sub-guid>",
  "resourceGroups": ["rg-app-dev", "rg-data-dev"],
  "outPath": "/assessment"
}
```
