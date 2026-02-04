/**
 * MCP Server Service
 * Handles all communication with the MCP server including HTTP requests and SSE connections
 */

import { config } from './config';
import type { 
  ExportJobRequest, 
  ExportJobResponse, 
  ProgressLog,
  SSEEvent 
} from '@/app/types/export';
import type { OrchestrationRequest } from '@/app/types/agent';

/**
 * Start an export job
 */
export const startExportJob = async (
  subscriptionId: string,
  resourceGroup: string,
  context?: string
): Promise<ExportJobResponse> => {
  const requestBody: ExportJobRequest = {
    toolName: 'aztfexport',
    args: {
      subscriptionId,
      resourceGroup,
      context,
    },
  };

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), config.mcpServer.timeout);

    const response = await fetch(config.mcpServer.endpoints.messages, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      throw new Error(`Failed to start export: ${response.status} ${response.statusText}`);
    }

    const result = await response.text();

    // Extract job ID from response
    const jobIdMatch = result.match(/Job ID: ([a-f0-9-]+)/i);

    if (!jobIdMatch) {
      throw new Error('Could not extract job ID from server response');
    }

    const jobId = jobIdMatch[1];

    return {
      jobId,
      message: result,
      timestamp: new Date().toISOString(),
    };
  } catch (error) {
    if (error instanceof Error) {
      if (error.name === 'AbortError') {
        throw new Error(`Request timeout after ${config.mcpServer.timeout}ms`);
      }
      throw error;
    }
    throw new Error('Unknown error occurred while starting export job');
  }
};

/**
 * Create SSE connection for job progress
 */
export const createProgressStream = (
  jobId: string,
  callbacks: {
    onOpen?: () => void;
    onConnected?: (data: any) => void;
    onStdout?: (data: any) => void;
    onStderr?: (data: any) => void;
    onComplete?: (data: any) => void;
    onError?: (error: Error) => void;
  }
): EventSource => {
  const eventSource = new EventSource(config.mcpServer.endpoints.jobProgress(jobId));

  eventSource.onopen = () => {
    if (callbacks.onOpen) {
      callbacks.onOpen();
    }
  };

  eventSource.addEventListener('connected', (event) => {
    try {
      const data = JSON.parse(event.data);
      if (callbacks.onConnected) {
        callbacks.onConnected(data);
      }
    } catch (error) {
      console.error('Error parsing connected event:', error);
    }
  });

  eventSource.addEventListener('stdout', (event) => {
    try {
      const data = JSON.parse(event.data);
      if (callbacks.onStdout) {
        callbacks.onStdout(data);
      }
    } catch (error) {
      console.error('Error parsing stdout event:', error);
    }
  });

  eventSource.addEventListener('stderr', (event) => {
    try {
      const data = JSON.parse(event.data);
      if (callbacks.onStderr) {
        callbacks.onStderr(data);
      }
    } catch (error) {
      console.error('Error parsing stderr event:', error);
    }
  });

  eventSource.addEventListener('complete', (event) => {
    try {
      const data = JSON.parse(event.data);
      if (callbacks.onComplete) {
        callbacks.onComplete(data);
      }
    } catch (error) {
      console.error('Error parsing complete event:', error);
    }
  });

  eventSource.onerror = (error) => {
    if (callbacks.onError) {
      callbacks.onError(new Error('SSE connection error'));
    }
  };

  return eventSource;
};

/**
 * Close SSE connection
 */
export const closeProgressStream = (eventSource: EventSource | null): void => {
  if (eventSource) {
    eventSource.close();
  }
};

/**
 * Start orchestration workflow (for future real implementation)
 */
export const startOrchestration = async (
  request: OrchestrationRequest
): Promise<{ success: boolean; message: string }> => {
  // Placeholder for future real orchestration API
  // Currently using simulation in useAgentStream
  
  try {
    const response = await fetch(`${config.mcpServer.baseUrl}/orchestrate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(request),
    });

    if (!response.ok) {
      throw new Error(`Orchestration failed: ${response.statusText}`);
    }

    const result = await response.json();
    return result;
  } catch (error) {
    // If orchestration endpoint doesn't exist yet, fall back to simulation
    console.warn('Orchestration endpoint not available, using simulation mode');
    return {
      success: true,
      message: 'Running in simulation mode',
    };
  }
};

/**
 * Health check for MCP server
 */
export const checkServerHealth = async (): Promise<{ healthy: boolean; message: string }> => {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    const response = await fetch(`${config.mcpServer.baseUrl}/health`, {
      method: 'GET',
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (response.ok) {
      return {
        healthy: true,
        message: 'MCP server is healthy',
      };
    }

    return {
      healthy: false,
      message: `Server returned status ${response.status}`,
    };
  } catch (error) {
    return {
      healthy: false,
      message: error instanceof Error ? error.message : 'Server unreachable',
    };
  }
};

/**
 * Retry helper for network requests
 */
export const retryRequest = async <T>(
  requestFn: () => Promise<T>,
  maxRetries: number = config.mcpServer.retryAttempts,
  delay: number = config.mcpServer.retryDelay
): Promise<T> => {
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await requestFn();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error('Unknown error');

      if (attempt < maxRetries) {
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError || new Error('All retry attempts failed');
};
