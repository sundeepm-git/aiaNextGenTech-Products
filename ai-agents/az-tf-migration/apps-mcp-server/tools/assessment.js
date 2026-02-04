import { z } from "zod";
import { v4 as uuidv4 } from 'uuid';
import { spawn } from 'child_process';
import { env } from "process";
import path from "path";
import fs from "fs";
import { BlobServiceClient, generateBlobSASQueryParameters, BlobSASPermissions } from '@azure/storage-blob';
import { DefaultAzureCredential } from '@azure/identity';

/**
 * Assessment Tool - Azure Environment Assessment for Terraform Migration
 * 
 * This tool initiates an async job to assess an Azure subscription/resource group
 * for Terraform migration readiness using PowerShell scripts.
 */

// --- JOB CLASS ---
export class AssessmentJob {
  constructor(id, subscriptionId, resourceGroup) {
    this.id = id;
    this.subscriptionId = subscriptionId;
    this.resourceGroup = resourceGroup;
    this.status = 'pending';
    this.createdAt = new Date().toISOString();
    this.startedAt = null;
    this.completedAt = null;
    this.stdout = '';
    this.stderr = '';
    this.error = null;
    this.reportFileName = null;
    this.reportUrl = null;
  }

  toJSON() {
    return {
      id: this.id,
      subscriptionId: this.subscriptionId,
      resourceGroup: this.resourceGroup,
      status: this.status,
      createdAt: this.createdAt,
      startedAt: this.startedAt,
      completedAt: this.completedAt,
      error: this.error,
      reportFileName: this.reportFileName,
      reportUrl: this.reportUrl
    };
  }
}

// --- AZURE BLOB STORAGE CONFIGURATION ---
let blobServiceClient = null;
let storageAccountName = null;
const containerName = 'assessment-reports';
let blobStorageAvailable = false;
let blobStorageError = null;

export async function initializeBlobStorage(isStdioMode = false) {
  try {
    storageAccountName = env.storageAccount?.trim();
    
    if (!storageAccountName) {
      blobStorageError = 'Storage account name not configured (storageAccount env var missing)';
      if (!isStdioMode) console.error(`[Blob Storage] ${blobStorageError}`);
      return { available: false, error: blobStorageError, accountName: null, containerName };
    }

    // Remove any whitespace or '=' characters from env parsing issues
    storageAccountName = storageAccountName.replace(/\s*=\s*/g, '').trim();

    const accountUrl = `https://${storageAccountName}.blob.core.windows.net`;
    if (!isStdioMode) console.error(`[Blob Storage] Initializing with account: ${storageAccountName}`);

    // Use Managed Identity (DefaultAzureCredential) for authentication
    const credential = new DefaultAzureCredential();
    blobServiceClient = new BlobServiceClient(accountUrl, credential);

    // Verify access and create container if needed
    const containerClient = blobServiceClient.getContainerClient(containerName);
    const exists = await containerClient.exists();
    
    if (!exists) {
      if (!isStdioMode) console.error(`[Blob Storage] Container '${containerName}' does not exist, creating...`);
      await containerClient.create(); // Private container (more secure)
      if (!isStdioMode) console.error(`[Blob Storage] Container '${containerName}' created successfully (private access)`);
    } else {
      if (!isStdioMode) console.error(`[Blob Storage] Container '${containerName}' exists and is accessible`);
    }

    blobStorageAvailable = true;
    if (!isStdioMode) console.error(`[Blob Storage] Initialized successfully`);
    return { available: true, error: null, accountName: storageAccountName, containerName };
  } catch (error) {
    blobStorageError = `Failed to initialize Blob Storage: ${error.message}`;
    if (!isStdioMode) console.error(`[Blob Storage] ${blobStorageError}`);
    blobStorageAvailable = false;
    return { available: false, error: blobStorageError, accountName: storageAccountName, containerName };
  }
}

// --- BLOB STORAGE UPLOAD HELPER ---
async function uploadReportToBlob(localFilePath, subscriptionId, jobId) {
  console.error(`[Blob Storage] uploadReportToBlob called for job ${jobId}`);
  console.error(`[Blob Storage] - localFilePath: ${localFilePath}`);
  console.error(`[Blob Storage] - subscriptionId: ${subscriptionId}`);
  console.error(`[Blob Storage] - blobStorageAvailable: ${blobStorageAvailable}`);
  console.error(`[Blob Storage] - blobStorageError: ${blobStorageError}`);
  
  if (!blobStorageAvailable) {
    console.error(`[Blob Storage] ❌ Skipping upload for job ${jobId}: ${blobStorageError}`);
    return null;
  }

  try {
    const fileName = path.basename(localFilePath);
    const blobName = `${subscriptionId}/${fileName}`;
    
    console.error(`[Blob Storage] Target blob: ${containerName}/${blobName}`);
    
    const containerClient = blobServiceClient.getContainerClient(containerName);
    const blockBlobClient = containerClient.getBlockBlobClient(blobName);

    console.error(`[Blob Storage] Starting upload: ${localFilePath} -> ${blobName}`);
    
    const fileStats = fs.statSync(localFilePath);
    console.error(`[Blob Storage] File size: ${fileStats.size} bytes`);
    
    await blockBlobClient.uploadFile(localFilePath, {
      blobHTTPHeaders: {
        blobContentType: 'text/html'
      }
    });

    console.error(`[Blob Storage] ✅ Upload completed successfully`);

    // Generate User Delegation SAS (Required for Identity-based auth)
    const now = new Date();
    const expiresOn = new Date();
    expiresOn.setDate(expiresOn.getDate() + 7); // 7 days valid
    const startsOn = new Date(now.valueOf() - 5 * 60 * 1000); // 5 mins ago
    
    console.error(`[Blob Storage] Generating User Delegation SAS (expires: ${expiresOn.toISOString()})...`);
    
    // 1. Get User Delegation Key
    const userDelegationKey = await blobServiceClient.getUserDelegationKey(
      startsOn, 
      expiresOn
    );
    
    // 2. Generate SAS Token
    const sasToken = generateBlobSASQueryParameters({
      containerName,
      blobName,
      permissions: BlobSASPermissions.parse("r"),
      startsOn,
      expiresOn,
      protocol: "https"
    }, userDelegationKey, storageAccountName).toString();
    
    const sasUrl = `${blockBlobClient.url}?${sasToken}`;
    
    console.error(`[Blob Storage] ✅ SAS URL generated successfully`);
    return sasUrl;
  } catch (error) {
    console.error(`[Blob Storage] ❌ Upload failed for job ${jobId}:`);
    console.error(`[Blob Storage] Error: ${error.message}`);
    console.error(`[Blob Storage] Stack: ${error.stack}`);
    return null;
  }
}

// --- ASSESSMENT JOB EXECUTION ---
export async function executeAssessmentJob(job, localReportDir, __dirname) {
  job.status = 'running';
  job.startedAt = new Date().toISOString();
  
  try {
    const scriptPath = env.POWERSHELL_SCRIPT_PATH || './ps/assessment-AzSubscription.ps1';

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

    const psExecutable = "pwsh";

    console.error(`[Job ${job.id}] Starting PowerShell: ${psExecutable} ${psArgs.join(' ')}`);

    await new Promise((resolve, reject) => {
      const ps = spawn(psExecutable, psArgs);
      
      ps.stdout.on('data', (data) => { 
        job.stdout += data.toString();
        console.error(`[Job ${job.id}] stdout: ${data.toString().substring(0, 200)}...`);
      });
      
      ps.stderr.on('data', (data) => { 
        job.stderr += data.toString();
        console.error(`[Job ${job.id}] stderr: ${data.toString().substring(0, 200)}...`);
      });

      const startTs = Date.now();
      const diag = setInterval(() => {
        const elapsed = Math.floor((Date.now() - startTs) / 1000);
        console.error(`[Job ${job.id}] PowerShell still running (${elapsed}s)`);
      }, 60000);

      ps.on('close', async (code) => {
        clearInterval(diag);
        
        if (code === 0) {
          console.error(`[Job ${job.id}] PowerShell completed successfully`);
          
          // Find the generated HTML report
          try {
            console.error(`[Job ${job.id}] Searching for HTML reports in: ${localReportDir}`);
            
            if (!fs.existsSync(localReportDir)) {
              console.error(`[Job ${job.id}] ERROR: Report directory does not exist: ${localReportDir}`);
            } else {
              const allFiles = fs.readdirSync(localReportDir);
              console.error(`[Job ${job.id}] All files in report dir: ${JSON.stringify(allFiles)}`);
            }
            
            const files = fs.readdirSync(localReportDir)
              .filter(f => f.toLowerCase().endsWith('.html'))
              .map(f => ({
                name: f,
                path: path.join(localReportDir, f),
                mtime: fs.statSync(path.join(localReportDir, f)).mtime
              }))
              .sort((a, b) => b.mtime - a.mtime);

            console.error(`[Job ${job.id}] Found ${files.length} HTML file(s)`);

            if (files.length > 0) {
              const latestReport = files[0];
              job.reportFileName = latestReport.name;
              const fileSize = fs.statSync(latestReport.path).size;
              
              console.error(`[Job ${job.id}] Found report: ${latestReport.name} (${fileSize} bytes)`);

              // Upload to Blob Storage
              console.error(`[Job ${job.id}] Attempting Blob Storage upload... (blobStorageAvailable: ${blobStorageAvailable})`);
              const blobUrl = await uploadReportToBlob(latestReport.path, job.subscriptionId, job.id);
              
              if (blobUrl) {
                job.reportUrl = blobUrl;
                console.error(`[Job ${job.id}] ✅ Report uploaded to Blob Storage: ${blobUrl}`);
              } else {
                // Fallback to server URL
                const host = process.env.PUBLIC_HOST || process.env.WEBSITE_HOSTNAME || 'localhost';
                const port = process.env.PORT || 8080;
                const protocol = process.env.PUBLIC_PROTOCOL || (host === 'localhost' ? 'http' : 'https');
                const portSuffix = (host === 'localhost' || host.includes('azurewebsites.net')) ? `:${port}` : '';
                job.reportUrl = `${protocol}://${host}${portSuffix}/reports/${encodeURIComponent(latestReport.name)}`;
                console.error(`[Job ${job.id}] ⚠ Blob upload failed, using server URL: ${job.reportUrl}`);
              }
            } else {
              console.error(`[Job ${job.id}] ❌ ERROR: No HTML report found in ${localReportDir}`);
            }
          } catch (reportErr) {
            console.error(`[Job ${job.id}] Error finding report: ${reportErr.message}`);
          }

          job.status = 'completed';
          job.completedAt = new Date().toISOString();
          resolve();
        } else {
          const errorMsg = job.stderr || `PowerShell exited with code ${code}`;
          console.error(`[Job ${job.id}] Failed: ${errorMsg}`);
          reject(new Error(errorMsg));
        }
      });

      ps.on('error', (err) => {
        clearInterval(diag);
        console.error(`[Job ${job.id}] Spawn error: ${err.message}`);
        reject(err);
      });
    });

  } catch (error) {
    job.status = 'failed';
    job.error = error.message;
    job.completedAt = new Date().toISOString();
    console.error(`[Job ${job.id}] Execution failed: ${error.message}`);
  }
}

// --- TOOL DEFINITION ---
export const assessmentToolDefinition = {
  name: "assess_azure_environment",
  description: "Assess an Azure subscription and resource group for Terraform migration readiness. Returns a Job ID for tracking the long-running assessment.",
  schema: {
    subscriptionId: z.string().describe("The Azure Subscription ID to assess"),
    resourceGroup: z.string().describe("The specific Resource Group to assess")
  }
};

// --- TOOL HANDLER ---
export async function assessmentToolHandler({ subscriptionId, resourceGroup }, context) {
  const { jobs, executeJob, blobStorageInfo } = context;

  try {
    const jobId = uuidv4();
    const job = new AssessmentJob(jobId, subscriptionId, resourceGroup);
    jobs.set(jobId, job);

    console.error(`[Job ${jobId}] Created for subscription: ${subscriptionId}, RG: ${resourceGroup}`);

    // Start job execution asynchronously (don't wait)
    executeJob(job).catch(err => {
      console.error(`[Job ${jobId}] Unhandled execution error: ${err.message}`);
    });

    const host = process.env.PUBLIC_HOST || process.env.WEBSITE_HOSTNAME || 'localhost';
    const port = process.env.PORT || 8080;
    const protocol = process.env.PUBLIC_PROTOCOL || (host === 'localhost' ? 'http' : 'https');
    const portSuffix = (host === 'localhost' || host.includes('azurewebsites.net')) ? `:${port}` : '';
    const statusUrl = `${protocol}://${host}${portSuffix}/jobs/${jobId}`;

    let storageMsg = '';
    if (blobStorageInfo.available) {
      storageMsg = `\n✓ Blob Storage: Reports will be uploaded to '${blobStorageInfo.accountName}/${blobStorageInfo.containerName}'`;
    } else {
      storageMsg = `\n⚠ Blob Storage: ${blobStorageInfo.error}\n  Reports will be available locally only.`;
    }

    return {
      content: [{
        type: "text",
        text: `Job started successfully!\n\nJob ID: ${jobId}\nStatus: ${job.status}\nStatus URL: ${statusUrl}\n\nPoll the status URL to check progress and retrieve the report when completed.${storageMsg}`
      }]
    };
  } catch (error) {
    console.error(`[Tool Error] ${error.message}`);
    return {
      isError: true,
      content: [{
        type: "text",
        text: `Error starting job: ${error.message}`
      }]
    };
  }
}
