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

# Az Steps to create ACR and Contanrization
# Create ACR
```az
az acr create -n aztfmcpacr -g rg-mcp-servers --sku Basic --admin-enabled true

az acr login -n  aztfmcpacr -g rg-mcp-servers

$ACR_LOGIN_SERVER = az acr show -n aztfmcpacr -g rg-mcp-servers --query loginServer -o tsv

$ACR_LOGIN_SERVER

docker tag mcp-azure-assessor:latest "$ACR_LOGIN_SERVER/mcp-azure-assessor:latest"

docker push "$ACR_LOGIN_SERVER/mcp-azure-assessor:latest"
```
# STEP 1- Install the Container Apps extension (PowerShell)
az extension add --name containerapp --upgrade
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights

# STEP 2 Set your variables

```pw
$RESOURCE_GROUP = "rg-mcp-servers"
$LOCATION       = "centralus"
$ACA_ENV        = "mcp-aca-env"
$LOG_WS         = "mcp-logs"
$APP_NAME       = "aztf-mcp-app"

# Use the same ACR name you created earlier
$ACR_NAME       = "aztfmcpacr"

```
# STEP 3 (Optional)
az monitor log-analytics workspace create `
  -g $RESOURCE_GROUP `
  -n $LOG_WS `
  -l $LOCATION
$LOG_WS_ID  = az monitor log-analytics workspace show `
  -g $RESOURCE_GROUP `
  -n $LOG_WS `
  --query customerId `
  -o tsv

$LOG_WS_KEY = az monitor log-analytics workspace get-shared-keys `
  -g $RESOURCE_GROUP `
  -n $LOG_WS `
  --query primarySharedKey `
  -o tsv  

# STEP 4 Create Container APP
az containerapp env create -g $RESOURCE_GROUP -n $ACA_ENV -l $LOCATION 

# STEP 5 — Get ACR login server + 
```ps
$ACR_LOGIN_SERVER = az acr show -n $ACR_NAME -g $RESOURCE_GROUP --query loginServer -o tsv

$ACR_USERNAME = az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query username -o tsv
 
$ACR_PASSWORD = az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query passwords[0].value -o tsv

  ```
# STEP 6 — Deploy your container to Azure Container Apps
az containerapp create -g $RESOURCE_GROUP -n $APP_NAME --environment $ACA_ENV --image "$ACR_LOGIN_SERVER/mcp-azure-assessor:latest" --target-port 8080 --ingress external --registry-server $ACR_LOGIN_SERVER  --registry-username $ACR_USERNAME --registry-password $ACR_PASSWORD --min-replicas 1 --max-replicas 3

#  STEP 7 — Get your public URL
$APP_URL = az containerapp show -g $RESOURCE_GROUP -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv

$APP_URL

$App_URL value shown in cli - aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io

Broser URL (MCP Server Running) =  https://aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io/

# STEP 8 — Add environment variables (if needed)
az containerapp update  -g $RESOURCE_GROUP  -n $APP_NAME --set-env-vars POWERSHELL_SCRIPT_PATH="/app/ps/ps/assessment-AzSubscription.ps1"

# Verify inside the running container (optional but useful)
az containerapp exec -g $RESOURCE_GROUP -n $APP_NAME --command "ls -R /app"

# Check environment variables inside the running container
az containerapp exec -g $RESOURCE_GROUP -n $APP_NAME --command "printenv"

# Check Environment Varoiable
az containerapp show -g $RESOURCE_GROUP -n $APP_NAME --query properties.template.containers[0].env -o table

# Steps to RUN MCP from UI
Today your MCP server is running in Azure
Your MCP server is now running at:
https://aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io


So if you want to use the Inspector again, you can run:
npx @modelcontextprotocol/inspector


And then in the Inspector UI, enter:
Remote MCP server endpoint
https://aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io


SSE
/sse


Messages
/messages


Then click Connect.
The Inspector will now connect to your Azure-hosted MCP server.

⭐ Why this matters for Azure AI Foundry
Azure AI Foundry behaves exactly like the Inspector:
- It opens SSE
- Gets sessionId
- Sends POST /messages
- Loads your tools
- Lets you run them
So if the Inspector works, Foundry will work.

⭐ Summary (super clear)
✔ npx @modelcontextprotocol/inspector
→ Opens the MCP Inspector UI (client)
✔ Your MCP server
→ Runs from your Node.js code
→ Hosted in Azure Container Apps
✔ To test your Azure MCP server
→ Use the Inspector or Foundry
→ Point them to your Azure URL

# REDEPLOY Container APP
docker build -t aztfmcpacr.azurecr.io/aztf-mcp-server:v2 .
az acr login --name aztfmcpacr -g rg-mcp-servers
docker push aztfmcpacr.azurecr.io/aztf-mcp-server:v2
aztfmcpacr.azurecr.io/aztf-mcp-server:v2

# TEST MCP MESSAGE -
curl -X POST https://aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io/messages -H "Content-Type: application/json" -d "{}"

# IMPORTANT COMMAND TO RUN INSPECTOR
npx @modelcontextprotocol/inspector --port 9000 --proxy-port 9001 --relay-port 9002

# Update mcp.json
{
  "mcpServers": {
    "azure-assessor": {
      "command": "node",
      "args": [
        "C:/Users/sunsu/OneDrive/Desktop/Sundeep/AI-Projects/ai-Repository/Generative-AI-Projects/aiaNextGen-Products/ai-agents/az-tf-migration/mcp-server/servers/subscription-assessment/index.js"
      ]
    },
    "aztf-remote-app": {
      "type": "http",
      "url": "https://aztf-mcp-app.gentlesmoke-1d011f4c.centralus.azurecontainerapps.io/sse"
    }
  }
}