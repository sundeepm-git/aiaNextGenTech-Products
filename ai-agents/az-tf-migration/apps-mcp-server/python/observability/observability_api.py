"""
Observability API Router — FastAPI endpoints for metrics, traces, costs, and health.
"""

from fastapi import APIRouter, Query
from typing import Optional

from observability.observability_service import (
    metrics_collector,
    trace_store,
    cost_calculator,
    retry_tracker,
    throughput_tracker,
)

# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

observability_router = APIRouter(prefix="/api/observability", tags=["observability"])


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@observability_router.get("/metrics")
async def get_metrics(agent: Optional[str] = Query(None, description="Filter by agent name")):
    """Return aggregated metrics, optionally filtered by agent."""
    return {
        "summary": metrics_collector.get_summary(),
        "agents": metrics_collector.get_agent_metrics(agent),
    }


@observability_router.get("/metrics/agents/{agent_name}")
async def get_agent_metrics(agent_name: str):
    """Return metrics for a specific agent."""
    data = metrics_collector.get_agent_metrics(agent_name)
    if not data:
        return {"agent_name": agent_name, "message": "No metrics recorded yet"}
    return data


@observability_router.get("/traces")
async def get_traces(limit: int = Query(50, ge=1, le=500)):
    """Return recent traces."""
    return {"traces": trace_store.get_recent_traces(limit)}


@observability_router.get("/traces/{job_id}")
async def get_trace(job_id: str):
    """Return a specific trace by job ID."""
    trace = trace_store.get_trace(job_id)
    if not trace:
        return {"job_id": job_id, "message": "Trace not found"}
    return trace


@observability_router.get("/costs")
async def get_costs(limit: int = Query(100, ge=1, le=2000)):
    """Return cost summary and recent records."""
    return {
        "summary": cost_calculator.get_cost_summary(),
        "records": cost_calculator.get_cost_records(limit),
    }


@observability_router.get("/retries")
async def get_retries(limit: int = Query(100, ge=1, le=1000)):
    """Return retry summary and recent retry events."""
    return {
        "summary": retry_tracker.get_summary(),
        "retries": retry_tracker.get_retries(limit),
    }


@observability_router.get("/throughput")
async def get_throughput():
    """Return current throughput (requests per minute)."""
    return throughput_tracker.get_summary()


@observability_router.get("/health-summary")
async def get_health_summary():
    """Return a high-level health overview combining all observability data."""
    summary = metrics_collector.get_summary()
    cost = cost_calculator.get_cost_summary()
    retry = retry_tracker.get_summary()
    throughput = throughput_tracker.get_summary()

    # Determine health status
    health = "healthy"
    issues = []
    if summary["total_calls"] == 0:
        health = "no_data"
        issues.append("No pipeline runs recorded yet")
    if summary["failure_rate"] > 0.1:
        health = "degraded"
        issues.append(f"High failure rate: {summary['failure_rate']:.1%}")
    if summary["latency_p95_ms"] > 30000:
        health = "degraded"
        issues.append(f"High p95 latency: {summary['latency_p95_ms']:.0f}ms")
    if retry["total_retries"] > 0 and summary["total_calls"] > 0:
        retry_ratio = retry["total_retries"] / summary["total_calls"]
        if retry_ratio > 0.2:
            health = "degraded"
            issues.append(f"High retry ratio: {retry_ratio:.1%}")

    return {
        "health": health,
        "issues": issues,
        "metrics": summary,
        "cost": cost,
        "retries": retry,
        "throughput": throughput,
    }
