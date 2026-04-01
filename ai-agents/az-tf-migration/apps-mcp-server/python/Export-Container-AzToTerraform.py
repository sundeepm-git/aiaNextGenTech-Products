
import os
import sys
import subprocess
import shutil
import argparse
import json
import re
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv

# --- Load Environment Configuration ---
env_path = Path(__file__).resolve().parent.parent / '.env'
load_dotenv(dotenv_path=env_path)

# --- Configuration ---
IS_CONTAINER = os.environ.get("RUNNING_IN_CONTAINER", "false").lower() == "true"
# Root Directory Logic
if IS_CONTAINER:
    BASE_DIR = Path("/app/azure-export")
else:
    BASE_DIR = Path(__file__).resolve().parent.parent / "azure-export"

AZ_CLI = "az.cmd" if os.name == "nt" else "az"

# --- Exclusion List for Data Blocks (Foundation Resources) ---
EXCLUDED_AZURE_TYPES = [
    "Microsoft.Network/virtualNetworks",
    "Microsoft.Network/virtualNetworks/subnets",
    "Microsoft.Network/networkSecurityGroups",
    "Microsoft.Network/networkSecurityGroups/securityRules",
    "Microsoft.Network/networkInterfaces",
    "Microsoft.Network/publicIPAddresses",
    "Microsoft.Network/loadBalancers",
    "Microsoft.Network/routeTables",
    "Microsoft.Network/applicationGateways",
    "Microsoft.Network/azureFirewalls",
    "Microsoft.Network/virtualNetworkGateways",
    "Microsoft.Network/localNetworkGateways",
    "Microsoft.Network/privateEndpoints",
    "Microsoft.Network/natGateways",
    "Microsoft.Network/bastionHosts",
    "Microsoft.Insights/diagnosticSettings",
    "Microsoft.Insights/actionGroups",
    "Microsoft.Insights/metricAlerts",
    "Microsoft.Insights/activityLogAlerts",
    "Microsoft.Insights/components",
    "Microsoft.Insights/workbooks",
    "Microsoft.OperationalInsights/workspaces",
    "Microsoft.OperationsManagement/solutions",
    "Microsoft.Authorization/roleAssignments",
    "Microsoft.Authorization/roleDefinitions",
    "Microsoft.Authorization/policyAssignments",
    "Microsoft.Authorization/policyDefinitions",
    "Microsoft.Authorization/locks",
    "Microsoft.Security/pricings",
    "Microsoft.Security/workspaceSettings",
    "Microsoft.SecurityInsights/alertRules",
    "Microsoft.SecurityInsights/automationRules",
    "Microsoft.SecurityInsights/dataConnectors",
    "Microsoft.SecurityInsights/watchlists"
]

def run_streaming_shell(cmd, cwd=None):
    """Executes command and prints output immediately to prevent buffering hangs."""
    env = os.environ.copy()
    env["AZTFEXPORT_PLAIN_UI"] = "true" 
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=cwd, env=env, bufsize=1, universal_newlines=True)
    full_output = []
    while True:
        line = process.stdout.readline()
        if not line and process.poll() is not None: break
        if line:
            clean_line = line.strip()
            print(f"  [AZTF]: {clean_line}")
            full_output.append(clean_line)
    return process.returncode, "\n".join(full_output)

def generate_html_report(export_dir, sub_id, rg_name, resources_exported):
    print("INFO: Generating HTML report...")
    now = datetime.now()
    date_str = now.strftime('%Y-%m-%d')
    time_str = now.strftime('%H:%M:%S')
    export_start = now.strftime('%Y-%m-%d %H:%M:%S')
    # File status
    def file_status(path):
        return '<span class="file-status">✓ Generated</span>' if (export_dir / path).exists() else 'Not Generated'

    # Managed resources by type
    managed_types = {}
    for r in resources_exported:
        t = r['type']
        managed_types[t] = managed_types.get(t, 0) + 1

    # Detailed resource listing
    detailed_resources = []
    for r in resources_exported:
        detailed_resources.append({
            'name': r['name'],
            'type': r['type'],
            'status': 'Managed',
            'file': 'main.tf'
        })

    # Data sources (reference resources)
    data_sources = []
    if (export_dir / 'data-block.tf').exists():
        with open(export_dir / 'data-block.tf', encoding='utf-8') as f:
            for line in f:
                m = re.match(r'data\s+"([^"]+)"\s+"([^"]+)"', line)
                if m:
                    data_sources.append({'name': m.group(2), 'type': m.group(1), 'status': 'Reference', 'file': 'data-block.tf'})

    # HTML content
    html = f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure to Terraform Export Report - {rg_name}</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #F5F5F5; color: #333; line-height: 1.6; }}
        .container {{ max-width: 1400px; margin: 0 auto; background: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px 30px; text-align: center; }}
        .header h1 {{ font-size: 32px; margin-bottom: 10px; font-weight: 600; }}
        .header p {{ font-size: 16px; opacity: 0.9; }}
        .content {{ padding: 30px; }}
        .section {{ margin-bottom: 40px; background: white; border-radius: 8px; }}
        .section-title {{ background: #F8F9FA; padding: 15px 20px; font-size: 20px; font-weight: bold; color: #2E5090; border-left: 5px solid #4472C4; margin-bottom: 20px; border-radius: 4px; }}
        .info-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; margin-bottom: 20px; }}
        .info-item {{ background: #F8F9FA; padding: 15px; border-radius: 5px; border-left: 3px solid #4472C4; }}
        .info-label {{ font-weight: bold; color: #2E5090; font-size: 14px; margin-bottom: 5px; }}
        .info-value {{ color: #333; font-size: 16px; }}
        .stats-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }}
        .stat-card {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; box-shadow: 0 4px 15px rgba(0,0,0,0.1); transition: transform 0.3s; }}
        .stat-card:hover {{ transform: translateY(-5px); }}
        .stat-number {{ font-size: 36px; font-weight: bold; margin-bottom: 5px; }}
        .stat-label {{ font-size: 14px; opacity: 0.9; }}
        table {{ width: 100%; border-collapse: collapse; margin-top: 15px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); border-radius: 8px; overflow: hidden; }}
        table thead {{ background: #4472C4; color: white; }}
        table th {{ padding: 12px; text-align: left; font-weight: 600; font-size: 14px; }}
        table tbody tr {{ border-bottom: 1px solid #E0E0E0; transition: background 0.2s; }}
        table tbody tr:hover {{ background: #F5F5F5; }}
        table tbody tr:last-child {{ border-bottom: none; }}
        table td {{ padding: 12px; font-size: 13px; }}
        .status-managed {{ background: #28A745; color: white; padding: 4px 12px; border-radius: 4px; font-size: 11px; font-weight: bold; display: inline-block; }}
        .status-reference {{ background: #FFC107; color: #333; padding: 4px 12px; border-radius: 4px; font-size: 11px; font-weight: bold; display: inline-block; }}
        .type-count {{ display: flex; justify-content: space-between; padding: 10px 15px; background: #F8F9FA; margin-bottom: 5px; border-radius: 3px; border-left: 3px solid #4472C4; }}
        .type-name {{ font-weight: 500; color: #333; }}
        .type-number {{ font-weight: bold; color: #4472C4; background: white; padding: 2px 8px; border-radius: 3px; }}
        .footer {{ background: #F8F9FA; padding: 20px 30px; text-align: center; color: #666; font-size: 14px; border-top: 2px solid #E0E0E0; }}
        .file-list {{ list-style: none; padding-left: 0; }}
        .file-list li {{ background: #F8F9FA; padding: 10px 15px; margin-bottom: 8px; border-left: 3px solid #4472C4; border-radius: 3px; }}
        .file-status {{ color: #28A745; font-weight: bold; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Azure to Terraform Export Report</h1>
            <p>Resource Group: {rg_name}</p>
        </div>
        <div class="content">
            <div class="section">
                <div class="section-title">Export Information</div>
                <div class="info-grid">
                    <div class="info-item"><div class="info-label">Subscription ID</div><div class="info-value">{sub_id}</div></div>
                    <div class="info-item"><div class="info-label">Resource Group</div><div class="info-value">{rg_name}</div></div>
                    <div class="info-item"><div class="info-label">Export Date</div><div class="info-value">{date_str}</div></div>
                    <div class="info-item"><div class="info-label">Export Time</div><div class="info-value">{time_str}</div></div>
                </div>
            </div>
            <div class="section">
                <div class="section-title">Resource Summary</div>
                <div class="stats-grid">
                    <div class="stat-card"><div class="stat-number">{len(resources_exported)}</div><div class="stat-label">Total Exported Resources</div></div>
                    <div class="stat-card"><div class="stat-number">{len([r for r in detailed_resources if r['status']=="Managed"])} </div><div class="stat-label">Managed Resources</div></div>
                    <div class="stat-card"><div class="stat-number">{len(data_sources)}</div><div class="stat-label">Data Sources</div></div>
                </div>
            </div>
            <div class="section">
                <div class="section-title">Terraform Files Generated</div>
                <ul class="file-list">
                    <li><strong>main.tf</strong> - {file_status('main.tf')} - Resource definitions</li>
                    <li><strong>provider.tf</strong> - {file_status('provider.tf')} - Azure provider configuration</li>
                    <li><strong>data-block.tf</strong> - {file_status('data-block.tf')} - Data sources (reference-only)</li>
                    <li><strong>terraform.tfstate</strong> - {file_status('terraform.tfstate')} - State file</li>
                </ul>
            </div>
            <div class="section">
                <div class="section-title">Managed Resources by Type</div>
                {''.join([f'<div class="type-count"><span class="type-name">{t}</span><span class="type-number">{c}</span></div>' for t, c in managed_types.items()]) or '<p style="color: #666; font-style: italic;">No managed resources found.</p>'}
            </div>
            <div class="section">
                <div class="section-title">Exported Resources - Detailed Listing</div>
                <table><thead><tr><th>Resource Name</th><th>Resource Type</th><th>Status</th><th>File</th></tr></thead><tbody>
                {''.join([f'<tr><td>{r["name"]}</td><td>{r["type"]}</td><td><span class="status-managed">{r["status"]}</span></td><td>{r["file"]}</td></tr>' for r in detailed_resources])}
                {''.join([f'<tr><td>{r["name"]}</td><td>{r["type"]}</td><td><span class="status-reference">{r["status"]}</span></td><td>{r["file"]}</td></tr>' for r in data_sources])}
                </tbody></table>
            </div>
        </div>
        <div class="footer">Generated by Azure to Terraform Export Tool</div>
    </div>
</body>
</html>
'''
    (export_dir / "Export-Report-Latest.html").write_text(html, encoding="utf-8")

def generate_data_blocks(export_dir, excluded_resources, rg_name):
    print("INFO: Generating data-block.tf...")
    content = "# Data blocks for foundation infrastructure\n\n"
    for res in excluded_resources:
        type_parts = res['type'].split('/')
        clean_type = type_parts[-1].lower().rstrip('s')
        tf_type = f"azurerm_{clean_type}"
        if "virtualnetworks" in res['type'].lower(): tf_type = "azurerm_virtual_network"
        if "networkinterfaces" in res['type'].lower(): tf_type = "azurerm_network_interface"
        safe_name = re.sub(r'[^a-zA-Z0-9_]', '_', res['name'])
        content += f'data "{tf_type}" "{safe_name}" {{\n  name = "{res["name"]}"\n  resource_group_name = "{rg_name}"\n}}\n\n'
    (export_dir / "data-block.tf").write_text(content, encoding="utf-8")

def upload_and_push(export_dir, sub_id, rg_name):
    # 1. Storage Upload
    storage_account = os.getenv("storageAccount")
    container = os.getenv("AZURE_STORAGE_CONTAINER", "aztfexport")
    upload_success = False
    
    if storage_account:
        print(f"INFO: Attempting upload to Storage Account: {storage_account}...")
        try:
            res = subprocess.run([AZ_CLI, "storage", "blob", "upload-batch", "--account-name", storage_account, "--destination", container, "--source", str(export_dir), "--destination-path", f"{sub_id}/{rg_name}", "--overwrite", "true", "--auth-mode", "login"], capture_output=True, text=True)
            if res.returncode == 0:
                print(f"SUCCESS: Files pushed to Storage Account '{storage_account}'.")
                upload_success = True
            else:
                print(f"ERROR: Storage upload failed. Check permissions for '{storage_account}'.")
                print(f"ERROR: stdout: {res.stdout}")
                print(f"ERROR: stderr: {res.stderr}")
                sys.exit(1)  # Exit with error code to mark job as failed
        except Exception as e: 
            print(f"ERROR: Storage operation failed: {e}")
            sys.exit(1)  # Exit with error code to mark job as failed
    else:
        print(f"WARNING: storageAccount not configured in environment - skipping upload")
        # Still consider it success if no storage account is configured

    # 2. GitHub Push
    token = os.getenv("GITHUB_TOKEN")
    repo_url = os.getenv("GITHUB_REPO_URL")
    if token and repo_url:
        print("INFO: Attempting push to GitHub...")
        auth_url = repo_url.replace("https://", f"https://{token}@")
        try:
            subprocess.run(["git", "init"], cwd=export_dir, capture_output=True, check=True)
            subprocess.run(["git", "config", "user.name", "Export-Bot"], cwd=export_dir, check=True)
            subprocess.run(["git", "config", "user.email", "bot@mcp.local"], cwd=export_dir, check=True)
            subprocess.run(["git", "remote", "add", "origin", auth_url], cwd=export_dir, check=True)
            subprocess.run(["git", "add", "."], cwd=export_dir, check=True)
            subprocess.run(["git", "commit", "-m", f"Auto-export: {rg_name}"], cwd=export_dir, check=True)
            push_res = subprocess.run(["git", "push", "-u", "origin", "master", "--force"], cwd=export_dir, capture_output=True, text=True, check=True)
            print(f"SUCCESS: Code pushed to GitHub: {repo_url}")
        except subprocess.CalledProcessError as e:
            print(f"ERROR: GitHub push failed. Verify GITHUB_TOKEN.")
            print(f"ERROR: {e}")
            # Don't fail the entire job for GitHub issues if storage upload succeeded
            if not upload_success:
                sys.exit(1)

def main():

    parser = argparse.ArgumentParser()
    parser.add_argument("--subscription-id", required=True)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--job-id", required=False) # Fixed job-id error
    args = parser.parse_args()

    # --- Azure CLI SPN Login ---
    client_id = os.getenv("AZURE_CLIENT_ID") or os.getenv("ARM_CLIENT_ID")
    client_secret = os.getenv("AZURE_CLIENT_SECRET") or os.getenv("ARM_CLIENT_SECRET")
    tenant_id = os.getenv("AZURE_TENANT_ID") or os.getenv("ARM_TENANT_ID")
    subscription_id = os.getenv("AZURE_SUBSCRIPTION_ID") or os.getenv("ARM_SUBSCRIPTION_ID") or args.subscription_id

    if client_id and client_secret and tenant_id and subscription_id:
        print("INFO: Authenticating to Azure CLI using Service Principal...")
        login_cmd = [
            AZ_CLI, "login", "--service-principal",
            "-u", client_id,
            "-p", client_secret,
            "--tenant", tenant_id
        ]
        try:
            subprocess.run(login_cmd, check=True)
            subprocess.run([AZ_CLI, "account", "set", "--subscription", subscription_id], check=True)
        except Exception as e:
            print(f"ERROR: Azure CLI SPN login failed: {e}")
            return
    else:
        print("WARNING: SPN credentials not found in environment. Azure CLI may not be authenticated.")

    export_dir = BASE_DIR / args.subscription_id / args.resource_group
    
    try:
        if export_dir.exists(): shutil.rmtree(export_dir)
        export_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        print(f"ERROR: Directory preparation failed: {e}")
        return

    # 1. Get Resources
    print(f"INFO: Fetching resources for {args.resource_group}...")
    try:
        res_cmd = [AZ_CLI, "resource", "list", "-g", args.resource_group, "--subscription", args.subscription_id, "-o", "json"]
        all_resources = json.loads(subprocess.check_output(res_cmd, env=os.environ, text=True))
    except Exception as e:
        print(f"ERROR: Azure resource fetch failed. Ensure you are logged in.")
        return

    to_export = [r for r in all_resources if r['type'] not in EXCLUDED_AZURE_TYPES]
    to_data = [r for r in all_resources if r['type'] in EXCLUDED_AZURE_TYPES]

    # 2. Export Managed
    master_main_tf = export_dir / "main.tf"
    master_main_tf.write_text("# Managed Resources Export\n", encoding="utf-8")
    resources_exported = []

    for idx, res in enumerate(to_export):
        print(f"\n[{idx+1}/{len(to_export)}] Exporting: {res['name']}")
        sys.stdout.flush()
        sandbox = export_dir / f"sb_{idx}"
        cmd = ["aztfexport", "resource", "--name", re.sub(r'[^a-zA-Z0-9_]', '_', res['name']), "--subscription-id", args.subscription_id, "--non-interactive", "--output-dir", str(sandbox), "--overwrite", res['id']]
        ret, _ = run_streaming_shell(cmd)
        
        if ret == 0:
            for tf_file in sandbox.glob("*.tf"):
                if tf_file.name in ["provider.tf", "terraform.tf", "import.tf"]: continue
                content = re.sub(r'(?s)provider\s+"[^"]+"\s*\{.*?\}', '', tf_file.read_text())
                content = re.sub(r'(?s)terraform\s*\{.*?\}', '', content)
                with open(master_main_tf, "a") as f: f.write(f"\n# {res['name']}\n{content.strip()}\n")
            if (sandbox / "terraform.tfstate").exists() and not (export_dir / "terraform.tfstate").exists():
                shutil.copy(sandbox / "terraform.tfstate", export_dir / "terraform.tfstate")
            resources_exported.append(res)
        shutil.rmtree(sandbox, ignore_errors=True)

    # 3. Finalize Provider.tf
    (export_dir / "provider.tf").write_text(f'terraform {{ required_providers {{ azurerm = {{ source = "hashicorp/azurerm" version = "~> 3.0" }} }} }}\nprovider "azurerm" {{ features {{}} subscription_id = "{args.subscription_id}" }}', encoding="utf-8")

    # 4. Generate Data and Report
    generate_data_blocks(export_dir, to_data, args.resource_group)
    generate_html_report(export_dir, args.subscription_id, args.resource_group, resources_exported)
    
    # 5. Success Message & Uploads
    print("\n" + "="*50)
    sys.stdout.flush()
    print(f"SUCCESS: Export completed for Resource Group: {args.resource_group}")
    sys.stdout.flush()
    print(f"Managed Resources: {len(resources_exported)} | Data References: {len(to_data)}")
    sys.stdout.flush()
    print("="*50 + "\n")
    sys.stdout.flush()

    upload_and_push(export_dir, args.subscription_id, args.resource_group)
    print(f"\nFINAL_RESULT_PATH::{export_dir}")

if __name__ == "__main__":
    main()