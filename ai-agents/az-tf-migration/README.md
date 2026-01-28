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

### 2. Expose MCP Server with ngrok

Open a new terminal and run:
```bash
ngrok http 4002 --request-header-add "ngrok-skip-browser-warning: true"

ngrok http 4002
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
# MCP Server

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
