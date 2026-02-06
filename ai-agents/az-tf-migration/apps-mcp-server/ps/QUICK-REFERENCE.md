# Export-AzToTerraform.ps1 - Quick Reference

## ✅ Configuration Summary

- **Script**: Export-AzToTerraform.ps1
- **Lines**: 1,555
- **Authentication**: Service Principal (environment variables) OR Azure CLI interactive
- **Reports**: HTML only (Excel disabled)
- **Storage**: Azure Blob Storage upload enabled
- **Mode**: Working `aztfexport rg` command (from Original-Export-AzToTerraform.ps1)

## 🚀 Quick Start with Service Principal

### 1. Set Environment Variables

```powershell
$env:AZURE_CLIENT_ID = "12345678-1234-1234-1234-123456789012"
$env:AZURE_CLIENT_SECRET = "your-secret-value"
$env:AZURE_TENANT_ID = "87654321-4321-4321-4321-210987654321"
```

### 2. Run Export

```powershell
.\Export-AzToTerraform.ps1 `
    -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" `
    -ResourceGroupName "rg-mcp-servers" `
    -StorageAccount "samcpstorage"
```

### 3. Check Results

**Local Output**: `C:\Exports\Azure-Terraform\rg-mcp-servers_<timestamp>\`
- `main.tf` - Terraform resources
- `providers.tf` - Provider configuration  
- `data-sources.tf` - External data sources
- `Export-Report-Latest.html` - **HTML report**

**Azure Storage**: `samcpstorage/aztfexport/`
- All files uploaded with timestamp

## 📋 What's Included vs Excluded

### ✅ Exported Resources (21 resources from rg-mcp-servers)

All resources **except** the excluded types below:

### ❌ Excluded Resource Types (38 types - built-in)

**Monitoring & Diagnostics**
- Microsoft.Insights/diagnosticSettings
- Microsoft.Insights/activityLogAlerts
- Microsoft.Insights/workbooks
- Microsoft.OperationalInsights/workspaces
- Microsoft.OperationsManagement/solutions

**Security & RBAC**
- Microsoft.Security/pricings
- Microsoft.Security/securityContacts
- Microsoft.Authorization/roleAssignments
- Microsoft.Authorization/policyAssignments
- Microsoft.Authorization/locks

**Networking** (Reference resources - handled separately)
- Microsoft.Network/virtualNetworks
- Microsoft.Network/networkSecurityGroups
- Microsoft.Network/applicationGateways
- Microsoft.Network/loadBalancers
- Microsoft.Network/publicIPAddresses
- And 23 more network types...

## 🔧 Authentication Options

### Option 1: Service Principal (Automated)

```powershell
# One-time setup
$env:AZURE_CLIENT_ID = "your-client-id"
$env:AZURE_CLIENT_SECRET = "your-secret"
$env:AZURE_TENANT_ID = "your-tenant-id"

# Run script - automatic authentication
.\Export-AzToTerraform.ps1 ...
```

**Output:**
```
Authenticating to Azure...
Using Service Principal authentication...
  Client ID: 1234****5678
  Tenant ID: 8765****4321
Service Principal authentication successful!
```

### Option 2: Interactive Login (Manual)

```powershell
# Login first
az login

# Run script - uses existing session
.\Export-AzToTerraform.ps1 ...
```

**Output:**
```
Authenticating to Azure...
Already authenticated to Azure
  User: user@example.com
  Tenant: 87654321-4321-4321-4321-210987654321
```

## 📊 Reports Generated

### HTML Report Only

**File**: `Export-Report-Latest.html`

**Contents**:
- Export summary (date, time, duration)
- Subscription and resource group details
- Resource counts (total, exported, excluded)
- List of exported resources with types
- List of excluded resources
- Data sources generated
- File sizes and upload status

**No Excel Report**: Excel generation code has been removed for simplicity

## 🔐 Required Permissions

### Service Principal Needs:

1. **Reader** role on subscription/resource group
   ```powershell
   az role assignment create --assignee $spId --role Reader --scope /subscriptions/$subId
   ```

2. **Storage Blob Data Contributor** role on storage account
   ```powershell
   az role assignment create --assignee-object-id $spObjectId --role "Storage Blob Data Contributor" --scope /subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$storage
   ```

## 📂 Output Structure

```
C:\Exports\Azure-Terraform\
└── rg-mcp-servers_20260206_143022\
    ├── main.tf                        # Main resources
    ├── providers.tf                    # Provider config
    ├── data-sources.tf                 # External data sources
    ├── terraform.tfstate               # State file
    ├── Export-Report-Latest.html       # HTML report
    └── exclude-resources.txt           # Exclusion list
```

## 🛠️ Troubleshooting

### "Service Principal authentication failed"

```powershell
# Test credentials
az login --service-principal `
    -u $env:AZURE_CLIENT_ID `
    -p $env:AZURE_CLIENT_SECRET `
    --tenant $env:AZURE_TENANT_ID
```

### "Insufficient permissions"

```powershell
# Check permissions
az role assignment list --assignee $env:AZURE_CLIENT_ID --all
```

### "Cannot upload to storage"

```powershell
# Grant storage access
az role assignment create `
    --assignee-object-id $(az ad sp show --id $env:AZURE_CLIENT_ID --query id -o tsv) `
    --role "Storage Blob Data Contributor" `
    --scope "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$storage"
```

## 📖 Documentation

- **Full Setup Guide**: [SERVICE-PRINCIPAL-SETUP.md](SERVICE-PRINCIPAL-SETUP.md)
- **aztfexport Docs**: https://github.com/Azure/aztfexport
- **Azure CLI Docs**: https://docs.microsoft.com/cli/azure/

## 🔄 Recent Changes

### v2.0 - Latest (February 2026)

✅ **Added**:
- Service Principal authentication via environment variables
- Enhanced authentication logging (masked credentials)
- Better error messages with solutions
- Comprehensive documentation

✅ **Fixed**:
- Restored working `aztfexport rg` command from original
- Removed failing individual resource export mode
- Simplified from 1,646 → 1,555 lines

❌ **Removed**:
- Excel report generation (HTML only)
- Complex ProcessStartInfo wrapper
- Individual resource export loop (~150 lines)
- Temporary workspace complexity

## 💡 Tips

1. **Use Service Principal** for automation/CI/CD
2. **HTML report** opens in any browser
3. **Storage upload** keeps historical exports
4. **Exclusion list** prevents network resource conflicts
5. **Check logs** for per-resource export progress

---

**Ready to use!** 🎉
