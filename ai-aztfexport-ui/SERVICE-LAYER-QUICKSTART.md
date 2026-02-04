# Quick Start - Service Layer

## ✅ Service Layer Architecture Implemented

All API calls and configuration have been moved to a centralized service layer.

---

## What Changed

### New Folder Structure
```
app/
├── services/          # NEW: All API calls here
│   ├── config.ts      # Configuration management
│   ├── mcpService.ts  # MCP Server API client
│   └── README.md      # Full documentation
│
├── types/             # NEW: Shared TypeScript types
│   ├── export.ts      # Export types
│   └── agent.ts       # Agent types
│
├── hooks/             # REFACTORED: Use services
│   ├── useExportProgress.ts
│   └── useAgentStream.ts
│
└── components/        # UPDATED: Import types from types/
    ├── AgentPipeline.tsx
    └── ConnectivityGuard.tsx
```

---

## Testing

### 1. Verify Configuration

Check that `.env.local` exists and contains:
```bash
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
```

If not, copy from example:
```bash
cp .env.local.example .env.local
```

### 2. Start the Application

```bash
cd ai-aztfexport-ui
npm run dev
```

### 3. Test Features

✅ **Migration Page** - Should work exactly as before
- Navigate to Migration page
- Enter subscription ID and resource group
- Click "Start Export"
- Watch real-time logs

✅ **Workflow Page** - Should work exactly as before
- Navigate to Workflow page
- Enter command with subscription ID and resource group
- Submit command
- Watch real-time logs

---

## Configuration

All configuration is now in `.env.local`:

```bash
# MCP Server
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080

# API Settings (optional)
NEXT_PUBLIC_API_TIMEOUT=30000
NEXT_PUBLIC_RETRY_ATTEMPTS=3

# Azure (optional)
NEXT_PUBLIC_AZURE_STORAGE_ACCOUNT=samcpstorage

# Features (optional)
NEXT_PUBLIC_ENABLE_REAL_MIGRATION=true
NEXT_PUBLIC_AUTO_RECONNECT=true
```

---

## Key Improvements

### ✅ Centralized Configuration
- All URLs and keys in one place (`.env.local`)
- No hardcoded values in code
- Type-safe configuration access

### ✅ Service Layer
- All API calls go through `mcpService.ts`
- Consistent error handling
- Easy to mock for testing
- Timeout and retry built-in

### ✅ Type Safety
- Shared types in `types/` folder
- Import types: `import type { ... } from '@/app/types/...'`
- Consistent interfaces across app

### ✅ Backward Compatible
- All existing code works unchanged
- Same hook APIs
- Same component imports
- No breaking changes

---

## Using the Service Layer

### Import Configuration
```typescript
import { config } from '@/app/services/config';

// Access any config value
const serverUrl = config.mcpServer.baseUrl;
const timeout = config.mcpServer.timeout;
```

### Import Services
```typescript
import { 
  startExportJob, 
  createProgressStream,
  checkServerHealth 
} from '@/app/services/mcpService';

// Start an export
const result = await startExportJob(subscriptionId, resourceGroup);

// Check server health
const health = await checkServerHealth();
```

### Import Types
```typescript
import type { ProgressLog } from '@/app/types/export';
import type { AgentType } from '@/app/types/agent';
```

---

## Health Check

Add to your code to check if MCP server is available:

```typescript
import { checkServerHealth } from '@/app/services/mcpService';

const health = await checkServerHealth();
if (!health.healthy) {
  console.error('MCP Server is offline:', health.message);
}
```

---

## Documentation

📚 **Full Documentation:**
- [app/services/README.md](app/services/README.md) - Complete service layer docs
- [SERVICE-LAYER-IMPLEMENTATION.md](SERVICE-LAYER-IMPLEMENTATION.md) - Implementation summary
- [.env.local.example](.env.local.example) - Configuration template

---

## Troubleshooting

### Problem: "Module not found" errors

**Solution:** Restart dev server
```bash
# Stop: Ctrl+C
# Start again:
npm run dev
```

### Problem: Configuration not loading

**Solution:** Check `.env.local` file exists and has correct format
```bash
# Should have this:
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080

# NOT this (no quotes):
NEXT_PUBLIC_MCP_SERVER_URL="http://localhost:8080"
```

### Problem: MCP Server not connecting

**Solution:** Verify server is running
```bash
# In another terminal:
cd ai-agents/az-tf-migration/apps-mcp-server
npm start
```

---

## Next Steps

### Optional: Add Health Check UI

Add server status indicator to your UI:

```typescript
import { checkServerHealth } from '@/app/services/mcpService';
import { useEffect, useState } from 'react';

const [serverHealthy, setServerHealthy] = useState(true);

useEffect(() => {
  const check = async () => {
    const health = await checkServerHealth();
    setServerHealthy(health.healthy);
  };
  
  check();
  const interval = setInterval(check, 30000); // Check every 30s
  
  return () => clearInterval(interval);
}, []);

return (
  <div>
    Server: {serverHealthy ? '🟢 Online' : '🔴 Offline'}
  </div>
);
```

---

## Summary

✅ Service layer created  
✅ Configuration centralized  
✅ Types extracted to types folder  
✅ Hooks refactored  
✅ Components updated  
✅ Documentation complete  
✅ Backward compatible  
✅ Ready to use!

**Everything should work exactly as before, but now with better architecture!** 🎉
