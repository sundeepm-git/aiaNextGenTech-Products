import { z } from "zod";
import { v4 as uuidv4 } from 'uuid';
import { spawn } from 'child_process';
import { env } from "process";
import path from "path";
import fs from "fs";
import { fileURLToPath } from 'url';

// --- Job Store ---
export const exportJobs = new Map();

// Helper to get current directory in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function executeExportJob(job, server) {
  job.status = 'running';
  job.startedAt = new Date().toISOString();
  
  if (server) {
      server.sendLoggingMessage({
          level: "info",
          data: `[Job ${job.id}] Starting export logic for RG: ${job.resourceGroup}`
      });
  }

  try {
    // UPDATED PATH: python/Export-Container-AzToTerraform.py
    const scriptName = "Export-Container-AzToTerraform.py";
    const scriptPath = path.join(__dirname, "..", "python", scriptName);

    if (!fs.existsSync(scriptPath)) {
        throw new Error(`Python executor not found at: ${scriptPath}`);
    }

    console.log(`[Job ${job.id}] Spawning Python executor: ${scriptPath}`);

    const pythonCmd = process.platform === "win32" ? "python" : "python3";
    
    const pyProcess = spawn(pythonCmd, [
      scriptPath,
      "--subscription-id", job.subscriptionId,
      "--resource-group", job.resourceGroup,
      "--job-id", job.id
    ], {
        env: { ...process.env }
    });

    let resultPath = "";

    pyProcess.stdout.on('data', (data) => {
        const msg = data.toString().trim();
        if (!msg) return;

        if (msg.includes("RESULT_PATH::")) {
            resultPath = msg.split("RESULT_PATH::")[1].trim();
            console.log(`[Job ${job.id}] Result Path Captured: ${resultPath}`);
            return;
        }

        console.log(`[Job ${job.id}] ${msg}`);
        
        if (msg.includes("INFO:") || msg.includes("AZTF:")) {
             server.sendLoggingMessage({
                level: "info",
                data: `[Job ${job.id}] ${msg}`
            });
        }
    });

    pyProcess.stderr.on('data', (data) => {
        const msg = data.toString().trim();
        if (!msg) return;
        console.error(`[Job ${job.id}] ERR: ${msg}`);
        server.sendLoggingMessage({ level: "warning", data: msg });
    });

    pyProcess.on('close', (code) => {
        job.completedAt = new Date().toISOString();
        
        if (code === 0) {
            job.status = 'completed';
            job.result = {
                message: "Export completed successfully.",
                localPath: resultPath
            };

            server.sendLoggingMessage({
                level: "info",
                data: `[Job ${job.id}] Success! Files generated at: ${resultPath}`
            });
        } else {
            job.status = 'failed';
            job.error = `Executor exited with code ${code}`;
            server.sendLoggingMessage({
                level: "error",
                data: `[Job ${job.id}] Export Failed (Exit Code: ${code})`
            });
        }
    });

  } catch (error) {
    console.error(`[Job ${job.id}] Launch Error:`, error);
    job.status = 'failed';
    job.error = error.message;
  }
}

export const aztfexportTool = {
  name: "export_azure_terraform",
  description: "Exports an Azure Resource Group to Terraform HCL using a Python wrapper.",
  inputSchema: z.object({
    subscriptionId: z.string().describe("Azure Subscription ID"),
    resourceGroup: z.string().describe("Azure Resource Group Name"),
  }),
  handler: async (args, server) => {
    const { subscriptionId, resourceGroup } = args;
    const jobId = uuidv4();
    const job = {
        id: jobId,
        subscriptionId,
        resourceGroup,
        status: 'queued',
        createdAt: new Date().toISOString()
    };
    exportJobs.set(jobId, job);
    executeExportJob(job, server);

    return {
      content: [
        {
          type: "text",
          text: `Job Started.\nID: ${jobId}\nTarget: ${resourceGroup}\n\nCheck logs for progress.`
        }
      ]
    };
  }
};