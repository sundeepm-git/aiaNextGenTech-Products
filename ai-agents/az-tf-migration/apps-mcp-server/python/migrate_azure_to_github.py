"""
Migrate Azure Storage Content to GitHub Repository
This script downloads all content from Azure Blob Storage and uploads to GitHub

Containers migrated:
- assessment-reports
- aztfexport
- code-refactored
"""
import os
import sys
import tempfile
import shutil
import subprocess
from pathlib import Path
from dotenv import load_dotenv
from github_helper import GitHubUploader

# Color codes for terminal output
BLUE = "\033[94m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
RESET = "\033[0m"

def print_step(message, color="blue"):
    """Print colored step messages."""
    colors = {"blue": BLUE, "green": GREEN, "yellow": YELLOW, "red": RED}
    print(f"{colors.get(color, BLUE)}{message}{RESET}")

def load_config():
    """Load configuration from .env file."""
    env_path = Path(__file__).parent.parent / '.env'
    load_dotenv(env_path)
    
    config = {
        'storage_account': os.getenv('storageAccount'),
        'storage_rg': os.getenv('storageAccountRG'),
        'github_token': os.getenv('GITHUB_TOKEN'),
        'github_owner': os.getenv('GITHUB_OWNER'),
        'github_repo': os.getenv('GITHUB_REPO'),
        'github_branch': os.getenv('GITHUB_BRANCH', 'main'),
        'assessment_folder': os.getenv('ASSESSMENT_FOLDER', 'assessment-reports'),
        'aztfexport_folder': os.getenv('AZTFEXPORT_FOLDER', 'aztfexport'),
        'code_refactored_folder': os.getenv('CODE_REFACTORED_FOLDER', 'code-refactored')
    }
    
    return config

def download_container_from_azure(storage_account, container_name, local_path):
    """Download entire container from Azure Blob Storage."""
    print_step(f"Downloading container '{container_name}' from Azure Storage...", "blue")
    
    try:
        # Create local directory
        local_path.mkdir(parents=True, exist_ok=True)
        
        # Download all blobs
        cmd = [
            'az.cmd', 'storage', 'blob', 'download-batch',
            '--account-name', storage_account,
            '--source', container_name,
            '--destination', str(local_path),
            '--auth-mode', 'login'
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, shell=True)
        
        if result.returncode == 0:
            # Count downloaded files
            file_count = sum(1 for _ in local_path.rglob('*') if _.is_file())
            print_step(f"  Downloaded {file_count} files from '{container_name}'", "green")
            return file_count
        else:
            print_step(f"  Error downloading container: {result.stderr}", "red")
            return 0
            
    except Exception as e:
        print_step(f"  Error: {str(e)}", "red")
        return 0

def upload_to_github(uploader, local_path, remote_folder, container_name):
    """Upload directory to GitHub repository."""
    print_step(f"Uploading '{container_name}' to GitHub...", "blue")
    
    try:
        if not local_path.exists() or not any(local_path.rglob('*')):
            print_step(f"  No files to upload for '{container_name}'", "yellow")
            return 0
        
        # Upload directory
        results = uploader.upload_directory(
            local_path,
            remote_folder,
            f"Migrate {container_name} from Azure Storage"
        )
        
        success_count = sum(1 for v in results.values() if v)
        total_count = len(results)
        
        if success_count == total_count:
            print_step(f"  Successfully uploaded {success_count} files", "green")
        else:
            print_step(f"  Uploaded {success_count} of {total_count} files (some failures)", "yellow")
        
        return success_count
        
    except Exception as e:
        print_step(f"  Error uploading: {str(e)}", "red")
        return 0

def main():
    print("=" * 70)
    print("Azure Storage to GitHub Migration Tool")
    print("=" * 70)
    print()
    
    # Load configuration
    print_step("1. Loading configuration...", "blue")
    config = load_config()
    
    # Validate Azure config
    if not config['storage_account']:
        print_step("ERROR: Azure Storage account not configured in .env", "red")
        sys.exit(1)
    
    print_step(f"   Azure Storage: {config['storage_account']}", "blue")
    
    # Validate GitHub config
    if not all([config['github_token'], config['github_owner'], config['github_repo']]):
        print_step("ERROR: GitHub configuration incomplete in .env", "red")
        print("   Required: GITHUB_TOKEN, GITHUB_OWNER, GITHUB_REPO")
        sys.exit(1)
    
    print_step(f"   GitHub Repo: {config['github_owner']}/{config['github_repo']}", "blue")
    print()
    
    # Initialize GitHub uploader
    print_step("2. Initializing GitHub connection...", "blue")
    uploader = GitHubUploader(
        config['github_token'],
        config['github_owner'],
        config['github_repo'],
        config['github_branch']
    )
    print_step("   GitHub connection initialized", "green")
    print()
    
    # Create temporary directory for downloads
    temp_root = Path(tempfile.mkdtemp(prefix='azure_to_github_'))
    print_step(f"3. Created temporary directory: {temp_root}", "blue")
    print()
    
    # Containers to migrate
    containers = [
        (config['assessment_folder'], config['assessment_folder']),
        (config['aztfexport_folder'], config['aztfexport_folder']),
        (config['code_refactored_folder'], config['code_refactored_folder'])
    ]
    
    total_migrated = 0
    
    try:
        for container_name, github_folder in containers:
            print_step(f"=== Migrating Container: {container_name} ===", "blue")
            
            # Download from Azure
            local_path = temp_root / container_name
            file_count = download_container_from_azure(
                config['storage_account'],
                container_name,
                local_path
            )
            
            if file_count > 0:
                # Upload to GitHub
                uploaded = upload_to_github(
                    uploader,
                    local_path,
                    github_folder,
                    container_name
                )
                total_migrated += uploaded
            
            print()
        
        # Summary
        print("=" * 70)
        print_step("Migration Complete!", "green")
        print_step(f"Total files migrated: {total_migrated}", "green")
        print()
        print_step(f"View on GitHub: https://github.com/{config['github_owner']}/{config['github_repo']}", "blue")
        print("=" * 70)
        
    finally:
        # Cleanup temp directory
        print()
        print_step("Cleaning up temporary files...", "yellow")
        try:
            shutil.rmtree(temp_root)
            print_step("Cleanup complete", "green")
        except Exception as e:
            print_step(f"Warning: Failed to cleanup temp directory: {str(e)}", "yellow")

if __name__ == "__main__":
    main()
