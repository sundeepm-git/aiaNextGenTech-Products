# Output Destination Configuration

This project supports two output destinations for assessment reports, aztfexport files, and refactored Terraform code:

1. **Azure Blob Storage** (default)
2. **GitHub Repository**

## Configuration

All configuration is managed through the `.env` file in the root directory.

### Environment Variables

```env
# Output Destination Configuration
# Options: "azure" or "github"
OUTPUT_DESTINATION=azure

# Azure Storage Configuration (when OUTPUT_DESTINATION=azure)
storageAccountRG=rg-mcp-servers
storageAccount=samcpstorage

# GitHub Configuration (when OUTPUT_DESTINATION=github)
GITHUB_TOKEN=your-github-personal-access-token
GITHUB_OWNER=your-github-username-or-org
GITHUB_REPO=your-repo-name
GITHUB_BRANCH=main

# Output Folder Names (used for both destinations)
ASSESSMENT_FOLDER=assessment-reports
AZTFEXPORT_FOLDER=aztfexport
CODE_REFACTORED_FOLDER=code-refactored
```

## Setup Instructions

### Option 1: Azure Blob Storage (Default)

1. Set `OUTPUT_DESTINATION=azure` in `.env`
2. Configure Azure Storage account details:
   ```env
   storageAccountRG=your-resource-group
   storageAccount=your-storage-account-name
   ```
3. Ensure you're logged in to Azure CLI:
   ```bash
   az login
   ```

**Output Structure in Azure:**
- Container: `assessment-reports`
  - Path: `{subscription_id}/Assessment-{subscription_id}.html`
- Container: `aztfexport`
  - Path: `{subscription_id}/{resource_group_name}/*.tf`
- Container: `code-refactored`
  - Path: `{subscription_id}/{resource_group_name}/*.tf`

### Option 2: GitHub Repository

1. Create a GitHub Personal Access Token:
   - Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Click "Generate new token (classic)"
   - Select scopes: `repo` (full control of private repositories)
   - Generate and copy the token

2. Configure `.env` file:
   ```env
   OUTPUT_DESTINATION=github
   GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   GITHUB_OWNER=your-username
   GITHUB_REPO=azure-terraform-migration
   GITHUB_BRANCH=main
   ```

3. Ensure the repository exists and you have write access

**Output Structure in GitHub:**
- Folder: `assessment-reports/`
  - Path: `assessment-reports/{subscription_id}/Assessment-{subscription_id}.html`
- Folder: `aztfexport/`
  - Path: `aztfexport/{subscription_id}/{resource_group_name}/*.tf`
- Folder: `code-refactored/`
  - Path: `code-refactored/{subscription_id}/{resource_group_name}/*.tf`

## Usage

### Python Refactor Engine

The refactor engine automatically detects the output destination from `.env`:

```bash
python refactor.py "subscription-id" "resource-group-name"
```

**With Azure (default):**
- Downloads from: Azure Blob Storage container `aztfexport`
- Uploads to: Azure Blob Storage container `code-refactored`

**With GitHub:**
- Downloads from: GitHub repo folder `aztfexport`
- Uploads to: GitHub repo folder `code-refactored`

### PowerShell Export Scripts

The PowerShell scripts can be enhanced to support GitHub output by importing the `GitHubHelper.psm1` module.

#### Example: Export-AzToTerraform.ps1 with GitHub

```powershell
# At the end of Export-AzToTerraform.ps1, add:

# Load configuration
$config = Get-Content ".env" | ConvertFrom-StringData

if ($config.OUTPUT_DESTINATION -eq "github") {
    Import-Module "$PSScriptRoot\GitHubHelper.psm1"
    
    $uploadParams = @{
        LocalDirectory = $exportDir
        RemoteBasePath = "aztfexport/$SubscriptionId/$ResourceGroupName"
        Token = $config.GITHUB_TOKEN
        Owner = $config.GITHUB_OWNER
        Repo = $config.GITHUB_REPO
        Branch = $config.GITHUB_BRANCH
        CommitMessagePrefix = "Export Terraform for $ResourceGroupName"
    }
    
    Upload-DirectoryToGitHub @uploadParams
}
```

## Python Dependencies

For GitHub integration, ensure you have the `requests` library installed:

```bash
pip install requests python-dotenv
```

## Testing

### Test Azure Connection
```bash
az storage account show --name your-storage-account-name --resource-group your-rg
```

### Test GitHub Connection
```bash
python -c "from github_helper import test_github_connection; import os; from dotenv import load_dotenv; load_dotenv(); test_github_connection(os.getenv('GITHUB_TOKEN'), os.getenv('GITHUB_OWNER'), os.getenv('GITHUB_REPO'))"
```

## Switching Between Destinations

To switch from Azure to GitHub:

1. Update `.env`:
   ```env
   OUTPUT_DESTINATION=github
   ```

2. Configure GitHub credentials in `.env`

3. Run your scripts normally - they will automatically use GitHub

To switch back to Azure:

1. Update `.env`:
   ```env
   OUTPUT_DESTINATION=azure
   ```

2. Ensure Azure credentials are configured

## Security Considerations

### Azure
- Uses Azure CLI authentication (`az login`)
- Leverages Azure RBAC for access control
- No credentials stored in `.env` (uses current Azure session)

### GitHub
- Requires Personal Access Token with `repo` scope
- Store token securely in `.env` file
- **Never commit `.env` file to version control**
- Add `.env` to `.gitignore`:
  ```gitignore
  .env
  *.env
  ```

## Folder Structure Mapping

| Component | Azure Container/Path | GitHub Path |
|-----------|---------------------|-------------|
| Assessment Reports | `assessment-reports/{subscription_id}/` | `assessment-reports/{subscription_id}/` |
| AzTfExport Output | `aztfexport/{subscription_id}/{rg_name}/` | `aztfexport/{subscription_id}/{rg_name}/` |
| Refactored Code | `code-refactored/{subscription_id}/{rg_name}/` | `code-refactored/{subscription_id}/{rg_name}/` |

## Troubleshooting

### GitHub Upload Fails

**Error: "Bad credentials"**
- Verify your GitHub token is valid
- Ensure the token has `repo` scope
- Check that the token hasn't expired

**Error: "Not Found"**
- Verify the repository exists
- Check that `GITHUB_OWNER` and `GITHUB_REPO` are correct
- Ensure you have write access to the repository

**Error: "Rate limit exceeded"**
- GitHub API has rate limits (5000 requests/hour for authenticated users)
- Wait for the rate limit to reset
- Consider uploading fewer files or implementing batching

### Azure Upload Fails

**Error: "Authentication required"**
- Run `az login` to authenticate
- Verify you have access to the storage account
- Check that the storage account name and resource group are correct

**Error: "Container does not exist"**
- The script will attempt to create containers automatically
- Ensure you have permissions to create containers
- Manually create containers if needed

## Examples

### Complete Workflow Example

**1. Run Assessment (outputs to Azure or GitHub based on .env):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\assessment-AzSubscription.ps1 -SubscriptionId "xxx" -resourceGroup "rg-test"
```

**2. Export Terraform (outputs to Azure or GitHub):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./Export-AzToTerraform.ps1 -StorageAccount samcpstorage -ResourceGroup "rg-test" -SubscriptionId "xxx"
```

**3. Refactor Code (reads from and writes to Azure or GitHub):**
```bash
python refactor.py "xxx" "rg-test"
```

## Benefits of Each Approach

### Azure Blob Storage
✅ Native Azure integration  
✅ High performance for large files  
✅ Built-in versioning and lifecycle management  
✅ No API rate limits  
✅ Direct integration with Azure services  

### GitHub Repository
✅ Version control built-in  
✅ Easy collaboration and review  
✅ Visible history of all changes  
✅ Can trigger GitHub Actions workflows  
✅ Free for public/private repos  
✅ Better for CI/CD integration  

## Migration Between Destinations

To migrate existing data from Azure to GitHub:

```bash
# Download from Azure
az storage blob download-batch --account-name samcpstorage --source aztfexport --destination ./local-aztfexport --auth-mode login

# Upload to GitHub using Python
python -c "
from github_helper import GitHubUploader
from pathlib import Path
import os
from dotenv import load_dotenv
load_dotenv()

uploader = GitHubUploader(
    os.getenv('GITHUB_TOKEN'),
    os.getenv('GITHUB_OWNER'),
    os.getenv('GITHUB_REPO'),
    os.getenv('GITHUB_BRANCH', 'main')
)

uploader.upload_directory(Path('./local-aztfexport'), 'aztfexport', 'Migrate from Azure Storage')
"
```
