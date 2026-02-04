import { config } from 'dotenv';
import express from "express";
import cors from "cors";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";

// Load .env from script directory (not CWD)
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
config({ path: path.join(__dirname, '.env') });

// Import modular tool definitions
import { 
  assessmentToolDefinition, 
  assessmentToolHandler, 
  AssessmentJob,
  initializeBlobStorage,
  executeAssessmentJob
} from './tools/assessment.js';
import { 
  aztfexportToolDefinition, 
  aztfexportToolHandler,
  executeExportJob as executeAzTfExportJob 
} from './tools/aztfexport.js';
import { refactorToolDefinition, refactorToolHandler } from './tools/code-refactor.js';

const app = express();

// --- GLOBAL CORS (required for MCP Inspector) ---
app.use(cors({
  origin: "*",
  methods: ["GET", "POST"],
  allowedHeaders: ["Content-Type", "Authorization"]
}));

// --- EXTENDED TIMEOUT FOR LONG-RUNNING OPERATIONS ---
// Azure exports can take significant time for large resource groups
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// --- JOB STORE (In-Memory for production, consider Redis/DB for multi-instance) ---
const jobs = new Map();

// --- AZURE BLOB STORAGE INITIALIZATION ---
const blobStorageInfo = await initializeBlobStorage();

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
  // Fallback: create first candidate
  localReportDir = reportDirCandidates[0];
  fs.mkdirSync(localReportDir, { recursive: true });
}

console.error(`[Local Report Dir] Using: ${localReportDir}`);

// --- STATIC REPORTS ENDPOINT (fallback for local files) ---
app.use('/reports', express.static(localReportDir, { index: false }));

// --- JOB EXECUTION WRAPPERS ---

// Assessment Job Execution Wrapper
async function executeJob(job) {
  await executeAssessmentJob(job, localReportDir, __dirname);
}

// Export Job Execution Wrapper
async function executeExportJob(job, progressCallback = null) {
  await executeAzTfExportJob(job, __dirname, progressCallback);
}

// Refactor Job Execution (Integrated with Python script)
async function executeRefactorJob(job, progressCallback = null) {
  job.status = 'running';
  job.startedAt = new Date().toISOString();
  
  try {
    console.error(`[Refactor Job ${job.id}] Starting refactor process...`);
    console.error(`[Refactor Job ${job.id}] Subscription: ${job.subscriptionId}`);
    console.error(`[Refactor Job ${job.id}] Resource Group: ${job.resourceGroup}`);
    console.error(`[Refactor Job ${job.id}] Options: ${JSON.stringify(job.refactorOptions)}`);
    
    // Resolve Python script path
    const refactorScript = env.REFACTOR_SCRIPT_PATH || './python/refactor.py';
    const normalizeSep = (p) => p.replace(/\\/g, '/');
    const candidates = [
      refactorScript,
      path.resolve(__dirname, refactorScript),
      path.resolve('/app', refactorScript)
    ].map(normalizeSep);

    let resolvedScript = candidates.find(p => fs.existsSync(p));
    if (!resolvedScript) resolvedScript = normalizeSep(refactorScript);

    // Determine Python executable (try python3 first, fallback to python)
    const pythonExecutable = process.platform === 'win32' ? 'python' : 'python3';
    
    // Build Python arguments
    const pythonArgs = [
      resolvedScript,
      job.subscriptionId,
      job.resourceGroup
    ];

    // Add optional arguments based on refactor options
    if (job.refactorOptions?.verbose) {
      pythonArgs.push('--verbose');
    }
    if (job.refactorOptions?.dryRun) {
      pythonArgs.push('--dry-run');
    }

    console.error(`[Refactor Job ${job.id}] Executing: ${pythonExecutable} ${pythonArgs.join(' ')}`);

    await new Promise((resolve, reject) => {
      const python = spawn(pythonExecutable, pythonArgs, {
        env: {
          ...process.env,
          storageAccount: env.storageAccount?.trim().replace(/\s*=\s*/g, '').trim()
        }
      });
      
      python.stdout.on('data', (data) => { 
        job.stdout += data.toString();
        const output = data.toString();
        console.error(`[Refactor Job ${job.id}] stdout: ${output}`);
        
        // Send real-time progress
        if (progressCallback) {
          progressCallback({
            type: 'stdout',
            message: output,
            timestamp: new Date().toISOString(),
            jobId: job.id
          });
        }
      });
      
      python.stderr.on('data', (data) => { 
        job.stderr += data.toString();
        const error = data.toString();
        console.error(`[Refactor Job ${job.id}] stderr: ${error}`);
        
        // Send real-time errors
        if (progressCallback) {
          progressCallback({
            type: 'stderr',
            message: error,
            timestamp: new Date().toISOString(),
            jobId: job.id
          });
        }
      });

      const startTs = Date.now();
      const diag = setInterval(() => {
        const elapsed = Math.floor((Date.now() - startTs) / 1000);
        console.error(`[Refactor Job ${job.id}] Python still running (${elapsed}s)`);
      }, 60000);

      python.on('close', async (code) => {
        clearInterval(diag);
        
        if (code === 0) {
          console.error(`[Refactor Job ${job.id}] Python refactor completed successfully`);
          
          // Generate report URL for refactored code
          const storageAccountName = env.storageAccount?.trim().replace(/\s*=\s*/g, '').trim();
          if (storageAccountName) {
            const refactorPath = `https://${storageAccountName}.blob.core.windows.net/code-refactored/${job.subscriptionId}/${job.resourceGroup}/`;
            job.reportUrl = refactorPath;
            job.reportFileName = 'Refactored Terraform Code';
            console.error(`[Refactor Job ${job.id}] ✅ Refactored code uploaded to: ${refactorPath}`);
          } else {
            job.reportUrl = `Refactored code stored in code-refactored/${job.subscriptionId}/${job.resourceGroup}/`;
            console.error(`[Refactor Job ${job.id}] ✅ Refactoring completed`);
          }

          job.status = 'completed';
          job.completedAt = new Date().toISOString();
          
          // Cleanup progress callbacks
          if (job.progressCallbacks) {
            job.progressCallbacks = [];
          }
          
          resolve();
        } else {
          const errorMsg = job.stderr || job.stdout || `Python exited with code ${code}`;
          job.status = 'failed';
          job.error = errorMsg;
          job.completedAt = new Date().toISOString();
          console.error(`[Refactor Job ${job.id}] Failed: ${errorMsg}`);
          
          // Cleanup progress callbacks
          if (job.progressCallbacks) {
            job.progressCallbacks = [];
          }
          
          reject(new Error(errorMsg));
        }
      });

      python.on('error', (err) => {
        clearInterval(diag);
        console.error(`[Refactor Job ${job.id}] Spawn error: ${err.message}`);
        reject(err);
      });
    });
    
  } catch (error) {
    job.status = 'failed';
    job.error = error.message;
    job.completedAt = new Date().toISOString();
    console.error(`[Refactor Job ${job.id}] Execution failed: ${error.message}`);
    
    // Cleanup progress callbacks on error
    if (job.progressCallbacks) {
      job.progressCallbacks = [];
    }
  }
}

// --- MCP SERVER SETUP ---
const server = new McpServer({
  name: "Azure-Terraform-MCP-Server",
  version: "2.0.1",
  capabilities: {
    tools: {}
  }
});

// Set extended timeout for long-running operations (3 hours in milliseconds)
// Azure exports can take significant time for large resource groups
const EXTENDED_TIMEOUT = 3 * 60 * 60 * 1000; // 3 hours

// --- SHARED CONTEXT FOR TOOL HANDLERS ---
const toolContext = {
  jobs,
  executeJob,
  executeExportJob,
  executeRefactorJob,
  blobStorageInfo
};

// --- TOOL REGISTRATION (Modular Pattern) ---

// 1. Assessment Tool
server.tool(
  assessmentToolDefinition.name,
  assessmentToolDefinition.schema,
  async (params) => assessmentToolHandler(params, toolContext)
);

// 2. AzTFExport Tool (placeholder execution logic)
server.tool(
  aztfexportToolDefinition.name,
  aztfexportToolDefinition.schema,
  async (params) => aztfexportToolHandler(params, toolContext)
);

// 3. Refactor Tool (fully implemented with Python integration)
server.tool(
  refactorToolDefinition.name,
  refactorToolDefinition.schema,
  async (params) => refactorToolHandler(params, toolContext)
);

// --- JOB STATUS API ---
app.get("/jobs/:id", (req, res) => {
  const job = jobs.get(req.params.id);
  
  if (!job) {
    return res.status(404).json({ error: "Job not found" });
  }

  const jobData = job.toJSON();
  
  // Add consolidated message based on job type and status
  const jobType = job.jobType || 'assessment';
  const resourceDesc = `subscription ${job.subscriptionId}, resource group '${job.resourceGroup}'`;
  
  if (job.status === 'completed' && job.reportUrl) {
    const isAzureBlob = job.reportUrl.includes('.blob.core.windows.net');
    
    if (jobType === 'export') {
      jobData.message = {
        status: "SUCCESS",
        summary: `Export completed successfully for ${resourceDesc}`,
        reportLocation: isAzureBlob ? "Azure Blob Storage" : "Local Server",
        reportUrl: job.reportUrl,
        instructions: isAzureBlob 
          ? `✓ Terraform files exported to Azure Storage\n✓ Access at: ${job.reportUrl}\n✓ Container: aztfexport/${job.subscriptionId}/${job.resourceGroup}/`
          : `✓ Export completed: ${job.reportUrl}`
      };
    } else if (jobType === 'refactor') {
      jobData.message = {
        status: "SUCCESS",
        summary: `Refactoring completed successfully for ${resourceDesc}`,
        reportLocation: isAzureBlob ? "Azure Blob Storage" : "Local Server",
        reportUrl: job.reportUrl,
        instructions: isAzureBlob 
          ? `✓ Refactored files uploaded to Azure Storage\n✓ Access at: ${job.reportUrl}\n✓ Container: code-refactored/${job.subscriptionId}/${job.resourceGroup}/`
          : `✓ Refactoring completed: ${job.reportUrl}`
      };
    } else {
      jobData.message = {
        status: "SUCCESS",
        summary: `Assessment completed successfully for ${resourceDesc}`,
        reportLocation: isAzureBlob ? "Azure Blob Storage" : "Local Server",
        reportUrl: job.reportUrl,
        instructions: isAzureBlob 
          ? `✓ Report uploaded to Azure Storage\n✓ Access the report at: ${job.reportUrl}\n✓ The SAS URL is valid for 7 days\n✓ Check Azure Portal > Storage Account > ${blobStorageInfo.accountName} > Container: ${blobStorageInfo.containerName} > ${job.subscriptionId}/`
          : `⚠ Report available on local server (Blob Storage upload failed)\n✓ Access the report at: ${job.reportUrl}`
      };
    }
  } else if (job.status === 'failed') {
    const errorText = job.error || "Unknown error occurred";
    const actionType = jobType === 'export' ? 'Export' : jobType === 'refactor' ? 'Refactoring' : 'Assessment';
    
    jobData.message = {
      status: "FAILED",
      summary: `${actionType} failed for ${resourceDesc}`,
      error: errorText,
      instructions: errorText.includes('aztfexport') && errorText.includes('not found')
        ? "❌ Required tool 'aztfexport' is not installed.\n\nInstall it using:\n  Windows: winget install aztfexport\n  macOS: brew install aztfexport\n  Linux: Download from https://github.com/Azure/aztfexport/releases\n\nThen restart the MCP server."
        : errorText.includes('python') && errorText.includes('not found')
        ? "❌ Python is not installed or not in PATH.\n\nInstall Python 3.8+ and ensure it's in your system PATH.\n\nThen restart the MCP server."
        : `Check the error details and retry the ${actionType.toLowerCase()}`
    };
  } else if (job.status === 'running') {
    const actionType = jobType === 'export' ? 'Export' : jobType === 'refactor' ? 'Refactoring' : 'Assessment';
    jobData.message = {
      status: "IN_PROGRESS",
      summary: `${actionType} in progress for ${resourceDesc}`,
      instructions: "Poll this endpoint to check for completion"
    };
  }

  res.json(jobData);
});

// --- LIST ALL JOBS ---
app.get("/jobs", (req, res) => {
  const allJobs = Array.from(jobs.values()).map(j => j.toJSON());
  res.json({ jobs: allJobs, count: allJobs.length });
});

// --- HEALTH CHECK WITH STORAGE STATUS ---
app.get("/health", (req, res) => {
  res.json({
    status: "healthy",
    serverVersion: "2.0.1",
    timestamp: new Date().toISOString(),
    blobStorage: {
      available: blobStorageInfo.available,
      accountName: blobStorageInfo.accountName,
      containerName: blobStorageInfo.containerName,
      error: blobStorageInfo.error
    },
    localReportDir: localReportDir,
    activeJobs: jobs.size
  });
});

// --- SSE TRANSPORT ---
const activeConnections = new Map();

app.get("/sse", async (req, res) => {
  const connId = Date.now();
  console.log(`[SSE ${connId}] New connection`);
  
  const transport = new SSEServerTransport("/messages", res);
  activeConnections.set(connId, transport);
  
  await server.connect(transport);
  console.log(`[SSE ${connId}] Connected`);
  
  req.on("close", () => {
    console.log(`[SSE ${connId}] Closed`);
    activeConnections.delete(connId);
  });
});

// POST endpoint - parse JSON-RPC and send to server via SSE transport
app.post("/messages", express.json(), async (req, res) => {
  console.log("[POST] Received:", req.body?.method);
  
  const transport = Array.from(activeConnections.values())[0];
  
  if (!transport) {
    console.log("[POST] No transport");
    return res.status(503).json({ 
      jsonrpc: "2.0", 
      error: { code: -32000, message: "No SSE connection" }, 
      id: req.body?.id || null 
    });
  }
  
  try {
    console.log("[POST] Calling handlePostMessage");
    // This will process and close the connection - that's the SDK bug
    // But at least the response should go through before closing
    await transport.handlePostMessage(req, res);
    console.log("[POST] Done");
  } catch (error) {
    console.error("[POST] Error:", error);
    if (!res.headersSent) {
      res.status(500).json({ 
        jsonrpc: "2.0", 
        error: { code: -32603, message: error.message }, 
        id: req.body?.id || null 
      });
    }
  }
});

app.get("/", (req, res) => {
  res.json({
    message: "Azure Terraform MCP Server",
    version: "2.0.1",
    tools: [
      {
        name: assessmentToolDefinition.name,
        description: assessmentToolDefinition.description
      },
      {
        name: aztfexportToolDefinition.name,
        description: aztfexportToolDefinition.description
      },
      {
        name: refactorToolDefinition.name,
        description: refactorToolDefinition.description
      }
    ],
    endpoints: {
      sse: "/sse",
      messages: "/messages",
      jobs: "/jobs",
      jobStatus: "/jobs/:id",
      jobProgress: "/jobs/:id/progress",
      reports: "/reports/:filename",
      health: "/health"
    }
  });
});

// --- REAL-TIME PROGRESS STREAMING ENDPOINT (SSE) ---
app.get("/jobs/:id/progress", (req, res) => {
  const jobId = req.params.id;
  const job = jobs.get(jobId);
  
  if (!job) {
    return res.status(404).json({ error: "Job not found" });
  }
  
  // Set up SSE headers
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');
  
  // Send initial connection message
  res.write(`data: ${JSON.stringify({ 
    type: 'connected', 
    jobId: jobId,
    status: job.status,
    message: 'Connected to progress stream'
  })}\n\n`);
  
  // Create progress callback for this connection
  const progressCallback = (progressData) => {
    if (res.writableEnded) return; // Don't write if connection is closed
    
    try {
      res.write(`data: ${JSON.stringify(progressData)}\n\n`);
    } catch (error) {
      console.error(`[SSE] Error sending progress for job ${jobId}:`, error.message);
    }
  };
  
  // Store the callback so the job can use it
  if (!job.progressCallbacks) {
    job.progressCallbacks = [];
  }
  job.progressCallbacks.push(progressCallback);
  
  // Send existing output if job is already running or completed
  if (job.stdout) {
    progressCallback({
      type: 'stdout',
      message: job.stdout,
      timestamp: new Date().toISOString(),
      jobId: jobId
    });
  }
  
  if (job.stderr) {
    progressCallback({
      type: 'stderr',
      message: job.stderr,
      timestamp: new Date().toISOString(),
      jobId: jobId
    });
  }
  
  // Send completion message if job is done
  if (job.status === 'completed' || job.status === 'failed') {
    progressCallback({
      type: 'complete',
      status: job.status,
      jobId: jobId,
      timestamp: new Date().toISOString(),
      completedAt: job.completedAt,
      error: job.error
    });
    
    // Close connection after sending completion
    setTimeout(() => {
      res.end();
    }, 1000);
  }
  
  // Handle client disconnect
  req.on('close', () => {
    console.error(`[SSE] Client disconnected from progress stream for job ${jobId}`);
    // Remove this callback from the job
    if (job.progressCallbacks) {
      const index = job.progressCallbacks.indexOf(progressCallback);
      if (index > -1) {
        job.progressCallbacks.splice(index, 1);
      }
    }
  });
  
  // Keep connection alive with heartbeat
  const heartbeat = setInterval(() => {
    if (res.writableEnded) {
      clearInterval(heartbeat);
      return;
    }
    res.write(`: heartbeat\n\n`);
  }, 30000);
  
  req.on('close', () => {
    clearInterval(heartbeat);
  });
});

// --- JOB CLEANUP SCHEDULER ---
// Automatically cleanup jobs older than 24 hours to prevent memory leaks
setInterval(() => {
  const oneDayAgo = Date.now() - 24 * 60 * 60 * 1000;
  let cleanedCount = 0;
  
  for (const [id, job] of jobs.entries()) {
    const jobTime = new Date(job.completedAt || job.createdAt).getTime();
    if (jobTime < oneDayAgo) {
      // Cleanup any remaining progress callbacks
      if (job.progressCallbacks) {
        job.progressCallbacks = [];
      }
      jobs.delete(id);
      cleanedCount++;
    }
  }
  
  if (cleanedCount > 0) {
    console.error(`[Job Cleanup] Removed ${cleanedCount} old job(s) (older than 24 hours)`);
  }
}, 60 * 60 * 1000); // Run every hour

// --- SERVER STARTUP ---
// Detect if running in stdio mode (Claude Desktop) vs HTTP mode (MCP Inspector)
const isStdioMode = !process.stdin.isTTY || process.argv.includes('--stdio');

if (isStdioMode) {
  // STDIO MODE - for Claude Desktop
  console.error(`[STDIO] Starting MCP server in stdio mode`);
  console.error(`Blob Storage: ${blobStorageInfo.available ? 'ENABLED' : 'DISABLED'}`);
  if (!blobStorageInfo.available) {
    console.error(`Blob Storage Error: ${blobStorageInfo.error}`);
  }
  
  const transport = new StdioServerTransport();
  server.connect(transport).catch(error => {
    console.error('[STDIO] Connection error:', error);
    process.exit(1);
  });
} else {
  // HTTP MODE - for MCP Inspector (currently has issues with SSE persistence)
  const port = process.env.PORT || 8080;
  
  const serverInstance = app.listen(port, () => {
    console.error(`[HTTP] MCP Server started successfully. Listening on: ${port}`);
    console.error(`Blob Storage: ${blobStorageInfo.available ? 'ENABLED' : 'DISABLED'}`);
    if (!blobStorageInfo.available) {
      console.error(`Blob Storage Error: ${blobStorageInfo.error}`);
    }
    console.error(`Job cleanup scheduler: ENABLED (runs every hour)`);
    console.error(`NOTE: HTTP/SSE mode may have connection persistence issues. Consider using stdio mode via Claude Desktop.`);
  });
  
  // Disable socket timeout for long-running SSE connections
  serverInstance.timeout = 0;
  serverInstance.keepAliveTimeout = 0;
}