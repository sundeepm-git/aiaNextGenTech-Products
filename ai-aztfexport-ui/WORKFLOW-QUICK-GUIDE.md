# Quick Guide: Real-time Migration Progress in Workflow

## 🚀 How to Trigger Real Migration from Workflow Page

### Method 1: Use the Quick Suggestion (Easiest)

1. Navigate to **Workflow** page
2. Click the **"🚀 Real Migration"** suggestion chip
3. Command auto-fills with working example
4. Click the **arrow button** to submit

```
┌────────────────────────────────────────────────────┐
│  FoundryCommandCenter                              │
│                                                    │
│  [Describe your Azure migration task...        ]→ │
│                                                    │
│  Suggestions:                                      │
│  [🚀 Real Migration] [Assess Subscription] [...]  │
│          ↑                                         │
│      CLICK HERE                                    │
└────────────────────────────────────────────────────┘
```

---

### Method 2: Type Your Own Command

Enter any command that includes BOTH:
- **Subscription ID** (after word "subscription")
- **Resource Group** (after "resource group" or "RG")

**Examples that work:**

```
✅ "I want to migrate Subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 
    and ResourceGroup rg-mcp-servers"

✅ "Migrate subscription: abc-123 resource group: my-rg"

✅ "Export subscription xyz123 RG my-resource-group to terraform"

✅ "subscription <id> and rg <name>"
```

---

## 📊 What Happens Next

### Instant Feedback

**1. Migration Status Badge Appears:**
```
┌────────────────────────────────────────────────────┐
│ 🟢 Real-time Migration: connected                 │
└────────────────────────────────────────────────────┘
```

**2. Terminal Shows Live Output:**
```
┌────────────────────────────────────────────────────┐
│ 📟 Agent Context: MIGRATION                        │
│ ┌────────────────────────────────────────────────┐ │
│ │ 10:45:00  [INFO] Starting export...            │ │
│ │ 10:45:05  [STDOUT] Initializing aztfexport...  │ │
│ │ 10:45:10  [STDOUT] Found 15 resources...       │ │
│ │ 10:45:15  [STDOUT] Importing resources...      │ │
│ │ 10:45:30  [STDOUT] Uploading to storage...     │ │
│ │ 10:45:35  [SUCCESS] Export complete ✅         │ │
│ └────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────┘
```

**3. Agent Pipeline Shows Progress:**
```
┌────────────────────────────────────────────────────┐
│  [ORCHESTRATOR] → [ASSESSMENT] → [MIGRATION] → ... │
│                                      ↑              │
│                                  (Active)           │
└────────────────────────────────────────────────────┘
```

---

## 🔄 Switching Between Views

You can view different perspectives:

### View Real Migration Logs
Click the **"MIGRATION"** badge or status indicator

### View Workflow Simulation
Click **"ORCHESTRATOR"**, **"ASSESSMENT"**, or **"REFACTOR"**

### View All Logs
Select **"Global"** view (if available)

```
Terminal Title Changes:
┌─────────────────────────────────┐
│ Agent Context: MIGRATION        │  ← Real SSE logs
│ Agent Context: ORCHESTRATOR     │  ← Simulated logs
│ Agent Context: ASSESSMENT       │  ← Simulated logs
│ Global Event Stream             │  ← All simulated logs
└─────────────────────────────────┘
```

---

## ✅ Success Indicators

### When Export Completes:

**Badge Updates:**
```
🟢 Real-time Migration: completed ✓ Export Complete
```

**Terminal Shows:**
```
[SUCCESS] Export completed successfully ✅

Files uploaded to:
aztfExport/d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-mcp-servers/
```

**Files in Azure Storage:**
- main.tf
- variables.tf
- provider.tf
- terraform.tfstate
- html-report/

---

## ❌ Troubleshooting

### Problem: Migration Status Badge Doesn't Appear

**Cause:** Command didn't include both subscription ID and resource group

**Solution:** Make sure your command has:
- Word "subscription" followed by ID
- Word "resourcegroup" or "RG" followed by name

**Example:**
```
❌ "Migrate my resources"  (missing both)
❌ "Subscription abc123"   (missing RG)
✅ "Subscription abc123 ResourceGroup my-rg"
```

---

### Problem: Terminal Shows "Disconnected"

**Cause:** MCP server not running

**Solution:**
```bash
cd ai-agents/az-tf-migration/apps-mcp-server
npm start
```

---

### Problem: Logs Stop Streaming

**Cause:** SSE connection lost

**Solution:**
- Wait 3 seconds for auto-reconnect
- Or click **"Reconnect"** button if available
- Check MCP server console for errors

---

### Problem: Simulation vs Real - How to Tell?

**Real Migration Indicators:**
- ✅ Migration status badge visible
- ✅ Logs show PowerShell/aztfexport output
- ✅ Terminal title: "Agent Context: MIGRATION"

**Simulation Indicators:**
- ❌ No migration status badge
- 📝 Logs show agent steps (orchestrator, assessment, etc.)
- 📝 Terminal title: "Agent Context: ORCHESTRATOR" or similar

---

## 🎯 Quick Tips

### Tip 1: Use Suggestions for First Test
The **"🚀 Real Migration"** chip has a working example - click it!

### Tip 2: Both Views Work Together
- Workflow simulation continues running
- Real migration streams in parallel
- Switch between views anytime

### Tip 3: Check MCP Server First
Before testing, make sure MCP server is running:
```bash
# Terminal 1
cd apps-mcp-server
npm start

# Terminal 2  
cd ai-aztfexport-ui
npm run dev
```

### Tip 4: Watch the Status Badge
The colored dot animation tells you connection status:
- 🟡 Pulsing yellow = Connecting
- 🟢 Pulsing green = Connected (streaming)
- 🔵 Static blue = Completed
- 🔴 Static red = Error

---

## 📋 Command Format Reference

### Required Pattern

```
<any text> Subscription <ID> <any text> ResourceGroup <NAME> <any text>
```

### Keyword Variations

**For Subscription:**
- `Subscription`
- `subscription:`
- `SUBSCRIPTION`

**For Resource Group:**
- `ResourceGroup`
- `resource group`
- `RG`
- `rg:`

**ID Format:**
- Can include angle brackets: `<id>`
- Will be auto-stripped: `<d0f1884d-...>` → `d0f1884d-...`
- Case-insensitive

---

## 🔍 Example Commands

### Simple Format
```
Subscription abc123 ResourceGroup my-rg
```

### Natural Language
```
I want to migrate Subscription abc123 and ResourceGroup my-rg
```

### With Context
```
Please export subscription abc123 resource group my-rg to terraform
with state management enabled
```

### Formal Style
```
subscription: abc123
resource group: my-rg
```

All of these will trigger the **same real migration**! 🎉

---

## 📖 Related Docs

- [WORKFLOW-MIGRATION-INTEGRATION.md](./WORKFLOW-MIGRATION-INTEGRATION.md) - Detailed technical docs
- [EXPORT-INTEGRATION-COMPLETE.md](../apps-mcp-server/EXPORT-INTEGRATION-COMPLETE.md) - Export functionality
- [SSE-INTEGRATION-GUIDE.md](./SSE-INTEGRATION-GUIDE.md) - SSE technical details
- [QUICK-START.md](./QUICK-START.md) - General getting started guide

---

**Ready to try real-time migration? Click the 🚀 Real Migration chip and watch it work!**
