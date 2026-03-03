# azure_clients.py
# Stub implementation for MCP detection agent compatibility

class sentinel:
    @staticmethod
    async def run_kql(workspace_id, query):
        # TODO: Implement Azure Sentinel KQL logic
        return {"status": "stub", "workspace_id": workspace_id, "query": query}

class xdr:
    @staticmethod
    async def list_alerts(severity=None, limit=50):
        # TODO: Implement XDR alert listing logic
        return {"status": "stub", "severity": severity, "limit": limit}
