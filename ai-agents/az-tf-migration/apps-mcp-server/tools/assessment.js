
import { z } from "zod";
import { v4 as uuidv4 } from 'uuid';
import { spawn } from 'child_process';
import path from "path";
import { fileURLToPath } from 'url';
import fs from 'fs';
import dotenv from 'dotenv';
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

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

  // Only change: return JSON schema as required by Microsoft Foundry
    let resultData;
    if (job.status === 'completed') {
      try {
        // Parse the perfect JSON straight from the Python script's stdout
        resultData = JSON.parse(job.stdout);
      } catch (err) {
        console.error("[AssessmentToolHandler] Failed to parse Python stdout:", job.stdout);
        resultData = { error: "Failed to parse valid JSON from Python script." };
      }
    } else {
      // Provide a fallback that still matches the schema if the job fails
      resultData = {
        jobId: job.id,
        subscriptionId: job.subscriptionId,
        resourceGroup: job.resourceGroup || "rg-mcp-servers",
        status: "failed",
        storageAccount: "unknown",
        startedAt: job.startedAt,
        completedAt: new Date().toISOString()
      };
    }

    // MCP strict wrapper: always return stringified JSON in content array
    // MCP strict wrapper: always return stringified JSON in content array
    // Return the resultData directly as an object within the content array
    // This allows Microsoft Foundry to recognize it as an 'Object' type
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(resultData, null, 2) // Keep this for logs/debugging
        }
      ],
      // We add the raw data as a property that Foundry can map to 'Object'
      data:{
       result: resultData 
      }
      
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