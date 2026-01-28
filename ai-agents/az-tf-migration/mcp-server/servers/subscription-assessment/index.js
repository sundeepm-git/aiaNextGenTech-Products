import express from "express";
import fs from "fs";
import path from "path";
import { spawn } from "child_process";
import { fileURLToPath } from "url";
import dotenv from "dotenv";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.resolve(__dirname, "../../../.env") });

// Simple log function
function log(message) {
  const logDir = path.join(__dirname, "../../log");
  const logFile = path.join(logDir, "server.log");
  const timestamp = new Date().toISOString();
  const entry = `[${timestamp}] ${message}\n`;
  try {
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
    fs.appendFileSync(logFile, entry);
  } catch (err) {
    console.error("Failed to write log:", err);
  }
}

const discoveryResponse = {
  tools: [
    {
      name: "execute_powershell_assessment",
      description: "Runs the PowerShell assessment for Azure to Terraform migration",
      inputSchema: {
        type: "object",
        required: ["subscriptionId", "resourceGroup"],
        properties: {
          subscriptionId: { type: "string" },
          resourceGroup: { type: "string" }
        },
        additionalProperties: false
      }
    }
  ]
};

const app = express();
app.use(express.json({ limit: "1mb" }));

// ---- MCP DISCOVERY ENDPOINTS ----
app.get("/assessment-ps/mcp", (req, res) => {
  log("GET /assessment-ps/mcp");
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  return res.status(200).json(discoveryResponse);
});

app.post("/assessment-ps/mcp", (req, res) => {
  log("POST /assessment-ps/mcp");
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  return res.status(200).json(discoveryResponse);
});

// ---- MCP TOOL EXECUTION ----
app.post("/mcp/tools/execute_powershell_assessment", (req, res) => {
  log("POST /mcp/tools/execute_powershell_assessment");

  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Connection", "keep-alive");

  const body = req.body || {};
  const subscriptionId = (body.subscriptionId || body.params?.arguments?.subscriptionId || "").trim();
  const resourceGroup = (body.resourceGroup || body.params?.arguments?.resourceGroup || "").trim();

  if (!subscriptionId || !resourceGroup) {
    log("400: Missing input data");
    return res.status(400).end(JSON.stringify({ status: "failed", message: "subscriptionId and resourceGroup required" }));
  }

  const scriptPath = process.env.POWERSHELL_SCRIPT_PATH;
  const heartbeat = setInterval(() => { if (!res.writableEnded) res.write(" "); }, 15000);

  let stdout = "";
  let stderr = "";

  try {
    const ps = spawn("pwsh", [
      "-NoLogo", "-NonInteractive", "-File", scriptPath,
      "-SubscriptionId", subscriptionId,
      "-ResourceGroup", resourceGroup
    ], { stdio: ["ignore", "pipe", "pipe"] });

    ps.stdout.on("data", (d) => { stdout += String(d); });
    ps.stderr.on("data", (d) => { stderr += String(d); });

    ps.on("close", (code) => {
      clearInterval(heartbeat);
      if (res.writableEnded) return;

      const reportFolder = "C:/Users/sunsu/OneDrive/Desktop/Sundeep/AI-Projects/ai-Repository/Generative-AI-Projects/azure-2-terraform-migration/Azure-2-terraform-powershell-exports/ps/report";

      try {
        const files = fs.readdirSync(reportFolder);
        const excelFile = files.find(f => f.endsWith(".xlsx") && f.startsWith("AzureAssessment"));
        
        if (excelFile) {
          return res.status(200).end(JSON.stringify({
            status: "completed",
            subscriptionId,
            resourceGroup,
            artifacts: {
              xlsx: path.join(reportFolder, excelFile),
              folder: reportFolder
            }
          }));
        } else {
          throw new Error("Excel report not found in directory.");
        }
      } catch (err) {
        return res.status(500).end(JSON.stringify({
          status: "failed",
          message: err.message,
          details: stderr || stdout
        }));
      }
    });

    ps.on("error", (err) => {
      clearInterval(heartbeat);
      if (!res.writableEnded) res.status(500).end(JSON.stringify({ status: "failed", message: err.message }));
    });

  } catch (err) {
    clearInterval(heartbeat);
    if (!res.writableEnded) res.status(500).end(JSON.stringify({ status: "failed", message: err.message }));
  }
});

// ---- HEALTH CHECK & SERVER START ----
app.get("/healthz", (req, res) => res.json({ status: "ok" }));

const PORT = process.env.SUBSCRIPTION_ASSESSMENT_PORT || 4002;
const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});
server.setTimeout(600000);