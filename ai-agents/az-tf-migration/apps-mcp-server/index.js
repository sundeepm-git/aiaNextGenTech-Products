import { config } from 'dotenv';
import express from "express";
import cors from "cors";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";

// --- CONFIG ---
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
config({ path: path.join(__dirname, '.env') });

// Only enable STDIO mode if explicitly requested via env or flag
// STDIO mode is only enabled if explicitly requested via the STDIO_MODE env variable or --stdio flag.
// In Azure Container Apps, this will default to HTTP/SSE mode and always start the Express server.
const isStdioMode = process.env.STDIO_MODE === 'true' || process.argv.includes('--stdio');
const PORT = process.env.PORT || 3000;

// --- MCP SERVER ---
const server = new McpServer({
    name: "Azure-Terraform-Migration-Server",
    version: "2.1.0"
});

// --- TOOL REGISTRATION ---
// Log environment details only in HTTP/SSE mode (not STDIO mode)
if(!isStdioMode) {
    console.error(`[Environment] Node Version: ${process.version}`);
    console.error(`[Environment] Platform: ${process.platform}`);
    console.error(`[Environment] CWD: ${process.cwd()}`);
    console.error(`[Environment] __dirname: ${__dirname}`);
}

import { executeAssessmentJob, assessmentToolDefinition, assessmentToolHandler } from './tools/assessment.js';
// Import the new Python tool wrapper
import { aztfexportTool, exportJobs } from './tools/aztfexport.js';
import { refactorToolDefinition, refactorToolHandler, executeRefactorJob } from './tools/code-refactor.js';

// Log tool registration only in HTTP/SSE mode
if(!isStdioMode) {
    console.error(`[Tool Registration] Assessment: ${assessmentToolDefinition?.name || 'MISSING'}`);
    console.error(`[Tool Registration] Export: ${aztfexportTool?.name || 'MISSING'}`);
    console.error(`[Tool Registration] Refactor: ${refactorToolDefinition?.name || 'MISSING'}`);
    console.error(`[Tool Import] All tools imported successfully`);
}

// Blob storage initialization is handled by Python. Stub for Node.js context:
const blobStorageInfo = { available: false };

// --- REPORT DIRECTORY DETECTION ---
const reportDirCandidates = [
  path.resolve(__dirname, 'ps', 'report'),
  path.resolve(__dirname, 'report'),
  path.resolve('/app', 'ps', 'report'),
  path.resolve('/app', 'report')
];

let localReportDir = reportDirCandidates.find(d => {
  try { 
    if (!fs.existsSync(d)) {
      fs.mkdirSync(d, { recursive: true });
    }
    return fs.statSync(d).isDirectory(); 
  } catch (e) { 
    return false; 
  }
});

if (!localReportDir) {
  localReportDir = path.resolve(__dirname, 'ps', 'report');
  try { fs.mkdirSync(localReportDir, { recursive: true }); } catch (e) {}
}
if(!isStdioMode) console.error(`[Local Report Dir] Using: ${localReportDir}`);

// Wrapper Functions
async function executeJobWrapper(job) {
    await executeAssessmentJob(job, localReportDir, __dirname);
}

const toolContext = { 
    jobs: new Map(), 
    blobStorageInfo,
    executeJob: executeJobWrapper,
    executeRefactorJob, // Make available to refactorToolHandler
    __dirname, // Pass ES module __dirname for refactor tool
    // Note: Export tool handles its own jobs internally via exportJobs map in aztfexport.js
};

// Added the description argument and ensured we pass the correct schema object
server.tool(
    assessmentToolDefinition.name,
    assessmentToolDefinition.description,
    assessmentToolDefinition.inputSchema.shape, // .shape is required for the Inspector to see Zod fields
    (params) => assessmentToolHandler(params, toolContext)
);

if(!isStdioMode) console.error(`[Server] ✓ Registered: ${assessmentToolDefinition.name}`);

// 2. Register Export Tool (Python Version)
server.tool(
    aztfexportTool.name,
    aztfexportTool.description,
    aztfexportTool.inputSchema.shape,
    (args) => aztfexportTool.handler(args, server)
);
if(!isStdioMode) console.error(`[Server] ✓ Registered: ${aztfexportTool.name}`);

// 3. Register Refactor Tool
server.tool(refactorToolDefinition.name, refactorToolDefinition.schema, (p) => refactorToolHandler(p, toolContext));
if(!isStdioMode) console.error(`[Server] ✓ Registered: ${refactorToolDefinition.name}`);

if(!isStdioMode) {
    console.error(`[Server] Registered tools: ${server.listTools ? 'listTools available' : 'listTools NOT available'}`);
    console.error(`[Server] Total tools registered: 3`);
    console.error(`[Server] Tool registration complete ✓`);
}

// --- APP SETUP ---
const app = express();

// 1. MUST use broad CORS for Browser Inspector
app.use(cors({
    origin: "*",
    methods: ["GET", "POST", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"]
}));

// 2. DO NOT use app.use(express.json()) globally. 
// It drains the stream and causes "Stream not readable".

let activeSseTransport = null;

// --- ENDPOINTS ---

// Health endpoint
app.get("/health", (req, res) => {
    res.status(200).json({ 
        status: "healthy",
        server: "Azure-Terraform-Migration-Server",
        version: "2.1.0",
        timestamp: new Date().toISOString(),
        tools: [
            assessmentToolDefinition.name,
            aztfexportTool.name, // FIXED: Now referencing the correct imported object
            refactorToolDefinition.name
        ],
        toolsCount: 3
    });
});

// Job status endpoint for polling (checks assessment/refactor jobs AND export jobs)
app.get("/jobs/:jobId", (req, res) => {
    const { jobId } = req.params;
    // Check both toolContext.jobs (assessment/refactor) and exportJobs (export)
    const job = toolContext.jobs.get(jobId) || exportJobs.get(jobId);
    
    if (!job) {
        return res.status(404).json({ error: "Job not found" });
    }
    
    res.status(200).json({
        jobId: job.id,
        jobType: job.jobType || 'assessment',
        status: job.status,
        subscriptionId: job.subscriptionId,
        resourceGroup: job.resourceGroup,
        createdAt: job.createdAt,
        startedAt: job.startedAt,
        completedAt: job.completedAt,
        reportUrl: job.reportUrl,
        reportFileName: job.reportFileName,
        error: job.error,
        stdout: job.stdout?.substring(0, 1000),  // Truncate for response size
        stderr: job.stderr?.substring(0, 1000)
    });
});

// Tools list endpoint for debugging
// --- Replace your app.get("/tools", ...) with this ---
app.get("/tools", (req, res) => {
    const pythonDir = path.resolve(__dirname, 'python');
    
    // Safely build the tool list to avoid "undefined" property crashes
    const toolsList = [
        {
            name: assessmentToolDefinition?.name || "azure_assessment",
            description: assessmentToolDefinition?.description || "Azure Assessment Tool"
        },
        {
            name: aztfexportTool?.name || "export_azure_terraform",
            description: aztfexportTool?.description || "Terraform Export Tool"
        },
        {
            name: refactorToolDefinition?.name || "refactor_terraform_code",
            description: refactorToolDefinition?.description || "Terraform Refactor Tool"
        }
    ];

    res.status(200).json({
        registered_tools: toolsList,
        blob_storage: blobStorageInfo ? "initialized" : "not initialized",
        local_report_dir: localReportDir || "/app/ps/report",
        filesystem_check: {
            // FIX: Removed reference to undefined 'psDir' to stop the crash
            python_dir_exists: fs.existsSync(pythonDir),
            python_dir_path: pythonDir,
            assessment_script_exists: fs.existsSync(path.join(pythonDir, 'assessment-AzSubscription.py')),
            export_script_exists: fs.existsSync(path.join(pythonDir, 'Export-Container-AzToTerraform.py')),
            refactor_script_exists: fs.existsSync(path.join(pythonDir, 'refactor.py'))
        },
        environment: {
            node_version: process.version,
            platform: process.platform,
            cwd: process.cwd(),
            dirname: __dirname
        }
    });
});

app.get("/sse", async (req, res) => {
    console.error(`[${new Date().toISOString()}] SSE connection attempt`);
    
    const transport = new SSEServerTransport("/messages", res);
    activeSseTransport = transport;

    try {
        await server.connect(transport);
        console.error(`[${new Date().toISOString()}] SSE connected`);

        req.on("close", () => {
            if (activeSseTransport === transport) activeSseTransport = null;
            console.error(`[${new Date().toISOString()}] SSE closed`);
        });
    } catch (err) {
        console.error("SSE Error:", err);
    }
});

// 3. Let the SDK handle the stream parsing directly
app.post("/messages", async (req, res) => {
    if (!activeSseTransport) {
        return res.status(503).send("No active SSE session");
    }

    try {
        // We do NOT use express.json() here. 
        // handlePostMessage will read the raw request stream.
        await activeSseTransport.handlePostMessage(req, res);
    } catch (err) {
        console.error("Message Error:", err);
        if (!res.headersSent) res.status(400).send(err.message);
    }
});

// --- START ---
// In Azure Container Apps, STDIO mode should NOT be enabled. The Express server will always start.
if (isStdioMode) {
    // STDIO mode: used for local CLI/pipe integration only
    console.error("[Startup Mode] STDIO mode enabled (local CLI/pipe)");
    server.connect(new StdioServerTransport());
} else {
    // HTTP/SSE mode: used for Azure Container Apps and local web server
    console.error("[Startup Mode] HTTP/SSE mode enabled (Azure Container App or local web)");
    // Detect public hostname: Azure Container Apps sets CONTAINER_APP_HOSTNAME automatically
    const containerHost = process.env.CONTAINER_APP_HOSTNAME || process.env.PUBLIC_HOST || process.env.WEBSITE_HOSTNAME;
    if (containerHost) {
        console.error(`\n🚀 Azure MCP Server running on https://${containerHost}`);
        console.error(`🔗 SSE URL: https://${containerHost}/sse`);
    } else {
        console.error(`\n🚀 Azure MCP Server running on http://localhost:${PORT}`);
        console.error(`🔗 SSE URL: http://localhost:${PORT}/sse`);
    }
    app.listen(PORT, '0.0.0.0');
}