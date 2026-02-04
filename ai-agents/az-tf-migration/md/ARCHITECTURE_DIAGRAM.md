# Architecture Diagram: Dual Output Destination System

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         .env Configuration File                      │
│                                                                      │
│  OUTPUT_DESTINATION = "azure" | "github"                            │
│                                                                      │
│  [Azure Config]              [GitHub Config]                        │
│  storageAccount              GITHUB_TOKEN                            │
│  storageAccountRG            GITHUB_OWNER                            │
│                              GITHUB_REPO                             │
│                              GITHUB_BRANCH                           │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ reads
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    refactor.py (Main Entry Point)                    │
│                                                                      │
│  • Loads .env configuration                                         │
│  • Initializes TerraformRefactorEngine                              │
│  • Passes subscription_id & resource_group_name                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ creates
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│              TerraformRefactorEngine (tf_refactor_variable.py)      │
│                                                                      │
│  __init__():                                                        │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ if OUTPUT_DESTINATION == "azure":                             │  │
│  │   • Initialize Azure Blob Storage config                      │  │
│  │   • Set containers: aztfexport, code-refactored              │  │
│  │                                                               │  │
│  │ elif OUTPUT_DESTINATION == "github":                          │  │
│  │   • Initialize GitHubUploader                                 │  │
│  │   • Set repo paths: aztfexport/, code-refactored/            │  │
│  │   • Fallback to Azure if credentials missing                  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ run()
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          Step 0: Download                            │
│                                                                      │
│  Decision Point: Which source?                                      │
│                                                                      │
│  OUTPUT_DESTINATION == "azure"    OUTPUT_DESTINATION == "github"   │
│         │                                    │                       │
│         ▼                                    ▼                       │
│  ┌──────────────────┐              ┌──────────────────────┐        │
│  │ Azure Download   │              │  GitHub Download     │        │
│  │                  │              │                      │        │
│  │ • az.cmd blob    │              │ • GitHub API call    │        │
│  │   list           │              │ • GET /contents/     │        │
│  │ • az.cmd blob    │              │ • Download each file │        │
│  │   download       │              │                      │        │
│  │ • Save to temp   │              │ • Save to temp       │        │
│  │   directory      │              │   directory          │        │
│  └──────────────────┘              └──────────────────────┘        │
│         │                                    │                       │
│         └────────────────┬───────────────────┘                       │
│                          ▼                                           │
│              Temp Directory: /tmp/aztf_refactor_xxxxx/source        │
│              Files: main.tf, provider.tf, terraform.tfstate, ...    │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Steps 1-2: Refactor & Process                    │
│                                                                      │
│  • Parse Terraform files                                            │
│  • Extract variables                                                │
│  • Generate variables.tf                                            │
│  • Create providers.tf, outputs.tf, locals.tf, data-sources.tf     │
│  • Generate terraform.tfvars (Step 3)                               │
│  • Update tfvars from main.tf (Step 4)                              │
│  • Write reports (REPORT.md, FAILED_RESOURCES_REPORT.md)           │
│                                                                      │
│  Output to: /tmp/aztf_refactor_xxxxx/output/                       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       Final Step: Upload                             │
│                                                                      │
│  Decision Point: Which destination?                                 │
│                                                                      │
│  OUTPUT_DESTINATION == "azure"    OUTPUT_DESTINATION == "github"   │
│         │                                    │                       │
│         ▼                                    ▼                       │
│  ┌──────────────────┐              ┌──────────────────────┐        │
│  │ Azure Upload     │              │  GitHub Upload       │        │
│  │                  │              │                      │        │
│  │ • Create         │              │ • For each file:     │        │
│  │   container if   │              │   • Read & base64    │        │
│  │   not exists     │              │   • Check SHA        │        │
│  │ • az.cmd blob    │              │   • PUT /contents/   │        │
│  │   upload for     │              │   • Commit message   │        │
│  │   each file      │              │                      │        │
│  └──────────────────┘              └──────────────────────┘        │
│         │                                    │                       │
│         ▼                                    ▼                       │
│  ┌──────────────────┐              ┌──────────────────────┐        │
│  │ Azure Container  │              │  GitHub Repository   │        │
│  │                  │              │                      │        │
│  │ code-refactored/ │              │ code-refactored/     │        │
│  │  └─ {sub-id}/    │              │  └─ {sub-id}/        │        │
│  │      └─ {rg}/    │              │      └─ {rg}/        │        │
│  │          ├─ *.tf │              │          ├─ *.tf     │        │
│  │          └─ ...  │              │          └─ ...      │        │
│  └──────────────────┘              └──────────────────────┘        │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Cleanup & Complete                           │
│                                                                      │
│  • Delete temp directory: /tmp/aztf_refactor_xxxxx/                 │
│  • Log success message                                              │
│  • Display output URL (Azure or GitHub)                             │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Scenario 1: Azure Storage (Default)

```
Azure Blob Container "aztfexport"
         │
         │ az.cmd blob download
         ▼
    Temp Directory
         │
         │ Process & Refactor
         ▼
    Temp Directory
         │
         │ az.cmd blob upload
         ▼
Azure Blob Container "code-refactored"
```

### Scenario 2: GitHub Repository

```
GitHub Repo "aztfexport/" folder
         │
         │ GitHub API GET
         ▼
    Temp Directory
         │
         │ Process & Refactor
         ▼
    Temp Directory
         │
         │ GitHub API PUT
         ▼
GitHub Repo "code-refactored/" folder
```

## Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Python Components                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  refactor.py                                                     │
│  └─ Main entry point                                            │
│  └─ CLI argument parsing                                        │
│  └─ Engine initialization                                       │
│                                                                  │
│  tf_refactor_variable.py                                        │
│  └─ TerraformRefactorEngine class                               │
│  └─ Download methods:                                           │
│      • _download_from_blob_storage()                            │
│      • _download_from_github()                                  │
│  └─ Upload methods:                                             │
│      • _upload_to_blob_storage()                                │
│      • _upload_to_github()                                      │
│  └─ Processing methods:                                         │
│      • _generate_tfvars()                                       │
│      • generate_providers_tf()                                  │
│      • extract_resources()                                      │
│                                                                  │
│  github_helper.py                                               │
│  └─ GitHubUploader class                                        │
│  └─ upload_file()                                               │
│  └─ upload_directory()                                          │
│  └─ test_github_connection()                                    │
│                                                                  │
│  test_github_integration.py                                     │
│  └─ Configuration validation                                    │
│  └─ Connection testing                                          │
│  └─ Upload testing                                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    PowerShell Components                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  GitHubHelper.psm1                                              │
│  └─ Get-EnvConfig                                               │
│  └─ Test-GitHubAccess                                           │
│  └─ Upload-FileToGitHub                                         │
│  └─ Upload-DirectoryToGitHub                                    │
│                                                                  │
│  Export-AzToTerraform.ps1                                       │
│  └─ Can be extended to use GitHubHelper                         │
│                                                                  │
│  assessment-AzSubscription.ps1                                  │
│  └─ Can be extended to use GitHubHelper                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration Decision Tree

```
                    Start
                      │
                      ▼
              Load .env file
                      │
                      ▼
        Check OUTPUT_DESTINATION
                      │
         ┌────────────┴────────────┐
         │                         │
         ▼                         ▼
    "azure"                   "github"
         │                         │
         ▼                         ▼
  Azure Storage           GitHub Repository
         │                         │
         ├─ Read from:             ├─ Read from:
         │  • Container            │  • Repo folder
         │  • Auth: az CLI         │  • Auth: Token
         │                         │
         ├─ Write to:              ├─ Write to:
         │  • Container            │  • Repo folder
         │  • Auth: az CLI         │  • Auth: Token
         │                         │
         └─────────────┬───────────┘
                       │
                       ▼
              Same folder structure
              Same file naming
              Same workflow
```

## Folder Structure Comparison

```
╔════════════════════════════════════════════════════════════════════╗
║                    Azure Blob Storage                              ║
╠════════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  Storage Account: samcpstorage                                    ║
║  │                                                                 ║
║  ├── Container: assessment-reports                                ║
║  │   └── {subscription_id}/                                       ║
║  │       └── Assessment-{subscription_id}.html                    ║
║  │                                                                 ║
║  ├── Container: aztfexport                                        ║
║  │   └── {subscription_id}/                                       ║
║  │       └── {resource_group_name}/                               ║
║  │           ├── main.tf                                          ║
║  │           ├── provider.tf                                      ║
║  │           ├── terraform.tf                                     ║
║  │           └── terraform.tfstate                                ║
║  │                                                                 ║
║  └── Container: code-refactored                                   ║
║      └── {subscription_id}/                                       ║
║          └── {resource_group_name}/                               ║
║              ├── main.tf                                          ║
║              ├── variables.tf                                     ║
║              ├── terraform.tfvars                                 ║
║              ├── providers.tf                                     ║
║              ├── outputs.tf                                       ║
║              ├── locals.tf                                        ║
║              ├── data-sources.tf                                  ║
║              ├── REPORT.md                                        ║
║              └── FAILED_RESOURCES_REPORT.md                       ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝

╔════════════════════════════════════════════════════════════════════╗
║                       GitHub Repository                            ║
╠════════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  Repository: {owner}/{repo}                                       ║
║  Branch: main (or configured)                                     ║
║  │                                                                 ║
║  ├── assessment-reports/                                          ║
║  │   └── {subscription_id}/                                       ║
║  │       └── Assessment-{subscription_id}.html                    ║
║  │                                                                 ║
║  ├── aztfexport/                                                  ║
║  │   └── {subscription_id}/                                       ║
║  │       └── {resource_group_name}/                               ║
║  │           ├── main.tf                                          ║
║  │           ├── provider.tf                                      ║
║  │           ├── terraform.tf                                     ║
║  │           └── terraform.tfstate                                ║
║  │                                                                 ║
║  └── code-refactored/                                             ║
║      └── {subscription_id}/                                       ║
║          └── {resource_group_name}/                               ║
║              ├── main.tf                                          ║
║              ├── variables.tf                                     ║
║              ├── terraform.tfvars                                 ║
║              ├── providers.tf                                     ║
║              ├── outputs.tf                                       ║
║              ├── locals.tf                                        ║
║              ├── data-sources.tf                                  ║
║              ├── REPORT.md                                        ║
║              └── FAILED_RESOURCES_REPORT.md                       ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝

                    ⚡ Identical Structure ⚡
```

## Authentication Flow

### Azure Authentication

```
User Terminal
     │
     │ az login
     ▼
Azure CLI
     │
     │ Stores credentials
     ▼
~/.azure/
     │
     │ refactor.py uses
     ▼
az.cmd commands
     │
     │ --auth-mode login
     ▼
Azure Storage API
     │
     ▼
Blob Operations
```

### GitHub Authentication

```
User
     │
     │ Create Personal Access Token
     ▼
GitHub Settings
     │
     │ Copy token
     ▼
.env file
     │
     │ GITHUB_TOKEN=ghp_xxxxx
     ▼
refactor.py loads
     │
     ▼
GitHubUploader
     │
     │ Authorization: token ghp_xxxxx
     ▼
GitHub API
     │
     ▼
Repository Operations
```

## Error Handling Flow

```
                 Operation Start
                       │
                       ▼
              Check OUTPUT_DESTINATION
                       │
           ┌───────────┴───────────┐
           │                       │
           ▼                       ▼
    If "azure"               If "github"
           │                       │
           ▼                       ▼
  Check credentials       Check credentials
  (az CLI logged in?)    (GITHUB_TOKEN set?)
           │                       │
           ├─ No → ERROR           ├─ No → ERROR
           │       Fallback?       │       Fallback to Azure
           │                       │
           ▼                       ▼
  Try operation           Try operation
           │                       │
     ┌─────┴─────┐           ┌────┴────┐
     │           │           │         │
   Success     Error       Success   Error
     │           │           │         │
     ▼           ▼           ▼         ▼
  Continue    Log &       Continue  Log &
              Cleanup              Cleanup
                       │
                       ▼
              Always cleanup temp dirs
                       │
                       ▼
                   Complete
```
