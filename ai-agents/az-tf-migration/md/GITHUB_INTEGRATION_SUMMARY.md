# GitHub Integration Feature - Implementation Summary

## Overview
Added support for storing assessment reports, aztfexport outputs, and refactored Terraform code in either **Azure Blob Storage** or **GitHub Repository** based on a configuration switch in the `.env` file.

## Files Created

### 1. **python/github_helper.py**
Python module providing GitHub API integration:
- `GitHubUploader` class for file/directory uploads
- `test_github_connection()` function to verify GitHub access
- Base64 encoding for binary file uploads
- Handles file updates (checks existing SHA)
- Supports recursive directory uploads

### 2. **ps/GitHubHelper.psm1**
PowerShell module for GitHub operations:
- `Get-EnvConfig` - Load configuration from .env
- `Test-GitHubAccess` - Verify GitHub credentials
- `Upload-FileToGitHub` - Upload single file via GitHub API
- `Upload-DirectoryToGitHub` - Upload entire directory

### 3. **python/test_github_integration.py**
Test script to verify GitHub configuration:
- Validates all required environment variables
- Tests GitHub API connectivity
- Creates and uploads test file
- Provides detailed feedback

### 4. **OUTPUT_DESTINATION_GUIDE.md**
Comprehensive documentation covering:
- Configuration instructions for both Azure and GitHub
- Setup steps for each destination
- Folder structure mapping
- Security considerations
- Troubleshooting guide
- Migration instructions
- Complete workflow examples

## Files Modified

### 1. **.env**
Added new configuration variables:
```env
OUTPUT_DESTINATION=azure          # Options: "azure" or "github"
GITHUB_TOKEN=                     # GitHub Personal Access Token
GITHUB_OWNER=                     # GitHub username or organization
GITHUB_REPO=                      # Repository name
GITHUB_BRANCH=main                # Target branch
ASSESSMENT_FOLDER=assessment-reports
AZTFEXPORT_FOLDER=aztfexport
CODE_REFACTORED_FOLDER=code-refactored
```

### 2. **python/tf_refactor_variable.py**
Major enhancements to support dual destination:

**In `__init__` method:**
- Load `OUTPUT_DESTINATION` from .env
- Initialize GitHub configuration variables
- Create `GitHubUploader` instance if destination is GitHub
- Fallback to Azure if GitHub credentials incomplete

**New Methods:**
- `_download_from_github()` - Download files from GitHub repo using API
- `_upload_to_github()` - Upload refactored files to GitHub repo

**Modified Methods:**
- `run()` - Check destination and call appropriate download method
- Upload section - Check destination and call appropriate upload method

**Key Logic:**
```python
if self.output_destination == 'github':
    self._download_from_github()
    # ... process ...
    self._upload_to_github()
else:
    self._download_from_blob_storage()
    # ... process ...
    self._upload_to_blob_storage()
```

### 3. **python/requirements.txt**
Added dependency:
```
requests  # For GitHub API integration
```

## Folder Structure

### Azure Blob Storage Structure
```
Container: assessment-reports
  └── {subscription_id}/
      └── Assessment-{subscription_id}.html

Container: aztfexport
  └── {subscription_id}/
      └── {resource_group_name}/
          ├── main.tf
          ├── provider.tf
          ├── terraform.tf
          └── terraform.tfstate

Container: code-refactored
  └── {subscription_id}/
      └── {resource_group_name}/
          ├── main.tf
          ├── variables.tf
          ├── terraform.tfvars
          ├── providers.tf
          ├── outputs.tf
          ├── locals.tf
          └── data-sources.tf
```

### GitHub Repository Structure
```
Repo Root
├── assessment-reports/
│   └── {subscription_id}/
│       └── Assessment-{subscription_id}.html
│
├── aztfexport/
│   └── {subscription_id}/
│       └── {resource_group_name}/
│           ├── main.tf
│           ├── provider.tf
│           ├── terraform.tf
│           └── terraform.tfstate
│
└── code-refactored/
    └── {subscription_id}/
        └── {resource_group_name}/
            ├── main.tf
            ├── variables.tf
            ├── terraform.tfvars
            ├── providers.tf
            ├── outputs.tf
            ├── locals.tf
            └── data-sources.tf
```

## Usage Instructions

### Quick Start - Azure (Default)

1. Configure `.env`:
```env
OUTPUT_DESTINATION=azure
storageAccount=samcpstorage
storageAccountRG=rg-mcp-servers
```

2. Login to Azure:
```bash
az login
```

3. Run refactor:
```bash
python refactor.py "subscription-id" "resource-group-name"
```

### Quick Start - GitHub

1. Create GitHub Personal Access Token:
   - Go to: Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Scope: `repo` (full control)

2. Configure `.env`:
```env
OUTPUT_DESTINATION=github
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GITHUB_OWNER=your-username
GITHUB_REPO=azure-terraform-migration
GITHUB_BRANCH=main
```

3. Test configuration:
```bash
cd python
python test_github_integration.py
```

4. Run refactor:
```bash
python refactor.py "subscription-id" "resource-group-name"
```

## Testing the Integration

### Test GitHub Connection
```bash
cd python
python test_github_integration.py
```

Expected output:
```
============================================================
GitHub Integration Test
============================================================

1. Configuration Check
   OUTPUT_DESTINATION: github
   GITHUB_OWNER: your-username
   GITHUB_REPO: azure-terraform-migration
   GITHUB_BRANCH: main
   GITHUB_TOKEN: (set)

2. Testing GitHub Connection
   [INFO] Connected to GitHub repo: your-username/azure-terraform-migration
   ✅ GitHub connection successful!

3. Testing File Upload
   ✅ Test file uploaded successfully!
   📁 View at: https://github.com/your-username/azure-terraform-migration/blob/main/test/github_integration_test.txt

4. Summary
   Configuration is correct and GitHub integration is working!
============================================================
```

### Test Azure Connection
```bash
az storage account show --name samcpstorage --resource-group rg-mcp-servers
```

## Security Best Practices

### Azure
- ✅ Uses Azure CLI authentication (no credentials in .env)
- ✅ Leverages Azure RBAC
- ✅ Uses managed identity when available

### GitHub
- ⚠️ Store GitHub token securely
- ⚠️ **Never commit .env file**
- ⚠️ Add .env to .gitignore
- ⚠️ Use tokens with minimal required scope (repo only)
- ⚠️ Rotate tokens regularly

**Add to .gitignore:**
```gitignore
.env
*.env
.env.local
.env.production
```

## Benefits Comparison

| Feature | Azure Blob Storage | GitHub Repository |
|---------|-------------------|------------------|
| Version Control | Requires separate setup | Built-in with commits |
| Collaboration | Via Azure Portal | Native Git workflow |
| Rate Limits | None | 5000 API calls/hour |
| Cost | Pay per GB stored | Free (public/private) |
| CI/CD Integration | Azure DevOps | GitHub Actions native |
| File Size Limits | Very large files OK | 100 MB per file |
| Access Control | Azure RBAC | GitHub permissions |
| Visibility | Portal UI | Web-based file browser |

## Switching Between Destinations

### From Azure to GitHub
1. Update `.env`: `OUTPUT_DESTINATION=github`
2. Add GitHub credentials
3. Run scripts normally

### From GitHub to Azure
1. Update `.env`: `OUTPUT_DESTINATION=azure`
2. Ensure Azure CLI logged in
3. Run scripts normally

## Migration Between Systems

### Migrate Azure → GitHub
```bash
# Download from Azure
az storage blob download-batch \
  --account-name samcpstorage \
  --source aztfexport \
  --destination ./local-backup \
  --auth-mode login

# Upload to GitHub (update .env first)
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
    'main'
)
uploader.upload_directory(
    Path('./local-backup'),
    'aztfexport',
    'Migrate from Azure Storage'
)
"
```

## Troubleshooting

### GitHub Issues

**"Bad credentials"**
- Verify token is valid and hasn't expired
- Ensure token has `repo` scope
- Check GITHUB_TOKEN in .env

**"Not Found (404)"**
- Verify repository exists
- Check GITHUB_OWNER and GITHUB_REPO spelling
- Ensure you have write access

**"Rate limit exceeded"**
- Wait for rate limit reset (check headers)
- Consider uploading fewer files
- Use Azure for large batch operations

### Azure Issues

**"Authentication required"**
- Run `az login`
- Check Azure subscription access
- Verify storage account permissions

**"Container does not exist"**
- Script auto-creates containers
- Verify write permissions
- Manually create if needed

## Future Enhancements

Potential improvements:
1. Support for AWS S3 as third destination
2. Batch upload optimization for GitHub (reduce API calls)
3. PowerShell scripts integration with GitHub (currently only Python)
4. Assessment report upload to GitHub (currently manual)
5. Automatic migration scripts between destinations
6. GitHub Large File Storage (LFS) support for large Terraform state files

## Dependencies

### Python
- `python-dotenv` - Environment variable management
- `requests` - HTTP library for GitHub API
- `pathlib` - File path operations (built-in)

### PowerShell
- PowerShell 5.1+ or PowerShell Core 7+
- `Invoke-RestMethod` cmdlet (built-in)

### External Tools
- Azure CLI (`az`) - for Azure operations
- Git (optional) - for repository cloning

## Installation

Install Python dependencies:
```bash
cd python
pip install -r requirements.txt
```

Verify installation:
```bash
python -c "import requests; import dotenv; print('Dependencies OK')"
```

## Complete Workflow Example

### Scenario: Migrate Azure Resource Group to Terraform with GitHub Storage

1. **Configure GitHub destination:**
```env
OUTPUT_DESTINATION=github
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GITHUB_OWNER=your-org
GITHUB_REPO=azure-terraform-exports
GITHUB_BRANCH=main
```

2. **Test connection:**
```bash
cd python
python test_github_integration.py
```

3. **Run assessment:**
```powershell
cd ps
powershell -NoProfile -ExecutionPolicy Bypass -File .\assessment-AzSubscription.ps1 `
  -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" `
  -resourceGroup "rg-production"
```

4. **Export Terraform:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./Export-AzToTerraform.ps1 `
  -StorageAccount samcpstorage `
  -ResourceGroup "rg-production" `
  -SubscriptionId "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2"
```

5. **Refactor code:**
```bash
cd ../python
python refactor.py "d0f1884d-1f98-4bf1-9e15-e2986fc1bca2" "rg-production"
```

6. **View results in GitHub:**
```
https://github.com/your-org/azure-terraform-exports/tree/main/code-refactored/d0f1884d-1f98-4bf1-9e15-e2986fc1bca2/rg-production
```

## Summary

This implementation provides a flexible, configurable system for storing Terraform exports and refactored code in either Azure Blob Storage or GitHub repositories. The switch is seamless and requires only updating the `.env` configuration file. Both destinations maintain identical folder structures for consistency.
