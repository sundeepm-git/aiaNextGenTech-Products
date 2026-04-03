/**
 * Deploy Service — API calls for deployment and settings
 */

import { config } from './config';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface DeployStartResponse {
  jobId: string;
  status: string;
  message: string;
  timestamp: string;
}

export interface DeployLogEntry {
  level: 'info' | 'warn' | 'error' | 'success';
  message: string;
  agent: string | null;
  timestamp: string;
}

export interface EnvSettingsResponse {
  env_variables: Record<string, string>;
  service_urls: Record<string, string>;
}

// ---------------------------------------------------------------------------
// API Calls
// ---------------------------------------------------------------------------

/**
 * Start deployment.
 */
export const startDeploy = async (): Promise<DeployStartResponse> => {
  const url = config.deploy.endpoints.start;
  const response = await fetch(url, { method: 'POST' });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Failed to start deployment: ${response.status} — ${text}`);
  }
  return response.json();
};

/**
 * Open an SSE stream to the deployment progress endpoint.
 */
export const streamDeployProgress = (
  jobId: string,
  callbacks: {
    onConnected?: (data: any) => void;
    onLog?: (data: DeployLogEntry) => void;
    onStatus?: (data: { jobId: string; status: string; progress: number }) => void;
    onComplete?: (data: any) => void;
    onError?: (err: Error) => void;
  },
): EventSource => {
  const url = config.deploy.endpoints.jobProgress(jobId);
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
  });

  es.onerror = () => {
    callbacks.onError?.(new Error('SSE connection lost'));
  };

  return es;
};

/**
 * Close an SSE stream.
 */
export const closeDeployStream = (es: EventSource | null) => {
  if (es) {
    es.close();
  }
};

/**
 * Fetch environment variables and service URLs from the API.
 */
export const fetchEnvSettings = async (): Promise<EnvSettingsResponse> => {
  const url = config.deploy.endpoints.env;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch env settings: ${response.status}`);
  }
  return response.json();
};

/**
 * Update service URLs and storage settings via the API.
 */
export const updateServiceUrls = async (
  urls: Record<string, string>,
): Promise<{ service_urls: Record<string, string> }> => {
  const url = `${config.deploy.baseUrl}/api/settings/urls`;
  const response = await fetch(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ urls }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Failed to update service URLs: ${response.status} — ${text}`);
  }
  return response.json();
};
