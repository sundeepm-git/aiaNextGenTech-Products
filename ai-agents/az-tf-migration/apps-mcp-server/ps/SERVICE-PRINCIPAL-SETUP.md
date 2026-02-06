# Service Principal Authentication Setup

This guide explains how to use the Export-AzToTerraform.ps1 script with Service Principal authentication for automated, unattended execution.

## Prerequisites

- Azure CLI installed (`az --version` should work)
- Appropriate permissions to create Service Principals in Azure AD
- Access to the Azure subscription and resource groups you want to export

## Step 1: Create Service Principal

### Option A: Using Azure CLI (Recommended)

```powershell
# Set variables
$subscriptionId = "your-subscription-id"
$spName = "sp-aztf-export"

# Create Service Principal with Contributor role at subscription level
$sp = az ad sp create-for-rbac `
    --name $spName `
    --role Reader `
    --scopes "/subscriptions/$subscriptionId" `
    --output json | ConvertFrom-Json

# Display credentials (SAVE THESE SECURELY - they won't be shown again!)
Write-Host "Service Principal Created Successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "CLIENT_ID (Application ID): $($sp.appId)" -ForegroundColor Yellow
Write-Host "CLIENT_SECRET (Password): $($sp.password)" -ForegroundColor Yellow
Write-Host "TENANT_ID: $($sp.tenant)" -ForegroundColor Yellow
```

**Note**: The `Reader` role is sufficient for exporting resources. Use `Contributor` if you plan to deploy the exported Terraform.

### Option B: Using Azure Portal

1. Navigate to **Azure Active Directory** > **App registrations**
2. Click **New registration**
3. Name: `sp-aztf-export`
4. Click **Register**
5. Note the **Application (client) ID** and **Directory (tenant) ID**
6. Go to **Certificates & secrets** > **New client secret**
7. Add description, set expiry, create
8. **Copy the secret value immediately** (it won't be shown again)
9. Go to your **Subscription** > **Access control (IAM)**
10. Click **Add role assignment**
11. Select **Reader** role
12. Search for your app registration name
13. Click **Review + assign**

## Step 2: Grant Storage Access (for uploading results)

The Service Principal needs permission to upload to Azure Storage:

```powershell
# Set variables
$storageAccountName = "samcpstorage"
$resourceGroup = "your-rg-name"
$spObjectId = az ad sp list --display-name $spName --query "[0].id" -o tsv

# Assign Storage Blob Data Contributor role
az role assignment create `
    --assignee-object-id $spObjectId `
    --assignee-principal-type ServicePrincipal `
    --role "Storage Blob Data Contributor" `
    --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccountName"
```

## Step 3: Configure Environment Variables

### For PowerShell Session

```powershell
# Set environment variables (current session only)
$env:AZURE_CLIENT_ID = "your-client-id"
$env:AZURE_CLIENT_SECRET = "your-client-secret"
$env:AZURE_TENANT_ID = "your-tenant-id"

# Verify they're set
Write-Host "CLIENT_ID: $env:AZURE_CLIENT_ID"
Write-Host "TENANT_ID: $env:AZURE_TENANT_ID"
Write-Host "SECRET: $($env:AZURE_CLIENT_SECRET.Substring(0,4))****"
```

### For System Environment Variables (Persistent)

#### Windows

```powershell
# Set as system environment variables (requires admin)
[System.Environment]::SetEnvironmentVariable('AZURE_CLIENT_ID', 'your-client-id', 'User')
[System.Environment]::SetEnvironmentVariable('AZURE_CLIENT_SECRET', 'your-client-secret', 'User')
[System.Environment]::SetEnvironmentVariable('AZURE_TENANT_ID', 'your-tenant-id', 'User')

# Restart PowerShell to load new environment variables
```

#### Linux/macOS

Add to `~/.bashrc` or `~/.zshrc`:

```bash
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"
```

Then reload: `source ~/.bashrc`

### For Azure DevOps Pipeline

```yaml
variables:
  AZURE_CLIENT_ID: $(clientId)  # From secure variable
  AZURE_CLIENT_SECRET: $(clientSecret)  # From secure variable
  AZURE_TENANT_ID: $(tenantId)  # From secure variable

steps:
- task: PowerShell@2
  inputs:
    filePath: 'Export-AzToTerraform.ps1'
    arguments: '-SubscriptionId "$(subscriptionId)" -ResourceGroupName "$(resourceGroup)" -StorageAccount "$(storageAccount)"'
```

### For GitHub Actions

```yaml
env:
  AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
  AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}

steps:
  - name: Export to Terraform
    shell: pwsh
    run: |
      ./Export-AzToTerraform.ps1 `
        -SubscriptionId "${{ secrets.SUBSCRIPTION_ID }}" `
        -ResourceGroupName "my-rg" `
        -StorageAccount "samcpstorage"
```

## Step 4: Run the Export Script

```powershell
# Navigate to script directory
cd "c:\path\to\ps"

# Run export
.\Export-AzToTerraform.ps1 `
    -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" `
    -ResourceGroupName "rg-mcp-servers" `
    -StorageAccount "samcpstorage"
```

**Expected Output:**
```
Starting Azure to Terraform Export...
Authenticating to Azure...
Using Service Principal authentication...
  Client ID: 1234****5678
  Tenant ID: 8765****4321
Service Principal authentication successful!
Already authenticated to Azure
  User: <service-principal-id>
  Tenant: 87654321-4321-4321-4321-210987654321
...
```

## Step 5: Verify Export

Check the generated files:
- **Local**: `C:\Exports\Azure-Terraform\rg-mcp-servers_YYYYMMDD_HHmmss\`
  - `main.tf` - Terraform resources
  - `providers.tf` - Provider configuration
  - `data-sources.tf` - External data sources
  - `Export-Report-Latest.html` - HTML report

- **Azure Storage**: `samcpstorage` / `aztfexport` container
  - All above files uploaded with timestamp

## Troubleshooting

### Error: "Service Principal authentication failed"

**Causes:**
- Incorrect credentials
- Service Principal deleted or expired
- Secret expired

**Solution:**
```powershell
# Test authentication manually
az login --service-principal `
    -u $env:AZURE_CLIENT_ID `
    -p $env:AZURE_CLIENT_SECRET `
    --tenant $env:AZURE_TENANT_ID

# Check if successful
az account show
```

### Error: "Insufficient permissions"

**Cause:** Service Principal doesn't have Reader role on subscription/resource group

**Solution:**
```powershell
# Verify role assignments
az role assignment list `
    --assignee $env:AZURE_CLIENT_ID `
    --all

# Add Reader role if missing
az role assignment create `
    --assignee $env:AZURE_CLIENT_ID `
    --role Reader `
    --scope "/subscriptions/<subscription-id>"
```

### Error: "Cannot upload to storage"

**Cause:** Service Principal doesn't have Storage Blob Data Contributor role

**Solution:**
```powershell
# Get Service Principal object ID
$spObjectId = az ad sp show --id $env:AZURE_CLIENT_ID --query id -o tsv

# Grant storage access
az role assignment create `
    --assignee-object-id $spObjectId `
    --assignee-principal-type ServicePrincipal `
    --role "Storage Blob Data Contributor" `
    --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage-name>"
```

## Security Best Practices

1. **Secret Rotation**: Rotate Service Principal secrets every 90 days
2. **Least Privilege**: Use `Reader` role only (not `Contributor`)
3. **Scope Limitation**: Scope to specific resource groups if possible
4. **Secret Storage**: Use Azure Key Vault or secure CI/CD secrets
5. **Audit Logging**: Enable activity logging for Service Principal actions

## Secret Rotation

```powershell
# Create new secret
$newSecret = az ad sp credential reset `
    --id $env:AZURE_CLIENT_ID `
    --query password -o tsv

# Update environment variable
$env:AZURE_CLIENT_SECRET = $newSecret

# Verify
.\Export-AzToTerraform.ps1 -SubscriptionId "..." -ResourceGroupName "..." -StorageAccount "..."
```

## Scheduled Automation

### Windows Task Scheduler

```powershell
# Create scheduled task
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-File C:\path\to\Export-AzToTerraform.ps1 -SubscriptionId 'xxx' -ResourceGroupName 'my-rg' -StorageAccount 'samcpstorage'"

$trigger = New-ScheduledTaskTrigger -Daily -At 2am

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

Register-ScheduledTask `
    -TaskName "Azure Terraform Export" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM"
```

### Linux Cron

```bash
# Edit crontab
crontab -e

# Add entry (runs daily at 2 AM)
0 2 * * * /usr/bin/pwsh /path/to/Export-AzToTerraform.ps1 -SubscriptionId "xxx" -ResourceGroupName "my-rg" -StorageAccount "samcpstorage" >> /var/log/aztf-export.log 2>&1
```

## Additional Resources

- [Azure Service Principal Documentation](https://learn.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli)
- [Azure RBAC Roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)
- [aztfexport Documentation](https://github.com/Azure/aztfexport)
