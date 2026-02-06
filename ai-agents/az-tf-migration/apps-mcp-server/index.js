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
    version: "1.0.0"
});

// --- TOOL REGISTRATION ---
// Log environment details only in HTTP/SSE mode (not STDIO mode)
if(!isStdioMode) {
    console.error(`[Environment] Node Version: ${process.version}`);
    console.error(`[Environment] Platform: ${process.platform}`);
    console.error(`[Environment] CWD: ${process.cwd()}`);
    console.error(`[Environment] __dirname: ${__dirname}`);
}

import { assessmentToolDefinition, assessmentToolHandler, initializeBlobStorage, executeAssessmentJob } from './tools/assessment.js';
import { aztfexportToolDefinition, aztfexportToolHandler, executeExportJob as executeAzTfExportJob } from './tools/aztfexport.js';
import { refactorToolDefinition, refactorToolHandler, executeRefactorJob } from './tools/code-refactor.js';

// Log tool registration only in HTTP/SSE mode
if(!isStdioMode) {
    console.error(`[Tool Registration] Assessment: ${assessmentToolDefinition?.name || 'MISSING'}`);
    console.error(`[Tool Registration] Export: ${aztfexportToolDefinition?.name || 'MISSING'}`);
    console.error(`[Tool Registration] Refactor: ${refactorToolDefinition?.name || 'MISSING'}`);
    console.error(`[Tool Import] All tools imported successfully`);
}

const blobStorageInfo = await initializeBlobStorage(isStdioMode);

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

async function executeExportJobWrapper(job, progressCallback) {
    await executeAzTfExportJob(job, __dirname, progressCallback);
}

async function executeRefactorJobWrapper(job, progressCallback) {
    await executeRefactorJob(job, __dirname, progressCallback);
}

const toolContext = { 
    jobs: new Map(), 
    blobStorageInfo,
    executeJob: executeJobWrapper,
    executeExportJob: executeExportJobWrapper,
    executeRefactorJob: executeRefactorJobWrapper
};

server.tool(assessmentToolDefinition.name, assessmentToolDefinition.schema, (p) => assessmentToolHandler(p, toolContext));
if(!isStdioMode) console.error(`[Server] ✓ Registered: ${assessmentToolDefinition.name}`);

server.tool(aztfexportToolDefinition.name, aztfexportToolDefinition.schema, (p) => aztfexportToolHandler(p, toolContext));
if(!isStdioMode) console.error(`[Server] ✓ Registered: ${aztfexportToolDefinition.name}`);

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
        version: "1.0.0",
        timestamp: new Date().toISOString(),
        tools: [
            assessmentToolDefinition.name,
            aztfexportToolDefinition.name,
            refactorToolDefinition.name
        ],
        toolsCount: 3
    });
});

// Tools list endpoint for debugging
app.get("/tools", (req, res) => {
    const psDir = path.resolve(__dirname, 'ps');
    const pythonDir = path.resolve(__dirname, 'python');
    
    res.status(200).json({
        registered_tools: [
            {
                name: assessmentToolDefinition.name,
                description: assessmentToolDefinition.schema.description
            },
            {
                name: aztfexportToolDefinition.name,
                description: aztfexportToolDefinition.schema.description
            },
            {
                name: refactorToolDefinition.name,
                description: refactorToolDefinition.schema.description
            }
        ],
        blob_storage: blobStorageInfo ? "initialized" : "not initialized",
        local_report_dir: localReportDir,
        filesystem_check: {
            ps_dir_exists: fs.existsSync(psDir),
            ps_dir_path: psDir,
            python_dir_exists: fs.existsSync(pythonDir),
            python_dir_path: pythonDir,
            assessment_script_exists: fs.existsSync(path.join(psDir, 'assessment-AzSubscription.ps1')),
            export_script_exists: fs.existsSync(path.join(psDir, 'Export-AzToTerraform.ps1')),
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
    app.listen(PORT, '0.0.0.0', () => {
        console.error(`\n🚀 Azure MCP Server running on http://127.0.0.1:${PORT}`);
        console.error(`🔗 SSE URL: http://127.0.0.1:${PORT}/sse`);
    });
}