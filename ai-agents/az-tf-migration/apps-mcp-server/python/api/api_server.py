"""
FastAPI wrapper for aztf-sequential-wf.py
Exposes the Azure-to-Terraform agentic workflow as a REST + SSE API.
Does NOT modify any existing Python files — imports run_aztf_enterprise_pipeline as-is.
"""

import os
import sys
import uuid
import asyncio
import threading
import io
import time
import re
import json
from datetime import datetime
from contextlib import redirect_stdout, redirect_stderr
from typing import Optional
from pathlib import Path

# Resolve directory paths for imports
_python_dir = str(Path(__file__).resolve().parent.parent)          # python/
_workflow_dir = str(Path(_python_dir) / "az-fndry-workflow")       # python/az-fndry-workflow/

# Add python/ for Report package, az-fndry-workflow/ for pipeline modules
sys.path.insert(0, _python_dir)
sys.path.insert(0, _workflow_dir)

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, Response
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Import the existing pipeline function (unchanged)
# ---------------------------------------------------------------------------
from importlib import import_module

_wf_module = import_module("aztf-sequential-wf")
run_aztf_enterprise_pipeline = _wf_module.run_aztf_enterprise_pipeline
run_agent_step = _wf_module.run_agent_step
AGENT_PROMPTS = _wf_module.AGENT_PROMPTS
PROJECT_ENDPOINT = _wf_module.PROJECT_ENDPOINT

# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class WorkflowRequest(BaseModel):
    prompt: str = Field(..., min_length=10, description="Natural language migration prompt containing subscription ID and resource group")

class AssessmentRequest(BaseModel):
    subscriptionId: str = Field(..., min_length=10, description="Azure subscription ID")
    resourceGroup: str = Field(..., min_length=1, description="Azure resource group name")

class WorkflowResponse(BaseModel):
    jobId: str
    status: str
    message: str
    timestamp: str

class JobProgress(BaseModel):
    jobId: str
    status: str
    currentAgent: Optional[str] = None
    progress: int = 0
    logs: list[dict] = []
    error: Optional[str] = None
    result: Optional[str] = None

# ---------------------------------------------------------------------------
# In-memory job store
# ---------------------------------------------------------------------------

class JobManager:
    """Thread-safe job store."""

    def __init__(self):
        self._jobs: dict[str, JobProgress] = {}
        self._locks: dict[str, threading.Lock] = {}
        self._events: dict[str, list[dict]] = {}     # SSE event buffer per job
        self._new_event: dict[str, threading.Event] = {}

    def create(self, job_id: str) -> JobProgress:
        jp = JobProgress(jobId=job_id, status="queued", progress=0, logs=[])
        self._jobs[job_id] = jp
        self._locks[job_id] = threading.Lock()
        self._events[job_id] = []
        self._new_event[job_id] = threading.Event()
        return jp

    def get(self, job_id: str) -> Optional[JobProgress]:
        return self._jobs.get(job_id)

    def update(self, job_id: str, **kwargs):
        with self._locks[job_id]:
            jp = self._jobs[job_id]
            for k, v in kwargs.items():
                setattr(jp, k, v)

    def append_log(self, job_id: str, level: str, message: str, agent: Optional[str] = None):
        entry = {
            "level": level,
            "message": message,
            "agent": agent,
            "timestamp": datetime.utcnow().isoformat() + "Z",
        }
        with self._locks[job_id]:
            self._jobs[job_id].logs.append(entry)
            self._events[job_id].append(entry)
            self._new_event[job_id].set()

    def wait_for_event(self, job_id: str, timeout: float = 5.0) -> bool:
        ev = self._new_event.get(job_id)
        if ev is None:
            return False
        triggered = ev.wait(timeout=timeout)
        ev.clear()
        return triggered

    def pop_events(self, job_id: str) -> list[dict]:
        with self._locks[job_id]:
            events = list(self._events[job_id])
            self._events[job_id].clear()
            return events

    def list_jobs(self) -> list[dict]:
        return [
            {"jobId": jp.jobId, "status": jp.status, "currentAgent": jp.currentAgent, "progress": jp.progress}
            for jp in self._jobs.values()
        ]


jobs = JobManager()

# ---------------------------------------------------------------------------
# Log capture — intercepts stdout from the pipeline and pushes to job store
# ---------------------------------------------------------------------------

AGENT_LABEL_RE = re.compile(r"\[ACTIVE AGENT\s*\]:\s*(.+)")
STEP_PATTERNS = {
    "aztf-orchestrator-v1": ("Orchestrator", 10),
    "aztf-assessment-v1": ("Assessment", 35),
    "aztf-export-v1": ("Export", 60),
    "aztf-coderefactor-v1": ("Refactor", 85),
}


class WorkflowLogCapture(io.TextIOBase):
    """Writable stream that parses pipeline console output into structured events."""

    def __init__(self, job_id: str):
        self.job_id = job_id
        self._buf = ""
        self._agent_start_time: dict[str, float] = {}   # agent_name -> time.time()
        self._current_agent: str | None = None
        self._current_agent_raw: str | None = None
        # Real metrics emitted by the workflow via [AGENT_METRICS] lines
        self._agent_metrics_cache: dict[str, dict] = {}  # agent_label -> {tokens_prompt, tokens_completion, model, tool_calls}
        # Per-agent trace payload emitted by workflow via [AGENT_TRACE] lines
        self._agent_trace_cache: dict[str, dict] = {}  # agent_label -> {input_prompt, output_prompt}

    def write(self, s: str) -> int:
        if not s:
            return 0
        self._buf += s
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            self._process_line(line)
        return len(s)

    def flush(self):
        if self._buf.strip():
            self._process_line(self._buf)
            self._buf = ""

    def _process_line(self, line: str):
        line = line.strip()
        if not line:
            return

        # Strip ANSI colour codes for clean storage
        clean = re.sub(r"\033\[[0-9;]*m", "", line)

        # Parse [AGENT_METRICS] lines emitted by the workflow with real Foundry usage data
        if "[AGENT_METRICS]:" in clean:
            try:
                payload = clean.split("[AGENT_METRICS]:", 1)[1].strip()
                # Parse key=value pairs safely even if extra spaces appear.
                parts = dict(re.findall(r"(\w+)\s*=\s*([^,]+)", payload))
                raw_agent = parts.get("agent", "").strip()
                label = STEP_PATTERNS.get(raw_agent, (raw_agent, None))[0]
                self._agent_metrics_cache[label] = {
                    "agent_name": raw_agent or label,
                    "tokens_prompt": int(parts.get("tokens_prompt", 0)),
                    "tokens_completion": int(parts.get("tokens_completion", 0)),
                    "model": parts.get("model", "unknown").strip(),
                    "tool_calls": int(parts.get("tool_calls", 0)),
                }
            except Exception:
                pass  # Don't crash on malformed metrics lines
            return

        # Parse [AGENT_TRACE] lines with per-agent input/output prompt snapshots
        if "[AGENT_TRACE]:" in clean:
            try:
                payload = clean.split("[AGENT_TRACE]:", 1)[1].strip()
                trace_obj = json.loads(payload)
                raw_agent = str(trace_obj.get("agent", "")).strip()
                label = STEP_PATTERNS.get(raw_agent, (raw_agent, None))[0]
                self._agent_trace_cache[label] = {
                    "input_prompt": str(trace_obj.get("input_prompt", "")).strip(),
                    "output_prompt": str(trace_obj.get("output_prompt", "")).strip(),
                }
            except Exception:
                pass
            return

        # Detect active agent
        m = AGENT_LABEL_RE.search(clean)
        if m:
            agent_name = m.group(1).strip()
            label, pct = STEP_PATTERNS.get(agent_name, (agent_name, None))

            # If switching agent, record latency for the previous one
            if self._current_agent and self._current_agent != label:
                self._finalize_agent_span(self._current_agent, success=True)

            self._current_agent = label
            self._current_agent_raw = agent_name
            self._agent_start_time[label] = time.time()

            jobs.update(self.job_id, currentAgent=label, status="running")
            if pct is not None:
                jobs.update(self.job_id, progress=pct)
            jobs.append_log(self.job_id, "info", f"Agent started: {label}", agent=label)
            return

        # Detect level from label
        level = "info"
        upper = clean.upper()
        if "[STATUS" in upper and "SUCCESS" in upper:
            level = "success"
        elif "[STATUS" in upper and ("ERROR" in upper or "FILTERED" in upper):
            level = "error"
        elif "FAIL" in upper or "ERROR" in upper:
            level = "error"
        elif "WARN" in upper:
            level = "warn"
        elif "PIPELINE" in upper and "COMPLETE" in upper:
            level = "success"

        # Track retries via log parsing
        if "RETRY" in upper and self._current_agent:
            attempt_match = re.search(r"attempt\s*(\d+)\s*/\s*(\d+)", clean, re.IGNORECASE)
            attempt = int(attempt_match.group(1)) if attempt_match else 1
            max_att = int(attempt_match.group(2)) if attempt_match else 3
            retry_tracker.record_retry(
                agent_name=self._current_agent,
                job_id=self.job_id,
                attempt=attempt,
                max_attempts=max_att,
                delay_ms=0,
                reason="hallucination_retry",
            )

        # Track failures
        if level == "error" and self._current_agent:
            self._finalize_agent_span(self._current_agent, success=False, error=clean)

        jobs.append_log(self.job_id, level, clean, agent=jobs.get(self.job_id).currentAgent if jobs.get(self.job_id) else None)

    def _finalize_agent_span(self, agent_label: str, success: bool = True, error: str | None = None):
        """Record metrics + trace span for agent completion using real Foundry data."""
        start = self._agent_start_time.get(agent_label)
        if not start:
            return
        latency_ms = (time.time() - start) * 1000

        # Use real metrics from the workflow's [AGENT_METRICS] line, or zeros if not available
        real = self._agent_metrics_cache.pop(agent_label, {})
        trace_payload = self._agent_trace_cache.pop(agent_label, {})
        metric_agent_name = real.get("agent_name", self._current_agent_raw or agent_label)
        tokens_prompt = real.get("tokens_prompt", 0)
        tokens_completion = real.get("tokens_completion", 0)
        model = real.get("model", "unknown")
        tool_calls = real.get("tool_calls", 0)
        estimated_cost = cost_calculator.estimate_cost(
            model=model,
            tokens_prompt=tokens_prompt,
            tokens_completion=tokens_completion,
        )

        metrics_collector.record_call(
            agent_name=metric_agent_name,
            job_id=self.job_id,
            latency_ms=latency_ms,
            tokens_prompt=tokens_prompt,
            tokens_completion=tokens_completion,
            success=success,
            error=error,
            tool_calls=tool_calls,
        )
        trace_store.add_span(
            job_id=self.job_id,
            span_type="agent_step",
            agent_name=metric_agent_name,
            duration_ms=latency_ms,
            tokens_prompt=tokens_prompt,
            tokens_completion=tokens_completion,
            tool_calls=tool_calls,
            status="ok" if success else "error",
            error=error,
            metadata={
                "model": model,
                "cost_total_usd": estimated_cost["cost_total"],
                "cost_prompt_usd": estimated_cost["cost_prompt"],
                "cost_completion_usd": estimated_cost["cost_completion"],
                "input_prompt": trace_payload.get("input_prompt", ""),
                "output_prompt": trace_payload.get("output_prompt", ""),
            },
        )
        # Only record cost if we have real token data
        if tokens_prompt > 0 or tokens_completion > 0:
            cost_calculator.record_usage(
                agent_name=metric_agent_name,
                job_id=self.job_id,
                model=model,
                tokens_prompt=tokens_prompt,
                tokens_completion=tokens_completion,
            )

    def finalize_all(self):
        """Call at pipeline end to finalize the last active agent."""
        if self._current_agent:
            self._finalize_agent_span(self._current_agent, success=True)


# ---------------------------------------------------------------------------
# Background runner
# ---------------------------------------------------------------------------

def _run_assessment_only(job_id: str, subscription_id: str, resource_group: str):
    """Execute assessment-only agent in a background thread."""
    capture = WorkflowLogCapture(job_id)
    jobs.update(job_id, status="running", progress=5)
    jobs.append_log(job_id, "info", f"Assessment started for {subscription_id}/{resource_group}")

    throughput_tracker.record_request()
    trace_store.start_trace(job_id, f"assessment: {subscription_id}/{resource_group}")

    old_stdout, old_stderr = sys.stdout, sys.stderr
    try:
        sys.stdout = capture
        sys.stderr = capture

        from azure.identity import DefaultAzureCredential
        from azure.ai.projects import AIProjectClient

        project_client = AIProjectClient(
            endpoint=PROJECT_ENDPOINT,
            credential=DefaultAzureCredential()
        )
        with project_client:
            openai_client = project_client.get_openai_client()
            conv = openai_client.conversations.create()
            prompt = AGENT_PROMPTS["aztf-assessment-v1"].format(
                sub_id=subscription_id, rg_name=resource_group
            )
            result = run_agent_step(
                openai_client, conv.id, "aztf-assessment-v1",
                prompt, tool_name="azure_assessment", force_tool=True
            )

        if result and result not in ("FILTERED", "NO_DATA_RETURNED"):
            jobs.update(job_id, status="completed", progress=100, result=result)
            jobs.append_log(job_id, "success", "Assessment completed successfully")
            trace_store.complete_trace(job_id, "completed")
        else:
            jobs.update(job_id, status="failed", error=result or "No data returned")
            jobs.append_log(job_id, "error", f"Assessment failed: {result}")
            trace_store.complete_trace(job_id, "failed")
    except Exception as exc:
        jobs.update(job_id, status="failed", error=str(exc))
        jobs.append_log(job_id, "error", f"Assessment failed: {exc}")
        trace_store.complete_trace(job_id, "failed")
    finally:
        capture.flush()
        capture.finalize_all()
        sys.stdout = old_stdout
        sys.stderr = old_stderr


def _run_pipeline(job_id: str, user_prompt: str):
    """Execute pipeline in a background thread, capturing stdout/stderr."""
    capture = WorkflowLogCapture(job_id)
    jobs.update(job_id, status="running", progress=5)
    jobs.append_log(job_id, "info", f"Pipeline started with prompt: {user_prompt[:100]}...")

    throughput_tracker.record_request()
    trace_store.start_trace(job_id, user_prompt)

    old_stdout, old_stderr = sys.stdout, sys.stderr
    try:
        sys.stdout = capture
        sys.stderr = capture
        result = run_aztf_enterprise_pipeline(user_prompt)

        pipeline_success = False
        pipeline_message = "Pipeline failed"
        if isinstance(result, dict):
            pipeline_success = bool(result.get("success", False))
            pipeline_message = str(result.get("message", pipeline_message))
        elif isinstance(result, bool):
            pipeline_success = result
            pipeline_message = "Pipeline completed successfully" if result else pipeline_message

        if pipeline_success:
            jobs.update(job_id, status="completed", progress=100)
            jobs.append_log(job_id, "success", pipeline_message)
            trace_store.complete_trace(job_id, "completed")
        else:
            current = jobs.get(job_id)
            fallback_error = pipeline_message or "Pipeline reported failure"
            jobs.update(job_id, status="failed", error=fallback_error)
            if current and current.progress >= 100:
                jobs.update(job_id, progress=95)
            jobs.append_log(job_id, "error", fallback_error)
            trace_store.complete_trace(job_id, "failed")
    except Exception as exc:
        jobs.update(job_id, status="failed", error=str(exc))
        jobs.append_log(job_id, "error", f"Pipeline failed: {exc}")
        trace_store.complete_trace(job_id, "failed")
    finally:
        capture.flush()
        capture.finalize_all()
        sys.stdout = old_stdout
        sys.stderr = old_stderr


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(title="AzTF Agentic Workflow API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount Report API router
from report.report_api import report_router
app.include_router(report_router)

# Mount Deploy API router
from autodeploy.deploy_api import deploy_router, set_job_manager
set_job_manager(jobs)
app.include_router(deploy_router)

# Mount Observability API router
from observability.observability_api import observability_router
app.include_router(observability_router)

# Observability singletons — used by log capture + background runners
from observability.observability_service import (
    metrics_collector,
    trace_store,
    cost_calculator,
    retry_tracker,
    throughput_tracker,
)


@app.post("/api/workflow/start", response_model=WorkflowResponse)
async def start_workflow(req: WorkflowRequest):
    """Launch the 4-agent pipeline in the background and return a job ID."""
    job_id = str(uuid.uuid4())
    jobs.create(job_id)

    t = threading.Thread(target=_run_pipeline, args=(job_id, req.prompt), daemon=True)
    t.start()

    return WorkflowResponse(
        jobId=job_id,
        status="queued",
        message="Agentic workflow started",
        timestamp=datetime.utcnow().isoformat() + "Z",
    )


@app.get("/api/jobs/{job_id}")
async def get_job(job_id: str):
    """Return current status snapshot for a job."""
    jp = jobs.get(job_id)
    if jp is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return jp


@app.get("/api/jobs/{job_id}/progress")
async def stream_progress(job_id: str):
    """Server-Sent Events stream for real-time progress."""
    jp = jobs.get(job_id)
    if jp is None:
        raise HTTPException(status_code=404, detail="Job not found")

    async def event_generator():
        # Send initial connected event
        yield f"event: connected\ndata: {_json({'jobId': job_id, 'message': 'Connected to workflow progress'})}\n\n"

        # Flush any events already buffered
        for ev in jobs.pop_events(job_id):
            yield f"event: log\ndata: {_json(ev)}\n\n"

        while True:
            current = jobs.get(job_id)
            if current is None:
                break

            # Wait for new events (up to 10s for long-running jobs) then flush
            await asyncio.get_event_loop().run_in_executor(None, jobs.wait_for_event, job_id, 10.0)

            for ev in jobs.pop_events(job_id):
                yield f"event: log\ndata: {_json(ev)}\n\n"

            # Send heartbeat with status and timestamp to prevent timeout
            yield f"event: status\ndata: {_json({'jobId': job_id, 'status': current.status, 'progress': current.progress, 'currentAgent': current.currentAgent, 'timestamp': datetime.utcnow().isoformat() + 'Z'})}\n\n"

            if current.status in ("completed", "failed"):
                yield f"event: complete\ndata: {_json({'jobId': job_id, 'status': current.status, 'progress': current.progress, 'error': current.error})}\n\n"
                break

    return StreamingResponse(event_generator(), media_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@app.post("/api/assessment/start", response_model=WorkflowResponse)
async def start_assessment(req: AssessmentRequest):
    """Launch assessment-only agent and return a job ID."""
    job_id = str(uuid.uuid4())
    jobs.create(job_id)

    t = threading.Thread(
        target=_run_assessment_only,
        args=(job_id, req.subscriptionId, req.resourceGroup),
        daemon=True,
    )
    t.start()

    return WorkflowResponse(
        jobId=job_id,
        status="queued",
        message="Assessment started",
        timestamp=datetime.utcnow().isoformat() + "Z",
    )


@app.get("/api/assessment/{job_id}/report")
def get_assessment_report(job_id: str, subscription_id: str, resource_group: str):
    """Download the HTML assessment report from Azure Blob Storage."""
    jp = jobs.get(job_id)
    if jp is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if jp.status != "completed":
        raise HTTPException(status_code=400, detail=f"Job not completed yet (status: {jp.status})")

    from report.report_service import download_blob, build_assessment_report_blob_name
    blob_name = build_assessment_report_blob_name(subscription_id, resource_group)
    content = download_blob("assessment-reports", blob_name)
    if content is None:
        raise HTTPException(status_code=404, detail=f"Report not found: {blob_name}")

    return Response(
        content=content,
        media_type="text/html",
        headers={"Content-Disposition": f'attachment; filename="Assessment-{subscription_id}-{resource_group}.html"'},
    )


@app.get("/api/jobs")
async def list_jobs():
    return jobs.list_jobs()


@app.get("/health")
async def health():
    return {"status": "ok"}


def _json(obj) -> str:
    import json
    return json.dumps(obj)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
