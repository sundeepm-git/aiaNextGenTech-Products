import express from "express";
import { spawn } from "child_process";
import path from "path";
import { fileURLToPath } from "url";
import dotenv from "dotenv";

// Load environment variables from .env file
dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(express.json({ limit: "1mb" }));

// ---- MCP discovery: what tools we expose ----
app.get("/assessment-ps/mcp", (req, res) => {
  res.json({
    tools: [
      {
        name: "execute_powershell_assessment",
        inputSchema: {
          type: "object",
          required: ["subscriptionId", "resourceGroups"],
          properties: {
            subscriptionId: { type: "string" },
            resourceGroups: {
              type: "array",
              items: { type: "string" },
              minItems: 1
            }
          },
          additionalProperties: false
        },
        outputSchema: {
          type: "object",
          required: ["status", "artifacts"],
          properties: {
            status: { type: "string", enum: ["completed", "failed"] },
            subscriptionId: { type: "string" },
            outPath: { type: "string" },
            artifacts: {
              type: "object",
              required: ["xlsx", "pdf"],
              properties: {
                xlsx: { type: "string" },
                pdf: { type: "string" }
              },
              additionalProperties: false
            },
            message: { type: "string" }
          },
          additionalProperties: false
        }
      }
    ]
  });
});

// ---- MCP tool invocation ----
app.post("/tools/execute_powershell_assessment", (req, res) => {
  const body = req.body || {};
  const subscriptionId = (body.subscriptionId || "").trim();
  const resourceGroups = Array.isArray(body.resourceGroups) ? body.resourceGroups : [];

  if (!subscriptionId || resourceGroups.length === 0) {
    return res.status(400).json({
      status: "failed",
      message: "subscriptionId (string) and resourceGroups (non-empty array) are required"
    });
  }

  // Build PowerShell call using script path from .env
  const scriptPath = process.env.POWERSHELL_SCRIPT_PATH;
  if (!scriptPath) {
    return res.status(500).json({
      status: "failed",
      message: "PowerShell script path is not set in .env file."
    });
  }
  const rgCsv = resourceGroups.join(",");

  let ps;
  try {
    ps = spawn("pwsh", [
      "-NoLogo",
      "-NonInteractive",
      "-File", scriptPath,
      "-SubscriptionId", subscriptionId,
      "-ResourceGroups", rgCsv
    ], { stdio: ["ignore", "pipe", "pipe"] });
  } catch (err) {
    console.error("Failed to start PowerShell process:", err);
    return res.status(500).json({
      status: "failed",
      message: "Failed to start PowerShell process. Check server logs for details."
    });
  }

  let stderr = "";
  let stdout = "";
  ps.stderr.on("data", d => { stderr += String(d); });
  ps.stdout.on("data", d => { stdout += String(d); });

  ps.on("error", (err) => {
    console.error("PowerShell process error:", err);
    return res.status(500).json({
      status: "failed",
      message: "PowerShell script failed to run. Check server logs for details."
    });
  });

  ps.on("close", (code) => {
    if (code !== 0) {
      console.error("PowerShell script failed:", stderr || stdout);
      return res.status(500).json({
        status: "failed",
        message: (stderr || stdout || "Assessment failed").slice(0, 1000)
      });
    }
    // Return artifact paths expected by your Foundry agent/workflow
    return res.json({
      status: "completed",
      subscriptionId,
      artifacts: {
        xlsx: `AzTfExport_Managed_RG_Report.xlsx`,
        pdf:  `AzTfExport_Managed_RG_Report.pdf`
      }
    });
  });
});

// Basic liveness
app.get("/healthz", (_req, res) => res.json({ status: "ok" }));

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`MCP server listening on http://localhost:${PORT}`);
});
