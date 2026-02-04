# Services Layer

This directory contains the service layer for the application, handling all external API calls and integrations.

## Structure

```
services/
├── config.ts          # Centralized configuration management
├── mcpService.ts      # MCP Server API client
└── README.md          # This file
```

## Files

### config.ts

Centralized configuration file that loads settings from environment variables.

**Features:**
- Type-safe configuration interface
- Environment variable loading with defaults
- Configuration validation
- Singleton pattern for consistent access

**Usage:**
```typescript
import { config } from '@/app/services/config';

// Access configuration
const serverUrl = config.mcpServer.baseUrl;
const timeout = config.mcpServer.timeout;
```

**Environment Variables:**
- `NEXT_PUBLIC_MCP_SERVER_URL` - MCP server base URL (default: http://localhost:8080)
- `NEXT_PUBLIC_API_TIMEOUT` - API request timeout in ms (default: 30000)
- `NEXT_PUBLIC_RETRY_ATTEMPTS` - Number of retry attempts (default: 3)
- `NEXT_PUBLIC_RETRY_DELAY` - Delay between retries in ms (default: 3000)
- `NEXT_PUBLIC_AZURE_STORAGE_ACCOUNT` - Azure storage account name (default: samcpstorage)
- `NEXT_PUBLIC_AZURE_CONTAINER` - Azure container name (default: aztfExport)
- `NEXT_PUBLIC_ENABLE_REAL_MIGRATION` - Enable real migration (default: true)
- `NEXT_PUBLIC_ENABLE_SIMULATION` - Enable simulation mode (default: true)
- `NEXT_PUBLIC_AUTO_RECONNECT` - Enable auto-reconnect (default: true)
- `NEXT_PUBLIC_LOG_RETENTION` - Log retention limit (default: 1000)
- `NEXT_PUBLIC_RECONNECT_DELAY` - Reconnect delay in ms (default: 3000)

---

### mcpService.ts

Service layer for all MCP Server API interactions.

**Functions:**

#### `startExportJob(subscriptionId, resourceGroup, context?)`
Starts an export job on the MCP server.

**Parameters:**
- `subscriptionId` (string) - Azure subscription ID
- `resourceGroup` (string) - Resource group name
- `context` (string, optional) - Additional context

**Returns:**
```typescript
Promise<{
  jobId: string;
  message: string;
  timestamp: string;
}>
```

**Usage:**
```typescript
import { startExportJob } from '@/app/services/mcpService';

const result = await startExportJob(
  'd0f1884d-1f98-4bf1-9e15-e2986fc1bca2',
  'rg-mcp-servers'
);
console.log('Job ID:', result.jobId);
```

---

#### `createProgressStream(jobId, callbacks)`
Creates an SSE connection to stream job progress.

**Parameters:**
- `jobId` (string) - Job ID returned from startExportJob
- `callbacks` (object) - Event callbacks:
  - `onOpen?: () => void` - Connection opened
  - `onConnected?: (data) => void` - Connection confirmed
  - `onStdout?: (data) => void` - Standard output received
  - `onStderr?: (data) => void` - Error output received
  - `onComplete?: (data) => void` - Job completed
  - `onError?: (error) => void` - Error occurred

**Returns:** `EventSource` - SSE connection

**Usage:**
```typescript
import { createProgressStream, closeProgressStream } from '@/app/services/mcpService';

const eventSource = createProgressStream(jobId, {
  onStdout: (data) => {
    console.log('Output:', data.message);
  },
  onComplete: (data) => {
    console.log('Completed:', data.message);
    closeProgressStream(eventSource);
  },
  onError: (error) => {
    console.error('Error:', error);
  }
});
```

---

#### `closeProgressStream(eventSource)`
Closes an SSE connection.

**Parameters:**
- `eventSource` (EventSource | null) - Connection to close

---

#### `startOrchestration(request)`
Starts an orchestration workflow (placeholder for future implementation).

**Parameters:**
```typescript
{
  command: string;
  context?: string;
  metadata?: Record<string, any>;
}
```

**Returns:**
```typescript
Promise<{
  success: boolean;
  message: string;
}>
```

---

#### `checkServerHealth()`
Checks if the MCP server is healthy.

**Returns:**
```typescript
Promise<{
  healthy: boolean;
  message: string;
}>
```

**Usage:**
```typescript
import { checkServerHealth } from '@/app/services/mcpService';

const health = await checkServerHealth();
if (health.healthy) {
  console.log('Server is up');
} else {
  console.error('Server is down:', health.message);
}
```

---

#### `retryRequest(requestFn, maxRetries?, delay?)`
Helper function to retry failed requests.

**Parameters:**
- `requestFn` (function) - Async function to retry
- `maxRetries` (number, optional) - Max retry attempts (default: from config)
- `delay` (number, optional) - Delay between retries in ms (default: from config)

**Usage:**
```typescript
import { retryRequest, startExportJob } from '@/app/services/mcpService';

const result = await retryRequest(
  () => startExportJob(subscriptionId, resourceGroup),
  3,
  2000
);
```

---

## Best Practices

1. **Always use the service layer** - Never make direct fetch calls from components or hooks
2. **Import config centrally** - Use `config` object instead of accessing `process.env` directly
3. **Handle errors** - Wrap service calls in try-catch blocks
4. **Use TypeScript types** - Import types from `@/app/types/*` for type safety
5. **Close connections** - Always close SSE connections when done
6. **Check server health** - Use `checkServerHealth()` before critical operations
7. **Use retry helper** - Wrap unstable network calls in `retryRequest()`

---

## Error Handling

All service functions throw errors that should be caught by the caller:

```typescript
try {
  const result = await startExportJob(subscriptionId, resourceGroup);
  // Handle success
} catch (error) {
  if (error instanceof Error) {
    console.error('Export failed:', error.message);
    // Show error to user
  }
}
```

Common errors:
- `Request timeout after Xms` - Request took too long
- `Failed to start export: 404` - Endpoint not found
- `Server unreachable` - Cannot connect to MCP server
- `Could not extract job ID from server response` - Invalid response format

---

## Testing

To test service functions:

```typescript
import { config, validateConfig } from '@/app/services/config';
import { checkServerHealth } from '@/app/services/mcpService';

// Validate configuration
const validation = validateConfig();
if (!validation.valid) {
  console.error('Config errors:', validation.errors);
}

// Check server health
const health = await checkServerHealth();
console.log('Server status:', health);
```

---

## Migration Guide

If you have existing code that makes direct API calls, migrate to the service layer:

**Before:**
```typescript
const response = await fetch('http://localhost:8080/messages', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ toolName: 'aztfexport', args: {...} })
});
```

**After:**
```typescript
import { startExportJob } from '@/app/services/mcpService';

const result = await startExportJob(subscriptionId, resourceGroup);
```

---

## Future Enhancements

Planned additions:
- Authentication service (OAuth, JWT)
- Caching layer (React Query integration)
- Request interceptors (logging, monitoring)
- WebSocket service (alternative to SSE)
- Mock service for testing
