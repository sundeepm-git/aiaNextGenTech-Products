/**
 * Shared TypeScript interfaces and types for export functionality
 */

export interface ProgressLog {
  type: 'stdout' | 'stderr' | 'info' | 'success' | 'error';
  message: string;
  timestamp: string;
}

export interface ExportJobRequest {
  toolName: string;
  args: {
    subscriptionId: string;
    resourceGroup: string;
    context?: string;
  };
}

export interface ExportJobResponse {
  jobId: string;
  message: string;
  timestamp: string;
}

export interface SSEEvent {
  event: 'connected' | 'stdout' | 'stderr' | 'complete' | 'error';
  data: {
    message: string;
    timestamp: string;
    jobId?: string;
    [key: string]: any;
  };
}

export type ExportStatus = 'idle' | 'connecting' | 'connected' | 'completed' | 'error' | 'disconnected';

export interface ExportProgressState {
  jobId: string | null;
  status: ExportStatus;
  logs: ProgressLog[];
  isRunning: boolean;
  error: string | null;
}
