import { z } from "zod";
import { v4 as uuidv4 } from 'uuid';
import { AssessmentJob } from './assessment.js';
import { spawn } from 'child_process';
import { env } from "process";
import path from "path";
import fs from "fs";

/**
 * Refactor Tool - Refactor Terraform Code
 * 
 * This tool analyzes and refactors Terraform code to follow best practices,
 * improve modularity, and optimize resource definitions.
 */

export const refactorToolDefinition = {
  name: "refactor_terraform_code",
  description: "Analyze and refactor Terraform code to follow best practices, improve modularity, and optimize resource definitions. Refactors the exported Terraform code for a specific subscription and resource group.",
  schema: {
    subscriptionId: z.string().describe("Azure Subscription ID containing the exported Terraform files"),
    resourceGroup: z.string().describe("Resource Group name whose Terraform files need to be refactored"),
    refactorOptions: z.object({
      verbose: z.boolean().optional().describe("Enable verbose logging"),
      dryRun: z.boolean().optional().describe("Simulate refactoring without making changes"),
      modularity: z.boolean().optional().describe("Extract reusable resources into modules"),
      variableOptimization: z.boolean().optional().describe("Optimize variable usage and naming"),
      resourceNaming: z.boolean().optional().describe("Standardize resource naming conventions"),
      securityHardening: z.boolean().optional().describe("Apply security best practices")
    }).optional().describe("Refactoring options to apply")
  }
};


// --- REFACTOR JOB EXECUTION ---
export async function executeRefactorJob(job, __dirname, progressCallback = null) {
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

export async function refactorToolHandler({ subscriptionId, resourceGroup, refactorOptions }, context) {
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
  const { jobs, executeRefactorJob, blobStorageInfo } = context;

  try {
    const jobId = uuidv4();
    
    // Create a job with refactor-specific properties
    const job = new AssessmentJob(jobId, subscriptionId, resourceGroup);
    job.jobType = 'refactor';
    job.refactorOptions = refactorOptions || {
      verbose: false,
      dryRun: false,
      modularity: true,
      variableOptimization: true,
      resourceNaming: true,
      securityHardening: true
    };
    
    jobs.set(jobId, job);

    console.error(`[Refactor Job ${jobId}] Created for subscription: ${subscriptionId}, RG: ${resourceGroup}`);
    console.error(`[Refactor Job ${jobId}] Options: ${JSON.stringify(job.refactorOptions)}`);

    // Progress callback that sends updates to all connected SSE clients
    const progressCallback = (progressData) => {
      if (job.progressCallbacks && job.progressCallbacks.length > 0) {
        job.progressCallbacks.forEach(callback => {
          try {
            callback(progressData);
          } catch (error) {
            console.error(`[Refactor Job ${jobId}] Error in progress callback:`, error.message);
          }
        });
      }
    };

    // Start refactor job execution asynchronously
    executeRefactorJob(job, progressCallback).catch(err => {
      console.error(`[Refactor Job ${jobId}] Unhandled execution error: ${err.message}`);
    });

    const host = process.env.PUBLIC_HOST || process.env.WEBSITE_HOSTNAME || 'localhost';
    const port = process.env.PORT || 8080;
    const protocol = process.env.PUBLIC_PROTOCOL || (host === 'localhost' ? 'http' : 'https');
    const portSuffix = (host === 'localhost' || host.includes('azurewebsites.net')) ? `:${port}` : '';
    const statusUrl = `${protocol}://${host}${portSuffix}/jobs/${jobId}`;

    const enabledOptions = Object.entries(job.refactorOptions)
      .filter(([_, enabled]) => enabled)
      .map(([option, _]) => option)
      .join(', ');

    let storageMsg = '';
    if (blobStorageInfo.available) {
      storageMsg = `\n\n✓ Storage: Refactored files will be uploaded to '${blobStorageInfo.accountName}/code-refactored/'`;
    }

    return {
      content: [{
        type: "text",
        text: `Refactor job started successfully!\n\nJob ID: ${jobId}\nSubscription: ${subscriptionId}\nResource Group: ${resourceGroup}\nEnabled Options: ${enabledOptions}\nStatus: ${job.status}\nStatus URL: ${statusUrl}${storageMsg}\n\nPoll the status URL to check progress. Refactored files will be available when completed.`
      }]
    };
  } catch (error) {
    console.error(`[Refactor Tool Error] ${error.message}`);
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Error starting refactor job: ${error.message}`
      }]
    };
  }
}
