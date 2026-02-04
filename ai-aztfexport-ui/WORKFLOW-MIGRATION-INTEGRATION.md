# Workflow Page - Real-time Migration Progress Integration

## Overview

The **Workflow page** now seamlessly integrates **real-time migration progress** alongside the simulated workflow visualization. When users specify subscription ID and resource group in their natural language command, the system automatically:

1. **Parses** the command to extract Azure credentials
2. **Triggers** real migration export via MCP Server SSE
3. **Displays** live progress in the terminal viewer
4. **Maintains** workflow simulation for orchestration visualization

---

## Architecture

### Dual-Mode Operation

```
┌────────────────────────────────────────────────────────────┐
│                    WORKFLOW PAGE                           │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  FoundryCommandCenter (Natural Language Input)       │ │
│  │  "I want to migrate Subscription X and RG Y"        │ │
│  └──────────────────────────────────────────────────────┘ │
│                         │                                  │
│                         ├───────────────┬─────────────────┐│
│                         │               │                 ││
│                    ┌────▼────┐    ┌────▼────┐           ││
│                    │ Parser  │    │ Parser  │           ││
│                    │  (Sub+RG)│    │(General)│           ││
│                    └────┬────┘    └────┬────┘           ││
│                         │               │                 ││
│                 ┌───────▼──────┐  ┌────▼──────┐         ││
│                 │  Real SSE    │  │ Simulated │         ││
│                 │  Migration   │  │ Workflow  │         ││
│                 │ (MCP Server) │  │(useAgent  │         ││
│                 │              │  │ Stream)   │         ││
│                 └───────┬──────┘  └────┬──────┘         ││
│                         │               │                 ││
│                         └───────┬───────┘                 ││
│                                 ▼                         ││
│  ┌──────────────────────────────────────────────────────┐ │
│  │         Live Terminal (Merged Logs)                  │ │
│  │  • Real migration stdout/stderr (if triggered)       │ │
│  │  • Simulated workflow steps (always active)          │ │
│  │  • Agent pipeline visualization                      │ │
│  └──────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

---

## How It Works

### 1. Command Parsing

When a user enters a command, the system uses regex to detect Azure credentials:

```typescript
// Extract Subscription ID
const subIdMatch = cmd.match(/subscription[\s:]+(<?[a-z0-9-]+>?)/i);

// Extract Resource Group
const rgMatch = cmd.match(/(?:resource\s?group|rg)[\s:]+(<?[\w-]+>?)/i);
```

**Supported Formats:**
- `"Subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2"`
- `"subscription: <subscription-id>"`
- `"ResourceGroup rg-mcp-servers"`
- `"RG: <rg-name>"`
- `"resource group my-rg"`

---

### 2. Dual Execution

```typescript
if (subIdMatch && rgMatch) {
  // Extract IDs (remove angle brackets)
  const subscriptionId = subIdMatch[1].replace(/[<>]/g, '');
  const resourceGroup = rgMatch[1].replace(/[<>]/g, '');
  
  // ✅ Start REAL migration
  setShowRealMigration(true);
  setSelectedView('migration');
  startExport(subscriptionId, resourceGroup, cmd);
}

// ✅ Always start simulation (for workflow visualization)
startOrchestration(cmd);
```

**Result:**
- Real SSE connection streams actual migration logs
- Simulation provides workflow visualization
- User sees both perspectives in UI

---

### 3. Log Display Strategy

```typescript
<LiveTerminal 
  logs={showRealMigration && selectedView === 'migration' 
    ? migrationLogs    // Show REAL logs when migration active
    : logsToShow       // Show SIMULATED logs otherwise
  }
  title={selectedView === 'global' 
    ? 'Global Event Stream' 
    : `Agent Context: ${selectedView.toUpperCase()}`
  }
/>
```

**Log Switching:**
- **Migration View:** Real-time SSE logs from MCP server
- **Other Views:** Simulated agent-specific logs
- **Global View:** All simulated logs merged

---

## User Experience

### Example Workflow

#### Step 1: Navigate to Workflow Page
```
Home → Sidebar → Click "Workflow"
```

#### Step 2: Enter Natural Language Command
```
Input: "I want to migrate Subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 
        and ResourceGroup rg-mcp-servers"
```

#### Step 3: System Parses and Executes
- ✅ Parser detects subscription ID and resource group
- ✅ Real migration starts via SSE
- ✅ Workflow simulation starts
- ✅ View switches to "migration"
- ✅ Migration status badge appears

#### Step 4: Watch Real-time Progress

**Status Badge Appears:**
```
┌────────────────────────────────────────────────────────┐
│ 🟢 Real-time Migration: connected                     │
│                                    ✓ Export Complete   │
└────────────────────────────────────────────────────────┘
```

**Terminal Shows Live Output:**
```
10:45:00  [INFO] Starting export for subscription: d0f1884d-...
10:45:01  [SUCCESS] Export job created with ID: xyz123
10:45:02  [INFO] Connected to export progress stream
10:45:05  [STDOUT] Initializing aztfexport...
10:45:07  [STDOUT] Connecting to Azure subscription...
10:45:10  [STDOUT] Found 15 resources in rg-mcp-servers
10:45:15  [STDOUT] Importing Microsoft.Storage/storageAccounts...
10:45:18  [STDOUT] Generating Terraform files...
10:45:30  [STDOUT] Uploading to Azure Storage...
10:45:35  [SUCCESS] Export completed successfully ✅
```

#### Step 5: Switch Between Views
- Click **"ORCHESTRATOR"** in AgentPipeline → See workflow simulation
- Click **"MIGRATION"** badge → See real migration logs
- Click **"ASSESSMENT"** → See assessment agent logs
- Click **"Global"** → See all agent logs

---

## UI Components

### Migration Status Badge

**Location:** Above LiveTerminal when real migration is running

**States:**

| Status | Display | Color | Animation |
|--------|---------|-------|-----------|
| **connecting** | Real-time Migration: connecting | Yellow | Pulsing dot |
| **connected** | Real-time Migration: connected | Green | Pulsing dot |
| **completed** | Real-time Migration: completed ✓ | Green | Static + checkmark |
| **error** | Real-time Migration: error | Red | Static |

**Code:**
```tsx
{showRealMigration && migrationRunning && (
  <div className="mb-4 p-3 bg-gradient-to-r from-sky-50 to-blue-50 
                  border border-sky-200 rounded-lg flex items-center gap-3">
    <div className="flex items-center gap-2">
      <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span>
      <span className="text-sm font-semibold text-sky-700">
        Real-time Migration: {migrationStatus}
      </span>
    </div>
    {migrationStatus === 'completed' && (
      <span className="ml-auto text-xs text-green-600 font-mono">
        ✓ Export Complete
      </span>
    )}
  </div>
)}
```

---

### FoundryCommandCenter Suggestions

Updated suggestions to include **real migration example**:

```typescript
const SUGGESTIONS = [
  { 
    label: "🚀 Real Migration", 
    value: "I want to migrate Subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 
            and ResourceGroup rg-mcp-servers" 
  },
  { 
    label: "Assess Subscription", 
    value: "I just want to assess my Azure subscription for migration candidates" 
  },
  { 
    label: "Refactor Codebase", 
    value: "I just want to do code refactoring based on Subscription <ID>, 
            Name <Name>, and RG <RG>" 
  }
];
```

**Clicking "🚀 Real Migration"** → Fills input with working example including real subscription ID

---

## State Management

### Hooks Used

#### useAgentStream (Simulation)
```typescript
const { 
  agents,           // Agent states
  activeAgent,      // Currently active agent
  streamStatus,     // Connection status
  startOrchestration, // Start simulation
  reconnect,        // Reconnect simulation
  terminalLogs      // Simulated logs
} = useAgentStream();
```

#### useExportProgress (Real Migration)
```typescript
const {
  logs: migrationLogs,       // Real SSE logs
  status: migrationStatus,   // 'connecting' | 'connected' | 'completed'
  isRunning: migrationRunning, // Boolean
  startExport,               // Start real export
  reconnect: reconnectMigration, // Reconnect SSE
  clearLogs: clearMigrationLogs  // Clear logs
} = useExportProgress();
```

### State Variables

```typescript
// Track if real migration is active
const [showRealMigration, setShowRealMigration] = useState(false);

// Current view selection
const [selectedView, setSelectedView] = useState<AgentType | 'global'>('global');
```

---

## Command Parsing Logic

### Regex Patterns

```typescript
// Subscription ID Pattern
/subscription[\s:]+(<?[a-z0-9-]+>?)/i

// Matches:
// - "Subscription d0f1884d-..."
// - "subscription: <id>"
// - "SUBSCRIPTION abc123"

// Resource Group Pattern
/(?:resource\s?group|rg)[\s:]+(<?[\w-]+>?)/i

// Matches:
// - "ResourceGroup rg-name"
// - "resource group my-rg"
// - "RG: <rg-name>"
// - "rg my-resource-group"
```

### ID Extraction

```typescript
// Remove angle brackets if present
const subscriptionId = subIdMatch[1].replace(/[<>]/g, '');
const resourceGroup = rgMatch[1].replace(/[<>]/g, '');

// Examples:
// "<id>" → "id"
// "id" → "id"
```

---

## View Selection Logic

### Auto-Switch Behavior

```typescript
if (subIdMatch && rgMatch) {
  // Real migration detected → Switch to migration view
  setShowRealMigration(true);
  setSelectedView('migration');
  startExport(subscriptionId, resourceGroup, cmd);
}

// If no credentials found, show orchestrator
if (!subIdMatch || !rgMatch) {
  setSelectedView('orchestrator');
}
```

### Manual Switching

Users can switch views by:
1. Clicking agent badges in AgentPipeline
2. Clicking view selector dropdown (if implemented)
3. System auto-switches based on active agent

---

## Terminal Log Display

### Log Source Priority

```typescript
logs={
  showRealMigration && selectedView === 'migration' 
    ? migrationLogs    // Priority 1: Real migration logs
    : logsToShow       // Priority 2: Simulated logs
}
```

### Log Format

**Real Migration Logs:**
```typescript
{
  timestamp: '10:45:05',
  type: 'stdout' | 'stderr' | 'info' | 'success' | 'error',
  message: 'Initializing aztfexport...',
  source: 'MCP Server SSE'
}
```

**Simulated Workflow Logs:**
```typescript
{
  timestamp: '10:45:05',
  agent: 'orchestrator' | 'assessment' | 'migration' | 'refactor',
  message: 'Step 1: Validating prerequisites...',
  source: 'useAgentStream'
}
```

---

## Error Handling

### Scenario 1: Missing Credentials

**Command:** `"I want to migrate my resources"`

**Behavior:**
- ❌ Real migration NOT triggered (missing sub ID and RG)
- ✅ Workflow simulation starts
- ✅ View switches to 'orchestrator'
- ℹ️ User sees simulated workflow only

---

### Scenario 2: Partial Credentials

**Command:** `"Migrate Subscription abc123"`

**Behavior:**
- ❌ Real migration NOT triggered (missing RG)
- ✅ Workflow simulation starts
- ℹ️ System requires BOTH subscription ID AND resource group

---

### Scenario 3: MCP Server Offline

**Behavior:**
- ✅ Workflow simulation works (local)
- ❌ Real migration fails with connection error
- 🔴 Error displayed in terminal
- ⚠️ Migration status badge shows 'disconnected'

---

### Scenario 4: SSE Connection Lost

**Behavior:**
- 🔄 Auto-reconnect in 3 seconds
- 📊 Migration status badge shows 'disconnected'
- ℹ️ Logs remain visible
- 🔘 Manual reconnect button available

---

## Benefits

### 1. Unified Interface
- Single page for both simulation and real execution
- No need to switch between pages
- Consistent user experience

### 2. Intelligent Parsing
- Natural language input automatically detected
- No separate input fields required
- Works with various command formats

### 3. Dual Visibility
- See workflow orchestration (simulation)
- See actual export progress (real-time)
- Switch between views on demand

### 4. Progressive Enhancement
- Works without real credentials (simulation only)
- Enhances when credentials provided (real migration)
- Graceful degradation if MCP server unavailable

---

## Testing Guide

### Test Case 1: Real Migration Trigger

**Input:**
```
"I want to migrate Subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 
 and ResourceGroup rg-mcp-servers"
```

**Expected:**
- ✅ Migration status badge appears
- ✅ View switches to 'migration'
- ✅ Real logs stream in terminal
- ✅ AgentPipeline shows workflow simulation
- ✅ Can switch between migration and agent views

---

### Test Case 2: Simulation Only

**Input:**
```
"I want to assess my Azure subscription"
```

**Expected:**
- ✅ Workflow simulation starts
- ✅ View switches to 'orchestrator'
- ✅ Simulated logs appear
- ❌ Migration status badge NOT visible
- ✅ AgentPipeline shows progress

---

### Test Case 3: View Switching

**Steps:**
1. Trigger real migration
2. Click "ORCHESTRATOR" badge
3. Click "ASSESSMENT" badge
4. Switch back to "MIGRATION"

**Expected:**
- ✅ Terminal content changes with each view
- ✅ Migration logs preserved when switching back
- ✅ Status badge remains visible throughout

---

### Test Case 4: Quick Suggestion Click

**Steps:**
1. Click "🚀 Real Migration" suggestion chip
2. Command fills input
3. Click Submit arrow

**Expected:**
- ✅ Real migration starts immediately
- ✅ Uses pre-filled subscription ID and RG
- ✅ Migration status badge appears
- ✅ Live logs stream

---

## Configuration

### Environment Variables

**UI (.env.local):**
```env
NEXT_PUBLIC_MCP_SERVER_URL=http://localhost:8080
```

**MCP Server (.env):**
```env
storageAccount=samcpstorage
PORT=8080
```

---

## Limitations

### Current Constraints

1. **Requires Both Credentials**
   - Must have BOTH subscription ID AND resource group
   - Partial matches won't trigger real migration

2. **Single Active Migration**
   - Only one real migration at a time
   - Starting new migration stops previous

3. **Parser Simplicity**
   - Uses regex (not NLP)
   - Requires specific keywords
   - Case-insensitive but format-sensitive

4. **No Validation**
   - Doesn't validate subscription ID format
   - Doesn't check if resource group exists
   - Errors appear in terminal during execution

---

## Future Enhancements

### Potential Improvements

1. **Smart Parsing**
   - Use LLM for command interpretation
   - Support more natural variations
   - Extract context from previous commands

2. **Credential Validation**
   - Pre-validate subscription ID format
   - Check resource group existence
   - Show warnings before starting

3. **Multi-Migration Support**
   - Queue multiple migrations
   - Parallel execution
   - Migration history/queue UI

4. **Enhanced Status**
   - Progress percentage
   - Estimated time remaining
   - Resource count imported

5. **Log Filtering**
   - Filter by log type (stdout, stderr, etc.)
   - Search within logs
   - Export logs to file

---

## Summary

### ✅ Integration Complete

The Workflow page now seamlessly combines:

1. **Natural Language Interface** → FoundryCommandCenter
2. **Intelligent Parsing** → Regex-based credential extraction
3. **Dual Execution** → Real migration + Workflow simulation
4. **Live Progress** → SSE streaming from MCP server
5. **Flexible Views** → Switch between migration and agent logs
6. **Status Indicators** → Real-time migration status badge

### 🎯 User Benefits

- **Single Command:** Natural language triggers everything
- **Real Progress:** Actual migration logs, not simulation
- **Workflow Context:** See orchestration alongside execution
- **Flexibility:** Works with or without credentials
- **Visibility:** Status badges and live terminal updates

### 📚 Documentation

- [WORKFLOW-MIGRATION-INTEGRATION.md](./WORKFLOW-MIGRATION-INTEGRATION.md) - This file
- [EXPORT-INTEGRATION-COMPLETE.md](../apps-mcp-server/EXPORT-INTEGRATION-COMPLETE.md) - Export details
- [SSE-INTEGRATION-GUIDE.md](./SSE-INTEGRATION-GUIDE.md) - Technical SSE guide
- [QUICK-START.md](./QUICK-START.md) - User getting started guide

---

**The Workflow page now displays real-time migration progress automatically when users provide Azure credentials!** 🎉
