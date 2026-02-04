"""
GitHub Helper Module for Azure-Terraform Migration
Handles uploading files to GitHub repository
"""
import os
import base64
import requests
from pathlib import Path
from typing import Optional, List, Dict
import json


class GitHubUploader:
    """Helper class to upload files to GitHub repository."""
    
    def __init__(self, token: str, owner: str, repo: str, branch: str = "main"):
        """
        Initialize GitHub uploader.
        
        Args:
            token: GitHub personal access token
            owner: GitHub username or organization
            repo: Repository name
            branch: Branch name (default: main)
        """
        self.token = token
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.base_url = f"https://api.github.com/repos/{owner}/{repo}"
        self.headers = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github.v3+json"
        }
    
    def _get_file_sha(self, file_path: str) -> Optional[str]:
        """
        Get the SHA of an existing file in the repository.
        
        Args:
            file_path: Path to file in repository
            
        Returns:
            SHA string if file exists, None otherwise
        """
        url = f"{self.base_url}/contents/{file_path}"
        params = {"ref": self.branch}
        
        try:
            response = requests.get(url, headers=self.headers, params=params)
            if response.status_code == 200:
                return response.json()["sha"]
            return None
        except Exception:
            return None
    
    def upload_file(self, local_path: Path, remote_path: str, commit_message: Optional[str] = None) -> bool:
        """
        Upload a single file to GitHub repository.
        
        Args:
            local_path: Path to local file
            remote_path: Path in repository (e.g., "assessment-reports/file.html")
            commit_message: Commit message (auto-generated if None)
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Read file content
            with open(local_path, 'rb') as f:
                content = f.read()
            
            # Encode to base64
            content_base64 = base64.b64encode(content).decode('utf-8')
            
            # Check if file already exists
            sha = self._get_file_sha(remote_path)
            
            # Prepare commit message
            if commit_message is None:
                action = "Update" if sha else "Add"
                commit_message = f"{action} {remote_path}"
            
            # Prepare request data
            data = {
                "message": commit_message,
                "content": content_base64,
                "branch": self.branch
            }
            
            if sha:
                data["sha"] = sha
            
            # Upload file
            url = f"{self.base_url}/contents/{remote_path}"
            response = requests.put(url, headers=self.headers, json=data)
            
            if response.status_code in [200, 201]:
                return True
            else:
                print(f"[ERROR] GitHub upload failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"[ERROR] Failed to upload {local_path}: {str(e)}")
            return False
    
    def upload_directory(self, local_dir: Path, remote_base_path: str, 
                        commit_message: Optional[str] = None) -> Dict[str, bool]:
        """
        Upload all files in a directory to GitHub repository.
        
        Args:
            local_dir: Path to local directory
            remote_base_path: Base path in repository (e.g., "aztfexport/subscription-id/rg-name")
            commit_message: Commit message prefix
            
        Returns:
            Dictionary mapping file names to success status
        """
        results = {}
        
        if not local_dir.exists() or not local_dir.is_dir():
            print(f"[ERROR] Directory does not exist: {local_dir}")
            return results
        
        # Get all files recursively
        files = [f for f in local_dir.rglob('*') if f.is_file()]
        
        print(f"[INFO] Uploading {len(files)} files to GitHub...")
        
        for file_path in files:
            # Calculate relative path
            relative_path = file_path.relative_to(local_dir)
            remote_path = f"{remote_base_path}/{relative_path}".replace('\\', '/')
            
            # Generate commit message
            msg = f"{commit_message}: {relative_path}" if commit_message else None
            
            # Upload file
            success = self.upload_file(file_path, remote_path, msg)
            results[str(relative_path)] = success
            
            if success:
                print(f"  ✓ Uploaded: {relative_path}")
            else:
                print(f"  ✗ Failed: {relative_path}")
        
        return results
    
    def create_folder_readme(self, folder_path: str, content: str) -> bool:
        """
        Create a README.md file in a folder.
        
        Args:
            folder_path: Path to folder in repository
            content: README content
            
        Returns:
            True if successful
        """
        readme_path = f"{folder_path}/README.md"
        
        try:
            # Encode content
            content_base64 = base64.b64encode(content.encode('utf-8')).decode('utf-8')
            
            # Check if exists
            sha = self._get_file_sha(readme_path)
            
            # Prepare data
            data = {
                "message": f"Add/Update README for {folder_path}",
                "content": content_base64,
                "branch": self.branch
            }
            
            if sha:
                data["sha"] = sha
            
            # Upload
            url = f"{self.base_url}/contents/{readme_path}"
            response = requests.put(url, headers=self.headers, json=data)
            
            return response.status_code in [200, 201]
            
        except Exception as e:
            print(f"[ERROR] Failed to create README: {str(e)}")
            return False


def test_github_connection(token: str, owner: str, repo: str) -> bool:
    """
    Test GitHub connection and repository access.
    
    Args:
        token: GitHub token
        owner: Repository owner
        repo: Repository name
        
    Returns:
        True if connection successful
    """
    try:
        headers = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github.v3+json"
        }
        
        url = f"https://api.github.com/repos/{owner}/{repo}"
        response = requests.get(url, headers=headers)
        
        if response.status_code == 200:
            repo_data = response.json()
            print(f"[INFO] Connected to GitHub repo: {repo_data['full_name']}")
            return True
        else:
            print(f"[ERROR] Cannot access repository: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"[ERROR] GitHub connection failed: {str(e)}")
        return False


if __name__ == "__main__":
    # Example usage
    from dotenv import load_dotenv
    load_dotenv()
    
    token = os.getenv("GITHUB_TOKEN")
    owner = os.getenv("GITHUB_OWNER")
    repo = os.getenv("GITHUB_REPO")
    
    if all([token, owner, repo]):
        print("Testing GitHub connection...")
        test_github_connection(token, owner, repo)
    else:
        print("GitHub credentials not configured in .env file")
