# MCP Tools - Modular Structure

This directory contains modular MCP (Model Context Protocol) tool implementations for the Azure Terraform MCP Server.

## Structure

```
tools/
├── assessment.js       # Azure environment assessment for Terraform migration
├── aztfexport.js       # Export Azure resources to Terraform configuration
└── refactor.js         # Refactor and optimize Terraform code
```

## How It Works

Each tool module exports two key components:

1. **Tool Definition** - Defines the tool name, description, and schema
2. **Tool Handler** - Contains the business logic for executing the tool

### Example Structure

```javascript
// Tool Definition
export const myToolDefinition = {
  name: "my_tool_name",
  description: "What this tool does",
  schema: {
    param1: z.string().describe("Description"),
    param2: z.number().optional().describe("Optional parameter")
  }
};

// Tool Handler
export async function myToolHandler({ param1, param2 }, context) {
  // Access shared resources from context
  const { jobs, executeJob, blobStorageAvailable } = context;
  
  // Implement tool logic
  // ...
  
  return {
    content: [{
      type: "text",
      text: "Tool execution result"
    }]
  };
}
```

## Shared Context

All tools receive a `context` object containing:

- `jobs` - Map of all active jobs
- `Job` - Job class constructor
- `executeJob` - Assessment job execution function
- `executeExportJob` - Export job execution function
- `executeRefactorJob` - Refactor job execution function
- `blobStorageAvailable` - Boolean indicating Azure Blob Storage availability
- `storageAccountName` - Storage account name (if configured)
- `containerName` - Blob container name
- `blobStorageError` - Error message if Blob Storage unavailable

## Adding New Tools

1. Create a new file in `tools/` directory (e.g., `mynewtool.js`)

2. Define your tool:

```javascript
import { z } from "zod";
import { v4 as uuidv4 } from 'uuid';

export const myNewToolDefinition = {
  name: "my_new_tool",
  description: "Description of what your tool does",
  schema: {
    // Define your parameters using zod
  }
};

export async function myNewToolHandler(params, context) {
  // Implement your logic
}
```

3. Import in `index.js`:

```javascript
import { myNewToolDefinition, myNewToolHandler } from './tools/mynewtool.js';
```

4. Register the tool:

```javascript
server.tool(
  myNewToolDefinition.name,
  myNewToolDefinition.schema,
  async (params) => myNewToolHandler(params, toolContext)
);
```

5. Update the root endpoint to list your tool:

```javascript
app.get("/", (req, res) => {
  res.json({
    // ...
    tools: [
      // ...existing tools
      {
        name: myNewToolDefinition.name,
        description: myNewToolDefinition.description
      }
    ]
  });
});
```

## Available Tools

### 1. Assessment Tool (`assess_azure_environment`)

**Purpose**: Assess Azure subscription/resource group for Terraform migration readiness

**Parameters**:
- `subscriptionId` (string) - Azure Subscription ID
- `resourceGroup` (string) - Resource Group name

**Returns**: Job ID for tracking the assessment process

**Status**: ✅ Fully Implemented

---

### 2. AzTFExport Tool (`export_azure_to_terraform`)

**Purpose**: Export Azure resources to Terraform configuration files

**Parameters**:
- `subscriptionId` (string) - Azure Subscription ID
- `resourceGroup` (string, optional) - Resource Group to export
- `resourceIds` (array, optional) - Specific resource IDs to export
- `outputPath` (string, optional) - Output directory for Terraform files

**Returns**: Job ID for tracking the export process

**Status**: 🚧 Placeholder Implementation - Needs PowerShell script integration

**TODO**:
- Integrate with `Export-AzToTerraform.ps1` script
- Implement proper Terraform file generation
- Add support for selective resource export

---

### 3. Refactor Tool (`refactor_terraform_code`)

**Purpose**: Analyze and refactor Terraform code to follow best practices

**Parameters**:
- `terraformPath` (string) - Path to Terraform files/directory
- `refactorOptions` (object, optional) - Refactoring options:
  - `modularity` - Extract reusable resources into modules
  - `variableOptimization` - Optimize variable usage
  - `resourceNaming` - Standardize naming conventions
  - `stateManagement` - Recommend state improvements
  - `securityHardening` - Apply security best practices
- `outputPath` (string, optional) - Output directory for refactored files

**Returns**: Job ID for tracking the refactoring process

**Status**: 🚧 Placeholder Implementation - Needs refactoring logic

**TODO**:
- Implement Terraform code analysis
- Build refactoring engine
- Create best practices rules
- Generate refactored output files

---

## Job Execution Functions

Each tool type has its own execution function:

### `executeJob(job)` - Assessment Jobs
- Runs PowerShell assessment script
- Uploads report to Azure Blob Storage
- Updates job status

### `executeExportJob(job)` - Export Jobs
- TODO: Call aztfexport or Export-AzToTerraform.ps1
- Generate Terraform configuration files
- Package and upload results

### `executeRefactorJob(job)` - Refactor Jobs
- TODO: Analyze Terraform code
- Apply refactoring rules
- Generate refactored files
- Create refactoring report

## Testing

Test individual tools using MCP Inspector:

```bash
npx @modelcontextprotocol/inspector
```

Connect to: `http://localhost:8080/sse`

Select a tool and provide the required parameters.

## Best Practices

1. **Error Handling**: Always wrap logic in try-catch and return proper error responses
2. **Logging**: Use `console.error()` for server-side logging (goes to container logs)
3. **Job Pattern**: Use async jobs for long-running operations
4. **Status URLs**: Always return a status URL for tracking job progress
5. **Validation**: Use Zod schemas for parameter validation
6. **Modularity**: Keep tools focused on a single responsibility

## Future Enhancements

- Add orchestrator tool to chain multiple tools
- Implement progress tracking with percentage updates
- Add webhook notifications for job completion
- Support batch operations
- Add dry-run mode for all tools
- Implement rollback functionality
