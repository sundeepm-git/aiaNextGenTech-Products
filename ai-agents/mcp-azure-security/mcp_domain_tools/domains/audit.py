# mcp_domain_tools/domains/audit.py

def register_audit_tools(mcp):
    """
    Registers Audit domain tools using the FastMCP instance.
    """

    @mcp.tool()
    async def audit_log_analytics_query(workspace_id: str, query: str) -> str:
        """
        Executes a KQL query against a Log Analytics workspace for auditing purposes.
        
        Args:
            workspace_id: The Azure Log Analytics Workspace ID.
            query: The KQL query string to execute.
        """
        # Ensure this matches your new folder name (e.g., mcp_domain_tools)
        from mcp_domain_tools.azure_clients import log_analytics
        
        return await log_analytics.run_query(workspace_id, query)