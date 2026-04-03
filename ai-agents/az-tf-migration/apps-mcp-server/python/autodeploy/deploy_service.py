"""
Deploy Service — business logic for running deploy.ps1 and reading environment config.
Streams subprocess output line-by-line into the JobManager for SSE delivery.
"""

import os
import re
import subprocess
import threading
from datetime import datetime
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

_THIS_DIR = Path(__file__).resolve().parent                       # python/autodeploy/
_PYTHON_DIR = _THIS_DIR.parent                                    # python/
_MCP_SERVER_DIR = _PYTHON_DIR.parent                              # apps-mcp-server/
_DEPLOY_SCRIPT = _MCP_SERVER_DIR / "deploy.ps1"
_ENV_FILE = _MCP_SERVER_DIR / ".env"


# ---------------------------------------------------------------------------
# URL parsing from deploy output
# ---------------------------------------------------------------------------

_URL_PATTERNS = {
    "ui_url": re.compile(r"UI\s*\(React/Next\.js\)\s*:\s*(https?://\S+)", re.IGNORECASE),
    "api_url": re.compile(r"API\s*\(FastAPI\)\s*:\s*(https?://\S+)", re.IGNORECASE),
    "mcp_url": re.compile(r"MCP\s*Server\s*\(Node\.js\)\s*:\s*(https?://\S+)", re.IGNORECASE),
}


def parse_deploy_urls(lines: list[str]) -> dict[str, str]:
    """Extract deployed service URLs from the final summary banner."""
    urls: dict[str, str] = {}
    for line in lines:
        for key, pattern in _URL_PATTERNS.items():
            m = pattern.search(line)
            if m:
                urls[key] = m.group(1).strip()
    return urls


# ---------------------------------------------------------------------------
# Log sanitiser — mask secrets/IDs in deployment stream output
# ---------------------------------------------------------------------------

# Env var names whose *values* must be masked in log output
_SENSITIVE_ENV_KEYS = {
    "AZURE_CLIENT_ID", "AZURE_CLIENT_SECRET", "AZURE_TENANT_ID",
    "AZURE_OBJECT_ID", "AZURE_SUBSCRIPTION_ID",
    "ARM_CLIENT_ID", "ARM_CLIENT_SECRET", "ARM_TENANT_ID",
    "FOUNDRY_API_KEY", "GITHUB_TOKEN",
}

def _build_sensitive_values() -> set[str]:
    """Collect actual secret/ID values from env + .env so we can redact them."""
    values: set[str] = set()
    # From running environment
    for key in _SENSITIVE_ENV_KEYS:
        val = os.environ.get(key, "").strip()
        if val and len(val) >= 8:
            values.add(val)
    # From .env file
    if _ENV_FILE.exists():
        for line in _ENV_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            parts = stripped.split("=", 1)
            if len(parts) != 2:
                continue
            key = parts[0].strip()
            if key in _SENSITIVE_ENV_KEYS:
                val = parts[1].strip().strip('"').strip("'").strip()
                if val and len(val) >= 8:
                    values.add(val)
    return values


def _mask_value(val: str) -> str:
    """Show first 4 and last 4 chars, mask the rest."""
    if len(val) <= 10:
        return val[:2] + "****" + val[-2:]
    return val[:4] + "****" + val[-4:]


def _sanitize_line(line: str, sensitive: set[str]) -> str:
    """Replace any occurrence of a sensitive value with its masked form."""
    for val in sensitive:
        if val in line:
            line = line.replace(val, _mask_value(val))
    return line


# ---------------------------------------------------------------------------
# Run deploy.ps1 in a background thread
# ---------------------------------------------------------------------------

def run_deploy(job_id: str, jobs) -> None:
    """
    Execute deploy.ps1 as a subprocess, streaming stdout/stderr into *jobs*.
    Designed to run inside ``threading.Thread(target=run_deploy, ...)``.

    The deploy script has an interactive ``Read-Host`` confirmation prompt.
    We pipe ``Y`` via stdin so it proceeds automatically.
    """
    jobs.update(job_id, status="running", progress=5)
    jobs.append_log(job_id, "info", "Starting deployment — executing deploy.ps1")

    if not _DEPLOY_SCRIPT.exists():
        jobs.update(job_id, status="failed", error="deploy.ps1 not found")
        jobs.append_log(job_id, "error", f"deploy.ps1 not found at {_DEPLOY_SCRIPT}")
        return

    # Build set of sensitive values to mask in log output
    sensitive = _build_sensitive_values()

    all_lines: list[str] = []

    try:
        proc = subprocess.Popen(
            ["pwsh", "-NoProfile", "-File", str(_DEPLOY_SCRIPT)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(_MCP_SERVER_DIR),
            env={**os.environ},
        )

        # Answer the confirmation prompt automatically
        if proc.stdin:
            proc.stdin.write("Y\n")
            proc.stdin.flush()
            proc.stdin.close()

        # Stream line-by-line
        for raw_line in iter(proc.stdout.readline, ""):
            line = raw_line.rstrip("\n\r")
            if not line:
                continue

            # Strip ANSI escape codes
            clean = re.sub(r"\033\[[0-9;]*m", "", line)

            # Mask sensitive IDs/secrets before streaming to UI
            clean = _sanitize_line(clean, sensitive)

            all_lines.append(clean)

            # Determine log level
            level = _classify_level(clean)

            # Update progress heuristic based on step markers
            progress = _estimate_progress(clean, jobs.get(job_id).progress if jobs.get(job_id) else 5)
            if progress:
                jobs.update(job_id, progress=progress)

            jobs.append_log(job_id, level, clean)

        proc.wait()

        # Parse final URLs
        urls = parse_deploy_urls(all_lines)

        if proc.returncode == 0:
            jobs.update(job_id, status="completed", progress=100, result=str(urls) if urls else "Deployment completed")
            jobs.append_log(job_id, "success", "Deployment completed successfully")
            if urls:
                for label, url in urls.items():
                    jobs.append_log(job_id, "success", f"  {label}: {url}")
        else:
            jobs.update(job_id, status="failed", error=f"deploy.ps1 exited with code {proc.returncode}")
            jobs.append_log(job_id, "error", f"Deployment failed (exit code {proc.returncode})")

    except Exception as exc:
        jobs.update(job_id, status="failed", error=str(exc))
        jobs.append_log(job_id, "error", f"Deployment error: {exc}")


# ---------------------------------------------------------------------------
# Read environment variables from .env
# ---------------------------------------------------------------------------

# Keys that must never be exposed to the frontend — completely hidden
_HIDDEN_KEYS = {
    # Secrets & credentials
    "FOUNDRY_API_KEY", "AZURE_CLIENT_SECRET", "ARM_CLIENT_SECRET",
    "GITHUB_TOKEN",
    # IDs & auth
    "AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_OBJECT_ID",
    "AZURE_SUBSCRIPTION_ID",
    # Git / repo
    "GITHUB_OWNER", "GITHUB_REPO",
    # Internal paths
    "POWERSHELL_SCRIPT_PATH", "EXPORT_SCRIPT_PATH", "REFACTOR_SCRIPT_PATH",
    "EXCLUDE_JSON_PATH", "AZ_TO_TERRAFORM_MAPPINGS_PATH", "TERRAFORM_MAPPING_PATH",
    # Internal config
    "STDIO_MODE", "EXECUTION_MODE",
    "containerName", "OUTPUT_DESTINATION",
    "ASSESSMENT_FOLDER", "AZTFEXPORT_FOLDER", "CODE_REFACTORED_FOLDER",
    # Resource identifiers
    "AZURE_RESOURCE_GROUP", "storageAccountRG",
}


def read_env_variables() -> dict:
    """Parse .env file and return only safe, non-secret key-value pairs."""
    result: dict[str, str] = {}
    if not _ENV_FILE.exists():
        return result

    for line in _ENV_FILE.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split("=", 1)
        if len(parts) != 2:
            continue
        key = parts[0].strip()
        value = parts[1].strip().strip('"').strip("'").strip()
        # Strip inline comments
        if "#" in value:
            value = re.sub(r"\s*#.*$", "", value).strip()

        if key in _HIDDEN_KEYS:
            continue  # skip entirely — do not expose
        result[key] = value

    return result


def get_service_urls() -> dict[str, str]:
    """
    Return the currently configured service URLs.
    Read from environment variables (set by the container or .env).
    """
    urls: dict[str, str] = {}

    # MCP Server
    mcp = os.environ.get("MCP_SERVER_URL") or os.environ.get("NEXT_PUBLIC_MCP_SERVER_URL", "")
    if mcp:
        urls["mcp_server_url"] = mcp

    # API Server (self — running on this host)
    api_port = os.environ.get("PORT", "8000")
    urls["api_server_url"] = os.environ.get("API_SERVER_URL", f"http://localhost:{api_port}")

    # UI
    ui = os.environ.get("UI_SERVER_URL") or os.environ.get("NEXT_PUBLIC_UI_URL", "")
    if ui:
        urls["ui_url"] = ui

    # Storage
    urls["storage_account"] = os.environ.get("storageAccount") or os.environ.get("AZURE_STORAGE_ACCOUNT", "")
    urls["storage_rg"] = os.environ.get("storageAccountRG", "")
    urls["container_name"] = os.environ.get("containerName") or os.environ.get("AZURE_STORAGE_CONTAINER", "")

    return urls


# Mapping: frontend key -> (.env key, os.environ key)
_URL_KEY_MAP: dict[str, tuple[str, str]] = {
    "mcp_server_url":  ("MCP_SERVER_URL", "MCP_SERVER_URL"),
    "api_server_url":  ("API_SERVER_URL", "API_SERVER_URL"),
    "ui_url":          ("UI_SERVER_URL", "UI_SERVER_URL"),
    "storage_account": ("storageAccount", "storageAccount"),
    "storage_rg":      ("storageAccountRG", "storageAccountRG"),
    "container_name":  ("containerName", "containerName"),
}


def update_service_urls(updates: dict[str, str]) -> dict[str, str]:
    """
    Persist URL / storage changes to the .env file and update os.environ.
    Returns the resolved service_urls dict after the update.
    """
    # 1. Build a map of .env key -> new value for valid keys only
    env_updates: dict[str, str] = {}
    for fe_key, value in updates.items():
        mapping = _URL_KEY_MAP.get(fe_key)
        if mapping is None:
            continue
        env_key, environ_key = mapping
        value = value.strip()
        env_updates[env_key] = value
        # Update running process env immediately
        os.environ[environ_key] = value

    if not env_updates:
        return get_service_urls()

    # 2. Read existing .env, update matching lines, append new ones
    lines: list[str] = []
    found_keys: set[str] = set()
    if _ENV_FILE.exists():
        for line in _ENV_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("#"):
                parts = stripped.split("=", 1)
                if len(parts) == 2:
                    key = parts[0].strip()
                    if key in env_updates:
                        lines.append(f"{key}={env_updates[key]}")
                        found_keys.add(key)
                        continue
            lines.append(line)

    # Append any new keys not already in the file
    for key, val in env_updates.items():
        if key not in found_keys:
            lines.append(f"{key}={val}")

    _ENV_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return get_service_urls()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _classify_level(line: str) -> str:
    upper = line.upper()
    if "[ERROR]" in upper or "[FAIL]" in upper or "✗" in line:
        return "error"
    if "[SUCCESS]" in upper or "✓" in line:
        return "success"
    if "[WARNING]" in upper or "⚠" in line:
        return "warn"
    if "[STEP]" in upper or "===>" in line:
        return "info"
    return "info"


def _estimate_progress(line: str, current: int) -> Optional[int]:
    """Map deploy.ps1 step markers to a rough progress percentage."""
    upper = line.upper()
    if "STEP 1" in upper or "SETTING AZURE SUBSCRIPTION" in upper:
        return max(current, 5)
    if "STEP 2" in upper or "CHECKING AND CREATING" in upper:
        return max(current, 10)
    if "STEP 3" in upper or "CLEANING UP OLD" in upper:
        return max(current, 15)
    if "STEP 4" in upper or "CLEANING LOCAL DOCKER" in upper:
        return max(current, 20)
    if "STEP 5" in upper or "BUILDING FRESH DOCKER" in upper:
        return max(current, 25)
    if "STEP 6" in upper or "PUSHING IMAGE" in upper:
        return max(current, 35)
    if "STEP 7" in upper or "DEPLOYING CONTAINER APP" in upper:
        return max(current, 45)
    if "STEP 8" in upper or "WAITING FOR CONTAINER" in upper:
        return max(current, 55)
    if "STEP 9" in upper or "VERIFYING DEPLOYMENT" in upper:
        return max(current, 65)
    if "STEP 10" in upper or "BUILDING & DEPLOYING FASTAPI" in upper:
        return max(current, 70)
    if "STEP 11" in upper or "BUILDING & DEPLOYING NEXT" in upper:
        return max(current, 85)
    if "DEPLOYMENT COMPLETE" in upper or "ALL 3 CONTAINER APPS" in upper:
        return 100
    return None
