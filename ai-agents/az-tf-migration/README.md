# Localtunnel Setup for Azure Foundry MCP Server Integration

Localtunnel is a simple way to expose your local MCP server to the internet for integration with Azure Foundry, especially when you don't have a custom domain. You can request a specific subdomain for easier management in Azure Foundry settings.

## Prerequisites
- Node.js installed on your machine
- Your MCP server running locally (e.g., on http://localhost:8000)
-
## Step 1: Install Localtunnel

```bash
npm install -g localtunnel
```

## Step 2: Start Your MCP Server

Make sure your MCP server is running locally. For example:
```bash
node server.js
```

## Step 3: Expose Your MCP Server with Localtunnel

You can request a preferred subdomain (not guaranteed):
```bash
lt --port 4002 --subdomain assessment-mcp-server
```
If available, you will get a public URL like:
```
https://my-mcp-server.loca.lt
```
I got 
https://assessment-mcp-server.loca.lt

## Step 4: Integrate with Azure AI Foundry
1. Open Azure AI Foundry Portal.
2. Go to **Build > Tools > + Add tool**.
3. Select **Model Context Protocol (MCP)**.
4. Set **Server URL** to your Localtunnel URL (e.g., `https://my-mcp-server.loca.lt`).
5. Click **Connect**.

## Notes
- If your preferred subdomain is taken, try another name or let Localtunnel assign a random one.
- Localtunnel is best for quick development and testing. For production or persistent URLs, consider a more robust tunneling solution.

## Helpful Commands
- List tunnels: `cloudflared tunnel list`
- Check health: `cloudflared tunnel info azure-mcp-tunnel`
- Run as service (Always on): `sudo cloudflared service install`

## ngrok Prerequisites

Before using ngrok, complete these steps:

1. **Sign up for an account:**
	- https://dashboard.ngrok.com/signup
2. **Install ngrok and your authtoken:**
	 - Windows setup guide: https://dashboard.ngrok.com/get-started/setup/windows
	 - Get your authtoken: https://dashboard.ngrok.com/get-started/your-authtoken
	 - After installing ngrok, run:
		 ```bash
		 ngrok config add-authtoken <YOUR_AUTHTOKEN>
		 ```
	 - Replace `<YOUR_AUTHTOKEN>` with the token from your ngrok dashboard.
	 - By default, ngrok authentication is saved at:
		 `C:\Users\sunsu\AppData\Local/ngrok/ngrok.yml`

## Step-by-Step ngrok Configuration for Assessment MCP

This section describes how to expose your local MCP server for assessment agent development using ngrok.

### 1. Start the Assessment MCP Server

Run the assessment agent server:
```bash
node servers/subscription-assessment/index.js
```
### 2. Expose Your MCP Server with Localtunnel 
bash lt --port 4002 --subdomain assessment-mcp-server

---

This directory contains the MCP server for the Azure-Terraform migration agents.

## How to Run the MCP Server

1. **Install dependencies:**
	 ```bash
	 npm install
	 ```
2. **Start the main server:**
	 ```bash
	 node server.js
	 ```

## Running an Individual Agent Server

You can run any of the following agent servers individually:

- **Orchestrator Agent:**
	```bash
	node servers/orchestrator/index.js
	```
- **AzTfExport Agent:**
	```bash
	node servers/aztfexport/index.js
	```
- **Subscription Assessment Agent:**
	```bash
	node servers/subscription-assessment/index.js
	```

## Project Structure

- `server.js`: Main entry point for the MCP server
- `servers/`: Contains individual agent server implementations

---
# Deploying MCP Server to Azure App Services



## Step 1: The Updated server.js

Replace your entire `server.js` with the following code. This version is ready for Azure App Services, handles the dynamic port, CORS, and includes a placeholder for PowerShell execution:

```js
import express from "express";
import { spawn } from "child_process";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(express.json());

// 1. SECURITY & CORS
app.use((req, res, next) => {
	res.setHeader("Access-Control-Allow-Origin", "*");
	res.setHeader("Access-Control-Allow-Headers", "*");
	console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
	next();
});

const tools = [{
	name: "execute_powershell_assessment",
	description: "Runs the PowerShell assessment for Azure to Terraform migration",
	inputSchema: {
		type: "object",
		required: ["subscriptionId", "resourceGroup"],
		properties: {
			subscriptionId: { type: "string" },
			resourceGroup: { type: "string" }
		}
	}
}];

// 2. MCP ROUTE HANDLER
app.all(["/mcp", "/assessment-ps/mcp"], (req, res) => {
	const { method, id, params } = req.body || {};

	// HANDSHAKE
	if (method === "initialize") {
		return res.json({
			jsonrpc: "2.0",
			id,
			result: {
				protocolVersion: "2024-11-05",
				capabilities: { tools: { listChanged: false } },
				serverInfo: { name: "az-tf-assessment", version: "1.0.1" }
			}
		});
	}

	// DISCOVERY
	if (method === "tools/list") {
		return res.json({ jsonrpc: "2.0", id, result: { tools: tools } });
	}

	// EXECUTION
	if (method === "tools/call") {
		if (params?.name === "execute_powershell_assessment") {
			const { subscriptionId, resourceGroup } = params.arguments || {};
      
			// In Azure App Service, we use 'pwsh' (PowerShell Core)
			// We pass the identity flag so it authenticates via Managed Identity
			const psScript = `
				Connect-AzAccount -Identity -SubscriptionId "${subscriptionId}"
				Get-AzResource -ResourceGroupName "${resourceGroup}" | ConvertTo-Json
			`;

			const child = spawn("pwsh", ["-Command", psScript]);

			let output = "";
			child.stdout.on("data", (data) => { output += data.toString(); });
      
			child.on("close", () => {
				res.json({
					jsonrpc: "2.0",
					id,
					result: {
						content: [{ type: "text", text: `Assessment Complete for ${resourceGroup}. Results: ${output.substring(0, 500)}...` }],
						isError: false
					}
				});
			});
			return;
		}
	}

	res.status(404).json({ jsonrpc: "2.0", id: id || null, error: { code: -32601, message: "Not found" } });
});

// 3. DYNAMIC PORT FOR AZURE
const port = process.env.PORT || 4002;
app.listen(port, "0.0.0.0", () => {
	console.log(`🚀 MCP Server running on port ${port}`);
});
```
## Step 2: The package.json

## Step 3: Test Your MCP Server Locally

Before deploying, verify your MCP server works as expected using these curl commands:

### 1. The "Handshake" Test (Initialize)
The most common reason Azure fails to connect is a bad handshake. Open your terminal (while your server is running) and run:

```bash
curl -X POST http://localhost:4002/mcp \
	-H "Content-Type: application/json" \
	-d '{
		"jsonrpc": "2.0",
		"method": "initialize",
		"id": 1,
		"params": {
			"protocolVersion": "2024-11-05",
			"capabilities": {},
			"clientInfo": {"name": "test", "version": "1.0.0"}
		}
	}'
```
**What to look for:** You should see a JSON response containing `"capabilities": {"tools": {...}}`. If you get a 404 or an error, your `app.all` path is incorrect.

### 2. The "Discovery" Test (Tools List)
This mimics exactly what Azure AI Foundry does after the handshake to find your PowerShell tool.

```bash
curl -X POST http://localhost:4002/mcp \
	-H "Content-Type: application/json" \
	-d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
```
**What to look for:** The response must contain your `execute_powershell_assessment` tool definition.

### 3. The "Execution" Test (Tool Call)
This tests the actual spawn logic that triggers PowerShell.

```bash
curl -X POST http://localhost:4002/mcp \
	-H "Content-Type: application/json" \
	-d '{
		"jsonrpc": "2.0",
		"method": "tools/call",
		"id": 1,
		"params": {
			"name": "execute_powershell_assessment",
			"arguments": {
				"subscriptionId": "123-456",
				"resourceGroup": "MyTestRG"
			}
		}
	}'
```
**What to look for:**
- **Success:** A JSON response saying "Assessment Complete".
- **Failure:** If the terminal where your server is running shows `pwsh is not recognized`, it means you need to install PowerShell Core or change the spawn command to `powershell` (for Windows-only PS).

### 4. Verify Local Permissions
Since your script will eventually use Managed Identity in Azure, you should test it locally with your own credentials first:
1. Open PowerShell on your computer.
2. Run `Connect-AzAccount`.
3. Then run your Node.js server. If the server can successfully pull resource info via the curl in Step 3, your code logic is solid.

---
### Summary Checklist

| Test         | Expected Result         | Why it matters                                 |
|--------------|------------------------|------------------------------------------------|
| Initialize   | capabilities returned  | Azure won't talk to the server without this.   |
| Tools/List   | tools array populated  | If empty, Azure won't show any buttons.        |
| Tools/Call   | content with PS output | Ensures the Node-to-PowerShell bridge works.   |

Create this file in the same folder as your `server.js`. The `postinstall` script is crucial—it installs the Azure PowerShell modules into the App Service environment.

```json
{
	"name": "azure-mcp-server",
	"version": "1.0.0",
	"type": "module",
	"main": "server.js",
	"scripts": {
		"start": "node server.js",
		"postinstall": "pwsh -Command \"Install-Module -Name Az.Resources -Force -Scope CurrentUser\""
	},
	"dependencies": {
		"express": "^4.19.0"
	}
}
```


You can deploy your MCP server to Azure App Services for a production-ready, always-on endpoint. This is recommended for persistent, secure, and scalable integration with Azure AI Foundry or other cloud services.

## Prerequisites
- An [Azure account](https://portal.azure.com/)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed and logged in (`az login`)
- Node.js (v16+) and your MCP server code ready

## 1. Prepare Your MCP Server for Deployment
- Ensure your `package.json` has a `start` script (e.g., `"start": "node server.js"`).
- Confirm your server listens on the port provided by the `PORT` environment variable (required by Azure):
  ```js
  const port = process.env.PORT || 4002;
  app.listen(port, () => console.log(`Server running on port ${port}`));
  ```

## 2. Create Azure App Service and Deploy

### a. Create a Resource Group (if needed)
```bash
az group create --name myResourceGroup --location eastus
```

### b. Create an App Service Plan
```bash
az appservice plan create --name myAppServicePlan --resource-group myResourceGroup --sku B1 --is-linux
```

### c. Create a Web App
```bash
az webapp create --resource-group myResourceGroup --plan myAppServicePlan --name <your-app-name> --runtime "NODE|16-lts"
```

### d. Deploy Your Code
```bash
az webapp deploy --resource-group myResourceGroup --name <your-app-name> --src-path .
```
Or use [GitHub Actions](https://learn.microsoft.com/azure/app-service/deploy-github-actions) for CI/CD.

### e. Set Environment Variables (Optional)
```bash
az webapp config appsettings set --resource-group myResourceGroup --name <your-app-name> --settings NODE_ENV=production
```

## 3. Get Your Public URL
Find your app's URL:
```bash
az webapp show --resource-group myResourceGroup --name <your-app-name> --query defaultHostName -o tsv
```
Your MCP endpoint will be at `https://<your-app-name>.azurewebsites.net/mcp`

## 4. Integrate with Azure AI Foundry
- Use the Azure App Service URL as your MCP server endpoint in Foundry or other integrations.
- No tunnel is needed—your endpoint is always available.

## 5. Notes
- For production, consider scaling up your App Service Plan and enabling authentication.
- Monitor logs with:
  ```bash
  az webapp log tail --resource-group myResourceGroup --name <your-app-name>
  ```
- For advanced deployment, see [Azure App Service Node.js docs](https://learn.microsoft.com/azure/app-service/quickstart-nodejs?tabs=windows&pivots=development-environment-vscode).

## Local MCP Development with ngrok

You can expose your local MCP server to the internet using [ngrok](https://ngrok.com/) for webhook, API, and agent integration testing.

### Steps

1. **Install ngrok:**
	- Download and install from [ngrok.com](https://ngrok.com/download).

2. **Start your MCP server locally** (see above).

3. **Expose your MCP server with ngrok:**
	```bash
	ngrok http <PORT>
	```
	Replace `<PORT>` with the port your MCP server is running on (e.g., 4002 or 80).

4. **Copy the HTTPS forwarding URL** from ngrok output (e.g., `https://xxxx.ngrok.io`).

5. **Use the ngrok URL for:**
	- **Local webhook testing:** Point external services/webhooks to your ngrok URL.
	- **Local API testing:** Use the ngrok URL in API clients (Postman, curl, etc.).
	- **Local agent integration:** Configure agents or Foundry to use the ngrok URL for MCP endpoints.

### Example

If your MCP server runs on port 4002:
```bash
ngrok http 4002
```
Your public endpoint will be something like:
```
https://xxxx.ngrok.io/mcp/tools/execute_powershell_assessment
```

---
Requires Node.js (v16+) installed.
- For development, you can use [nodemon](https://www.npmjs.com/package/nodemon) for auto-reloading:
	```bash
	npx nodemon server.js

	```

	### 2. Expose MCP Server with ngrok (THIS Solution is Not Working, Agent is not able hit the ngrok generated MCP URL)

Open a new terminal and run:
```bash
ngrok http 4002 --request-header-add "ngrok-skip-browser-warning: true"

ngrok http 4002
```
ou must restart ngrok with the rewrite flag:
```bash
ngrok http 4002 --host-header=rewrite
```

If you changed the port, use your configured port instead of 4002.

### 3. Copy the HTTPS Forwarding URL

ngrok will display a forwarding URL like:
```
https://xxxx.ngrok.io
```

### 4. Configure Endpoints for Foundry or External Integration

- **MCP Server Discovery Method:**
	- `GET https://xxxx.ngrok.io/assessment-ps/mcp`
- **MCP Server Invocation Method:**
	- `POST https://xxxx.ngrok.io/mcp/tools/execute_powershell_assessment`

### 5. Test Webhook/API/Agent Integration

- Use the ngrok URL in your API client, Foundry, or webhook configuration.
- You can now access your local MCP server from anywhere via the public ngrok URL.

---
# Integration Steps: Local MCP Server to Azure AI Foundry via Cloudflare Tunnel

## Phase 1: Start Your Local MCP Server
Ensure your Node.js server is running and listening on port 4002.

Open your terminal in your project folder.

Run:
```bash
node server.js
```

Verify locally: Open another terminal and run:
```bash
curl -X POST http://localhost:4002/mcp -H "Content-Type: application/json" -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
```
If you see your `execute_powershell_assessment` tool in the JSON response, your code is perfect.

## Phase 2: Create a Reliable Bridge (Cloudflare)
Cloudflare's "Quick Tunnel" is free, requires no account, and doesn't show the "Click to Continue" screen that breaks AI agents.

Install Cloudflared:
- **Mac:** `brew install cloudflared`
- **Windows:** Download `.exe` and add to PATH.

Launch the Tunnel:
```bash
cloudflared tunnel --url http://localhost:4002
```

Find the URL: Look for a line in the terminal that says: `Your worker at https://some-random-words.trycloudflare.com has been created.`

Keep this terminal open. If you close it, the tunnel dies.

## Phase 3: Integrate with Azure AI Foundry
1. Go to Azure AI Foundry Portal > Your Project.
2. Navigate to **Build > Tools > + Add tool**.
3. Select **Custom > Model Context Protocol (MCP)**.
4. Fill in the details:
   - **Name:** PowerShell_Assessment_Tool
   - **Server URL:** Paste your Cloudflare URL including the path: `https://your-random-words.trycloudflare.com/mcp`
   - **Authentication:** Select None.
5. Click **Connect**.

### Why this will work where others failed:
- **No "Interstitials":** Unlike Localtunnel, Cloudflare doesn't force a "Click to continue" page. Azure's backend can hit your API directly.
- **Protocol Alignment:** Your code correctly implements the initialize handshake. Azure's first request is `initialize` to check capabilities. Because your code returns `tools: {}` in the capabilities, Azure immediately sends the second request (`tools/list`).
- **Correct Port Mapping:** By using port 4002 in both your code and the tunnel command, you eliminate the 503 "Tunnel Unavailable" errors.

## Troubleshooting the "Empty Tools" List
If you still see `tools: []` in Azure after following these steps:

- **Check Terminal Logs:** Look at your `node server.js` terminal. Do you see `[LOG] POST request to: /mcp`?
  - No logs? The request isn't reaching your computer (check your firewall).
  - Logs show 404? Your URL path in Azure doesn't match the paths in `app.all`. Use exactly `https://.../mcp`.
- **Restart the Agent:** Sometimes Azure Foundry caches the "empty" tool list. Delete the tool in Azure and re-add it with the new Cloudflare URL.

---
# Cloudflare Tunnel Client Installation and Setup

## 1. Install cloudflared (Fastest Methods)

### Windows (PowerShell/CMD)
- The easiest way is using the Windows Package Manager:
  1. Open PowerShell as Administrator.
  2. Run:
     ```powershell
     winget install --id Cloudflare.cloudflared
     ```
  3. Restart your terminal for the changes to take effect.
- If you prefer a manual download:
  1. Download the `.exe` from Cloudflare.
  2. Rename it to `cloudflared.exe`.
  3. In your terminal, navigate to the folder where you saved it and run it using `./cloudflared.exe` instead of just `cloudflared`.

### macOS
- Open Terminal.
- Run:
  ```bash
  brew install cloudflared
  ```
- If you don't have Homebrew, you can download the Darwin binary, extract it, and move it to `/usr/local/bin`.

### Linux (Ubuntu/Debian)
- Run:
  ```bash
  curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  sudo dpkg -i cloudflared.deb
  ```

## 2. Verify the Installation
Once installed, type this to make sure it works:
```bash
cloudflared --version
```
## Installed on Path
C:\Program Files (x86)\cloudflared\cloudflared.exe

If you are on Windows and didn't use winget, remember to use `./cloudflared.exe --version` inside the folder where the file is.

## 3. Start the Tunnel
Now that the command is recognized, run your tunnel command:
```bash
cloudflared tunnel --url http://localhost:4002
```

### Troubleshooting "Command Not Found" after installation:
- **Path:** If you manually downloaded the `.exe` on Windows, you must either move it to `C:\Windows\system32` or run the command from the exact folder where the file sits (e.g., `cd Downloads` then `./cloudflared.exe ...`).
- **Refresh:** Always close and reopen your terminal after a new installation so it can "see" the new command.

Once you get that `https://...trycloudflare.com` URL from the output, you are ready to paste it into Azure Foundry. Do you have the URL yet?

