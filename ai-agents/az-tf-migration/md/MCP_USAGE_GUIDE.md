# MCP Server Usage Guide

This server supports **two modes**: stdio (recommended) and HTTP/SSE.

## Mode 1: Stdio (Recommended - Works Reliably)

**Use with:** Claude Desktop, or any MCP client that supports stdio transport

### Setup for Claude Desktop:

1. **Locate Claude Desktop config** (Windows):
   ```
   %APPDATA%\Claude\claude_desktop_config.json
   ```

2. **Add this server to the config**:
   ```json
   {
     "mcpServers": {
       "azure-terraform": {
         "command": "node",
         "args": ["C:\\Users\\sunsu\\OneDrive\\Desktop\\Sundeep\\AI-Projects\\ai-Repository\\Generative-AI-Projects\\aiaNextGen-Products\\ai-agents\\az-tf-migration\\apps-mcp-server\\index.js"],
         "env": {
           "GITHUB_TOKEN": "your-github-token-here"
         }
       }
     }
   }
   ```

3. **Restart Claude Desktop**

4. **Verify tools appear**: Look for the hammer/tools icon in Claude Desktop. You should see:
   - `assess` - Azure subscription assessment tool
   - `export` - Export resource groups to Terraform
   - `refactor` - Refactor Terraform code

### Test from Command Line:
```powershell
node index.js --stdio
```

The server will start in stdio mode and wait for JSON-RPC messages on stdin.

---

## Mode 2: HTTP/SSE (For MCP Inspector - Has Known Issues)

**Use with:** MCP Inspector web tool

### Known Limitations:
⚠️ **SSE connection persistence issue**: The MCP SDK's `SSEServerTransport.handlePostMessage()` closes the SSE connection after each POST request. This causes tools to not appear reliably in MCP Inspector.

### Start HTTP Server:
```powershell
# From workspace root
node ai-agents/az-tf-migration/apps-mcp-server/index.js

# Or set custom port
$env:PORT=8080; node ai-agents/az-tf-migration/apps-mcp-server/index.js
```

### Connect MCP Inspector:
1. Open MCP Inspector: https://inspector.modelcontextprotocol.io/
2. Enter URL: `http://localhost:8080/sse`
3. Click "Connect"

**Expected behavior**: Connection may repeatedly close and reconnect. Tools may not appear due to the SSE persistence issue documented in the code.

### Alternative - Use Inspector with Stdio:
```powershell
npx @modelcontextprotocol/inspector node index.js --stdio
```

This launches Inspector in proxy mode connecting to your stdio server, avoiding HTTP/SSE entirely.

---

## Available Tools

### 1. assess - Azure Subscription Assessment
Analyzes an Azure subscription and generates compliance/readiness report.

**Parameters:**
- `subscriptionId` (required): Azure subscription GUID
- `resourceGroup` (optional): Specific resource group to assess

**Example in Claude:**
```
Please assess subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2
```

### 2. export - Export to Terraform
Exports Azure resource groups to Terraform code using aztfexport.

**Parameters:**
- `subscriptionId` (required): Azure subscription GUID
- `resourceGroups` (required): Array of resource group names
- `outputDirectory` (required): Path to save generated Terraform files

**Example:**
```
Export resource groups ["rg-prod", "rg-dev"] from subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 to ./terraform
```

### 3. refactor - Refactor Terraform Code
Refactors Terraform code with Azure best practices and standards.

**Parameters:**
- `terraformDirectory` (required): Path to Terraform files
- `namingPrefix` (optional): Naming convention prefix
- `outputDirectory` (optional): Where to save refactored code

**Example:**
```
Refactor the Terraform code in ./terraform/exports with naming prefix "az-prod"
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PORT` | No | HTTP server port (default: 8080) |
| `GITHUB_TOKEN` | Yes (refactor) | GitHub Personal Access Token for private repo access |
| `AZURE_STORAGE_CONNECTION_STRING` | No | For blob storage upload (optional) |
| `storageAccount` | No | Azure Storage account name (optional) |

---

## Troubleshooting

### Stdio Mode Issues

**Problem**: Server starts but Claude Desktop doesn't show tools
- Check Claude Desktop logs: `%APPDATA%\Claude\logs\`
- Verify absolute paths in config
- Ensure Node.js is in PATH
- Restart Claude Desktop after config changes

### HTTP Mode Issues

**Problem**: "HTTP 400" or "Connection closed" errors in MCP Inspector
- **Root cause**: SSE transport limitation in MCP SDK
- **Solution**: Use stdio mode instead
- **Workaround**: Use Inspector with stdio proxy:
  ```powershell
  npx @modelcontextprotocol/inspector node index.js --stdio
  ```

**Problem**: "No tools showing up"
- This is expected with HTTP/SSE mode due to connection closing
- Switch to stdio mode for reliable operation

### Tool Execution Issues

**Problem**: Tool fails with Azure authentication error
- Ensure you're authenticated: `az login`
- Check subscription access: `az account show`
- Verify subscription ID is correct

**Problem**: Export tool fails
- Ensure aztfexport.exe is in PATH or in ps/ directory
- Check Azure CLI is installed and working
- Verify resource groups exist in subscription

---

## Technical Details

### Mode Detection
The server auto-detects mode based on:
1. `--stdio` command-line argument
2. `process.stdin.isTTY === false` (piped stdin)

### Architecture
- **Stdio mode**: Uses `StdioServerTransport` - reads JSON-RPC from stdin, writes to stdout
- **HTTP mode**: Uses Express + `SSEServerTransport` - SSE on GET /sse, messages on POST /messages

### SSE Implementation Issue
The current MCP SDK (v1.0.1) has a limitation where `SSEServerTransport.handlePostMessage()` closes the SSE connection after processing each POST. This breaks the persistent connection requirement of the MCP protocol. Until this is resolved, stdio mode is the recommended approach.

### Job Management
- Refactor jobs run asynchronously with progress tracking
- Jobs are stored in memory with cleanup after 24 hours
- Progress updates via SSE for HTTP mode, or polling for stdio mode

---

## Recommendations

1. ✅ **Use stdio mode with Claude Desktop** for production use
2. ⚠️ **Use HTTP mode only for debugging** specific HTTP/SSE issues
3. 🔧 **Use Inspector stdio proxy** if you need Inspector's UI
4. 📝 **Monitor Claude Desktop logs** to debug stdio connection issues

---

## Files

- `index.js` - Main server with dual-mode support
- `claude-desktop-config.json` - Template config for Claude Desktop
- `tools/assessment.js` - Azure subscription assessment tool
- `tools/aztfexport.js` - Terraform export tool
- `tools/code-refactor.js` - Terraform refactoring tool
- `ps/` - PowerShell scripts for Azure operations

---

## Support

For issues or questions, refer to:
- MCP Protocol: https://modelcontextprotocol.io
- MCP SDK: https://github.com/modelcontextprotocol/sdk
- Azure CLI: https://learn.microsoft.com/cli/azure/
