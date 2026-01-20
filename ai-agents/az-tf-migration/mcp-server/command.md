# Commands to Run All MCP Servers

Open three terminals and run each server in its own terminal:

```
# Orchestrator MCP server
cd servers/orchestrator
node index.js

# Subscription Assessment MCP server
cd ../subscription-assessment
node index.js

# AZTF Export MCP server
cd ../aztfexport
node index.js
```

Or, from the mcp-server root, run:

```
# Orchestrator
node servers/orchestrator/index.js

# Subscription Assessment
node servers/subscription-assessment/index.js

# AZTF Export
node servers/aztfexport/index.js
```

Make sure your .env file is configured and all dependencies are installed.
