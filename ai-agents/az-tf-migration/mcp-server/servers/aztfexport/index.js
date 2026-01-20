import express from "express";
import dotenv from "dotenv";
dotenv.config();

const app = express();
app.use(express.json({ limit: "1mb" }));

// MCP discovery endpoint
app.get("/aztfexport/mcp", (_req, res) => {
  res.json({
    tools: [
      {
        name: "run-export",
        inputSchema: { type: "object" },
        outputSchema: { type: "object" }
      },
      {
        name: "generate-tf",
        inputSchema: { type: "object" },
        outputSchema: { type: "object" }
      },
      {
        name: "post-process",
        inputSchema: { type: "object" },
        outputSchema: { type: "object" }
      }
    ]
  });
});

// Example tool endpoints
app.post("/tools/run-export", (req, res) => {
  res.json({ status: "completed", message: "Export run" });
});
app.post("/tools/generate-tf", (req, res) => {
  res.json({ status: "completed", message: "Terraform generated" });
});
app.post("/tools/post-process", (req, res) => {
  res.json({ status: "completed", message: "Post-processing done" });
});

app.get("/healthz", (_req, res) => res.json({ status: "ok" }));

const PORT = process.env.AZTFEXPORT_PORT || 4003;
app.listen(PORT, () => {
  console.log(`AZTF Export MCP server listening on http://localhost:${PORT}`);
});