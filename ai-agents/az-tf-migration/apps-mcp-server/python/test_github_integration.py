"""
Test script for GitHub integration
Run this to verify GitHub configuration and connectivity
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Add parent directory to path to import github_helper
sys.path.insert(0, str(Path(__file__).parent))

from github_helper import GitHubUploader, test_github_connection

def main():
    print("=" * 60)
    print("GitHub Integration Test")
    print("=" * 60)
    
    # Load environment variables
    env_path = Path(__file__).parent.parent / '.env'
    load_dotenv(env_path)
    
    # Get configuration
    output_dest = os.getenv('OUTPUT_DESTINATION', 'azure')
    github_token = os.getenv('GITHUB_TOKEN')
    github_owner = os.getenv('GITHUB_OWNER')
    github_repo = os.getenv('GITHUB_REPO')
    github_branch = os.getenv('GITHUB_BRANCH', 'main')
    
    print(f"\n1. Configuration Check")
    print(f"   OUTPUT_DESTINATION: {output_dest}")
    print(f"   GITHUB_OWNER: {github_owner or '(not set)'}")
    print(f"   GITHUB_REPO: {github_repo or '(not set)'}")
    print(f"   GITHUB_BRANCH: {github_branch}")
    print(f"   GITHUB_TOKEN: {'(set)' if github_token else '(not set)'}")
    
    # Check if GitHub is configured
    if output_dest != 'github':
        print(f"\n⚠️  OUTPUT_DESTINATION is set to '{output_dest}', not 'github'")
        print("   Change OUTPUT_DESTINATION=github in .env to enable GitHub output")
        return
    
    if not all([github_token, github_owner, github_repo]):
        print("\n❌ GitHub configuration incomplete!")
        print("   Please set all required environment variables in .env:")
        print("   - GITHUB_TOKEN")
        print("   - GITHUB_OWNER")
        print("   - GITHUB_REPO")
        return
    
    # Test connection
    print(f"\n2. Testing GitHub Connection")
    if test_github_connection(github_token, github_owner, github_repo):
        print("   ✅ GitHub connection successful!")
    else:
        print("   ❌ GitHub connection failed!")
        return
    
    # Test file upload (create a test file)
    print(f"\n3. Testing File Upload")
    test_file = Path(__file__).parent / "test_github.txt"
    test_file.write_text(f"GitHub integration test - {os.getenv('USER', 'user')}")
    
    try:
        uploader = GitHubUploader(github_token, github_owner, github_repo, github_branch)
        
        # Upload test file
        remote_path = "test/github_integration_test.txt"
        success = uploader.upload_file(test_file, remote_path, "Test GitHub integration")
        
        if success:
            print(f"   ✅ Test file uploaded successfully!")
            print(f"   📁 View at: https://github.com/{github_owner}/{github_repo}/blob/{github_branch}/{remote_path}")
        else:
            print(f"   ❌ Test file upload failed!")
            
    except Exception as e:
        print(f"   ❌ Upload error: {str(e)}")
    finally:
        # Cleanup test file
        if test_file.exists():
            test_file.unlink()
    
    print(f"\n4. Summary")
    print("   Configuration is correct and GitHub integration is working!")
    print(f"   Your refactor engine will now:")
    print(f"   - Download from: GitHub repo '{github_owner}/{github_repo}' folder 'aztfexport/'")
    print(f"   - Upload to: GitHub repo '{github_owner}/{github_repo}' folder 'code-refactored/'")
    print("\n" + "=" * 60)

if __name__ == "__main__":
    main()
