# =============================================================
# Name: sundeep k maheshwari
# Date: 2026-01-21
# Description: Core refactoring logic for applying transformation rules, variable extraction, and standards enforcement to Terraform code.
# =============================================================

"""
Auto-generated via Enterprise Terraform Refactoring Engine
Core transformation engine: applies rules, rewrites files.
"""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import os
from dotenv import load_dotenv

from tf_loader import TerraformLoader
from tf_writer import TerraformWriters
from tf_backup import BackupManager
from tf_validation import TerraformValidator




class TerraformRefactorEngine:
    # Resource type to abbreviation mapping (extend as needed)
    RESOURCE_ABBR = {
        'azurerm_resource_group': 'rg',
        'azurerm_virtual_network': 'vnet',
        'azurerm_subnet': 'subnet',
        'azurerm_network_interface': 'nic',
        'azurerm_public_ip': 'pip',
        'azurerm_network_security_group': 'nsg',
        'azurerm_virtual_machine': 'vm',
        'azurerm_linux_virtual_machine': 'azvm',
        'azurerm_windows_virtual_machine': 'azwvm',
        'azurerm_managed_disk': 'disk',
        'azurerm_storage_account': 'stg',
        'azurerm_key_vault': 'kv',
        'azurerm_app_service': 'appsvc',
        'azurerm_sql_server': 'sqlsvr',
        'azurerm_sql_database': 'sqldb',
        'azurerm_cosmosdb_account': 'cosmos',
        'azurerm_lb': 'lb',
        'azurerm_application_gateway': 'agw',
        'azurerm_availability_set': 'aset',
        'azurerm_dev_test_global_vm_shutdown_schedule': 'dtvmss',
        'azurerm_virtual_machine_extension': 'vmext',
        'azurerm_bastion_host': 'bastion',
        'azurerm_firewall': 'afw',
        'azurerm_application_insights': 'appi',
        'azurerm_container_registry': 'acr',
        'azurerm_kubernetes_cluster': 'aks',
        'azurerm_function_app': 'func',
        'azurerm_logic_app': 'logic',
        'azurerm_servicebus_namespace': 'sb',
        'azurerm_eventhub_namespace': 'eh',
        'azurerm_redis_cache': 'redis',
        'azurerm_data_factory': 'adf',
        'azurerm_data_lake_store': 'adls',
        'azurerm_synapse_workspace': 'synapse',
        'azurerm_application_security_group': 'asg',
        'azurerm_private_endpoint': 'pep',
        'azurerm_private_dns_zone': 'pdns',
        'azurerm_route_table': 'rt',
        'azurerm_nat_gateway': 'natgw',
        'azurerm_express_route_circuit': 'er',
        'azurerm_virtual_network_gateway': 'vpngw',
        'azurerm_api_management': 'apim',
        'azurerm_cdn_profile': 'cdn',
        'azurerm_frontdoor': 'afd',
        'azurerm_monitor_diagnostic_setting': 'monitor',
        'azurerm_automation_account': 'aa',
        # Add more as needed
    }
    # Property abbreviation mapping (extend as needed)
    PROP_ABBR = {
        'name': 'name',
        'address_space': 'addr',
        'timezone': 'tz',
        'platform_fault_domain_count': 'pfdc',
        # Add more as needed
    }
    def _print_step(self, msg, color="green"):
        colors = {
            "green": "\033[92m",
            "yellow": "\033[93m",
            "blue": "\033[94m",
            "red": "\033[91m",
            "reset": "\033[0m"
        }
        print(f"{colors.get(color, '')}{msg}{colors['reset']}")
    def _sanitize_tf_content(self, tf_content):
        """Pre-clean invalid HCL: remove lines that are just ')' or '})', and skip arguments after a block closure until a new block starts."""
        lines = tf_content.splitlines()
        cleaned = []
        skip_mode = False
        for i, line in enumerate(lines):
            stripped = line.strip()
            # Remove lines that are just ')' or '})'
            if stripped in [')', '})']:
                continue
            # If we just closed a block, skip lines until a new resource/data block or block start
            if skip_mode:
                if re.match(r'^(resource|data)\s+"', stripped) or stripped.startswith('}'):  # new block or block closure
                    skip_mode = False
                else:
                    continue
            if stripped == '}':
                cleaned.append(line)
                # Look ahead: if next line is not a new block, skip until next block
                if i+1 < len(lines):
                    next_stripped = lines[i+1].strip()
                    if not (re.match(r'^(resource|data)\s+"', next_stripped) or next_stripped.startswith('}')):
                        skip_mode = True
                continue
            cleaned.append(line)
        return '\n'.join(cleaned)

    def _extract_resource_blocks(self, tf_content):
        """Return only resource blocks, skipping data blocks. Also return excluded data block names/vars."""
        resource_blocks = []
        tf_content = self._sanitize_tf_content(tf_content)
        lines = tf_content.splitlines()
        n = len(lines)
        i = 0
        while i < n:
            line = lines[i]
            m = re.match(r'\s*resource\s+"([^"]+)"\s+"([^"]+)"\s*{', line)
            if m:
                rtype, rname = m.group(1), m.group(2)
                block_lines = []
                brace_count = 0
                # Count braces in the declaration line
                decl = line[line.find('{')+1:] if '{' in line else ''
                if decl.strip():
                    block_lines.append(decl)
                for c in line[line.find('{')+1:] if '{' in line else '':
                    if c == '{':
                        brace_count += 1
                    elif c == '}':
                        brace_count -= 1
                brace_count += 1  # for the opening '{' in the declaration
                i += 1
                while i < n and brace_count > 0:
                    line_content = lines[i]
                    for c in line_content:
                        if c == '{':
                            brace_count += 1
                        elif c == '}':
                            brace_count -= 1
                    block_lines.append(line_content)
                    i += 1
                # Remove the last closing '}' if present
                if block_lines and block_lines[-1].strip() == '}':
                    block_lines = block_lines[:-1]
                block = '\n'.join(block_lines)
                print(f"[DEBUG] Block substring for {rtype} {rname}:\nFIRST 100:\n{block[:100]}\n...\nLAST 100:\n{block[-100:]}")
                resource_blocks.append((rtype, rname, block))
            else:
                i += 1
        data_blocks = re.findall(r'data\s+"([^"]+)"\s+"([^"]+)"\s*{(.*?)}\s*', tf_content, re.DOTALL)
        excluded_data_vars = {}
        for dtype, dname, dblock in data_blocks:
            dlines = dblock.splitlines()
            for line in dlines:
                m = re.match(r'(\w+)\s*=\s*(.+)', line.strip())
                if m:
                    excluded_data_vars.setdefault(f"data.{dtype}.{dname}", []).append(m.group(1))
        return resource_blocks, excluded_data_vars


    def __init__(self, subscription_id, resource_group_name, dry_run=False, verbose=False):
        self.subscription_id = subscription_id
        self.subscription_name = subscription_id  # Use subscription_id as name for folder structure
        self.resource_group_name = resource_group_name
        self.dry_run = dry_run
        self.verbose = verbose

        # Load environment variables from .env file
        load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))
        self.storage_account = os.getenv('storageAccount')
        self.storage_account_rg = os.getenv('storageAccountRG')
        
        # Output destination configuration
        self.output_destination = os.getenv('OUTPUT_DESTINATION', 'azure').lower()
        
        # Azure Blob Storage configuration
        self.source_container = os.getenv('AZTFEXPORT_FOLDER', 'aztfexport')
        self.output_container = os.getenv('CODE_REFACTORED_FOLDER', 'code-refactored')
        self.blob_source_path = f"{subscription_id}/{resource_group_name}"
        self.blob_output_path = f"{subscription_id}/{resource_group_name}"
        
        # GitHub configuration
        self.github_token = os.getenv('GITHUB_TOKEN')
        self.github_owner = os.getenv('GITHUB_OWNER')
        self.github_repo = os.getenv('GITHUB_REPO')
        self.github_branch = os.getenv('GITHUB_BRANCH', 'main')
        self.github_uploader = None
        
        # Initialize GitHub uploader if needed
        if self.output_destination in ['github', 'both']:
            from github_helper import GitHubUploader
            if all([self.github_token, self.github_owner, self.github_repo]):
                self.github_uploader = GitHubUploader(
                    self.github_token, 
                    self.github_owner, 
                    self.github_repo, 
                    self.github_branch
                )
                self._print_step(f"GitHub output enabled: {self.github_owner}/{self.github_repo}", "green")
            else:
                self._print_step("WARNING: GitHub destination selected but credentials not configured!", "red")
                self._print_step("Falling back to Azure Storage", "yellow")
                self.output_destination = 'azure'

        # Create temporary directories for download/refactor operations
        self.temp_root = Path(tempfile.mkdtemp(prefix='aztf_refactor_'))
        self.source_dir = self.temp_root / "source"
        self.output_dir = self.temp_root / "output"
        self.source_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.loader = TerraformLoader(self.source_dir, verbose)
        self.backup = BackupManager(self.source_dir, verbose)
        self.validator = TerraformValidator(self.output_dir, verbose)
        self.writers = TerraformWriters(self.output_dir, verbose)
        self.failed_resources = {}

    def _print_step(self, message, color="blue"):
        """Print colored step messages."""
        colors = {
            "blue": "\033[94m",
            "green": "\033[92m",
            "yellow": "\033[93m",
            "red": "\033[91m",
            "reset": "\033[0m"
        }
        print(f"{colors.get(color, colors['blue'])}{message}{colors['reset']}")

    def _download_from_github(self):
        """Download Terraform files from GitHub repository to local temp directory."""
        self._print_step(f"Downloading files from GitHub...", "blue")
        self._print_step(f"  Repository: {self.github_owner}/{self.github_repo}", "blue")
        self._print_step(f"  Branch: {self.github_branch}", "blue")
        self._print_step(f"  Folder: {self.source_container}/{self.blob_source_path}", "blue")
        self._print_step(f"  Local Path: {self.source_dir}", "blue")
        
        try:
            import requests
            
            # GitHub API URL to get directory contents
            github_path = f"{self.source_container}/{self.blob_source_path}"
            api_url = f"https://api.github.com/repos/{self.github_owner}/{self.github_repo}/contents/{github_path}"
            params = {"ref": self.github_branch}
            headers = {
                "Authorization": f"token {self.github_token}",
                "Accept": "application/vnd.github.v3+json"
            }
            
            # Get list of files
            response = requests.get(api_url, headers=headers, params=params)
            
            if response.status_code != 200:
                raise Exception(f"Failed to access GitHub path: {response.status_code} - {response.text}")
            
            files = response.json()
            
            if not isinstance(files, list):
                raise Exception(f"Unexpected response from GitHub API")
            
            self._print_step(f"Found {len(files)} files to download", "blue")
            
            # Download each file
            for file_info in files:
                if file_info.get('type') == 'file':
                    file_name = file_info['name']
                    download_url = file_info['download_url']
                    
                    # Download file content
                    file_response = requests.get(download_url)
                    
                    if file_response.status_code == 200:
                        local_file = self.source_dir / file_name
                        local_file.write_bytes(file_response.content)
                        self._print_step(f"  Downloaded: {file_name}", "blue")
                    else:
                        self._print_step(f"  Failed to download: {file_name}", "red")
            
            self._print_step(f"Successfully downloaded all files from GitHub", "green")
            
        except Exception as e:
            self._print_step(f"ERROR: {str(e)}", "red")
            raise

    def _download_from_blob_storage(self):
        """Download Terraform files from Azure Blob Storage to local temp directory."""
        self._print_step(f"Downloading files from Azure Blob Storage...", "blue")
        self._print_step(f"  Container: {self.source_container}", "blue")
        self._print_step(f"  Blob Path: {self.blob_source_path}", "blue")
        self._print_step(f"  Local Path: {self.source_dir}", "blue")
        
        try:
            # List all blobs in the source path
            list_cmd = [
                'az.cmd', 'storage', 'blob', 'list',
                '--account-name', self.storage_account,
                '--container-name', self.source_container,
                '--prefix', self.blob_source_path,
                '--auth-mode', 'login',
                '--query', '[].name',
                '--output', 'json'
            ]
            
            result = subprocess.run(list_cmd, capture_output=True, text=True, check=True, shell=True)
            import json
            blob_names = json.loads(result.stdout)
            
            if not blob_names:
                raise Exception(f"No files found in {self.source_container}/{self.blob_source_path}")

            self._print_step(f"Found {len(blob_names)} files to download", "blue")

            # Download each blob
            for blob_name in blob_names:
                # Get just the filename from the blob path
                filename = Path(blob_name).name
                local_file = self.source_dir / filename

                download_cmd = [
                    'az.cmd', 'storage', 'blob', 'download',
                    '--account-name', self.storage_account,
                    '--container-name', self.source_container,
                    '--name', blob_name,
                    '--file', str(local_file),
                    '--auth-mode', 'login'
                ]

                subprocess.run(download_cmd, capture_output=True, check=True, shell=True)
                self._print_step(f"  Downloaded: {filename}", "green")

            self._print_step(f"Successfully downloaded all files", "green")
            
        except subprocess.CalledProcessError as e:
            self._print_step(f"ERROR downloading from Blob Storage: {e.stderr}", "red")
            raise
        except Exception as e:
            self._print_step(f"ERROR: {str(e)}", "red")
            raise

    def _create_gitignore(self):
        """Create .gitignore file to exclude sensitive files from GitHub."""
        gitignore_path = self.output_dir / ".gitignore"
        gitignore_content = """# Terraform sensitive files - DO NOT commit to GitHub
# These files contain secrets and should only be stored in Azure Blob Storage

# State files contain sensitive data
terraform.tfstate
terraform.tfstate.backup
*.tfstate
*.tfstate.*

# Main.tf may contain hardcoded secrets (Azure keys, passwords, etc.)
# Uncomment the line below if your main.tf contains secrets
main.tf

# Variable values that may contain sensitive data
# terraform.tfvars should be excluded if it contains real secrets
# Uncomment the line below if needed
# terraform.tfvars

# Terraform directories
.terraform/
.terraform.lock.hcl

# Crash log files
crash.log

# Sensitive export reports that may contain keys
**/Export-Report*.html
"""
        gitignore_path.write_text(gitignore_content)
        self._print_step(f"Created .gitignore to protect sensitive files", "blue")

    def _should_upload_to_github(self, file_path):
        """Check if file should be uploaded to GitHub based on .gitignore rules."""
        filename = file_path.name
        
        # List of sensitive files to exclude from GitHub
        excluded_patterns = [
            'terraform.tfstate',
            'main.tf',  # May contain secrets
            '.terraform.lock.hcl',
            'Export-Report',  # HTML reports may contain keys
        ]
        
        # Check if file matches any excluded pattern
        for pattern in excluded_patterns:
            if pattern in filename:
                return False
        
        return True

    def _upload_to_github(self):
        """Upload refactored Terraform files to GitHub repository (excluding sensitive files)."""
        self._print_step(f"Uploading refactored files to GitHub...", "blue")
        self._print_step(f"  Repository: {self.github_owner}/{self.github_repo}", "blue")
        self._print_step(f"  Branch: {self.github_branch}", "blue")
        self._print_step(f"  Folder: {self.output_container}/{self.blob_output_path}", "blue")
        
        try:
            # GitHub path: code-refactored/{subscription_id}/{resource_group_name}
            github_base_path = f"{self.output_container}/{self.blob_output_path}"
            
            # Filter files before upload - exclude sensitive files
            all_files = list(self.output_dir.glob('*'))
            files_to_upload = [f for f in all_files if f.is_file() and self._should_upload_to_github(f)]
            skipped_files = [f for f in all_files if f.is_file() and not self._should_upload_to_github(f)]
            
            if skipped_files:
                self._print_step(f"Skipping {len(skipped_files)} sensitive files (protected by .gitignore):", "yellow")
                for f in skipped_files:
                    self._print_step(f"  ⊘ {f.name} (contains secrets)", "yellow")
            
            # Upload only safe files
            results = {}
            commit_msg = f"Update Terraform refactored code for {self.resource_group_name}"
            
            for file_path in files_to_upload:
                github_file_path = f"{github_base_path}/{file_path.name}"
                try:
                    result = self.github_uploader.upload_file(file_path, github_file_path, commit_msg)
                    results[file_path.name] = result
                except Exception as e:
                    results[file_path.name] = False
                    self._print_step(f"  ✗ Failed: {file_path.name} - {str(e)}", "red")
            
            # Check results
            success_count = sum(1 for v in results.values() if v)
            total_count = len(results)
            
            if success_count == total_count:
                self._print_step(f"Successfully uploaded all {total_count} safe files to GitHub", "green")
                github_url = f"https://github.com/{self.github_owner}/{self.github_repo}/tree/{self.github_branch}/{github_base_path}"
                self._print_step(f"GitHub URL: {github_url}", "green")
            else:
                failed_count = total_count - success_count
                self._print_step(f"Uploaded {success_count}/{total_count} files ({failed_count} failed)", "yellow")
            
        except Exception as e:
            self._print_step(f"ERROR uploading to GitHub: {str(e)}", "red")
            raise

    def _upload_to_blob_storage(self):
        """Upload refactored Terraform files to Azure Blob Storage."""
        self._print_step(f"Uploading refactored files to Azure Blob Storage...", "blue")
        self._print_step(f"  Container: {self.output_container}", "blue")
        self._print_step(f"  Blob Path: {self.blob_output_path}", "blue")
        
        try:
            # Ensure container exists
            container_check = subprocess.run([
                'az.cmd', 'storage', 'container', 'exists',
                '--account-name', self.storage_account,
                '--name', self.output_container,
                '--auth-mode', 'login'
            ], capture_output=True, text=True, shell=True)
            
            import json
            container_exists = json.loads(container_check.stdout).get('exists', False)
            
            if not container_exists:
                self._print_step(f"Creating container: {self.output_container}", "yellow")
                subprocess.run([
                    'az.cmd', 'storage', 'container', 'create',
                    '--account-name', self.storage_account,
                    '--name', self.output_container,
                    '--auth-mode', 'login'
                ], check=True, shell=True)
            
            # Upload all files from output directory
            files_to_upload = list(self.output_dir.glob('**/*'))
            files_to_upload = [f for f in files_to_upload if f.is_file()]
            
            self._print_step(f"Uploading {len(files_to_upload)} files...", "blue")
            
            for file_path in files_to_upload:
                relative_path = file_path.relative_to(self.output_dir)
                blob_name = f"{self.blob_output_path}/{relative_path}".replace('\\', '/')
                
                upload_cmd = [
                    'az.cmd', 'storage', 'blob', 'upload',
                    '--account-name', self.storage_account,
                    '--container-name', self.output_container,
                    '--name', blob_name,
                    '--file', str(file_path),
                    '--auth-mode', 'login',
                    '--overwrite', 'true'
                ]
                
                subprocess.run(upload_cmd, capture_output=True, check=True, shell=True)
                self._print_step(f"  Uploaded: {relative_path}", "green")
            
            storage_url = f"https://{self.storage_account}.blob.core.windows.net/{self.output_container}/{self.blob_output_path}/"
            self._print_step(f"Successfully uploaded all files", "green")
            self._print_step(f"Storage URL: {storage_url}", "green")
            
        except subprocess.CalledProcessError as e:
            self._print_step(f"ERROR uploading to Blob Storage: {e.stderr}", "red")
            raise
        except Exception as e:
            self._print_step(f"ERROR: {str(e)}", "red")
            raise

    def _cleanup_temp_dirs(self):
        """Clean up temporary directories."""
        try:
            if self.temp_root.exists():
                shutil.rmtree(self.temp_root)
                self._print_step(f"Cleaned up temporary files", "green")
        except Exception as e:
            self._print_step(f"Warning: Failed to clean up temp directory: {str(e)}", "yellow")

    def _generate_tfvars(self):
        """Generate and update terraform.tfvars from variables.tf and main.tf."""
        import subprocess
        import sys
        from pathlib import Path
        
        self._print_step("=== Generating terraform.tfvars ===", "blue")
        
        variables_tf = self.output_dir / "variables.tf"
        tfvars_file = self.output_dir / "terraform.tfvars"
        main_tf = self.output_dir / "main.tf"
        
        # Step 1: Generate initial tfvars from variables.tf
        if variables_tf.exists():
            try:
                self._print_step("Step 3 - Running tf_refactor_tfvars.py", "yellow")
                tf_refactor_tfvars_path = Path(__file__).parent / "tf_refactor_tfvars.py"
                subprocess.run([
                    sys.executable,
                    str(tf_refactor_tfvars_path),
                    str(variables_tf),
                    str(tfvars_file)
                ], check=True, capture_output=True, text=True)
                self._print_step("Step 3 - tfvars file created successfully", "green")
            except subprocess.CalledProcessError as e:
                self._print_step(f"ERROR in tf_refactor_tfvars.py: {e.stderr}", "red")
            except Exception as e:
                self._print_step(f"ERROR: {str(e)}", "red")
        else:
            self._print_step("WARNING: variables.tf not found, skipping tfvars generation", "yellow")
        
        # Step 2: Update tfvars with all variables from main.tf
        tf_readupdate_path = Path(__file__).parent / "tf_readupdate_tfvars.py"
        if main_tf.exists() and tf_readupdate_path.exists() and tfvars_file.exists():
            try:
                self._print_step("Step 4 - Updating tfvars from main.tf", "yellow")
                subprocess.run([
                    sys.executable,
                    str(tf_readupdate_path),
                    str(main_tf),
                    str(tfvars_file)
                ], check=True, capture_output=True, text=True)
                self._print_step("Step 4 - tfvars file updated with all variables from main.tf successfully", "green")
            except subprocess.CalledProcessError as e:
                self._print_step(f"ERROR in tf_readupdate_tfvars.py: {e.stderr}", "red")
            except Exception as e:
                self._print_step(f"ERROR: {str(e)}", "red")
        else:
            if not main_tf.exists():
                self._print_step("WARNING: main.tf not found, skipping Step 4", "yellow")
            elif not tf_readupdate_path.exists():
                self._print_step("WARNING: tf_readupdate_tfvars.py not found, skipping Step 4", "yellow")

    def generate_providers_tf(self):
        """Ensure providers.tf declares the required azurerm provider block, including subscription_id."""
        self.log("Generating providers.tf...")
        self.writers.providers_tf = [
            f'provider "azurerm" {{\n  features {{}}\n  subscription_id = "{self.subscription_id}"\n}}'
        ]


    def run(self):
        # Step 0: Download files from configured source (Azure or GitHub)
        # When using "both", always download from Azure (primary source)
        if self.output_destination == 'github':
            self._print_step("=== Step 0: Downloading from GitHub ===", "blue")
            self._download_from_github()
        else:
            # For "azure" or "both", download from Azure
            self._print_step("=== Step 0: Downloading from Azure Blob Storage ===", "blue")
            self._download_from_blob_storage()
            
        # Ensure output directory exists
        self.output_dir.parent.mkdir(parents=True, exist_ok=True)


        # (Backup step removed as requested)

        # Load and parse all .tf files from export folder
        try:
            parsed_files, failed_files = self.loader.load()
            self.failed_resources.update(failed_files)
            self.hcl_data = {k: v for k, v in parsed_files.items() if k.startswith(str(self.source_dir)) and k.endswith('.tf')}
        except Exception as e:
            print(f"[ERROR] Loading/parsing failed: {e}")
            self.failed_resources['__loader__'] = str(e)
            self.hcl_data = {}



        # Ensure output directory exists before copying
        self.output_dir.mkdir(parents=True, exist_ok=True)


        # Always copy main.tf, terraform.tfstate, and data-sources.tf from export to refactor folder (unmodified)

        # Debug: Log file copy operations

        # Improved: Use absolute paths and print resolved paths for diagnostics
        export_main = (self.source_dir / "main.tf").resolve()
        refactor_main = (self.output_dir / "main.tf").resolve()
        main_copied = False
        print(f"[DEBUG] Copy main.tf: {export_main} -> {refactor_main}")
        if export_main.is_file():
            try:
                shutil.copy2(str(export_main), str(refactor_main))
                main_copied = True
                print("[DEBUG] main.tf copied successfully.")
            except Exception as e:
                print(f"[ERROR] Failed to copy main.tf: {e} | Source: {export_main} | Dest: {refactor_main}")
        else:
            print(f"[ERROR] main.tf does not exist at {export_main} (checked with Path.is_file())")

        export_tfstate = (self.source_dir / "terraform.tfstate").resolve()
        refactor_tfstate = (self.output_dir / "terraform.tfstate").resolve()
        tfstate_copied = False
        print(f"[DEBUG] Copy terraform.tfstate: {export_tfstate} -> {refactor_tfstate}")
        if export_tfstate.is_file():
            try:
                shutil.copy2(str(export_tfstate), str(refactor_tfstate))
                tfstate_copied = True
                print("[DEBUG] terraform.tfstate copied successfully.")
            except Exception as e:
                print(f"[ERROR] Failed to copy terraform.tfstate: {e} | Source: {export_tfstate} | Dest: {refactor_tfstate}")
        else:
            print(f"[ERROR] terraform.tfstate does not exist at {export_tfstate} (checked with Path.is_file())")

        export_datasources = (self.source_dir / "data-sources.tf").resolve()
        refactor_datasources = (self.output_dir / "data-sources.tf").resolve()
        datasources_copied = False
        print(f"[DEBUG] Copy data-sources.tf: {export_datasources} -> {refactor_datasources}")
        if export_datasources.is_file():
            try:
                shutil.copy2(str(export_datasources), str(refactor_datasources))
                datasources_copied = True
                print("[DEBUG] data-sources.tf copied successfully.")
            except Exception as e:
                print(f"[ERROR] Failed to copy data-sources.tf: {e} | Source: {export_datasources} | Dest: {refactor_datasources}")
        else:
            print(f"[ERROR] data-sources.tf does not exist at {export_datasources} (checked with Path.is_file())")

        # Remove any generated data-sources.tf content to ensure only the copied file is used
        self.writers.data_sources = []


        if main_copied and tfstate_copied:
            if datasources_copied:
                self._print_step("Step 1 - main.tf, tfstate, and data-sources.tf refactored successfully.", color="green")
            else:
                self._print_step("Step 1 - main.tf and tfstate refactored successfully. data-sources.tf not found (optional).", color="yellow")
        else:
            self._print_step("Step 1 - One or more required files (main.tf, tfstate) missing in export folder. Stopping workflow.", color="red")
            # Stop workflow if any required file is missing
            import sys
            sys.exit(1)

        # Apply refactoring rules and best practices
        try:
            self.apply_rules()
        except Exception as e:
            print(f"[ERROR] Refactor rules failed: {e}")
            self.failed_resources['__refactor__'] = str(e)

        # Write all output files (except tfvars first)
        try:
            tfvars_content = self.writers.tfvars
            self.writers.tfvars = []
            self.writers.write_all()
        except Exception as e:
            print(f"[ERROR] Writing output files failed: {e}")
            self.failed_resources['__writer__'] = str(e)

        # Print variables.tf message and count
        variables_tf_path = self.output_dir / "variables.tf"
        try:
            with open(variables_tf_path, "r") as f:
                lines = f.readlines()
            var_count = sum(1 for line in lines if line.strip().startswith('variable '))
            self._print_step(f"Step 2 - variables.tf created successfully with {var_count} variables.", color="blue")
        except Exception as e:
            self._print_step(f"Step 2 - [ERROR] Could not read variables.tf at runtime: {e}", color="red")

        # Write tfvars file
        try:
            self.writers.tfvars = tfvars_content
            tfvars_path = self.output_dir / "terraform.tfvars"
            with open(tfvars_path, "w") as f:
                f.write("# Auto-generated via Enterprise Terraform Refactoring Engine\n\n")
                f.write("\n\n".join(self.writers.tfvars))
        except Exception as e:
            print(f"[ERROR] Writing tfvars file failed: {e}")

        # (terraform CLI command execution removed)

        # Write summary and error reports
        self._write_summary_report()
        if self.failed_resources:
            self._write_failed_report()
        
        # Create .gitignore file to protect sensitive files
        self._create_gitignore()
        
        # Step: Generate and update terraform.tfvars before upload
        self._generate_tfvars()
        
        # Final Step: Upload to configured destination (Azure or GitHub or both)
        try:
            if self.output_destination == 'github':
                self._print_step("=== Final Step: Uploading to GitHub ===", "blue")
                self._upload_to_github()
            elif self.output_destination == 'both':
                self._print_step("=== Final Step: Uploading to Azure Blob Storage ===", "blue")
                self._upload_to_blob_storage()
                self._print_step("=== Uploading to GitHub ===", "blue")
                try:
                    self._upload_to_github()
                except Exception as github_error:
                    self._print_step(f"GitHub upload failed: {str(github_error)}", "red")
                    import traceback
                    traceback.print_exc()
            else:
                self._print_step("=== Final Step: Uploading to Azure Blob Storage ===", "blue")
                self._upload_to_blob_storage()
        except Exception as e:
            print(f"[ERROR] Upload failed: {e}")
            import traceback
            traceback.print_exc()
        finally:
            # Always cleanup temp directories
            self._cleanup_temp_dirs()

    def _write_summary_report(self):
        report_path = self.output_dir / "REPORT.md"
        self.output_dir.mkdir(parents=True, exist_ok=True)
        lines = []
        lines.append("# Refactor Summary Report\n\n")
        lines.append(f"**Subscription:** {self.subscription_name}\n\n")
        lines.append(f"**Resource Group:** {self.resource_group_name}\n\n")
        lines.append("## Processed Files\n")
        for fname in sorted(self.hcl_data.keys()):
            lines.append(f"- {fname}\n")

        # One-to-one mapping table with reasons
        lines.append("\n## Variable Mapping Table\n")
        var_names = set()
        tfvars_names = set()
        main_vars = set()
        var_comments = {}
        tfvars_comments = {}
        # variables.tf
        for var_block in self.writers.variables_tf:
            m = re.match(r'# Variable: ([^\n]+)\n# Used in main.tf as var\.([a-zA-Z0-9_]+)', var_block)
            if m:
                var_names.add(m.group(1))
                var_comments[m.group(1)] = m.group(2)
        # terraform.tfvars
        for line in self.writers.tfvars:
            m = re.match(r'# ([a-zA-Z0-9_]+) maps to variable ([a-zA-Z0-9_]+)', line)
            if m:
                tfvars_names.add(m.group(1))
                tfvars_comments[m.group(1)] = m.group(2)
        # main.tf
        # Use cleaned main.tf if available
        cleaned_main_tf_path = self.output_dir / "main.cleaned.tf"
        if cleaned_main_tf_path.exists():
            main_tf_path = cleaned_main_tf_path
        else:
            main_tf_path = self.output_dir / "main.tf"
        if main_tf_path.exists():
            with open(main_tf_path, "r") as f:
                main_content = f.read()
            main_vars.update(re.findall(r'var\.([a-zA-Z0-9_]+)', main_content))
        all_vars = sorted(var_names | tfvars_names | main_vars)
        lines.append("| Variable | variables.tf | terraform.tfvars | main.tf | Reason |\n")
        lines.append("|----------|-------------|------------------|---------|--------|\n")
        for v in all_vars:
            included = []
            reason = ""
            if v in var_names and v in tfvars_names and v in main_vars:
                included = ["Y", "Y", "Y"]
                reason = "Mapped 1:1 in all files"
            elif v in var_names and v in tfvars_names:
                included = ["Y", "Y", ""]
                reason = "Declared and assigned, not referenced in main.tf"
            elif v in var_names and v in main_vars:
                included = ["Y", "", "Y"]
                reason = "Declared and referenced, not assigned in tfvars"
            elif v in tfvars_names and v in main_vars:
                included = ["", "Y", "Y"]
                reason = "Assigned and referenced, not declared in variables.tf"
            elif v in var_names:
                included = ["Y", "", ""]
                reason = "Declared only"
            elif v in tfvars_names:
                included = ["", "Y", ""]
                reason = "Assigned only"
            elif v in main_vars:
                included = ["", "", "Y"]
                reason = "Referenced only"
            else:
                included = ["", "", ""]
                reason = "Not included"
            lines.append(f"| {v} | {included[0]} | {included[1]} | {included[2]} | {reason} |\n")

        # Excluded data blocks
        if hasattr(self, 'excluded_data_vars') and self.excluded_data_vars:
            lines.append("\n## Excluded Data Blocks\n")
            for dblock, dvars in self.excluded_data_vars.items():
                lines.append(f"- {dblock}: {', '.join(dvars)}\n")
        # Omitted variables from tfvars
        if hasattr(self, 'omitted_tfvars_reasons') and self.omitted_tfvars_reasons:
            lines.append("\n## Omitted Variables from terraform.tfvars\n")
            for var, reason in self.omitted_tfvars_reasons:
                lines.append(f"- {var}: {reason}\n")
        # Omitted hardcoded values from main.tf
        if hasattr(self, 'omitted_main_hardcoded_reasons') and self.omitted_main_hardcoded_reasons:
            lines.append("\n## Omitted Hardcoded Values from main.tf\n")
            for var, reason in self.omitted_main_hardcoded_reasons:
                lines.append(f"- {var}: {reason}\n")
        if self.failed_resources:
            lines.append("\n## Failed Resources\n")
            for res, err in self.failed_resources.items():
                lines.append(f"- **{res}**: {err}\n")
        else:
            lines.append("\nNo failed resources.\n")
        # Check for drift report
        drift_report = self.output_dir / "DRIFT_REPORT.md"
        if drift_report.exists():
            lines.append("\n## Drift Detected\nSee DRIFT_REPORT.md for details.\n")
        else:
            lines.append("\nNo drift detected.\n")
        with open(report_path, "w") as f:
            f.writelines(lines)

    def _write_failed_report(self):
        report_path = self.output_dir / "FAILED_RESOURCES_REPORT.md"
        self.output_dir.mkdir(parents=True, exist_ok=True)
        with open(report_path, "w") as f:
            f.write("# Failed Resources Report\n\n")
            for res, err in self.failed_resources.items():
                f.write(f"- **{res}**: {err}\n")

        self.hcl_data = {}

    def log(self, msg):
        if self.verbose:
            print(f"[ENGINE] {msg}")

    # ----------------------------------------------------------
    # MAIN PIPELINE
    # ----------------------------------------------------------


    # ----------------------------------------------------------
    # RULE APPLICATION LOGIC
    # ----------------------------------------------------------

    def apply_rules(self):
        """
        Apply YAML-defined rule transformations.
        Populate TerraformWriters buffers with refactored content.
        """
        self.log("Applying refactor rules...")

        # Map file names to writer buffers
        file_map = {
            'main.tf': self.writers.main_tf,
            'variables.tf': self.writers.variables_tf,
            'outputs.tf': self.writers.outputs_tf,
            'providers.tf': self.writers.providers_tf,
            'locals.tf': self.writers.locals_tf,
            'data-sources.tf': self.writers.data_sources,
            'terraform.tfvars': self.writers.tfvars,
        }

        # Clear all buffers first
        for buf in file_map.values():
            buf.clear()

        # --- Patch: Replace all hardcoded values in resource blocks with variable references ---
        def to_snake(name):
            return re.sub(r'[^a-zA-Z0-9]', '_', name).lower()

        def replace_block_literals(rtype, rname, block, parent_keys=None):
            parent_keys = parent_keys or []
            lines = block.splitlines()
            out_lines = []  # Ensure this is always defined at the start
            i = 0
            while i < len(lines):
                line = lines[i].rstrip()
                # tags block
                if line.strip().startswith('tags = {'):
                    var_name = to_snake(f"tags_{rname}")
                    out_lines.append(f"tags = var.{var_name}")
                    # skip to closing '}'
                    i += 1
                    while i < len(lines) and lines[i].strip() != '}':
                        i += 1
                    i += 1
                    continue
                # Multi-line jsonencode or similar (e.g., settings = jsonencode({ ... }))
                jsonencode_match = re.match(r'(\w+)\s*=\s*jsonencode\(\{', line.strip())
                if jsonencode_match:
                    key = jsonencode_match.group(1)
                    var_base = '_'.join([key] + parent_keys + [rname])
                    var_name = to_snake(var_base)
                    # Skip all lines until the matching closing '})' is found
                    depth = 1
                    i += 1
                    while i < len(lines) and depth > 0:
                        line_content = lines[i]
                        if '{' in line_content:
                            depth += line_content.count('{')
                        if '}' in line_content:
                            depth -= line_content.count('}')
                        # If this line contains only ')' or '})', skip it
                        if line_content.strip() in [')', '})']:
                            i += 1
                            continue
                        i += 1
                    out_lines.append(f"{key} = var.{var_name}")
                    # After skipping, also skip any immediate trailing ')' or '})' lines
                    # After skipping, also skip any immediate trailing ')' or '})' lines
                    while i < len(lines) and lines[i].strip() in [')', '})']:
                        # If we see '})', break out of the block entirely (end of this resource block)
                        if lines[i].strip() == '})':
                            i = len(lines)  # force exit from while loop
                            break
                        i += 1
                    # If the next line is a block closure, let the main loop handle it
                    # If the next line is a valid argument, it will be processed as normal
                    continue
                # Skip any line that is just ')' or '})' (anywhere in the block)
                if line.strip() in [')', '})']:
                    # If this is '})', immediately return the current output for the block
                    if line.strip() == '})':
                        return '\n'.join(out_lines)
                    i += 1
                    continue
                # Nested block (e.g., os_disk { ... })
                nested_match = re.match(r'(\w+)\s*{', line.strip())
                if nested_match:
                    nested_key = nested_match.group(1)
                    # Find the full nested block
                    nested_lines = []
                    depth = 1
                    i += 1
                    while i < len(lines) and depth > 0:
                        line_content = lines[i]
                        if '{' in line_content:
                            depth += line_content.count('{')
                        if '}' in line_content:
                            depth -= line_content.count('}')
                        if depth > 0:
                            nested_lines.append(line_content)
                        i += 1
                    nested_block = '\n'.join(nested_lines)
                    replaced_nested = replace_block_literals(rtype, rname, nested_block, parent_keys + [nested_key])
                    out_lines.append(f"{nested_key} {{")
                    out_lines.extend(["  " + line for line in replaced_nested.splitlines()])
                    out_lines.append("}")
                    continue
                # block closure
                if line.strip() == '}':
                    out_lines.append('}')
                    i += 1
                    continue
                # key = value
                match = re.match(r'(\w+)\s*=\s*(.+)', line.strip())
                if match:
                    key, value = match.group(1), match.group(2).strip()
                    # Skip computed/data-sourced values, never parameterize 'depends_on', and never parameterize *_id, *_ids, or ARM IDs
                    if (
                        "data.azurerm_resource_group.rg" in value or
                        "data.azurerm_network_interface" in value or
                        "azurerm_linux_virtual_machine" in value or
                        "azurerm_resource_group" in value or
                        key == "depends_on" or
                        re.match(r'.*_id(s)?$', key) or
                        re.match(r'.*id(s)?$', key) or
                        (isinstance(value, str) and value.startswith('"/subscriptions/'))
                    ):
                        out_lines.append(f"{key} = {value}")
                        i += 1
                        continue
                    elif any(x in key for x in ["self_link", "uri"]):
                        out_lines.append(f"{key} = {value}")
                        i += 1
                        continue
                    var_base = '_'.join([key] + parent_keys + [rname])
                    var_name = to_snake(var_base)
                    out_lines.append(f"{key} = var.{var_name}")
                    i += 1
                    continue
                # Default: emit the line as-is
                out_lines.append(line)
                i += 1
            return '\n'.join(out_lines)

        # Only refactor and write main.tf once, then generate variables.tf and tfvars from that, but do not re-update main.tf
        for filename, parsed in self.hcl_data.items():
            raw_text = Path(filename).read_text()
            fname = Path(filename).name
            buf = file_map.get(fname)
            if buf is not None:
                # For main.tf, copy as-is from export folder to refactor folder, no refactoring
                buf.append(raw_text)
            else:
                self.log(f"Skipping unknown file type: {fname}")

        # Copy terraform.tfstate if it exists in the export folder
        export_tfstate = self.source_dir / "terraform.tfstate"
        refactor_tfstate = self.output_dir / "terraform.tfstate"
        if export_tfstate.exists():
            import shutil
            shutil.copy2(export_tfstate, refactor_tfstate)
            self.log("Copied terraform.tfstate from export to refactor folder.")

        self.generate_data_sources()
        self.generate_providers_tf()
        self.generate_variables_tf()
        self.generate_tfvars()

        # Check if variables.tf or terraform.tfvars are empty, and stop with a message if so
        if not self.writers.variables_tf or all(not block.strip() for block in self.writers.variables_tf):
            print("[ERROR] variables.tf content was not generated. Stopping engine.")
            import sys
            sys.exit(1)
        if not self.writers.tfvars or all(not line.strip() for line in self.writers.tfvars):
            print("[ERROR] terraform.tfvars content was not generated. Stopping engine.")
            import sys
            sys.exit(1)



    def generate_variables_tf(self):
        import collections
        variables = collections.OrderedDict()
        resource_groups = collections.OrderedDict()
        def to_snake(name):
            return re.sub(r'[^a-zA-Z0-9]', '_', name).lower()

        def get_resource_abbr(rtype):
            return self.RESOURCE_ABBR.get(rtype, to_snake(rtype))

        def get_prop_abbr(prop):
            return self.PROP_ABBR.get(prop, to_snake(prop))

        def build_var_name(rtype, rname, prop, parent_keys=None):
            # Strictly enforce only a single res_N in the variable name
            parent_keys = parent_keys or []
            resource_abbr = get_resource_abbr(rtype)
            prop_abbr = get_prop_abbr(prop)
            # Find the first res_N in rname or parent_keys
            instance = None
            # Check rname first
            if isinstance(rname, str):
                rname_clean = rname.replace('-', '_')
                match = re.search(r'res_\d+', rname_clean)
                if match:
                    instance = match.group(0)
            # If not found in rname, check parent_keys
            if not instance:
                for k in parent_keys:
                    k_clean = k.replace('-', '_')
                    match = re.search(r'res_\d+', k_clean)
                    if match:
                        instance = match.group(0)
                        break
            # If still not found, fallback to rname as-is
            if not instance:
                instance = rname.replace('-', '_') if isinstance(rname, str) else rname
            # Remove any res_N from parent_keys to avoid duplication
            filtered_parents = [k for k in parent_keys if not re.match(r'res_\d+', k.replace('-', '_'))]
            nested_abbr = ''
            for k in filtered_parents:
                nested_abbr += '_' + get_prop_abbr(k)
            return f"{resource_abbr}_{instance}{nested_abbr}_{prop_abbr}".replace('__','_').strip('_')
        def is_sensitive(key):
            return any(x in key.lower() for x in ["password", "secret", "key", "token", "sas", "connection_string", "client_secret", "private_key"])
        def is_id_field(key):
            return key.endswith('_id') or key.endswith('_ids') or key == 'id' or key == 'ids' or 'self_link' in key or 'uri' in key
        def is_data_sourced(value):
            return isinstance(value, str) and (value.startswith('data.') or value.startswith('"/subscriptions/'))
        def guess_type(val):
            if isinstance(val, bool):
                return 'bool'
            if isinstance(val, int) or (isinstance(val, str) and val.isdigit()):
                return 'number'
            if isinstance(val, list):
                # Try to infer type from first element
                if val:
                    subtype = guess_type(val[0])
                    return f'list({subtype})'
                else:
                    return 'list(string)'
            if isinstance(val, dict):
                return 'map(string)'
            if isinstance(val, str) and val.lower() in ['true', 'false']:
                return 'bool'
            if isinstance(val, str) and val.startswith('[') and val.endswith(']'):
                return 'list(string)'
            return 'string'

        tags_added = False
        tags_group = None
        def extract_from_dict(d, group_label, parent_keys=None, rtype=None, rname=None):
            nonlocal tags_added, tags_group
            parent_keys = parent_keys or []
            for key, value in d.items():
                # Always include sensitive fields (e.g., admin_password), even if hardcoded
                if is_sensitive(key):
                    if rtype and rname:
                        var_name = build_var_name(rtype, rname, key, parent_keys)
                    else:
                        var_name = to_snake('_'.join(parent_keys + [group_label, key]))
                    variables[var_name] = {
                        'type': 'string',
                        'desc': f"{key.replace('_', ' ').capitalize()} for the {group_label.replace('_', ' ')}.",
                        'sensitive': True
                    }
                    resource_groups.setdefault(group_label, []).append(var_name)
                    continue
                # Exclude ids and Azure location
                if is_id_field(key) or (key == 'location'):
                    continue
                # Exclude data-sourced values (string or list)
                if isinstance(value, str) and is_data_sourced(value):
                    continue
                if isinstance(value, list) and all(isinstance(v, str) and is_data_sourced(v) for v in value):
                    continue
                # Handle jsonencode({ ... }) blocks
                if isinstance(value, str) and value.strip().startswith('jsonencode({'):
                    # Extract the JSON dict inside jsonencode
                    json_block = value.strip()[len('jsonencode('):].strip()
                    if json_block.startswith('{') and json_block.endswith('})'):
                        json_block = json_block[1:-2].strip()
                        # Parse key-value pairs (simple, not nested)
                        for line in json_block.splitlines():
                            m = re.match(r'([a-zA-Z0-9_]+)\s*=\s*(.+)', line.strip())
                            if m:
                                jkey, jval = m.group(1), m.group(2)
                                # Only extract if not a reference or computed
                                if not is_data_sourced(jval) and not is_id_field(jkey) and not is_sensitive(jkey):
                                    if rtype and rname:
                                        var_name = build_var_name(rtype, rname, jkey, parent_keys+[key])
                                    else:
                                        var_name = to_snake('_'.join(parent_keys + [group_label, key, jkey]))
                                    variables[var_name] = {
                                        'type': guess_type(jval),
                                        'desc': f"{jkey.replace('_', ' ').capitalize()} for the {group_label.replace('_', ' ')}.",
                                        'sensitive': is_sensitive(jkey)
                                    }
                                    resource_groups.setdefault(group_label, []).append(var_name)
                        continue
                if isinstance(value, dict):
                    # tags block
                    if key == 'tags':
                        if not tags_added:
                            var_name = 'tags'
                            variables[var_name] = {
                                'type': 'map(string)',
                                'desc': "Tags for all resources.",
                                'sensitive': False
                            }
                            tags_added = True
                            tags_group = group_label
                            resource_groups.setdefault(group_label, []).append('tags')
                        continue
                    # Nested block: pass rtype/rname down
                    extract_from_dict(value, group_label + '_' + key, parent_keys + [key], rtype, rname)
                elif isinstance(value, list):
                    # List of blocks or values
                    if value and isinstance(value[0], dict):
                        for idx, item in enumerate(value):
                            extract_from_dict(item, group_label + '_' + key + str(idx), parent_keys + [f"{key}{idx}"], rtype, rname)
                    else:
                        # Use rtype/rname from parent
                        if rtype and rname:
                            var_name = build_var_name(rtype, rname, key, parent_keys)
                        else:
                            var_name = to_snake('_'.join(parent_keys + [group_label, key]))
                        variables[var_name] = {
                            'type': guess_type(value),
                            'desc': f"{key.replace('_', ' ').capitalize()} for the {group_label.replace('_', ' ')}.",
                            'sensitive': is_sensitive(key)
                        }
                        resource_groups.setdefault(group_label, []).append(var_name)
                else:
                    # Use rtype/rname from parent
                    if rtype and rname:
                        var_name = build_var_name(rtype, rname, key, parent_keys)
                    else:
                        var_name = to_snake('_'.join(parent_keys + [group_label, key]))
                    variables[var_name] = {
                        'type': guess_type(value),
                        'desc': f"{key.replace('_', ' ').capitalize()} for the {group_label.replace('_', ' ')}.",
                        'sensitive': is_sensitive(key)
                    }
                    resource_groups.setdefault(group_label, []).append(var_name)

        # Walk parsed HCL for all resource blocks
        for filename, parsed in self.hcl_data.items():
            fname = Path(filename).name
            if fname == 'main.tf':
                for block in parsed.get('resource', []):
                    for rtype, resources in block.items():
                        for rname, attrs in resources.items():
                            # rname is the resource instance string (e.g., res_3)
                            group_label = to_snake(f"{rtype}_{rname}")
                            extract_from_dict(attrs, group_label, parent_keys=[rname], rtype=rtype, rname=rname)

        # Compose variables.tf in grouped, formatted blocks
        var_blocks = ["# Auto-generated by Terraform Variable Refactoring Engine.\n# Edits may be overwritten.\n"]
        for group, var_list in resource_groups.items():
            header = f"\n# {'-'*75}\n# {group.replace('_', ' ').upper()}\n# {'-'*75}\n"
            var_blocks.append(header)
            for var_name in var_list:
                v = variables[var_name]
                block = f'variable "{var_name}" {{\n  type        = {v["type"]}\n  description = "{v["desc"]}"'
                # Mark sensitive fields explicitly
                if v['sensitive'] or any(s in var_name.lower() for s in ["password", "secret", "key", "token", "sas", "connection_string", "client_secret", "private_key"]):
                    block += '\n  sensitive = true'
                # Add validation for region, sku, tier if present
                if var_name.endswith('region'):
                    block += '\n  validation {\n    condition     = contains(["eastus", "centralus", "westeurope", "southcentralus"], var.' + var_name + ')\n    error_message = "Region must be a valid Azure region."\n  }'
                if var_name.endswith('sku') or var_name.endswith('tier'):
                    block += '\n  validation {\n    condition     = contains(["Basic", "Standard", "Premium"], var.' + var_name + ')\n    error_message = "SKU tier must be Basic, Standard, or Premium."\n  }'
                block += '\n}'
                var_blocks.append(block)
        # Always ensure resource_group_name is present in variables.tf
        found_rg_var = any('variable "resource_group_name"' in b for b in var_blocks)
        if not found_rg_var:
            block = f'variable "resource_group_name" {{\n  description = "The name of the Azure resource group."\n  type = string\n  default = "{self.resource_group_name}"\n}}'
            var_blocks.append(block)
        self.log(f"Populating variables.tf with {len(var_blocks)} variable blocks.")
        self.writers.variables_tf = var_blocks

        # Helper: snake_case conversion
        def to_snake(name):
            return re.sub(r'[^a-zA-Z0-9]', '_', name).lower()

        # Parse main.tf for resource blocks and extract variable candidates
        # Use cleaned main.tf if available
        cleaned_main_tf_path = self.output_dir / "main.cleaned.tf"
        if cleaned_main_tf_path.exists():
            main_tf_path = cleaned_main_tf_path
        else:
            main_tf_path = self.output_dir / "main.tf"
        if main_tf_path.exists():
            with open(main_tf_path, "r") as f:
                content = f.read()
            # Find all resource blocks
            resource_blocks = re.findall(r'resource\s+"[^"]+"\s+"[^"]+"\s*{(.*?)}\s*', content, re.DOTALL)
            for block in resource_blocks:
                # Find all key = value pairs, including nested blocks and tags
                lines = block.splitlines()
                in_tags = False
                tags_dict = {}
                for line in lines:
                    line = line.strip()
                    if line.startswith('tags = {'):
                        in_tags = True
                        continue
                    if in_tags:
                        if line == '}':
                            in_tags = False
                            # Add tags as a map variable
                            if tags_dict:
                                var_name = 'tags'
                                variables[var_name] = 'tags'
                                descriptions[var_name] = 'Tags for resource.'
                                types[var_name] = 'map(string)'
                                defaults[var_name] = tags_dict
                            tags_dict = {}
                        else:
                            tag_match = re.match(r'(\w+)\s*=\s*"([^"]+)"', line)
                            if tag_match:
                                tags_dict[tag_match.group(1)] = tag_match.group(2)
                        continue
                    # Match key = value
                    match = re.match(r'(\w+)\s*=\s*(.+)', line.strip())
                    if match:
                        key, value = match.group(1), match.group(2).strip()
                        # Skip computed/data-sourced values, never parameterize 'depends_on', and never parameterize *_id, *_ids, or ARM IDs
                        if (
                            "data.azurerm_resource_group.rg" in value or
                            "data.azurerm_network_interface" in value or
                            "azurerm_linux_virtual_machine" in value or
                            "azurerm_resource_group" in value or
                            key == "depends_on" or
                            re.match(r'.*_id(s)?$', key) or
                            re.match(r'.*id(s)?$', key) or
                            (isinstance(value, str) and value.startswith('"/subscriptions/'))
                        ):
                            out_lines.append(f"{key} = {value}")
                            i += 1
                            continue
                        elif any(x in key for x in ["self_link", "uri"]):
                            out_lines.append(f"{key} = {value}")
                            i += 1
                            continue
                        # Use new variable naming pattern
                        var_name = build_var_name(rtype, rname, key)
                        out_lines.append(f"{key} = var.{var_name}")
                        i += 1
                        continue

        # Generate variables.tf content
        var_blocks = []
        for var_name in variables:
            # Skip provider/data-sourced/computed fields, IDs, self-links, URIs, or environment-specific names
            if any(x in var_name for x in ["id", "self_link", "uri"]):
                continue
            if re.search(r'(prod|dev|qa|test|stage)', var_name):
                continue
            type_val = types[var_name]
            # Use strict types for objects/maps/lists
            if type_val.startswith('map') or type_val.startswith('object'):
                type_str = type_val
            elif type_val.startswith('list'):
                type_str = type_val
            elif type_val in ["string", "number", "bool"]:
                type_str = type_val
            else:
                type_str = 'string'
            block = f'variable "{var_name}" {{\n  description = "{descriptions[var_name]}"\n  type = {type_str}'
            # Sensitive fields
            if var_name in sensitive or any(s in var_name for s in ["password", "secret", "key"]):
                block += '\n  sensitive = true'
            # Validation blocks for enumerated fields
            if var_name in defaults and isinstance(defaults[var_name], str):
                if var_name in ["region", "sku", "tier"]:
                    allowed = [defaults[var_name]]
                    block += f'\n  validation {{\n    condition = contains({allowed}, var.{var_name})\n    error_message = "Invalid value for {var_name}."\n  }}'
            # Default value (only if not sensitive and not required)
            if var_name in defaults:
                if type_val == 'map(string)' and isinstance(defaults[var_name], dict):
                    tags_lines = ['  default = {']
                    for k, v in defaults[var_name].items():
                        tags_lines.append(f'    {k} = "{v}"')
                    tags_lines.append('  }')
                    block += '\n' + '\n'.join(tags_lines)
                elif type_val == 'bool':
                    block += f'\n  default = {str(defaults[var_name]).lower()}'
                elif type_val == 'number':
                    block += f'\n  default = {defaults[var_name]}'
                elif type_val.startswith('list'):
                    val = defaults[var_name]
                    if isinstance(val, str) and val.startswith('[') and val.endswith(']'):
                        items = re.findall(r'"([^"]+)"', val)
                        hcl_list = '[' + ', '.join(f'"{item}"' for item in items) + ']'
                        block += f'\n  default = {hcl_list}'
                    elif isinstance(val, list):
                        hcl_list = '[' + ', '.join(f'"{item}"' for item in val) + ']'
                        block += f'\n  default = {hcl_list}'
                    else:
                        block += f'\n  default = {val}'
                else:
                    block += f'\n  default = "{defaults[var_name]}"'
            block += '\n}\n'
            var_blocks.append(block)
        # Always ensure resource_group_name is present in variables.tf
        found_rg_var = any('variable "resource_group_name"' in b for b in var_blocks)
        if not found_rg_var:
            block = f'variable "resource_group_name" {{\n  description = "The name of the Azure resource group."\n  type = string\n  default = "{self.resource_group_name}"\n}}\n'
            var_blocks.append(block)

        # Compare variables.tf and main.tf
        main_tf_path = self.output_dir / "main.tf"
        main_tf_vars = set()
        if main_tf_path.exists():
            with open(main_tf_path, "r") as f:
                content = f.read()
            main_tf_vars = set(re.findall(r'var\.([a-zA-Z0-9_]+)', content))
        var_names_in_tf = set()
        for block in var_blocks:
            match = re.match(r'variable "([^"]+)"', block)
            if match:
                var_names_in_tf.add(match.group(1))
        alignment = main_tf_vars == var_names_in_tf
        self.variables_alignment_result = alignment
        self.variables_alignment_message = f"Variables alignment: {alignment}. main.tf variables: {len(main_tf_vars)}, variables.tf: {len(var_names_in_tf)}"
        print(self.variables_alignment_message)
        self.log(f"Populating variables.tf with {len(var_blocks)} variable blocks.")
        self.writers.variables_tf = var_blocks

    def generate_tfvars(self):
        """Generate a blank terraform.tfvars structure with all variable names (except sensitive/id/data), ready for user input."""
        self.log("Generating blank terraform.tfvars structure...")
        tfvars_lines = []
        # Load variables.tf
        variables_tf_path = self.output_dir / "variables.tf"
        var_blocks = []
        if variables_tf_path.exists():
            with open(variables_tf_path, "r") as f:
                block = ""
                for line in f:
                    if line.strip().startswith("variable "):
                        if block:
                            var_blocks.append(block)
                        block = line
                    else:
                        block += line
                if block:
                    var_blocks.append(block)
        else:
            var_blocks = self.writers.variables_tf

        for var_block in var_blocks:
            match = re.match(r'variable "([^"]+)"', var_block)
            if match:
                var_name = match.group(1)
                # Exclude *_id, *_ids, ARM IDs
                if (
                    var_name.endswith('_id') or var_name.endswith('_ids') or
                    var_name == 'id' or var_name == 'ids' or
                    re.match(r'.*id(s)?$', var_name)
                ):
                    continue
                # Check for sensitive attribute
                sensitive_match = re.search(r'sensitive\s*=\s*true', var_block)
                if sensitive_match or any(s in var_name for s in ["password", "secret", "key"]):
                    tfvars_lines.append(f'# {var_name} is sensitive and not exported')
                    continue
                tfvars_lines.append(f'{var_name} = ""')
        self.writers.tfvars = tfvars_lines

    # ----------------------------------------------------------

    def convert_literals_to_variables(self):
        """
        Scan for hardcoded literals and convert them to variables.tf entries.
        """
        self.log("Extracting literals -> variables...")

        # Real implementation would walk HCL AST.
        # For now, placeholder structure.
        pass

    # ----------------------------------------------------------

    def generate_data_sources(self):
        """Create data-sources.tf"""
        self.log("Generating data sources...")

        self.writers.data_sources = [
            """
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}
            """.strip()
        ]

    # ----------------------------------------------------------

# Auto-generated main.tf
