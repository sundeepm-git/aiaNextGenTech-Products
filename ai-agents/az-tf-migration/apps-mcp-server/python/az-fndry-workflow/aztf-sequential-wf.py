import os
import re
import sys
import json
import time
import logging
import ssl
import urllib.request
import urllib.error
import subprocess
import yaml  # For reading agent prompts from YAML
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.storage.blob import BlobServiceClient

# Inject Windows certificate store so corporate MITM/proxy certs are trusted
try:
    import truststore
    truststore.inject_into_ssl()
except ImportError:
    pass

# Ensure stdout/stderr use UTF-8 on Windows (required for emoji output)
if sys.stdout.encoding and sys.stdout.encoding.lower() != 'utf-8':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

# --- Enterprise UI Styling ---
# This class is used to print colored and formatted log messages to the console.
# It helps users visually distinguish between different steps and statuses.
# Example: UI.log("STEP", UI.GREEN, "Assessment completed successfully")
class UI:
    GREEN, CYAN, YELLOW, RED, BOLD, END = '\033[92m', '\033[96m', '\033[93m', '\033[91m', '\033[1m', '\033[0m'
    @staticmethod
    def log(label, color, msg):
        # Print a short, readable message with a colored label
        preview = str(msg).strip().replace('\n', ' ')
        if len(preview) > 110:
            preview = preview[:107] + "..."
        print(f"{color}{UI.BOLD}[{label:15}]:{UI.END} {preview}")


# 1. Initialization
# This section sets up everything needed for the workflow to run.
# - Loads environment variables (like passwords and URLs) from .env files
# - Loads agent prompts from a YAML file so business users can edit them easily
# - Sets up logging so errors are easy to spot
logging.basicConfig(level=logging.ERROR)
load_dotenv()  # Loads .env in current folder
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '..', '.env'))  # Loads .env from parent folder for shared config
PROJECT_ENDPOINT = os.getenv("AZURE_AI_PROJECT_ENDPOINT")  # The URL for your Azure Foundry project
MCP_SERVER_URL = os.getenv("MCP_SERVER_URL", "").rstrip("/")  # The URL for the MCP server (used for job status)

# How many times to retry if an agent doesn't call its tool (e.g., if it "hallucinates")
MAX_TOOL_RETRIES = 3

# How often to check job status, how long to wait, and how often to print a heartbeat message
JOB_POLL_INTERVAL = int(os.getenv("JOB_POLL_INTERVAL", "15"))  # seconds between checks
JOB_POLL_TIMEOUT  = int(os.getenv("JOB_POLL_TIMEOUT", "1800"))  # max seconds to wait for a job
JOB_HEARTBEAT_LOG = int(os.getenv("JOB_HEARTBEAT_LOG", "60"))  # seconds between "still waiting" messages

# Load agent prompts from a YAML file so business users can edit them without touching code
PROMPT_FILE = os.path.join(os.path.dirname(__file__), "agent-prompts.yaml")
with open(PROMPT_FILE, "r", encoding="utf-8") as f:
    AGENT_PROMPTS = yaml.safe_load(f)


def verify_storage_files(sub_id: str, rg_name: str) -> bool:
    """
    Verify that export files actually exist in Azure Blob Storage.
    Uses Python SDK with DefaultAzureCredential (supports managed identity).
    Returns True if .tf files are found, False otherwise.
    """
    storage_account = os.getenv("storageAccount") or os.getenv("AZURE_STORAGE_ACCOUNT", "")
    container = os.getenv("AZTFEXPORT_FOLDER", "aztfexport")  # Must match export script's container
    if not storage_account:
        UI.log("STORAGE CHECK", UI.RED, "storageAccount not configured — cannot verify files in storage")
        return False

    prefix = f"{sub_id}/{rg_name}"
    UI.log("STORAGE CHECK", UI.CYAN, f"Verifying files in storage: {storage_account}/{container}/{prefix}")

    try:
        # Use DefaultAzureCredential to support both local dev (az login) and container (managed identity)
        credential = DefaultAzureCredential()
        account_url = f"https://{storage_account}.blob.core.windows.net"
        blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        
        container_client = blob_service_client.get_container_client(container)
        
        # List blobs with prefix (filter by sub_id/rg_name path)
        blob_list = list(container_client.list_blobs(name_starts_with=prefix))
        blob_names = [blob.name for blob in blob_list]
        tf_files = [b for b in blob_names if b.endswith(".tf")]
        
        if tf_files:
            UI.log("STORAGE CHECK", UI.GREEN, f"Found {len(tf_files)} .tf file(s) in storage ✅ (total blobs: {len(blob_names)})")
            return True
        else:
            UI.log("STORAGE CHECK", UI.YELLOW, f"No .tf files found yet under {prefix} (total blobs: {len(blob_names)})")
            UI.log("STORAGE CHECK", UI.YELLOW, "Note: Export job shows 'completed' — files may still be uploading. Proceeding anyway...")
            return True  # Allow pipeline to continue since job status was 'completed'
    except Exception as e:
        UI.log("STORAGE CHECK", UI.YELLOW, f"Storage verification error: {e}")
        UI.log("STORAGE CHECK", UI.YELLOW, "Since export job reported 'completed', proceeding with pipeline...")
        return True  # Don't block pipeline on verification errors


def extract_job_id(text):
    """
    This function looks for a Job ID (a unique code like '123e4567-e89b-12d3-a456-426614174000') in the agent's response.
    Example: If the agent says 'Export job started. Job ID: 123e4567-e89b-12d3-a456-426614174000',
    this function will return just the Job ID part.
    """
    if not text:
        return None
    # Look for a standard UUID pattern (8-4-4-4-12 hex digits)
    match = re.search(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', text)
    return match.group(0) if match else None


def poll_job_status(job_id, step_label="JOB", timeout=JOB_POLL_TIMEOUT, interval=JOB_POLL_INTERVAL):
    """
    This function keeps checking the status of a long-running job (like export or refactor) until it finishes or times out.
    It talks to the MCP server and waits for the job to say 'completed' or 'failed'.
    Example: If you start an export, this will keep checking every 15 seconds until the export is done.
    """
    if not MCP_SERVER_URL:
        UI.log(step_label, UI.YELLOW, "MCP_SERVER_URL not set — skipping job polling (proceeding immediately).")
        return {"status": "unknown", "reason": "no_mcp_url"}

    url = f"{MCP_SERVER_URL}/jobs/{job_id}"
    UI.log(step_label, UI.CYAN, f"Polling job status: {url}  (timeout={timeout}s)")

    start_time = time.time()
    last_status = None
    last_heartbeat = 0  # When did we last print a heartbeat?

    while True:
        elapsed = int(time.time() - start_time)
        if elapsed > timeout:
            UI.log(step_label, UI.RED, f"TIMEOUT after {elapsed}s waiting for job {job_id}")
            return {"status": "timeout", "jobId": job_id, "elapsed": elapsed}

        try:
            req = urllib.request.Request(url, headers={"Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode())
                status = data.get("status", "unknown")

                # Print status if it changed, or print a heartbeat every so often
                if status != last_status:
                    UI.log(step_label, UI.CYAN, f"Job {job_id}: status={status} ({elapsed}s elapsed)")
                    last_status = status
                    last_heartbeat = elapsed
                elif elapsed - last_heartbeat >= JOB_HEARTBEAT_LOG:
                    # Print a message so the user knows we're still waiting
                    UI.log(step_label, UI.YELLOW, f"Still waiting... status={status} ({elapsed}s / {timeout}s)")
                    last_heartbeat = elapsed

                # If job is done, print result and return
                if status in ("completed", "failed"):
                    if status == "completed":
                        UI.log(step_label, UI.GREEN, f"Job {job_id} COMPLETED in {elapsed}s ✅")
                    else:
                        error_msg = data.get("error", "unknown error")
                        UI.log(step_label, UI.RED, f"Job {job_id} FAILED: {error_msg}")
                    return data

        except urllib.error.HTTPError as e:
            if e.code == 404:
                UI.log(step_label, UI.YELLOW, f"Job {job_id} not found yet (404) — retrying in {interval}s...")
            else:
                UI.log(step_label, UI.RED, f"HTTP {e.code} polling job {job_id}: {e.reason}")
        except urllib.error.URLError as e:
            UI.log(step_label, UI.RED, f"Connection error polling {url}: {e.reason}")
        except Exception as e:
            UI.log(step_label, UI.RED, f"Unexpected error polling job: {e}")

        time.sleep(interval)

def get_clean_response(openai_client, conv_id):
    """
    This function gets the latest message from the agent's chat history.
    It's a backup in case the main response is empty or too short.
    Example: If the agent's response is missing, this will try to fetch the last message from the conversation.
    """
    try:
        # SDK 2.0.0b4: conversations.items.list() replaces conversations.list_messages()
        items = openai_client.conversations.items.list(conversation_id=conv_id)
        if items and hasattr(items, 'data') and len(items.data) > 0:
            # Get the most recent item and extract text content
            latest = items.data[0]
            if hasattr(latest, 'content') and len(latest.content) > 0:
                return str(latest.content[0].text.value)
            elif hasattr(latest, 'text'):
                return str(latest.text)
    except Exception:
        pass
    return None

def looks_like_hallucination(text, tool_name):
    """
    This function checks if the agent's response looks like it "made something up" instead of calling the real tool.
    Example: If the agent says "Here's an example Terraform file..." instead of actually running the export tool, this will detect it.
    Returns True if the response is likely fake, False if it looks real.
    """
    if not text:
        return True
    text_lower = text.lower().strip()
    # List of phrases that mean the agent is probably hallucinating
    hallucination_markers = [
        "i don't have access",
        "i cannot call",
        "i'm unable to",
        "as an ai",
        "i would need",
        "unfortunately, i",
        "i can help you",
        "here's an example",
        "here is an example",
        "here's a sample",
        "let me explain",
        "```terraform",           # agent generating terraform code instead of calling tool
        "```hcl",                 # agent generating HCL instead of calling tool
        "resource \"azurerm_",    # raw terraform resource block = fabricated
        "critical error",          # agent's own error protocol = tool was NOT reached
        "mcp server is unreachable",
        "tool failed to initialize",
    ]
    is_hallucinated = any(marker in text_lower for marker in hallucination_markers)
    if is_hallucinated:
        UI.log("DETECT", UI.YELLOW, f"Hallucination detected: agent did not call '{tool_name}' tool")
    return is_hallucinated

def run_agent_step(openai_client, conv_id, agent_name, prompt, tool_name=None, force_tool=False):
    """
    Sends a prompt to a specific AI agent and waits for its response.
    Think of it like asking an employee (agent) to do a task and waiting for their answer.

    How it works:
      1. Sends the prompt to the named agent via Azure Foundry.
      2. Reads back the agent's reply.
      3. If the agent "made something up" instead of running the real tool, it will retry up to 3 times.
      4. Returns the agent's response text, or None if all attempts failed.

    Args:
        openai_client:  The Foundry client used to talk to agents.
        conv_id:        The chat session ID (each agent gets its own fresh session).
        agent_name:     The name of the agent in Foundry (e.g., 'aztf-assessment-v1').
        prompt:         The instruction to send to the agent (loaded from agent-prompts.yaml).
        tool_name:      The name of the MCP tool the agent is expected to call (e.g., 'azure_assessment').
        force_tool:     If True, retry with a stricter prompt if the agent didn't actually call the tool.
    """
    UI.log("ACTIVE AGENT", UI.CYAN, agent_name)

    for attempt in range(1, MAX_TOOL_RETRIES + 1):
        try:
            UI.log("STEP", UI.YELLOW, f"attempt={attempt}, target_tool='{tool_name}', force_tool={force_tool}")

            # Send the prompt to the named agent in Azure Foundry and wait for its response
            response = openai_client.responses.create(
                conversation=conv_id,
                extra_body={
                    "agent_reference": {"name": agent_name, "type": "agent_reference"}
                },
                input=prompt,
                stream=False 
            )

            # --- Phase 1: Capture the agent's reply text ---
            content = getattr(response, 'output_text', None)

            # --- Phase 2: Logging — summarize what the agent returned (tool calls, messages, etc.) ---
            # This helps you see at a glance: Did the agent call a tool? How many messages came back?
            tool_call_count = 0
            if hasattr(response, 'output'):
                type_counts = {}        # Count each output type, e.g. {"function_call": 1, "message": 3}
                seen_msgs = set()       # Track unique message texts (avoid printing duplicates)
                tool_calls = []         # List of tool calls the agent made (e.g., "azure_assessment(...)")
                for item in response.output:
                    item_type = getattr(item, 'type', 'unknown')
                    type_counts[item_type] = type_counts.get(item_type, 0) + 1
                    if item_type in ('function_call', 'tool_call', 'mcp_call'):
                        # The agent called an MCP tool — log which one and its arguments
                        tool_calls.append(f"{getattr(item, 'name', '?')}({getattr(item, 'arguments', '?')})")
                    elif item_type == 'message':
                        # The agent sent a text message — collect unique texts only
                        for mc in getattr(item, 'content', []):
                            msg_text = getattr(mc, 'text', str(mc)[:100])
                            if msg_text not in seen_msgs:
                                seen_msgs.add(msg_text)
                tool_call_count = len(tool_calls)
                # Print a one-line summary like: "mcp_list_tools:1, mcp_call:1, message:3"
                summary = ", ".join(f"{t}:{c}" for t, c in type_counts.items())
                UI.log("RESPONSE ITEMS", UI.YELLOW, summary)
                for tc in tool_calls:
                    UI.log("TOOL CALL", UI.GREEN, tc)
                for msg in seen_msgs:
                    UI.log("MSG (unique)", UI.CYAN, msg)

            # --- Phase 2b: Extract real usage metrics from Foundry response (multiple shapes) ---
            _tokens_prompt = 0
            _tokens_completion = 0
            _model_name = "unknown"

            def _to_int(value):
                try:
                    return int(value or 0)
                except Exception:
                    return 0

            def _normalize_usage(usage_obj):
                if not usage_obj:
                    return (0, 0)

                # Handle SDK objects and plain dict payloads across API variants.
                if isinstance(usage_obj, dict):
                    prompt_val = (
                        usage_obj.get('prompt_tokens')
                        or usage_obj.get('input_tokens')
                        or usage_obj.get('promptTokenCount')
                        or 0
                    )
                    completion_val = (
                        usage_obj.get('completion_tokens')
                        or usage_obj.get('output_tokens')
                        or usage_obj.get('completionTokenCount')
                        or 0
                    )
                    return (_to_int(prompt_val), _to_int(completion_val))

                prompt_val = (
                    getattr(usage_obj, 'prompt_tokens', None)
                    or getattr(usage_obj, 'input_tokens', None)
                    or getattr(usage_obj, 'promptTokenCount', None)
                    or 0
                )
                completion_val = (
                    getattr(usage_obj, 'completion_tokens', None)
                    or getattr(usage_obj, 'output_tokens', None)
                    or getattr(usage_obj, 'completionTokenCount', None)
                    or 0
                )
                return (_to_int(prompt_val), _to_int(completion_val))

            usage = getattr(response, 'usage', None)
            _tokens_prompt, _tokens_completion = _normalize_usage(usage)

            # Fallback for SDK shapes that expose nested dict payloads.
            if (_tokens_prompt == 0 and _tokens_completion == 0) and hasattr(response, 'model_dump'):
                try:
                    raw = response.model_dump()
                    usage_candidates = [
                        raw.get('usage'),
                        raw.get('response', {}).get('usage'),
                        raw.get('metadata', {}).get('usage'),
                    ]
                    # Some SDK responses place usage on output items (e.g., tool or message items).
                    for item in raw.get('output', []) or []:
                        if isinstance(item, dict):
                            usage_candidates.append(item.get('usage'))

                    for candidate in usage_candidates:
                        p, c = _normalize_usage(candidate)
                        if p > 0 or c > 0:
                            _tokens_prompt, _tokens_completion = p, c
                            break
                except Exception:
                    pass

            if hasattr(response, 'model') and response.model:
                _model_name = response.model
            elif hasattr(response, 'model_dump'):
                try:
                    raw = response.model_dump()
                    _model_name = raw.get('model') or raw.get('response', {}).get('model') or "unknown"
                except Exception:
                    pass

            # If structured tool calls were not detected, use response metadata hints.
            if tool_call_count == 0 and hasattr(response, 'output'):
                try:
                    tool_call_count = sum(
                        1 for item in response.output
                        if getattr(item, 'name', None) or 'tool' in str(getattr(item, 'type', '')).lower() or 'mcp' in str(getattr(item, 'type', '')).lower()
                    )
                except Exception:
                    pass
            # Emit structured metrics line so WorkflowLogCapture can capture real values
            print(f"[AGENT_METRICS]: agent={agent_name}, tokens_prompt={_tokens_prompt}, tokens_completion={_tokens_completion}, model={_model_name}, tool_calls={tool_call_count}")

            # --- Phase 3: Fallback — if agent reply is empty, fetch last message from chat history ---
            if not content or len(str(content).strip()) < 20:
                content = get_clean_response(openai_client, conv_id)

            # If still empty after fallback, skip to next retry attempt
            if not content:
                UI.log("STATUS", UI.RED, f"NO_DATA_RETURNED (attempt {attempt})")
                continue

            # Show the final captured text for debugging
            UI.log("RESPONSE", UI.CYAN, content)

            # Emit structured trace payload for observability (trim to keep logs bounded).
            prompt_for_trace = str(prompt or "").strip()
            content_for_trace = str(content or "").strip()
            if len(prompt_for_trace) > 4000:
                prompt_for_trace = prompt_for_trace[:4000] + "..."
            if len(content_for_trace) > 4000:
                content_for_trace = content_for_trace[:4000] + "..."
            print(
                "[AGENT_TRACE]: "
                + json.dumps(
                    {
                        "agent": agent_name,
                        "input_prompt": prompt_for_trace,
                        "output_prompt": content_for_trace,
                    },
                    ensure_ascii=False,
                )
            )

            # --- Phase 4: Validate — did the agent actually call its tool or just make something up? ---
            if force_tool and tool_name and looks_like_hallucination(content, tool_name):
                if attempt < MAX_TOOL_RETRIES:
                    # Agent hallucinated — retry with a stricter instruction
                    UI.log("RETRY", UI.YELLOW, 
                           f"Hallucination detected (attempt {attempt}/{MAX_TOOL_RETRIES}). Retrying with stricter prompt...")
                    prompt = (
                        f"IMPORTANT: Your previous response did NOT call any tool. "
                        f"You MUST call the '{tool_name}' tool with parameters: "
                        f"subscriptionId and resourceGroup. "
                        f"Do NOT explain, summarize, or generate code. "
                        f"Call the tool and return only its status."
                    )
                    continue
                else:
                    # Final attempt — accept whatever the agent returned even if it looks suspicious
                    UI.log("WARN", UI.YELLOW, 
                           f"Agent may not have called tool, but accepting response on final attempt.")

            UI.log("STATUS", UI.GREEN, f"SUCCESS: Response captured ✅ (attempt {attempt})")
            return str(content)

        except Exception as e:
            # Azure Content Safety may block certain prompts/responses
            if "filtered" in str(e).lower():
                UI.log("STATUS", UI.RED, "FILTERED: Azure Content Safety blocked the request.")
                return "FILTERED"
            UI.log("STATUS", UI.RED, f"EXECUTION ERROR (attempt {attempt}): {str(e)}")
            if attempt == MAX_TOOL_RETRIES:
                return None

    # All retry attempts exhausted — agent never called its tool successfully
    UI.log("STATUS", UI.RED, f"EXHAUSTED: Agent '{agent_name}' failed to call tool after {MAX_TOOL_RETRIES} attempts.")
    return None


def run_aztf_enterprise_pipeline(user_prompt):
    """
    This function runs the full Azure-to-Terraform migration pipeline step by step.
    It accepts a natural-language prompt from the user. The Orchestrator agent extracts
    subscriptionId and resourceGroup from the prompt, then passes them to downstream agents.
    """
    if not PROJECT_ENDPOINT:
        msg = "AZURE_AI_PROJECT_ENDPOINT is not set. Configure it as an environment variable before running the pipeline."
        print(f"{UI.RED}Error: {msg}{UI.END}")
        raise RuntimeError(msg)

    # Connect to Azure AI Foundry using the project endpoint and your Azure credentials
    project_client = AIProjectClient(endpoint=PROJECT_ENDPOINT, credential=DefaultAzureCredential())

    with project_client:
        # Get the OpenAI-compatible client from Foundry — this is used to talk to agents
        openai_client = project_client.get_openai_client()
        conversations_to_cleanup = []  # Keep track of all chat sessions so we can clean them up at the end
        
        UI.log("PIPELINE", UI.CYAN, "Starting Sequential Run (each agent gets a fresh chat)")
        print("-" * 115)

        def create_agent_conversation():
            """
            Create a new, independent chat session for each agent.
            Why? So agents don't see each other's context — this prevents mix-ups between steps.
            Example: The export agent should NOT see whatever the assessment agent said.
            """
            conv = openai_client.conversations.create()
            conversations_to_cleanup.append(conv.id)
            return conv.id

        # ─────────────────────────────────────────────────────────────────────────
        # STEP 1: ORCHESTRATOR
        # Purpose: Takes the user's natural-language prompt, extracts the
        #          subscription ID and resource group, and returns a clean JSON object.
        # Example output: {"subscriptionId": "d0f1...", "resourceGroup": "rg-mcp-servers"}
        # ─────────────────────────────────────────────────────────────────────────
        orch_conv = create_agent_conversation()
        orch_prompt = AGENT_PROMPTS["aztf-orchestrator-v1"].format(user_prompt=user_prompt)
        orch_out = run_agent_step(openai_client, orch_conv, "aztf-orchestrator-v1", orch_prompt)
        UI.log("ORCH OUTPUT", UI.CYAN, orch_out)

        # Parse JSON from orchestrator response to extract sub_id and rg_name
        sub_id = None
        rg_name = None
        if orch_out:
            json_match = re.search(r'\{[^}]+\}', orch_out)
            if json_match:
                try:
                    parsed = json.loads(json_match.group())
                    sub_id = parsed.get("subscriptionId")
                    rg_name = parsed.get("resourceGroup")
                except json.JSONDecodeError:
                    pass

        if not sub_id or not rg_name:
            UI.log("PIPELINE", UI.RED, "Orchestrator could not extract subscriptionId and resourceGroup from the prompt.")
            UI.log("HINT", UI.YELLOW, "Example prompt: Migrate resource group 'rg-mcp-servers' from subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2")
            return {
                "success": False,
                "message": "Orchestrator could not extract subscriptionId/resourceGroup",
                "subscriptionId": None,
                "resourceGroup": None,
            }

        UI.log("EXTRACTED", UI.GREEN, f"subscriptionId={sub_id}, resourceGroup={rg_name}")

        # ─────────────────────────────────────────────────────────────────────────
        # STEP 2: ASSESSMENT
        # Purpose: Scans the Azure resource group and generates a detailed assessment report.
        #          The report is uploaded directly to Azure Blob Storage (not returned in text).
        # Tool called: 'azure_assessment' (synchronous — waits for completion)
        # ─────────────────────────────────────────────────────────────────────────
        assess_conv = create_agent_conversation()
        assess_prompt = AGENT_PROMPTS["aztf-assessment-v1"].format(sub_id=sub_id, rg_name=rg_name)
        assess_out = run_agent_step(openai_client, assess_conv, "aztf-assessment-v1", 
                                    assess_prompt, tool_name="azure_assessment", force_tool=True)
        UI.log("ASSESS OUTPUT", UI.CYAN, assess_out)

        # Check: Did the assessment succeed? If not, we stop here — no point exporting without a report.
        assess_ok = assess_out and assess_out not in ("FILTERED", "NO_DATA_RETURNED") and "critical error" not in str(assess_out).lower()

        # ─────────────────────────────────────────────────────────────────────────
        # STEP 3: EXPORT
        # Purpose: Converts Azure resources into Terraform files (.tf) and uploads them to storage.
        # Tool called: 'export_azure_terraform' (ASYNC — starts a background job)
        # After starting: We poll the MCP server every 15 seconds to wait for the export to finish.
        #                 This ensures Terraform files are fully uploaded before the refactor step begins.
        # ─────────────────────────────────────────────────────────────────────────
        export_out = None
        export_job_id = None
        if assess_ok:
            export_conv = create_agent_conversation()
            export_prompt = AGENT_PROMPTS["aztf-export-v1"].format(sub_id=sub_id, rg_name=rg_name)
            export_out = run_agent_step(openai_client, export_conv, "aztf-export-v1", 
                                        export_prompt, tool_name="export_azure_terraform", force_tool=True)
            UI.log("EXPORT QUEUED", UI.CYAN, f"Agent response (job async): {export_out}")

            # The agent returned a Job ID — now poll the MCP server until the export finishes
            if export_out and export_out not in ("FILTERED", "NO_DATA_RETURNED"):
                export_job_id = extract_job_id(export_out)  # Pull the UUID Job ID from the agent's text
                if export_job_id:
                    UI.log("EXPORT POLL", UI.CYAN, f"Export tool returned Job ID: {export_job_id} — waiting for completion...")
                    job_result = poll_job_status(export_job_id, step_label="EXPORT POLL")
                    if job_result and job_result.get("status") == "completed":
                        # MCP server says job completed — now verify files actually exist in storage
                        storage_ok = verify_storage_files(sub_id, rg_name)
                        if storage_ok:
                            UI.log("EXPORT POLL", UI.GREEN, "Export job finished — files verified in storage ✅")
                        else:
                            UI.log("EXPORT POLL", UI.RED, "Export job reported completed but NO .tf files found in storage ❌")
                            UI.log("EXPORT POLL", UI.RED, "Pipeline will stop — refactor requires exported files in storage")
                            export_out = None  # Mark as failed so refactor is skipped
                    elif job_result and job_result.get("status") == "failed":
                        error_detail = job_result.get('error', 'unknown')
                        UI.log("EXPORT POLL", UI.RED, f"Export job FAILED")
                        # Print full error without truncation
                        print(f"{UI.RED}{UI.BOLD}[FULL ERROR     ]:{UI.END}")
                        print(f"{error_detail}")
                        print(f"{UI.RED}{'─' * 100}{UI.END}")
                        export_out = None  # Mark as failed so the refactor step is skipped
                    else:
                        # Timed out or unknown status — treat as failure
                        UI.log("EXPORT POLL", UI.RED, f"Export job did not complete (status: {job_result.get('status') if job_result else 'timeout'})")
                        export_out = None
                else:
                    UI.log("EXPORT POLL", UI.YELLOW, "Could not extract Job ID from export response — proceeding without polling.")
        else:
            UI.log("SKIP", UI.YELLOW, "Skipping Export — Assessment failed or returned CRITICAL ERROR.")

        # Check: Did the export succeed AND are files in storage?
        export_ok = export_out and export_out not in ("FILTERED", "NO_DATA_RETURNED") and "critical error" not in str(export_out).lower()

        # ─────────────────────────────────────────────────────────────────────────
        # STEP 4: REFACTOR
        # Purpose: Cleans up the exported Terraform code — applies naming conventions, tagging rules,
        #          and best practices, then uploads the improved code to Azure Storage.
        # Tool called: 'refactor_terraform_code' (ASYNC — starts a background job)
        # After starting: We poll the MCP server until the refactor job finishes.
        # ─────────────────────────────────────────────────────────────────────────
        final_out = None
        if export_ok:
            refactor_conv = create_agent_conversation()
            refactor_prompt = AGENT_PROMPTS["aztf-coderefactor-v1"].format(sub_id=sub_id, rg_name=rg_name)
            final_out = run_agent_step(openai_client, refactor_conv, "aztf-coderefactor-v1", 
                                       refactor_prompt, tool_name="refactor_terraform_code", force_tool=True)
            UI.log("REFACTOR QUEUED", UI.CYAN, f"Agent response (job async): {final_out}")

            # The agent returned a Job ID — now poll the MCP server until the refactor finishes
            if final_out and final_out not in ("FILTERED", "NO_DATA_RETURNED"):
                refactor_job_id = extract_job_id(final_out)
                if refactor_job_id:
                    UI.log("REFACTOR POLL", UI.CYAN, f"Refactor tool returned Job ID: {refactor_job_id} — waiting for completion...")
                    job_result = poll_job_status(refactor_job_id, step_label="REFACTOR POLL")
                    if job_result and job_result.get("status") == "completed":
                        # Refactor succeeded — clean code is now in Azure Storage
                        UI.log("REFACTOR POLL", UI.GREEN, "Refactor job finished — code uploaded to storage ✅")
                    elif job_result and job_result.get("status") == "failed":
                        error_detail = job_result.get('error', 'unknown')
                        UI.log("REFACTOR POLL", UI.RED, f"Refactor job FAILED")
                        # Print full error without truncation
                        print(f"{UI.RED}{UI.BOLD}[FULL ERROR     ]:{UI.END}")
                        print(f"{error_detail}")
                        print(f"{UI.RED}{'─' * 100}{UI.END}")
                        final_out = "REFACTOR_FAILED"
                    else:
                        UI.log("REFACTOR POLL", UI.RED, f"Refactor job did not complete (status: {job_result.get('status') if job_result else 'timeout'})")
                else:
                    UI.log("REFACTOR POLL", UI.YELLOW, "Could not extract Job ID from refactor response — proceeding without polling.")
        else:
            UI.log("SKIP", UI.YELLOW, "Skipping Refactor — Export failed or no files found in storage. Cannot refactor without exported .tf files.")

        # ─────────────────────────────────────────────────────────────────────────
        # FINALIZATION: Summarize the overall result and clean up all chat sessions
        # ─────────────────────────────────────────────────────────────────────────
        print("\n" + "="*115)
        
        # Determine the final pipeline outcome and print a clear summary
        final_ok = final_out and "critical error" not in str(final_out).lower()
        pipeline_success = bool(final_ok and any(word in str(final_out).upper() for word in ["SUCCESS", "UPLOADED", "COMPLETED", "JOB STARTED", "JOB_ID"]))

        if pipeline_success:
            UI.log("PIPELINE", UI.GREEN, "MIGRATION COMPLETE: All tools executed successfully.")
            pipeline_message = "MIGRATION COMPLETE: All tools executed successfully"
        elif final_ok:
            UI.log("PIPELINE", UI.YELLOW, "PIPELINE FINISHED: Got output but could not confirm tool execution.")
            pipeline_message = "PIPELINE FINISHED: Output received but tool execution could not be confirmed"
        else:
            UI.log("PIPELINE", UI.RED, "PIPELINE STALLED: One or more agents failed to call their MCP tool.")
            pipeline_message = "PIPELINE STALLED: One or more stages failed"
            # Provide diagnostic hints for troubleshooting
            if not assess_ok:
                UI.log("DIAGNOSE", UI.RED, "Assessment agent could not reach 'azure_assessment' MCP tool. Check MCP server connection in Foundry.")
            if not export_ok:
                UI.log("DIAGNOSE", UI.RED, "Export agent could not reach 'export_azure_terraform' MCP tool. Check MCP server connection in Foundry.")

        # Release all chat sessions — these are temporary and should be cleaned up after the pipeline
        for cid in conversations_to_cleanup:
            try:
                openai_client.conversations.delete(conversation_id=cid)
            except Exception:
                pass
        UI.log("CLEANUP", UI.GREEN, f"Released {len(conversations_to_cleanup)} conversation sessions.")

        return {
            "success": pipeline_success,
            "message": pipeline_message,
            "subscriptionId": sub_id,
            "resourceGroup": rg_name,
        }


# ─────────────────────────────────────────────────────────────────────────
# ENTRY POINT: This runs when you execute `python aztf-sequential-wf.py`
# Usage:
#   python aztf-sequential-wf.py "Migrate resource group 'rg-mcp-servers' from subscription d0f1884d-..."
# Or set AZURE_SUBSCRIPTION_ID and AZURE_RESOURCE_GROUP env vars as fallback.
# ─────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) > 1:
        user_prompt = " ".join(sys.argv[1:])
    else:
        # Fallback: construct prompt from env vars
        SUB = os.getenv("AZURE_SUBSCRIPTION_ID", "")
        RG = os.getenv("AZURE_RESOURCE_GROUP", "")
        if not SUB or not RG:
            print(f"{UI.RED}Error: Pass a prompt as argument or set AZURE_SUBSCRIPTION_ID and AZURE_RESOURCE_GROUP env vars.{UI.END}")
            print(f"{UI.YELLOW}Example: python aztf-sequential-wf.py \"Migrate resource group 'rg-mcp-servers' from subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2\"{UI.END}")
            sys.exit(1)
        user_prompt = f"Migrate resource group '{RG}' from subscription {SUB}"
    run_aztf_enterprise_pipeline(user_prompt)