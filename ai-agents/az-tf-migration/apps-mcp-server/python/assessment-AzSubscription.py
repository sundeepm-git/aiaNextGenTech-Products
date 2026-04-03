
import os
import sys
import argparse
import subprocess
import shutil
import re
from dotenv import load_dotenv
from azure.identity import ClientSecretCredential

from azure.mgmt.resource import ResourceManagementClient
from datetime import datetime, timezone

# List of Azure resource types to be classified as 'Reference' (excluded from 'Managed')
EXCLUDED_AZURE_TYPES = [
    "Microsoft.OperationalInsights/workspaces",
    "Microsoft.Insights/components",
    "Microsoft.Automation/automationAccounts",
    "Microsoft.RecoveryServices/vaults",
    "Microsoft.KeyVault/vaults",
    "Microsoft.EventHub/namespaces",
    "Microsoft.ServiceBus/namespaces",
    "Microsoft.Cache/Redis",
    "Microsoft.DBforPostgreSQL/servers",
    "Microsoft.DBforMySQL/servers",
    "Microsoft.DBforMariaDB/servers",
    "Microsoft.Sql/servers",
    "Microsoft.Sql/managedInstances",
    "Microsoft.CosmosDB/databaseAccounts",
    "Microsoft.Search/searchServices",
    "Microsoft.DataFactory/factories",
    "Microsoft.AppConfiguration/configurationStores",
    "Microsoft.Web/serverfarms",
    "Microsoft.Network/virtualNetworks",
    "Microsoft.Network/publicIPAddresses",
    "Microsoft.Network/networkSecurityGroups",
    "Microsoft.Network/applicationGateways",
    "Microsoft.Network/loadBalancers",
    "Microsoft.Network/virtualNetworkGateways",
    "Microsoft.Network/privateEndpoints",
    "Microsoft.Network/privateLinkServices",
    "Microsoft.Network/dnsZones",
    "Microsoft.Network/expressRouteCircuits",
    "Microsoft.Network/expressRouteGateways",
    "Microsoft.Network/expressRoutePorts",
    "Microsoft.Network/expressRouteCrossConnections",
    "Microsoft.Network/routeTables",
    "Microsoft.Network/connections",
    "Microsoft.Network/firewallPolicies",
    "Microsoft.Network/azureFirewalls",
    "Microsoft.Network/natGateways",
    "Microsoft.Network/trafficManagerProfiles",
    "Microsoft.Network/frontdoors",
    "Microsoft.Network/privateDnsZones",
    "Microsoft.Network/vpnGateways",
    "Microsoft.Network/vpnSites",
    "Microsoft.Network/vpnConnections",
    "Microsoft.Network/virtualRouters",
    "Microsoft.Network/virtualHubs",
    "Microsoft.Network/routeMaps",
    "Microsoft.Network/peerings",
    "Microsoft.Network/serviceEndpointPolicies",
    "Microsoft.Network/applicationSecurityGroups",
    "Microsoft.Network/firewallPolicyRuleCollectionGroups",
    "Microsoft.Network/virtualWANs",
    "Microsoft.Network/virtualHubRouteTables",
    "Microsoft.Network/virtualHubRouteTableV2s",
    "Microsoft.Network/virtualHubBgpConnections",
    "Microsoft.Network/virtualHubIpConfigurations",
    "Microsoft.Network/virtualHubRouteTableV2s",
    "Microsoft.Network/virtualHubRouteTableV2s",
    "Microsoft.Network/virtualHubRouteTableV2s",
    "Microsoft.Network/virtualHubRouteTableV2s"
]

# ...existing code...

# If get_args() is needed, define it properly below. Otherwise, remove the empty definition.

# Load environment variables from .env file at startup
load_dotenv()

def azure_cli_login():
    """
    Authenticates to Azure CLI using Service Principal credentials from environment variables.
    Exits with code 1 if authentication fails or credentials are missing.
    Only SPN authentication is allowed. Local authentication is not permitted.
    """
    client_id = os.getenv("AZURE_CLIENT_ID")
    client_secret = os.getenv("AZURE_CLIENT_SECRET")
    tenant_id = os.getenv("AZURE_TENANT_ID")
    object_id = os.getenv("AZURE_OBJECT_ID")  # Loaded for completeness if needed elsewhere
    if not all([client_id, client_secret, tenant_id, object_id]):
        print("Error: Missing one or more required SPN environment variables (AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, AZURE_OBJECT_ID).", file=sys.stderr)
        sys.exit(1)
    try:
        result = subprocess.run([
            "az", "login",
            "--service-principal",
            "-u", client_id,
            "-p", client_secret,
            "--tenant", tenant_id
        ], capture_output=True, text=True)
        if result.returncode != 0:
            print("Azure CLI login failed:", result.stderr, file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        print(f"Exception during Azure CLI login: {e}", file=sys.stderr)
        sys.exit(1)


def get_args():
    parser = argparse.ArgumentParser(description='Azure Subscription Assessment')
    parser.add_argument('--subscription_id', required=True, help='Azure Subscription ID')
    parser.add_argument('--resource_groups', nargs='*', help='Optional list of Resource Groups')
    return parser.parse_args()

def generate_report_html(data):
    managed = [item for item in data["items"] if item["status"] == "Managed"]
    reference = [item for item in data["items"] if item["status"] == "Reference"]
    now = datetime.now()
    date_str = now.strftime('%Y-%m-%d %H:%M:%S')

    # Decision logic
    count_managed = len(managed)
    count_reference = len(reference)
    total_count = count_managed + count_reference
    if total_count == 0:
        decision = "Not Applicable"
        recommendation = "No resources found to export."
        color_class = "neutral"
    elif count_managed > 0:
        decision = "Strong Candidate"
        recommendation = f"Contains {count_managed} supported workload resources. Use 'aztfexport' to codify."
        color_class = "success"
    else:
        decision = "Review Required"
        recommendation = "Mostly platform resources. Verify if these are already managed by another state file before importing."
        color_class = "warning"

    # Group by type
    from collections import Counter, defaultdict
    managed_by_type = Counter([r["type"] for r in managed])
    reference_by_type = Counter([r["type"] for r in reference])

    # Modern HTML/CSS
    html = f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure Subscription Assessment Report</title>
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
        .success {{ background-color: #dff6dd; color: #107c10; font-weight: bold; padding: 8px; }}
        .warning {{ background-color: #fff4ce; color: #795e00; font-weight: bold; padding: 8px; }}
        .neutral {{ background-color: #f3f2f1; color: #323130; padding: 8px; }}
        .type-count {{ display: flex; justify-content: space-between; padding: 10px 15px; background: #F8F9FA; margin-bottom: 5px; border-radius: 3px; border-left: 3px solid #4472C4; }}
        .type-name {{ font-weight: 500; color: #333; }}
        .type-number {{ font-weight: bold; color: #4472C4; background: white; padding: 2px 8px; border-radius: 3px; }}
        .footer {{ background: #F8F9FA; padding: 20px 30px; text-align: center; color: #666; font-size: 14px; border-top: 2px solid #E0E0E0; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Azure Subscription Assessment Report</h1>
            <p>Subscription: {data.get("sub_id")}</p>
        </div>
        <div class="content">
            <!-- Assessment Summary -->
            <div class="section">
                <div class="section-title">Assessment Summary</div>
                <div class="stats-grid">
                    <div class="stat-card">
                        <div class="stat-number">{total_count}</div>
                        <div class="stat-label">Total Resources</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">{count_managed}</div>
                        <div class="stat-label">Managed Resources</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">{count_reference}</div>
                        <div class="stat-label">Reference Resources</div>
                    </div>
                </div>
            </div>
            <!-- Report Outcome -->
            <div class="section">
                <div class="section-title">Report Outcome: aztfexport Suitability</div>
                <table>
                    <thead>
                        <tr><th>Metric</th><th>Value</th></tr>
                    </thead>
                    <tbody>
                        <tr><td>Total Resources</td><td><strong>{total_count}</strong></td></tr>
                        <tr><td>Managed (Workload)</td><td><span class="status-managed">{count_managed}</span></td></tr>
                        <tr><td>Reference (Platform)</td><td><span class="status-reference">{count_reference}</span></td></tr>
                        <tr class='{color_class}'><td><strong>Decision</strong></td><td><strong>{decision}</strong></td></tr>
                        <tr><td>Recommendation</td><td>{recommendation}</td></tr>
                    </tbody>
                </table>
            </div>
            <!-- Managed Resources by Type -->
            <div class="section">
                <div class="section-title">Managed Resources by Type</div>
                {''.join([f'<div class="type-count"><span class="type-name">{t}</span><span class="type-number">{n}</span></div>' for t, n in managed_by_type.items()]) if managed_by_type else '<p style="color: #666; font-style: italic; padding: 10px;">No managed resources found.</p>'}
            </div>
            <!-- Reference Resources by Type -->
            <div class="section">
                <div class="section-title">Reference Resources by Type</div>
                {''.join([f'<div class="type-count"><span class="type-name">{t}</span><span class="type-number">{n}</span></div>' for t, n in reference_by_type.items()]) if reference_by_type else '<p style="color: #666; font-style: italic; padding: 10px;">No reference resources found.</p>'}
            </div>
            <!-- Managed Resources - Detailed Listing -->
            <div class="section">
                <div class="section-title">Managed Resources - Detailed Listing</div>
                {f'''<table><thead><tr><th>Resource Group</th><th>Resource Name</th><th>Resource Type</th><th>Status</th></tr></thead><tbody>{''.join([f'<tr><td>{r["rg"]}</td><td>{r["name"]}</td><td>{r["type"]}</td><td><span class="status-managed">Managed</span></td></tr>' for r in managed])}</tbody></table>''' if managed else '<p style="color: #666; font-style: italic; padding: 10px;">No managed resources found.</p>'}
            </div>
            <!-- Reference Resources - Detailed Listing -->
            <div class="section">
                <div class="section-title">Reference Resources - Detailed Listing</div>
                {f'''<table><thead><tr><th>Resource Group</th><th>Resource Name</th><th>Resource Type</th><th>Status</th></tr></thead><tbody>{''.join([f'<tr><td>{r["rg"]}</td><td>{r["name"]}</td><td>{r["type"]}</td><td><span class="status-reference">Reference</span></td></tr>' for r in reference])}</tbody></table>''' if reference else '<p style="color: #666; font-style: italic; padding: 10px;">No reference resources found.</p>'}
            </div>
        </div>
        <div class="footer">
            <p>Report Generated: {date_str}</p>
            <p>Azure Subscription Assessment Tool</p>
        </div>
    </div>
</body>
</html>'''
    return html

def main():
    args = get_args()
    
    # Strictly fetch SPN credentials
    client_id = os.getenv("AZURE_CLIENT_ID")
    client_secret = os.getenv("AZURE_CLIENT_SECRET")
    tenant_id = os.getenv("AZURE_TENANT_ID")
    subscription_id = args.subscription_id
    
    # Locate Azure CLI
    AZ_CLI = os.getenv("AZ_CLI_PATH") or shutil.which("az") or shutil.which("az.cmd")

    # 1. Start Progress message
    print("PROGRESS: Starting SPN authentication...", file=sys.stderr)

    if not all([client_id, client_secret, tenant_id]):
        print("ERROR: Missing required SPN environment variables (AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID). Local login is not supported.")
        sys.exit(1)

    try:
        # Perform Login - capture_output=True silences the "Request/Response headers" messages
        login_res = subprocess.run(
            [AZ_CLI, "login", "--service-principal", "-u", client_id, "-p", client_secret, "--tenant", tenant_id],
            capture_output=True, text=True, check=True
        )
        
        # Set subscription context
        subprocess.run(
            [AZ_CLI, "account", "set", "--subscription", subscription_id],
            capture_output=True, text=True, check=True
        )
        
        # 2. Authentication Success message
        print("SPN authentication done.", file=sys.stderr)

    except subprocess.CalledProcessError as e:
        print(f"ERROR: SPN authentication failed. {e.stderr}")
        sys.exit(1)

    # 3. Resource Scanning and Report Generation
    try:
        credential = ClientSecretCredential(tenant_id=tenant_id, client_id=client_id, client_secret=client_secret)
        resource_client = ResourceManagementClient(credential, subscription_id)

        resources_found = []
        if args.resource_groups:
            for rg in args.resource_groups:
                for res in resource_client.resources.list_by_resource_group(rg):
                    resources_found.append({"name": res.name, "type": res.type, "rg": rg})
        else:
            for res in resource_client.resources.list():
                rg_name = res.id.split('/')[4] if '/' in res.id else "Global"
                resources_found.append({"name": res.name, "type": res.type, "rg": rg_name})

        # Classify resources
        managed = [r for r in resources_found if r["type"] not in EXCLUDED_AZURE_TYPES]
        reference = [r for r in resources_found if r["type"] in EXCLUDED_AZURE_TYPES]

        report_data = {
            "sub_id": subscription_id,
            "items": [{**r, "status": "Managed"} for r in managed] + [{**r, "status": "Reference"} for r in reference]
        }


        html_report = generate_report_html(report_data)

        # Build unique report name per subscription+resource-group to avoid overwrites.
        rg_for_name = args.resource_groups[0] if args.resource_groups else "all-resource-groups"
        rg_safe = re.sub(r"[^A-Za-z0-9._-]", "-", rg_for_name)
        report_filename = f"{subscription_id}-{rg_safe}-assessment-report.html"
        with open(report_filename, "w", encoding="utf-8") as f:
            f.write(html_report)

        storage_account = os.getenv("storageAccount")
        container_name = os.getenv("ASSESSMENT_FOLDER", "assessment-reports")  # Distinct per-process container
        stdout_msgs = []
        stderr_msgs = []
        started_at = datetime.now(timezone.utc).isoformat()
        completed_at = None

        if storage_account:
            blob_path = f"{subscription_id}/{report_filename}"
            subprocess.run([AZ_CLI, "storage", "container", "create", "--account-name", storage_account, "--name", container_name, "--auth-mode", "login"], capture_output=True)
            upload_res = subprocess.run([
                AZ_CLI, "storage", "blob", "upload",
                "--account-name", storage_account,
                "--container-name", container_name,
                "--name", blob_path,
                "--file", report_filename,
                "--overwrite", "true",
                "--auth-mode", "login"
            ], capture_output=True, text=True)
            if upload_res.returncode == 0:
                stdout_msgs.append(f"SUCCESS: HTML report successfully uploaded in storage account '{storage_account}'.")
            else:
                stderr_msgs.append("ERROR: Storage upload failed.")
        else:
            stdout_msgs.append("SUCCESS: Local report generated (storageAccount environment variable not set).")

        completed_at = datetime.now(timezone.utc).isoformat()
        import uuid
        import json
        response = {
            "jobId": str(uuid.uuid4()),
            "subscriptionId": subscription_id,
            "resourceGroup": rg_for_name,
            "reportFileName": report_filename,
            "status": "completed",
            "storageAccount": storage_account or "unknown",
            "startedAt": started_at,
            "completedAt": completed_at
        }
        print(json.dumps(response, indent=2))

    except Exception as e:
        print(f"ERROR: Assessment process failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()