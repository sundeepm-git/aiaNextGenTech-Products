# mcp_domain_tools/domains/posture.py

def register_posture_tools(mcp):
    """
    Registers Posture domain tools (Resource Graph & Defender) using FastMCP.
    """

    # 1. Resource Graph Query Tool
    @mcp.tool(name="posture.resource_graph.query")
    async def resource_graph_query(query: str, subscriptions: list[str] | None = None) -> str:
        """
        Executes an Azure Resource Graph query to analyze security posture across resources.
        
        Args:
            query: The KQL query string to execute.
            subscriptions: Optional list of subscription IDs to scope the query.
        """
        from mcp_domain_tools.azure_clients import resource_graph
        return await resource_graph.run_query(query, subscriptions)

    # 2. Defender Recommendations Tool
    @mcp.tool(name="posture.defender.recommendations")
    async def defender_recommendations(subscription_id: str, severity: str | None = None) -> str:
        """
        Fetches security recommendations from Microsoft Defender for Cloud.
        
        Args:
            subscription_id: The Azure subscription ID to check.
            severity: Optional filter (e.g., 'High', 'Medium', 'Low').
        """
        from mcp_domain_tools.azure_clients import defender_cloud
        return await defender_cloud.list_recommendations(subscription_id, severity)