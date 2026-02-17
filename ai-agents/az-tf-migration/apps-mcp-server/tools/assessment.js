import { z } from "zod";
import { v4 as uuidv4 } from 'uuid';
import { spawn } from 'child_process';
import path from "path";
import { fileURLToPath } from 'url';
import fs from 'fs';

export class AssessmentJob {
  constructor(id, subscriptionId, resourceGroup = null) {
    this.id = id || uuidv4();
    this.subscriptionId = subscriptionId;
    this.resourceGroup = resourceGroup;
    this.status = 'pending';
    this.createdAt = new Date().toISOString();
    this.stdout = '';
    this.stderr = '';
  }
}

// Aligning to the same Zod pattern as Refactor and Export
export const assessmentToolDefinition = {
  name: "azure_assessment",
  description: "Assess an Azure subscription or resource group for Terraform migration suitability.",
  inputSchema: z.object({
    subscriptionId: z.string().describe("The Azure Subscription ID (GUID)"),
    resourceGroup: z.string().optional().describe("Optional: Specific Resource Group name")
  })
};

export async function assessmentToolHandler(params, toolContext) {
  console.error(`[AssessmentToolHandler] Called with params:`, params);
  const jobId = uuidv4();
  const job = new AssessmentJob(jobId, params.subscriptionId, params.resourceGroup);
  toolContext.jobs.set(job.id, job);
  await toolContext.executeJob(job);
  console.error(`[AssessmentToolHandler] Job created:`, job);
  return {
    content: [{ 
      type: "text", 
      text: `🚀 Assessment job started!\n\nJob ID: ${jobId}\nSubscription: ${params.subscriptionId}\n\nStatus: ${job.status}\n\nCheck the status at /jobs/${jobId}` 
    }]
  };
}

export async function executeAssessmentJob(job, localReportDir, serverDir) {
  job.status = 'running';
  job.startedAt = new Date().toISOString();

  // Use __dirname logic as in aztfexport.js
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);

  try {
    const scriptName = "assessment-AzSubscription.py";
    const scriptPath = path.join(__dirname, "..", "python", scriptName);

    console.error(`[executeAssessmentJob] Spawning Python:`, {
      scriptPath,
      subscriptionId: job.subscriptionId,
      resourceGroup: job.resourceGroup
    });

    if (!fs.existsSync(scriptPath)) {
      throw new Error(`Python executor not found at: ${scriptPath}`);
    }

    const pyExecutable = process.platform === 'win32' ? 'python' : 'python3';

    let pyArgs = [scriptPath, '--subscription_id', job.subscriptionId];
    if (job.resourceGroup) {
      pyArgs.push('--resource_groups', job.resourceGroup);
    }

    const py = spawn(pyExecutable, pyArgs, {
      env: { ...process.env },
      cwd: path.dirname(scriptPath)
    });

    py.stdout.on('data', (data) => {
      job.stdout += data.toString();
      console.error(`[executeAssessmentJob][stdout]:`, data.toString());
    });
    py.stderr.on('data', (data) => {
      job.stderr += data.toString();
      console.error(`[executeAssessmentJob][stderr]:`, data.toString());
    });

    await new Promise((resolve, reject) => {
      py.on('close', (code) => {
        job.status = code === 0 ? 'completed' : 'failed';
        job.completedAt = new Date().toISOString();
        console.error(`[executeAssessmentJob] Python exited with code:`, code);
        resolve();
      });
    });
  } catch (err) {
    job.status = 'failed';
    job.error = err.message;
    console.error(`[executeAssessmentJob][error]:`, err);
  }
}