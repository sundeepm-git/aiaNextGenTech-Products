'use client';

import { useState, useCallback, useRef, useEffect } from 'react';
import {
  startAgenticWorkflow,
  streamWorkflowProgress,
  closeWorkflowStream,
} from '@/app/services/workflowService';
import type { WorkflowLogEntry } from '@/app/services/workflowService';
import { config } from '@/app/services/config';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type WorkflowStatus =
  | 'idle'
  | 'starting'
  | 'running'
  | 'completed'
  | 'failed'
  | 'disconnected';

export interface WorkflowProgressLog {
  type: 'info' | 'warn' | 'error' | 'success' | 'stdout' | 'stderr';
  message: string;
  agent: string | null;
  timestamp: string;
}

export interface UseAgenticWorkflowReturn {
  jobId: string | null;
  status: WorkflowStatus;
  currentAgent: string | null;
  progress: number;
  logs: WorkflowProgressLog[];
  isRunning: boolean;
  error: string | null;
  startWorkflow: (prompt: string) => Promise<void>;
  clearLogs: () => void;
  reconnect: () => void;
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export const useAgenticWorkflow = (): UseAgenticWorkflowReturn => {
  const [jobId, setJobId] = useState<string | null>(null);
  const [status, setStatus] = useState<WorkflowStatus>('idle');
  const [currentAgent, setCurrentAgent] = useState<string | null>(null);
  const [progress, setProgress] = useState(0);
  const [logs, setLogs] = useState<WorkflowProgressLog[]>([]);
  const [error, setError] = useState<string | null>(null);

  const esRef = useRef<EventSource | null>(null);
  const reconnectRef = useRef<NodeJS.Timeout | null>(null);

  // -- helpers --

  const addLog = useCallback((log: WorkflowProgressLog) => {
    setLogs((prev) => [...prev, log]);
  }, []);

  const mapLevel = (level: string): WorkflowProgressLog['type'] => {
    if (level === 'success') return 'success';
    if (level === 'warn') return 'warn';
    if (level === 'error') return 'error';
    return 'info';
  };

  // -- SSE connection --

  const connectSSE = useCallback(
    (id: string) => {
      closeWorkflowStream(esRef.current);
      esRef.current = null;

      const es = streamWorkflowProgress(id, {
        onConnected: () => {
          setStatus('running');
          addLog({ type: 'info', message: 'Connected to workflow progress stream', agent: null, timestamp: new Date().toISOString() });
        },
        onLog: (entry: WorkflowLogEntry) => {
          if (entry.agent) setCurrentAgent(entry.agent);
          addLog({ type: mapLevel(entry.level), message: entry.message, agent: entry.agent, timestamp: entry.timestamp });
        },
        onStatus: (data) => {
          setProgress(data.progress);
          if (data.currentAgent) setCurrentAgent(data.currentAgent);
          if (data.status === 'completed' || data.status === 'failed') {
            setStatus(data.status as WorkflowStatus);
          }
        },
        onComplete: (data) => {
          setStatus(data.status === 'failed' ? 'failed' : 'completed');
          setProgress(data.progress ?? 100);
          if (data.error) setError(data.error);
          addLog({
            type: data.status === 'failed' ? 'error' : 'success',
            message: data.status === 'failed' ? `Pipeline failed: ${data.error}` : 'Pipeline completed successfully',
            agent: null,
            timestamp: new Date().toISOString(),
          });
          closeWorkflowStream(esRef.current);
          esRef.current = null;
        },
        onError: () => {
          setStatus('disconnected');
          addLog({ type: 'warn', message: 'Connection lost — will retry…', agent: null, timestamp: new Date().toISOString() });
          closeWorkflowStream(esRef.current);
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

  // -- public API --

  const startWorkflow = useCallback(
    async (prompt: string) => {
      setJobId(null);
      setStatus('starting');
      setCurrentAgent(null);
      setProgress(0);
      setLogs([]);
      setError(null);

      addLog({ type: 'info', message: `Starting agentic workflow with prompt: ${prompt.substring(0, 80)}...`, agent: null, timestamp: new Date().toISOString() });

      try {
        const res = await startAgenticWorkflow(prompt);
        setJobId(res.jobId);
        addLog({ type: 'success', message: `Job created: ${res.jobId}`, agent: null, timestamp: res.timestamp });
        connectSSE(res.jobId);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        setStatus('failed');
        setError(msg);
        addLog({ type: 'error', message: msg, agent: null, timestamp: new Date().toISOString() });
      }
    },
    [addLog, connectSSE],
  );

  const clearLogs = useCallback(() => setLogs([]), []);

  const reconnect = useCallback(() => {
    if (jobId) connectSSE(jobId);
  }, [jobId, connectSSE]);

  // -- cleanup --
  useEffect(() => {
    return () => {
      closeWorkflowStream(esRef.current);
      if (reconnectRef.current) clearTimeout(reconnectRef.current);
    };
  }, []);

  return {
    jobId,
    status,
    currentAgent,
    progress,
    logs,
    isRunning: status === 'starting' || status === 'running',
    error,
    startWorkflow,
    clearLogs,
    reconnect,
  };
};
