import { z } from "zod";
import { v4 as uuidv4 } from 'uuid';
import { AssessmentJob } from './assessment.js';
import { spawn } from 'child_process';
import { env } from "process";
import path from "path";
import fs from "fs";

/**
 * AzTFExport Tool - Export Azure Resources to Terraform
 * 
 * This tool exports existing Azure resources to Terraform configuration files
 * using the Export-AzToTerraform.ps1 PowerShell script.
 * Exported files are stored in Azure Storage Account under 'aztfExport' folder.
 */

// --- EXPORT JOB EXECUTION ---
export async function executeExportJob(job, __dirname, progressCallback = null) {
  job.status = 'running';
  job.startedAt = new Date().toISOString();
  
  try {
    const scriptPath = env.EXPORT_SCRIPT_PATH || './ps/Export-AzToTerraform.ps1';

    // Resolve and sanitize script path
    const normalizeSep = (p) => p.replace(/\\/g, '/');
    const sanitizePsPs = (p) => p.replace(/\/ps\/+ps\//g, '/ps/');

    const candidates = [
      scriptPath,
      sanitizePsPs(scriptPath),
      path.resolve(__dirname, scriptPath),
      sanitizePsPs(path.resolve(__dirname, scriptPath)),
      path.resolve('/app', scriptPath),
      sanitizePsPs(path.resolve('/app', scriptPath))
    ].map(normalizeSep);

    let resolvedScript = candidates.find(p => fs.existsSync(p));
    if (!resolvedScript) resolvedScript = normalizeSep(scriptPath);

    // Build PowerShell arguments
    let psArgs = [
      '-NoProfile', 
      '-ExecutionPolicy', 
      'Bypass', 
      '-File', 
      resolvedScript, 
      '-SubscriptionId', 
      job.subscriptionId,
      '-ResourceGroupName',
      job.resourceGroup
    ];

    // Storage account will be read from .env file by the PowerShell script
    // No need to pass it as a parameter - the script loads it from environment variables

    const psExecutable = "pwsh";

    console.error(`[Export Job ${job.id}] Starting PowerShell: ${psExecutable} ${psArgs.join(' ')}`);

    await new Promise((resolve, reject) => {
      // Spawn PowerShell process with environment variables (including storageAccount from .env)
      const ps = spawn(psExecutable, psArgs, {
        env: {
          ...process.env  // Inherit all environment variables including storageAccount from .env
        }
      });
      
      ps.stdout.on('data', (data) => {
        job.stdout += data.toString();
        const output = data.toString();
        // Log full output for debugging
        console.error(`[Export Job ${job.id}] stdout: ${output}`);
        
        // Send real-time progress to frontend via callback
        if (progressCallback) {
          progressCallback({
            type: 'stdout',
            message: output,
            timestamp: new Date().toISOString(),
            jobId: job.id
          });
        }
      });
      
      ps.stderr.on('data', (data) => { 
        job.stderr += data.toString();
        const error = data.toString();
        // Log full stderr for debugging
        console.error(`[Export Job ${job.id}] stderr: ${error}`);
        
        // Send real-time errors to frontend via callback
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
        console.error(`[Export Job ${job.id}] PowerShell still running (${elapsed}s)`);
      }, 60000);

      ps.on('close', async (code) => {
        clearInterval(diag);
        
        if (code === 0) {
          console.error(`[Export Job ${job.id}] PowerShell completed successfully`);
          
          // The Export-AzToTerraform.ps1 script stores files in Azure Storage
          // under aztfExport/{SubscriptionId}/{ResourceGroupName}/ folder
          const storageAccountName = env.storageAccount?.trim().replace(/\s*=\s*/g, '').trim();
          if (storageAccountName) {
            const exportPath = `https://${storageAccountName}.blob.core.windows.net/aztfExport/${job.subscriptionId}/${job.resourceGroup}/`;
            job.reportUrl = exportPath;
            job.reportFileName = 'Terraform Export';
            console.error(`[Export Job ${job.id}] ✅ Terraform files exported to: ${exportPath}`);
          } else {
            job.reportUrl = `Exported to storage account aztfExport/${job.subscriptionId}/${job.resourceGroup}/`;
            console.error(`[Export Job ${job.id}] ✅ Export completed`);
          }

          job.status = 'completed';
          job.completedAt = new Date().toISOString();
          resolve();
        } else {
          const errorMsg = job.stderr || job.stdout || `PowerShell exited with code ${code}`;
          job.status = 'failed';
          job.error = errorMsg;
          job.completedAt = new Date().toISOString();
          console.error(`[Export Job ${job.id}] Failed: ${errorMsg}`);
          reject(new Error(errorMsg));
        }
      });

      ps.on('error', (err) => {
        clearInterval(diag);
        console.error(`[Export Job ${job.id}] Spawn error: ${err.message}`);
        reject(err);
      });
    });

  } catch (error) {
    job.status = 'failed';
    job.error = error.message;
    job.completedAt = new Date().toISOString();
    console.error(`[Export Job ${job.id}] Execution failed: ${error.message}`);
  }
}

export const aztfexportToolDefinition = {
  name: "export_azure_to_terraform",
  description: "Export existing Azure Resource Group to Terraform configuration files. Exports are stored in Azure Storage Account under 'aztfexport' folder. Returns a Job ID for tracking the export process.",
  schema: {
    subscriptionId: z.string().describe("The Azure Subscription ID containing the resources to export"),
    resourceGroup: z.string().describe("The Resource Group name to export")
  }
};

export async function aztfexportToolHandler({ subscriptionId, resourceGroup }, context) {
  // Input validation
  if (!subscriptionId || typeof subscriptionId !== 'string' || subscriptionId.trim() === '') {
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Error: 'subscriptionId' is required and must be a non-empty string.`
      }]
    };
  }
  if (!resourceGroup || typeof resourceGroup !== 'string' || resourceGroup.trim() === '') {
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Error: 'resourceGroup' is required and must be a non-empty string.`
      }]
    };
  }
  const { jobs, executeExportJob, blobStorageInfo } = context;

  try {
    const jobId = uuidv4();
    
    // Create a job with export-specific properties
    const job = new AssessmentJob(jobId, subscriptionId, resourceGroup);
    job.jobType = 'export';
    
    jobs.set(jobId, job);

    console.error(`[Export Job ${jobId}] Created for subscription: ${subscriptionId}`);
    console.error(`[Export Job ${jobId}] Targeting Resource Group: ${resourceGroup}`);

    // Execute export job asynchronously (fire-and-forget) to avoid MCP timeout
    // Progress callback that sends updates to all connected SSE clients
    const progressCallback = (progressData) => {
      if (job.progressCallbacks && job.progressCallbacks.length > 0) {
        job.progressCallbacks.forEach(callback => {
          try {
            callback(progressData);
          } catch (error) {
            console.error(`[Export Job ${jobId}] Error in progress callback:`, error.message);
          }
        });
      }
    };
    
    // Start the job asynchronously - DO NOT await
    executeExportJob(job, progressCallback).catch(err => {
      console.error(`[Export Job ${jobId}] Async execution error: ${err.message}`);
      job.status = 'failed';
      job.error = err.message;
      job.completedAt = new Date().toISOString();
    });
    
    // Return immediately with job ID (job runs in background)
    let storageMsg = '';
    if (blobStorageInfo.available) {
      storageMsg = `\n\n📦 Storage: Terraform files will be exported to '${blobStorageInfo.accountName}/aztfexport/${subscriptionId}/${resourceGroup}/'`;
    }
    
    return {
      content: [{
        type: "text",
        text: `🚀 Export job started!\n\nJob ID: ${jobId}\nSubscription: ${subscriptionId}\nResource Group: ${resourceGroup}\nStatus: ${job.status}${storageMsg}\n\n⏳ The export is running in the background. This may take several minutes depending on the number of resources.\n\n💡 Check the terminal/logs for real-time progress updates.`
      }]
    };
  } catch (error) {
    console.error(`[Export Tool Error] ${error.message}`);
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Error starting export job: ${error.message}`
      }]
    };
  }
}
