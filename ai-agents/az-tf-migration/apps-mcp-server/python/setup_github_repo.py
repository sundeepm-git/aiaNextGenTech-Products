"""
GitHub Repository Setup and Verification Script
Checks repository access and initializes if needed
"""
import os
import sys
import requests
from pathlib import Path
from dotenv import load_dotenv

# Load environment
env_path = Path(__file__).parent.parent / '.env'
load_dotenv(env_path)

# Get config
token = os.getenv('GITHUB_TOKEN', '').strip('"')
owner = os.getenv('GITHUB_OWNER', '').strip()
repo = os.getenv('GITHUB_REPO', '').strip()

print("=" * 70)
print("GitHub Repository Setup")
print("=" * 70)
print()

# Validate config
if not all([token, owner, repo]):
    print("❌ ERROR: GitHub configuration incomplete!")
    print("   Please set in .env file:")
    print("   - GITHUB_TOKEN")
    print("   - GITHUB_OWNER")
    print("   - GITHUB_REPO")
    sys.exit(1)

print(f"📋 Configuration:")
print(f"   Owner: {owner}")
print(f"   Repo: {repo}")
print(f"   Token: {token[:10]}...{token[-4:]}")
print()

# Test API access
headers = {
    'Authorization': f'token {token}',
    'Accept': 'application/vnd.github.v3+json'
}

# Check if repo exists
print("🔍 Checking repository...")
url = f'https://api.github.com/repos/{owner}/{repo}'
response = requests.get(url, headers=headers)

if response.status_code == 200:
    repo_data = response.json()
    print(f"✅ Repository exists: {repo_data['full_name']}")
    print(f"   URL: {repo_data['html_url']}")
    print(f"   Private: {repo_data['private']}")
    print(f"   Default Branch: {repo_data['default_branch']}")
    print()
    
    # Check permissions
    permissions = repo_data.get('permissions', {})
    print(f"📝 Your permissions:")
    print(f"   Admin: {permissions.get('admin', False)}")
    print(f"   Push: {permissions.get('push', False)}")
    print(f"   Pull: {permissions.get('pull', False)}")
    print()
    
    if not permissions.get('push', False):
        print("⚠️  WARNING: Token doesn't have push access!")
        print("   You need to regenerate the token with 'repo' scope")
        print()
        print("📝 Steps to fix:")
        print("   1. Go to: https://github.com/settings/tokens")
        print("   2. Click 'Generate new token (classic)'")
        print("   3. Select scopes: [✓] repo (Full control of private repositories)")
        print("   4. Generate token and update .env file")
        sys.exit(1)
    
    print("✅ All permissions OK!")
    print()
    print("🎉 Repository is ready for migrations!")
    
elif response.status_code == 404:
    print(f"❌ Repository not found: {owner}/{repo}")
    print()
    print("📝 Options:")
    print(f"   1. Create repository manually at: https://github.com/new")
    print(f"   2. Or create via API:")
    print()
    
    create = input("Would you like to create it now? (yes/no): ").strip().lower()
    if create in ['yes', 'y']:
        print()
        print("Creating repository...")
        
        create_url = 'https://api.github.com/user/repos'
        create_data = {
            'name': repo,
            'description': 'Azure Terraform Migration - Assessment Reports, Exports, and Refactored Code',
            'private': True,
            'auto_init': True
        }
        
        create_response = requests.post(create_url, headers=headers, json=create_data)
        
        if create_response.status_code == 201:
            repo_data = create_response.json()
            print(f"✅ Repository created: {repo_data['html_url']}")
            print()
            print("🎉 Repository is ready for migrations!")
        else:
            print(f"❌ Failed to create repository: {create_response.status_code}")
            print(create_response.text)
            sys.exit(1)
    else:
        print("❌ Cannot proceed without repository")
        sys.exit(1)
        
else:
    print(f"❌ GitHub API Error: {response.status_code}")
    print(response.text)
    print()
    
    if response.status_code == 401:
        print("🔑 Authentication failed!")
        print("   Your token may be invalid or expired")
        print()
        print("📝 Steps to fix:")
        print("   1. Go to: https://github.com/settings/tokens")
        print("   2. Generate new token (classic)")
        print("   3. Select scopes: [✓] repo")
        print("   4. Update GITHUB_TOKEN in .env file")
    
    sys.exit(1)

print()
print("=" * 70)
print("Next steps:")
print("  1. Run: python migrate_azure_to_github.py")
print("  2. Or run refactor with OUTPUT_DESTINATION=both in .env")
print("=" * 70)
