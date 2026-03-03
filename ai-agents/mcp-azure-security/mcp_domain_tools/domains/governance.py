# mcp_domain_tools/domains/governance.py

def register_governance_tools(mcp):
    """
    Registers Governance domain tools (ITSM, RBAC, PIM, Policy) using FastMCP.
    """

    # 1. ITSM Ticket Creation
    @mcp.tool(name="governance.itsm.ticket.create")
    async def create_ticket(
        title: str, 
        description: str, 
        priority: str = "Medium",
        assignment_group: str | None = None
    ) -> str:
        """Creates an ITSM ticket (ServiceNow/Jira/Remedy)."""
        from mcp_domain_tools.azure_clients import itsm
        return await itsm.create_ticket(
            title=title,
            description=description,
            priority=priority,
            assignment_group=assignment_group,
        )

    # 2. ITSM Ticket Update
    @mcp.tool(name="governance.itsm.ticket.update")
    async def update_ticket(
        ticket_id: str, 
        status: str | None = None, 
        comment: str | None = None
    ) -> str:
        """Updates an existing ITSM ticket status or adds a comment."""
        from mcp_domain_tools.azure_clients import itsm
        return await itsm.update_ticket(ticket_id, status, comment)

    # 3. RBAC Evaluation (Entra ID)
    @mcp.tool(name="governance.entra.rbac.evaluate")
    async def evaluate_rbac(
        principal_id: str, 
        role_definition_id: str, 
        scope: str
    ) -> str:
        """Evaluates RBAC permissions for a specific principal and role in Entra ID."""
        from mcp_domain_tools.azure_clients import entra
        return await entra.evaluate_rbac(principal_id, role_definition_id, scope)

    # 4. PIM Activation
    @mcp.tool(name="governance.pim.activate")
    async def pim_activate(
        principal_id: str, 
        role_definition_id: str, 
        scope: str, 
        justification: str
    ) -> str:
        """Activates a Privileged Identity Management (PIM) role assignment."""
        from mcp_domain_tools.azure_clients import entra
        return await entra.pim_activate(
            principal_id=principal_id,
            role_definition_id=role_definition_id,
            scope=scope,
            justification=justification,
        )

    # 5. Change Calendar Check
    @mcp.tool(name="governance.change_calendar.check")
    async def change_calendar_check(
        timestamp: str, 
        environment: str | None = None
    ) -> str:
        """Checks if a specific timestamp falls within an allowed maintenance window."""
        from mcp_domain_tools.azure_clients import itsm
        return await itsm.check_change_window(timestamp, environment)

    # 6. Policy Exception Registration
    @mcp.tool(name="governance.policy.exception.create")
    async def create_policy_exception(
        scope: str, 
        policy_definition_id: str,
        justification: str, 
        expires_on: str | None = None
    ) -> str:
        """Registers a temporary exception for an Azure Policy definition."""
        from mcp_domain_tools.azure_clients import policy
        return await policy.create_exception(
            scope=scope,
            policy_definition_id=policy_definition_id,
            justification=justification,
            expires_on=expires_on,
        )