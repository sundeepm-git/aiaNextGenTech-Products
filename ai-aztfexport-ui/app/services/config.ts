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
  };
}

/**
 * Load configuration from environment variables
 */
const loadConfig = (): AppConfig => {
  const mcpBaseUrl = process.env.NEXT_PUBLIC_MCP_SERVER_URL || 'http://localhost:8080';

  return {
    mcpServer: {
      baseUrl: mcpBaseUrl,
      endpoints: {
        messages: `${mcpBaseUrl}/messages`,
        jobProgress: (jobId: string) => `${mcpBaseUrl}/jobs/${jobId}/progress`,
      },
      timeout: parseInt(process.env.NEXT_PUBLIC_API_TIMEOUT || '30000', 10),
      retryAttempts: parseInt(process.env.NEXT_PUBLIC_RETRY_ATTEMPTS || '3', 10),
      retryDelay: parseInt(process.env.NEXT_PUBLIC_RETRY_DELAY || '3000', 10),
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
