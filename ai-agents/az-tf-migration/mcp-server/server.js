import express from "express";
import { spawn } from "child_process";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(express.json({ limit: "1mb" }));

// ---- MCP discovery: what tools we expose ----
app.get("/.well-known/mcp", (req, res) => {
  res.json({
    tools: [
      {
        name: "execute_powershell_assessment",
        inputSchema: {
          type: "object",
          required: ["subscriptionId", "resourceGroups", "outPath"],
          properties: {
            subscriptionId: { type: "string" },
            resourceGroups: {
              type: "array",
              items: { type: "string" },
              minItems: 1
            },
            outPath: { type: "string" }
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
  const outPath = (body.outPath || "/assessment").trim();

  if (!subscriptionId || resourceGroups.length === 0) {
    return res.status(400).json({
      status: "failed",
      message: "subscriptionId (string) and resourceGroups (non-empty array) are required"
    });
  }

  // Build PowerShell call:
  //   ./scripts/run-assessment.ps1 -SubscriptionId <id> -ResourceGroups <rg1,rg2> -OutPath <dir>
  const scriptPath = path.resolve(__dirname, "scripts", "run-assessment.ps1");
  const rgCsv = resourceGroups.join(",");

  const ps = spawn("pwsh", [
    "-NoLogo",
    "-NonInteractive",
    "-File", scriptPath,
    "-SubscriptionId", subscriptionId,
    "-ResourceGroups", rgCsv,
    "-OutPath", outPath
  ], { stdio: ["ignore", "pipe", "pipe"] });

  let stderr = "";
  ps.stderr.on("data", d => { stderr += String(d); });

  ps.on("close", (code) => {
    if (code !== 0) {
      return res.json({
        status: "failed",
        message: (stderr || "Assessment failed").slice(0, 1000)
      });
    }
    // Return artifact paths expected by your Foundry agent/workflow
    return res.json({
      status: "completed",
      subscriptionId,
      outPath,
      artifacts: {
        xlsx: `${outPath}/AzTfExport_Managed_RG_Report.xlsx`,
        pdf:  `${outPath}/AzTfExport_Managed_RG_Report.pdf`
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
