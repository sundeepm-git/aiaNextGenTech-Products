
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

To run a specific agent server (for example, the orchestrator):

```bash
node servers/orchestrator/index.js
```

Replace `orchestrator` with the desired agent directory (e.g., `aztfexport`, `subscription-assessment`).

## Project Structure

- `server.js`: Main entry point for the MCP server
- `servers/`: Contains individual agent server implementations

## Notes

- Requires Node.js (v16+) installed.
- For development, you can use [nodemon](https://www.npmjs.com/package/nodemon) for auto-reloading:
  ```bash
  npx nodemon server.js
  ```
