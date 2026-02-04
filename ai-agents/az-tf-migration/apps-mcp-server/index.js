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

const isStdioMode = !process.stdin.isTTY || process.argv.includes('--stdio');
const PORT = process.env.PORT || 3000;

// --- MCP SERVER ---
const server = new McpServer({
    name: "Azure-Terraform-Migration-Server",
    version: "1.0.0"
});

// --- TOOL REGISTRATION ---
import { assessmentToolDefinition, assessmentToolHandler, initializeBlobStorage, executeAssessmentJob } from './tools/assessment.js';
import { aztfexportToolDefinition, aztfexportToolHandler, executeExportJob as executeAzTfExportJob } from './tools/aztfexport.js';
import { refactorToolDefinition, refactorToolHandler, executeRefactorJob } from './tools/code-refactor.js';

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
server.tool(aztfexportToolDefinition.name, aztfexportToolDefinition.schema, (p) => aztfexportToolHandler(p, toolContext));
server.tool(refactorToolDefinition.name, refactorToolDefinition.schema, (p) => refactorToolHandler(p, toolContext));

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
if (isStdioMode) {
    server.connect(new StdioServerTransport());
} else {
    app.listen(PORT, '0.0.0.0', () => {
        console.error(`\n🚀 Azure MCP Server running on http://127.0.0.1:${PORT}`);
        console.error(`🔗 SSE URL: http://127.0.0.1:${PORT}/sse`);
    });
}