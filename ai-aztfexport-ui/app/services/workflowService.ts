/**
 * Agentic Workflow Service
 * Communicates with the FastAPI api_server.py wrapper for the 4-agent pipeline.
 */

import { config } from './config';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface WorkflowStartRequest {
  prompt: string;
}

export interface WorkflowStartResponse {
  jobId: string;
  status: string;
  message: string;
  timestamp: string;
}

export interface WorkflowJobStatus {
  jobId: string;
  status: 'queued' | 'running' | 'completed' | 'failed';
  currentAgent: string | null;
  progress: number;
  logs: WorkflowLogEntry[];
  error: string | null;
  result: string | null;
}

export interface WorkflowLogEntry {
  level: 'info' | 'warn' | 'error' | 'success';
  message: string;
  agent: string | null;
  timestamp: string;
}

// ---------------------------------------------------------------------------
// API Calls
// ---------------------------------------------------------------------------

/**
 * Start the agentic workflow pipeline.
 */
export const startAgenticWorkflow = async (
  prompt: string,
): Promise<WorkflowStartResponse> => {
  const url = config.workflow.endpoints.start;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt } satisfies WorkflowStartRequest),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Failed to start workflow: ${response.status} — ${text}`);
  }

  return response.json();
};

/**
 * Get current job status snapshot.
 */
export const getWorkflowJobStatus = async (jobId: string): Promise<WorkflowJobStatus> => {
  const url = config.workflow.endpoints.jobStatus(jobId);

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch job status: ${response.status}`);
  }
  return response.json();
};

/**
 * Open an SSE stream to the workflow progress endpoint.
 * Returns the EventSource so the caller can close it.
 */
export const streamWorkflowProgress = (
  jobId: string,
  callbacks: {
    onConnected?: (data: any) => void;
    onLog?: (data: WorkflowLogEntry) => void;
    onStatus?: (data: { jobId: string; status: string; progress: number; currentAgent: string | null }) => void;
    onComplete?: (data: any) => void;
    onError?: (err: Error) => void;
  },
): EventSource => {
  const url = config.workflow.endpoints.jobProgress(jobId);
  const es = new EventSource(url);

  es.addEventListener('connected', (e) => {
    try { callbacks.onConnected?.(JSON.parse((e as MessageEvent).data)); } catch { /* ignore */ }
  });

  es.addEventListener('log', (e) => {
    try { callbacks.onLog?.(JSON.parse((e as MessageEvent).data)); } catch { /* ignore */ }
  });

  es.addEventListener('status', (e) => {
    try { callbacks.onStatus?.(JSON.parse((e as MessageEvent).data)); } catch { /* ignore */ }
  });

  es.addEventListener('complete', (e) => {
    try { callbacks.onComplete?.(JSON.parse((e as MessageEvent).data)); } catch { /* ignore */ }
    es.close();
  });

  es.onerror = () => {
    callbacks.onError?.(new Error('SSE connection error'));
  };

  return es;
};

/**
 * Close an existing SSE stream.
 */
export const closeWorkflowStream = (es: EventSource | null): void => {
  es?.close();
};

/**
 * List all workflow jobs.
 */
export const listWorkflowJobs = async (): Promise<any[]> => {
  const url = config.workflow.endpoints.listJobs;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to list jobs: ${response.status}`);
  }
  return response.json();
};
