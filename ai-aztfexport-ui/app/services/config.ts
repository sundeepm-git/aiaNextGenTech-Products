/**
 * Application Configuration
 * Centralized configuration for all API endpoints, keys, and settings
 */

interface AppConfig {
  mcpServer: {
    baseUrl: string;
    endpoints: {
      messages: string;
      jobProgress: (jobId: string) => string;
    };
    timeout: number;
    retryAttempts: number;
    retryDelay: number;
  };
  workflow: {
    baseUrl: string;
    endpoints: {
      start: string;
      jobStatus: (jobId: string) => string;
      jobProgress: (jobId: string) => string;
      listJobs: string;
    };
  };
  assessment: {
    baseUrl: string;
    endpoints: {
      start: string;
      jobStatus: (jobId: string) => string;
      jobProgress: (jobId: string) => string;
      report: (jobId: string, subscriptionId: string, resourceGroup: string) => string;
    };
  };
  reports: {
    baseUrl: string;
    endpoints: {
      subscriptions: string;
      resourceGroups: (subscriptionId: string) => string;
      tree: (subscriptionId: string, resourceGroup: string) => string;
      download: (container: string, blobName: string) => string;
    };
  };
  deploy: {
    baseUrl: string;
    endpoints: {
      start: string;
      jobStatus: (jobId: string) => string;
      jobProgress: (jobId: string) => string;
      env: string;
    };
  };
  observability: {
    baseUrl: string;
    endpoints: {
      metrics: string;
      agentMetrics: (agentName: string) => string;
      traces: string;
      traceDetail: (jobId: string) => string;
      costs: string;
      retries: string;
      throughput: string;
      healthSummary: string;
    };
  };
  azure: {
    storageAccount: string;
    containerName: string;
  };
  features: {
    enableRealTimeMigration: boolean;
    enableSimulation: boolean;
    autoReconnect: boolean;
  };
  ui: {
    logRetentionLimit: number;
    reconnectDelay: number;
    sseHeartbeatInterval: number; // Max time between SSE events before timeout
    longRunningJobThreshold: number; // When to consider a job "long-running"
  };
}

/**
 * Load configuration from environment variables
 */
const loadConfig = (): AppConfig => {
  const mcpBaseUrl = process.env.NEXT_PUBLIC_MCP_SERVER_URL ?? 'http://localhost:8080';
  const workflowBaseUrl = process.env.NEXT_PUBLIC_WORKFLOW_API_URL ?? 'http://localhost:8000';

  return {
    mcpServer: {
      baseUrl: mcpBaseUrl,
      endpoints: {
        messages: `${mcpBaseUrl}/messages`,
        jobProgress: (jobId: string) => `${mcpBaseUrl}/jobs/${jobId}/progress`,
      },
      timeout: parseInt(process.env.NEXT_PUBLIC_API_TIMEOUT || '600000', 10), // 10 minutes for long exports
      retryAttempts: parseInt(process.env.NEXT_PUBLIC_RETRY_ATTEMPTS || '3', 10),
      retryDelay: parseInt(process.env.NEXT_PUBLIC_RETRY_DELAY || '5000', 10), // 5s between retries
    },
    workflow: {
      baseUrl: workflowBaseUrl,
      endpoints: {
        start: `${workflowBaseUrl}/api/workflow/start`,
        jobStatus: (jobId: string) => `${workflowBaseUrl}/api/jobs/${jobId}`,
        jobProgress: (jobId: string) => `${workflowBaseUrl}/api/jobs/${jobId}/progress`,
        listJobs: `${workflowBaseUrl}/api/jobs`,
      },
    },
    assessment: {
      baseUrl: workflowBaseUrl,
      endpoints: {
        start: `${workflowBaseUrl}/api/assessment/start`,
        jobStatus: (jobId: string) => `${workflowBaseUrl}/api/jobs/${jobId}`,
        jobProgress: (jobId: string) => `${workflowBaseUrl}/api/jobs/${jobId}/progress`,
        report: (jobId: string, subscriptionId: string, resourceGroup: string) =>
          `${workflowBaseUrl}/api/assessment/${jobId}/report?subscription_id=${encodeURIComponent(subscriptionId)}&resource_group=${encodeURIComponent(resourceGroup)}`,
      },
    },
    reports: {
      baseUrl: workflowBaseUrl,
      endpoints: {
        subscriptions: `${workflowBaseUrl}/api/reports/subscriptions`,
        resourceGroups: (subscriptionId: string) =>
          `${workflowBaseUrl}/api/reports/subscriptions/${encodeURIComponent(subscriptionId)}/resource-groups`,
        tree: (subscriptionId: string, resourceGroup: string) =>
          `${workflowBaseUrl}/api/reports/tree?subscription_id=${encodeURIComponent(subscriptionId)}&resource_group=${encodeURIComponent(resourceGroup)}`,
        download: (container: string, blobName: string) =>
          `${workflowBaseUrl}/api/reports/download?container=${encodeURIComponent(container)}&blob_name=${encodeURIComponent(blobName)}`,
      },
    },
    deploy: {
      baseUrl: workflowBaseUrl,
      endpoints: {
        start: `${workflowBaseUrl}/api/deploy/start`,
        jobStatus: (jobId: string) => `${workflowBaseUrl}/api/deploy/${jobId}`,
        jobProgress: (jobId: string) => `${workflowBaseUrl}/api/deploy/${jobId}/progress`,
        env: `${workflowBaseUrl}/api/settings/env`,
      },
    },
    observability: {
      baseUrl: workflowBaseUrl,
      endpoints: {
        metrics: `${workflowBaseUrl}/api/observability/metrics`,
        agentMetrics: (agentName: string) => `${workflowBaseUrl}/api/observability/metrics/agents/${encodeURIComponent(agentName)}`,
        traces: `${workflowBaseUrl}/api/observability/traces`,
        traceDetail: (jobId: string) => `${workflowBaseUrl}/api/observability/traces/${encodeURIComponent(jobId)}`,
        costs: `${workflowBaseUrl}/api/observability/costs`,
        retries: `${workflowBaseUrl}/api/observability/retries`,
        throughput: `${workflowBaseUrl}/api/observability/throughput`,
        healthSummary: `${workflowBaseUrl}/api/observability/health-summary`,
      },
    },
    azure: {
      storageAccount: process.env.NEXT_PUBLIC_AZURE_STORAGE_ACCOUNT || 'samcpstorage',
      containerName: process.env.NEXT_PUBLIC_AZURE_CONTAINER || 'aztfExport',
    },
    features: {
      enableRealTimeMigration: process.env.NEXT_PUBLIC_ENABLE_REAL_MIGRATION !== 'false',
      enableSimulation: process.env.NEXT_PUBLIC_ENABLE_SIMULATION !== 'false',
      autoReconnect: process.env.NEXT_PUBLIC_AUTO_RECONNECT !== 'false',
    },
    ui: {
      logRetentionLimit: parseInt(process.env.NEXT_PUBLIC_LOG_RETENTION || '1000', 10),
      reconnectDelay: parseInt(process.env.NEXT_PUBLIC_RECONNECT_DELAY || '3000', 10),
    },
  };
};

/**
 * Application configuration singleton
 */
export const config = loadConfig();

/**
 * Validate configuration
 */
export const validateConfig = (): { valid: boolean; errors: string[] } => {
  const errors: string[] = [];

  if (!config.mcpServer.baseUrl) {
    errors.push('MCP Server base URL is not configured');
  }

  if (config.mcpServer.timeout < 1000) {
    errors.push('API timeout must be at least 1000ms');
  }

  if (config.mcpServer.retryAttempts < 0) {
    errors.push('Retry attempts must be non-negative');
  }

  return {
    valid: errors.length === 0,
    errors,
  };
};

/**
 * Export config for testing/debugging
 */
export const getConfig = (): AppConfig => config;
