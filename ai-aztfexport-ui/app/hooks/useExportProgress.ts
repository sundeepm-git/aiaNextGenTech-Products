import { useState, useEffect, useCallback, useRef } from 'react';
import { config } from '@/app/services/config';
import { 
  startExportJob, 
  createProgressStream, 
  closeProgressStream 
} from '@/app/services/mcpService';
import type { 
  ProgressLog, 
  ExportProgressState 
} from '@/app/types/export';

export type { ProgressLog, ExportProgressState };

interface UseExportProgressReturn extends ExportProgressState {
  startExport: (subscriptionId: string, resourceGroup: string, prompt?: string) => Promise<void>;
  clearLogs: () => void;
  reconnect: () => void;
}

export const useExportProgress = (): UseExportProgressReturn => {
  const [state, setState] = useState<ExportProgressState>({
    jobId: null,
    status: 'idle',
    logs: [],
    isRunning: false,
    error: null,
  });

  const eventSourceRef = useRef<EventSource | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  const addLog = useCallback((log: ProgressLog) => {
    setState((prev) => ({
      ...prev,
      logs: [...prev.logs, log],
    }));
  }, []);

  const connectToProgress = useCallback((jobId: string) => {
    // Close any existing connection
    closeProgressStream(eventSourceRef.current);
    eventSourceRef.current = null;

    setState((prev) => ({ ...prev, status: 'connecting' }));

    const eventSource = createProgressStream(jobId, {
      onOpen: () => {
        setState((prev) => ({ ...prev, status: 'connected' }));
        addLog({
          type: 'info',
          message: 'Connected to export progress stream',
          timestamp: new Date().toISOString(),
        });
      },
      onConnected: (data) => {
        addLog({
          type: 'info',
          message: data.message || 'Connection established',
          timestamp: data.timestamp || new Date().toISOString(),
        });
      },
      onStdout: (data) => {
        addLog({
          type: 'stdout',
          message: data.message,
          timestamp: data.timestamp,
        });
      },
      onStderr: (data) => {
        addLog({
          type: 'stderr',
          message: data.message,
          timestamp: data.timestamp,
        });
      },
      onComplete: (data) => {
        setState((prev) => ({
          ...prev,
          status: 'completed',
          isRunning: false,
        }));
        addLog({
          type: 'success',
          message: data.message || 'Export completed successfully',
          timestamp: data.timestamp || new Date().toISOString(),
        });
        closeProgressStream(eventSourceRef.current);
        eventSourceRef.current = null;
      },
      onError: (error) => {
        console.error('SSE connection error:', error);
        
        setState((prev) => ({
          ...prev,
          status: 'disconnected',
        }));

        addLog({
          type: 'error',
          message: `Connection lost. Attempting to reconnect in ${config.ui.reconnectDelay / 1000} seconds...`,
          timestamp: new Date().toISOString(),
        });

        closeProgressStream(eventSourceRef.current);
        eventSourceRef.current = null;

        // Attempt to reconnect after configured delay
        if (config.features.autoReconnect) {
          reconnectTimeoutRef.current = setTimeout(() => {
            if (state.isRunning) {
              addLog({
                type: 'info',
                message: 'Reconnecting to progress stream...',
                timestamp: new Date().toISOString(),
              });
              connectToProgress(jobId);
            }
          }, config.ui.reconnectDelay);
        }
      },
    });

    eventSourceRef.current = eventSource;
  }, [addLog, state.isRunning]);

  const startExport = useCallback(async (subscriptionId: string, resourceGroup: string, prompt?: string) => {
    // Clear previous state
    setState({
      jobId: null,
      status: 'idle',
      logs: [],
      isRunning: true,
      error: null,
    });

    try {
      addLog({
        type: 'info',
        message: `Starting export for subscription: ${subscriptionId}, resource group: ${resourceGroup}`,
        timestamp: new Date().toISOString(),
      });

      // Call MCP server to start the export
      const response = await startExportJob(subscriptionId, resourceGroup, prompt);
      const jobId = response.jobId;

      setState((prev) => ({
        ...prev,
        jobId,
      }));

      addLog({
        type: 'success',
        message: `Export job created with ID: ${jobId}`,
        timestamp: new Date().toISOString(),
      });

      // Connect to the SSE progress stream
      connectToProgress(jobId);

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
      
      setState((prev) => ({
        ...prev,
        status: 'error',
        isRunning: false,
        error: errorMessage,
      }));

      addLog({
        type: 'error',
        message: errorMessage,
        timestamp: new Date().toISOString(),
      });
    }
  }, [addLog, connectToProgress]);

  const clearLogs = useCallback(() => {
    setState((prev) => ({
      ...prev,
      logs: [],
    }));
  }, []);

  const reconnect = useCallback(() => {
    if (state.jobId) {
      connectToProgress(state.jobId);
    }
  }, [state.jobId, connectToProgress]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      closeProgressStream(eventSourceRef.current);
      eventSourceRef.current = null;
      
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }
    };
  }, []);

  return {
    ...state,
    startExport,
    clearLogs,
    reconnect,
  };
};
