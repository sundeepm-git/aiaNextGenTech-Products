import express from "express";
import dotenv from "dotenv";
dotenv.config();

const app = express();
app.use(express.json({ limit: "1mb" }));

// MCP discovery endpoint
app.get("/orchestrator/mcp", (_req, res) => {
  res.json({
    tools: [
      {
        name: "run-orchestration",
        inputSchema: { type: "object" },
        outputSchema: { type: "object" }
      },
      {
        name: "start-pipeline",
        inputSchema: { type: "object" },
        outputSchema: { type: "object" }
      }
    ]
  });
});

// Example tool endpoint
app.post("/tools/run-orchestration", (req, res) => {
  // Placeholder logic
  res.json({ status: "completed", message: "Orchestration run" });
});

app.post("/tools/start-pipeline", (req, res) => {
  // Placeholder logic
  res.json({ status: "completed", message: "Pipeline started" });
});

app.get("/healthz", (_req, res) => res.json({ status: "ok" }));

const PORT = process.env.ORCHESTRATOR_PORT || 4001;
app.listen(PORT, () => {
  console.log(`Orchestrator MCP server listening on http://localhost:${PORT}`);
});