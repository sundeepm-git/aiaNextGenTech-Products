import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawn } from 'child_process';
import { env } from "process";

// 1. Initialize the MCP Server
const server = new McpServer({
  name: "Azure-Resource-Assessor",
  version: "1.0.1",
});

// 2. Define the Assessment Tool for a Single Resource Group
server.tool(
  "assess_azure_environment",
  {
    subscriptionId: z.string().describe("The Azure Subscription ID to assess"),
    resourceGroup: z.string().optional().describe("A single specific Resource Group to assess (e.g., 'rg-production'). If omitted, the whole subscription is scanned.")
  },
  async ({ subscriptionId, resourceGroup }) => {
    try {
      // Path verified in your Kudu/App Service environment
      const scriptPath = env.POWERSHELL_SCRIPT_PATH //'D:\\home\\site\\wwwroot\\ps\\ps\\assessment-AzSubscription.ps1';
      
      // Prepare base PowerShell arguments
      let psArgs = [
        '-NoProfile', 
        '-ExecutionPolicy', 'Bypass', 
        '-File', scriptPath, 
        '-SubscriptionId', subscriptionId
      ];

      // Add single ResourceGroup if provided
      if (resourceGroup) {
        psArgs.push('-ResourceGroups', resourceGroup);
      }

      const result = await new Promise((resolve, reject) => {
        // Spawn the process
        const ps = spawn('powershell.exe', psArgs);

        let stdout = '';
        let stderr = '';

        // Capture standard output (Data)
        ps.stdout.on('data', (data) => {
            stdout += data.toString();
        });

        // Capture standard error (Logs/Errors)
        ps.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        ps.on('close', (code) => {
          if (code === 0) {
            resolve({
              content: [
                { 
                  type: "text", 
                  text: `Assessment Complete for ${resourceGroup || 'Full Subscription'}.\n\nOutput:\n${stdout}` 
                }
              ]
            });
          } else {
            // Include stderr in the rejection to help debug Kudu permissions or paths
            reject(new Error(stderr || `PowerShell exited with code ${code}`));
          }
        });
      });

      return result;

    } catch (error) {
      return {
        isError: true,
        content: [{ type: "text", text: `Execution Failed: ${error.message}` }]
      };
    }
  }
);

// 3. Start the Server with Stdio Transport
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  // Logs to stderr are visible in Kudu logs without interfering with MCP protocol
  console.error("Azure MCP Server started successfully.");
}

main().catch((error) => {
  console.error("Fatal error in MCP Server:", error);
  process.exit(1);
});