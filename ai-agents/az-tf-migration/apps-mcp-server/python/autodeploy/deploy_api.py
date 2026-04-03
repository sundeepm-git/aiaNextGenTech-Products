"""
Deploy API Router — FastAPI endpoints for triggering deployments,
streaming progress via SSE, and reading environment configuration.
"""

import uuid
import asyncio
import threading
from datetime import datetime

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel


# ---------------------------------------------------------------------------
# Reuse the JobManager from api_server (imported at wire-up time)
# We import deploy_service functions directly.
# ---------------------------------------------------------------------------

from autodeploy.deploy_service import run_deploy, read_env_variables, get_service_urls, update_service_urls, parse_deploy_urls

# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

deploy_router = APIRouter(tags=["deploy"])

# ---------------------------------------------------------------------------
# We need access to the shared JobManager from api_server.
# The router will be wired in api_server.py which sets this reference.
# ---------------------------------------------------------------------------

_jobs = None          # set by set_job_manager()


def set_job_manager(jm):
    """Called once from api_server.py after import to share the JobManager."""
    global _jobs
    _jobs = jm


def _get_jobs():
    if _jobs is None:
        raise RuntimeError("JobManager not initialised — call set_job_manager first")
    return _jobs


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class DeployResponse(BaseModel):
    jobId: str
    status: str
    message: str
    timestamp: str


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@deploy_router.post("/api/deploy/start", response_model=DeployResponse)
async def start_deploy():
    """Launch deploy.ps1 in the background and return a job ID."""
    jm = _get_jobs()
    job_id = str(uuid.uuid4())
    jm.create(job_id)

    t = threading.Thread(target=run_deploy, args=(job_id, jm), daemon=True)
    t.start()

    return DeployResponse(
        jobId=job_id,
        status="queued",
        message="Deployment started",
        timestamp=datetime.utcnow().isoformat() + "Z",
    )


@deploy_router.get("/api/deploy/{job_id}")
async def get_deploy_status(job_id: str):
    """Return current deployment job status."""
    jm = _get_jobs()
    jp = jm.get(job_id)
    if jp is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return jp


@deploy_router.get("/api/deploy/{job_id}/progress")
async def stream_deploy_progress(job_id: str):
    """SSE stream for real-time deployment progress."""
    jm = _get_jobs()
    jp = jm.get(job_id)
    if jp is None:
        raise HTTPException(status_code=404, detail="Job not found")

    async def event_generator():
        import json

        yield f"event: connected\ndata: {json.dumps({'jobId': job_id, 'message': 'Connected to deployment progress'})}\n\n"

        # Flush buffered events
        for ev in jm.pop_events(job_id):
            yield f"event: log\ndata: {json.dumps(ev)}\n\n"

        while True:
            current = jm.get(job_id)
            if current is None:
                break

            await asyncio.get_event_loop().run_in_executor(None, jm.wait_for_event, job_id, 5.0)

            for ev in jm.pop_events(job_id):
                yield f"event: log\ndata: {json.dumps(ev)}\n\n"

            yield f"event: status\ndata: {json.dumps({'jobId': job_id, 'status': current.status, 'progress': current.progress})}\n\n"

            if current.status in ("completed", "failed"):
                yield f"event: complete\ndata: {json.dumps({'jobId': job_id, 'status': current.status, 'progress': current.progress, 'error': current.error, 'result': current.result})}\n\n"
                break

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@deploy_router.get("/api/settings/env")
async def get_env_settings():
    """Return all .env variables (secrets masked) and service URLs."""
    env_vars = read_env_variables()
    service_urls = get_service_urls()
    return {
        "env_variables": env_vars,
        "service_urls": service_urls,
    }


class UpdateUrlsRequest(BaseModel):
    urls: dict[str, str]


@deploy_router.put("/api/settings/urls")
async def put_service_urls(body: UpdateUrlsRequest):
    """Update service URLs and storage settings in .env and return refreshed values."""
    updated = update_service_urls(body.urls)
    return {"service_urls": updated}
