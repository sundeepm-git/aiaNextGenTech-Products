import logging
from fastmcp import FastMCP

# 1. Initialize FastMCP
mcp = FastMCP("mcp-azure-security")

# 2. Register Domain Tools
try:
    from mcp_domain_tools.domains.posture import register_posture_tools
    from mcp_domain_tools.domains.detection import register_detection_tools
    from mcp_domain_tools.domains.controlplane import register_controlplane_tools
    from mcp_domain_tools.domains.governance import register_governance_tools
    from mcp_domain_tools.domains.audit import register_audit_tools

    register_posture_tools(mcp)
    register_detection_tools(mcp)
    register_controlplane_tools(mcp)
    register_governance_tools(mcp)
    register_audit_tools(mcp)
    print("✅ All Azure Security domains registered.")
except Exception as e:
    print(f"❌ Registration Error: {e}")

# 3. Add a basic health check tool
@mcp.tool()
async def get_server_status() -> str:
    """Returns the current status of the MCP Azure Security server."""
    return "Azure Security MCP Server is Online and Connected."

# 4. THE FINAL RUNNER
if __name__ == "__main__":
    # We run the internal server. FastMCP's run() method 
    # handles the SSE transport and the port mapping automatically.
    print("🚀 Starting FastMCP Server...")
    print("👉 Connect your Inspector to http://localhost:8000/sse")
    
    # Using transport="sse" is the most stable way to expose tools to the Inspector.
    mcp.run(transport="sse")