import os
import json
import logging
import datetime
from typing import List, Dict, Any

# Azure SDK imports
from azure.identity.aio import DefaultAzureCredential
from azure.mgmt.resourcegraph import ResourceGraphClient
from azure.mgmt.resourcegraph.models import QueryRequest

# MCP client imports
from mcp_domain_tools.azure_clients import sentinel  # Azure Sentinel client
from mcp_domain_tools.azure_clients import xdr       # Azure XDR client

# Logging Configuration
logger = logging.getLogger("mcp.detection.agent")

def load_query(file_name: str) -> str:
    """Helper to read KQL queries from external files."""
    try:
        # Get path relative to this script for container compatibility
        base_path = os.path.dirname(os.path.abspath(__file__))
        file_path = os.path.join(base_path, file_name)
        with open(file_path, "r") as f:
            return f.read()
    except Exception as e:
        logger.error(f"Failed to load query file {file_name}: {e}")
        return ""

def register_detection_tools(mcp):
    """
    Main registration function called by server.py using FastMCP instance.
    """

    # 1. MDFC Detection Agent
    # FastMCP uses the @mcp.tool decorator. Schema is inferred from type hints.
    @mcp.tool(name="detection.mdfc.alerts")
    async def mdfc_alerts(subscription_id: str = None) -> str:
        """
        Building Detection Agent: Detects threats based on Microsoft Defender for Cloud alerts.
        Extracts resourceId, issueType, severity, and alertId. 
        Adheres to MCSB, CIS, and NIST standards via queries.kql.
        """
        kql_query = load_query("queries.kql")
        if not kql_query:
            return json.dumps({"error": "KQL query file 'queries.kql' not found or empty"})

        credential = DefaultAzureCredential()
        client = ResourceGraphClient(credential)

        try:
            subs = [subscription_id] if subscription_id else []
            query_request = QueryRequest(subscriptions=subs, query=kql_query)
            
            # Execute Query via Azure Resource Graph
            response = client.resources(query_request)
            
            extracted_alerts = []
            for alert in response.data:
                extracted_alerts.append({
                    "alertId": alert.get("alertId"),
                    "issueType": alert.get("issueType"),
                    "severity": alert.get("severity"),
                    "resourceId": alert.get("resourceId"),
                    "extracted_at": datetime.datetime.utcnow().isoformat(),
                    "hitl_validation": "pending"  # Requirement 16: Human-In-The-Loop
                })

            return json.dumps(extracted_alerts, indent=2)

        except Exception as e:
            logger.error(f"Detection Agent Execution Failed: {str(e)}")
            return json.dumps({"status": "error", "message": str(e)})
        finally:
            await credential.close()

    # 2. Sentinel KQL Tool
    @mcp.tool(name="detection.sentinel.kql")
    async def sentinel_kql(workspace_id: str, query: str) -> str:
        """Runs a KQL query against Azure Sentinel."""
        return await sentinel.run_kql(workspace_id, query)

    # 3. XDR Alerts Tool
    @mcp.tool(name="detection.xdr.alerts")
    async def xdr_alerts(severity: str = None, limit: int = 50) -> str:
        """Fetches alerts from Microsoft Defender XDR."""
        return await xdr.list_alerts(severity, limit)