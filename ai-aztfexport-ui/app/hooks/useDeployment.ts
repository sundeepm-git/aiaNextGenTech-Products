'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import {
  startDeploy,
  streamDeployProgress,
  closeDeployStream,
  fetchEnvSettings,
  updateServiceUrls,
} from '@/app/services/deployService';
import type { DeployLogEntry, EnvSettingsResponse } from '@/app/services/deployService';
import { config } from '@/app/services/config';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type DeployStatus = 'idle' | 'starting' | 'running' | 'completed' | 'failed' | 'disconnected';

export interface DeployLog {
  type: 'info' | 'warn' | 'error' | 'success';
  message: string;
  timestamp: string;
}

export interface DeployUrls {
  ui_url?: string;
  api_url?: string;
  mcp_url?: string;
}

export interface UseDeploymentReturn {
  jobId: string | null;
  status: DeployStatus;
  progress: number;
  logs: DeployLog[];
  isRunning: boolean;
  error: string | null;
  deployUrls: DeployUrls;
  envSettings: EnvSettingsResponse | null;
  envLoading: boolean;
  envSaving: boolean;
  startDeployment: () => Promise<void>;
  clearLogs: () => void;
  loadEnvSettings: () => Promise<void>;
  saveServiceUrls: (urls: Record<string, string>) => Promise<boolean>;
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export const useDeployment = (): UseDeploymentReturn => {
  const [jobId, setJobId] = useState<string | null>(null);
  const [status, setStatus] = useState<DeployStatus>('idle');
  const [progress, setProgress] = useState(0);
  const [logs, setLogs] = useState<DeployLog[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [deployUrls, setDeployUrls] = useState<DeployUrls>({});
  const [envSettings, setEnvSettings] = useState<EnvSettingsResponse | null>(null);
  const [envLoading, setEnvLoading] = useState(false);
  const [envSaving, setEnvSaving] = useState(false);

  const esRef = useRef<EventSource | null>(null);
  const reconnectRef = useRef<NodeJS.Timeout | null>(null);

  const addLog = useCallback((log: DeployLog) => {
    setLogs((prev) => [...prev, log]);
  }, []);

  const mapLevel = (level: string): DeployLog['type'] => {
    if (level === 'success') return 'success';
    if (level === 'warn') return 'warn';
    if (level === 'error') return 'error';
    return 'info';
  };

  // -- SSE connection --

  const connectSSE = useCallback(
    (id: string) => {
      closeDeployStream(esRef.current);
      esRef.current = null;

      const es = streamDeployProgress(id, {
        onConnected: () => {
          setStatus('running');
          addLog({ type: 'info', message: 'Connected to deployment progress stream', timestamp: new Date().toISOString() });
        },
        onLog: (entry: DeployLogEntry) => {
          addLog({ type: mapLevel(entry.level), message: entry.message, timestamp: entry.timestamp });
        },
        onStatus: (data) => {
          setProgress(data.progress);
          if (data.status === 'completed' || data.status === 'failed') {
            setStatus(data.status as DeployStatus);
          }
        },
        onComplete: (data) => {
          setStatus(data.status === 'failed' ? 'failed' : 'completed');
          setProgress(data.progress ?? 100);
          if (data.error) setError(data.error);

          // Parse URLs from result if available
          if (data.result) {
            try {
              const parsed = typeof data.result === 'string' ? JSON.parse(data.result.replace(/'/g, '"')) : data.result;
              setDeployUrls(parsed);
            } catch {
              // result might not be valid JSON
            }
          }

          addLog({
            type: data.status === 'failed' ? 'error' : 'success',
            message: data.status === 'failed' ? `Deployment failed: ${data.error}` : 'Deployment completed successfully',
            timestamp: new Date().toISOString(),
          });
          closeDeployStream(esRef.current);
          esRef.current = null;
        },
        onError: () => {
          setStatus('disconnected');
          addLog({ type: 'warn', message: 'Connection lost — will retry…', timestamp: new Date().toISOString() });
          closeDeployStream(esRef.current);
          esRef.current = null;

          if (config.features.autoReconnect) {
            reconnectRef.current = setTimeout(() => connectSSE(id), config.ui.reconnectDelay);
          }
        },
      });

      esRef.current = es;
    },
    [addLog],
  );

  // -- Start deployment --

  const startDeployment = useCallback(async () => {
    setJobId(null);
    setStatus('starting');
    setProgress(0);
    setLogs([]);
    setError(null);
    setDeployUrls({});

    addLog({ type: 'info', message: 'Initiating deployment — launching deploy.ps1...', timestamp: new Date().toISOString() });

    try {
      const res = await startDeploy();
      setJobId(res.jobId);
      addLog({ type: 'success', message: `Deployment job created: ${res.jobId}`, timestamp: res.timestamp });
      connectSSE(res.jobId);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setStatus('failed');
      setError(msg);
      addLog({ type: 'error', message: msg, timestamp: new Date().toISOString() });
    }
  }, [addLog, connectSSE]);

  // -- Load env settings --

  const loadEnvSettings = useCallback(async () => {
    setEnvLoading(true);
    try {
      const data = await fetchEnvSettings();
      setEnvSettings(data);
    } catch (err) {
      console.error('Failed to load env settings:', err);
    } finally {
      setEnvLoading(false);
    }
  }, []);

  // -- Save service URLs --

  const saveServiceUrls = useCallback(async (urls: Record<string, string>): Promise<boolean> => {
    setEnvSaving(true);
    try {
      const res = await updateServiceUrls(urls);
      // Merge updated service_urls back into envSettings
      setEnvSettings((prev) => prev ? { ...prev, service_urls: res.service_urls } : { env_variables: {}, service_urls: res.service_urls });
      return true;
    } catch (err) {
      console.error('Failed to save service URLs:', err);
      return false;
    } finally {
      setEnvSaving(false);
    }
  }, []);

  const clearLogs = useCallback(() => setLogs([]), []);

  // -- cleanup --
  useEffect(() => {
    return () => {
      closeDeployStream(esRef.current);
      if (reconnectRef.current) clearTimeout(reconnectRef.current);
    };
  }, []);

  return {
    jobId,
    status,
    progress,
    logs,
    isRunning: status === 'starting' || status === 'running',
    error,
    deployUrls,
    envSettings,
    envLoading,
    envSaving,
    startDeployment,
    clearLogs,
    loadEnvSettings,
    saveServiceUrls,
  };
};
