# mcp_domain_tools/domains/controlplane.py

def register_controlplane_tools(mcp):
    """
    Registers Control Plane domain tools using the FastMCP instance.
    """

    @mcp.tool(name="controlplane.arm.deploy")
    async def arm_deploy(
        subscription_id: str, 
        resource_group: str, 
        template_uri: str, 
        parameters: dict | None = None
    ) -> str:
        """
        Deploys an ARM template to a specified Azure Resource Group.
        
        Args:
            subscription_id: The Target Azure Subscription ID.
            resource_group: The name of the Resource Group for deployment.
            template_uri: The public URI of the ARM template to deploy.
            parameters: Optional dictionary of deployment parameters.
        """
        # Ensure this matches your renamed folder
        from mcp_domain_tools.azure_clients import arm
        
        return await arm.deploy(
            subscription_id, 
            resource_group, 
            template_uri, 
            parameters or {}
        )