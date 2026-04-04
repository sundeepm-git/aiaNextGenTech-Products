"""
Observability Service — Metrics, traces, cost tracking, and health for the agentic pipeline.
"""

import time
import hashlib
import threading
from datetime import datetime, timezone
from typing import Optional
from collections import defaultdict


# ---------------------------------------------------------------------------
# Metrics Collector
# ---------------------------------------------------------------------------

class MetricsCollector:
    """Collects per-agent and per-job metrics: latency, tokens, retries, failures, tool calls."""

    def __init__(self):
        self._lock = threading.Lock()
        # Per-agent cumulative metrics
        self._agent_metrics: dict[str, dict] = defaultdict(lambda: {
            "total_calls": 0,
            "total_failures": 0,
            "total_retries": 0,
            "total_tokens_prompt": 0,
            "total_tokens_completion": 0,
            "total_latency_ms": 0,
            "total_tool_calls": 0,
            "last_called": None,
            "latencies": [],        # recent latencies for p50/p95/p99
            "errors": [],           # recent error messages
        })
        # Per-job metrics
        self._job_metrics: dict[str, dict] = {}

    def record_call(
        self,
        agent_name: str,
        job_id: str,
        latency_ms: float,
        tokens_prompt: int = 0,
        tokens_completion: int = 0,
        tool_calls: int = 0,
        success: bool = True,
        error: Optional[str] = None,
        retries: int = 0,
    ):
        now = datetime.now(timezone.utc).isoformat()
        with self._lock:
            m = self._agent_metrics[agent_name]
            m["total_calls"] += 1
            m["total_latency_ms"] += latency_ms
            m["total_tokens_prompt"] += tokens_prompt
            m["total_tokens_completion"] += tokens_completion
            m["total_tool_calls"] += tool_calls
            m["total_retries"] += retries
            m["last_called"] = now
            # Keep last 200 latencies for percentile calculations
            m["latencies"].append(latency_ms)
            if len(m["latencies"]) > 200:
                m["latencies"] = m["latencies"][-200:]
            if not success:
                m["total_failures"] += 1
                if error:
                    m["errors"].append({"error": error, "timestamp": now})
                    if len(m["errors"]) > 50:
                        m["errors"] = m["errors"][-50:]

            # Job-level tracking
            if job_id not in self._job_metrics:
                self._job_metrics[job_id] = {
                    "agents": {},
                    "started_at": now,
                    "total_tokens": 0,
                    "total_latency_ms": 0,
                }
            jm = self._job_metrics[job_id]
            jm["agents"][agent_name] = {
                "latency_ms": latency_ms,
                "tokens_prompt": tokens_prompt,
                "tokens_completion": tokens_completion,
                "tool_calls": tool_calls,
                "success": success,
                "retries": retries,
            }
            jm["total_tokens"] += tokens_prompt + tokens_completion
            jm["total_latency_ms"] += latency_ms

    def get_agent_metrics(self, agent_name: Optional[str] = None) -> dict:
        with self._lock:
            if agent_name:
                raw = dict(self._agent_metrics.get(agent_name, {}))
                if not raw:
                    return {}
                return self._enrich_agent(agent_name, raw)
            return {
                name: self._enrich_agent(name, dict(data))
                for name, data in self._agent_metrics.items()
            }

    def get_job_metrics(self, job_id: Optional[str] = None) -> dict:
        with self._lock:
            if job_id:
                return dict(self._job_metrics.get(job_id, {}))
            return {jid: dict(jm) for jid, jm in self._job_metrics.items()}

    def get_summary(self) -> dict:
        with self._lock:
            total_calls = sum(m["total_calls"] for m in self._agent_metrics.values())
            total_failures = sum(m["total_failures"] for m in self._agent_metrics.values())
            total_retries = sum(m["total_retries"] for m in self._agent_metrics.values())
            total_tokens = sum(
                m["total_tokens_prompt"] + m["total_tokens_completion"]
                for m in self._agent_metrics.values()
            )
            all_latencies = []
            for m in self._agent_metrics.values():
                all_latencies.extend(m["latencies"])

            return {
                "total_calls": total_calls,
                "total_failures": total_failures,
                "total_retries": total_retries,
                "total_tokens": total_tokens,
                "failure_rate": round(total_failures / total_calls, 4) if total_calls > 0 else 0,
                "retry_rate": round(total_retries / total_calls, 4) if total_calls > 0 else 0,
                "latency_p50_ms": self._percentile(all_latencies, 50),
                "latency_p95_ms": self._percentile(all_latencies, 95),
                "latency_p99_ms": self._percentile(all_latencies, 99),
                "avg_latency_ms": round(sum(all_latencies) / len(all_latencies), 1) if all_latencies else 0,
                "agents_tracked": len(self._agent_metrics),
                "jobs_tracked": len(self._job_metrics),
            }

    def _enrich_agent(self, name: str, data: dict) -> dict:
        latencies = data.get("latencies", [])
        total_calls = data.get("total_calls", 0)
        data["agent_name"] = name
        data["avg_latency_ms"] = round(data["total_latency_ms"] / total_calls, 1) if total_calls > 0 else 0
        data["total_tokens"] = data["total_tokens_prompt"] + data["total_tokens_completion"]
        data["p50_latency_ms"] = self._percentile(latencies, 50)
        data["p95_latency_ms"] = self._percentile(latencies, 95)
        data["p99_latency_ms"] = self._percentile(latencies, 99)
        data["failure_rate"] = round(data["total_failures"] / total_calls, 4) if total_calls > 0 else 0
        # Remove raw latencies array from output
        data.pop("latencies", None)
        return data

    @staticmethod
    def _percentile(values: list[float], pct: int) -> float:
        if not values:
            return 0
        s = sorted(values)
        idx = int(len(s) * pct / 100)
        idx = min(idx, len(s) - 1)
        return round(s[idx], 1)


# ---------------------------------------------------------------------------
# Trace Store
# ---------------------------------------------------------------------------

class TraceStore:
    """Stores structured traces with spans for each agent step and tool call."""

    def __init__(self, max_traces: int = 500):
        self._lock = threading.Lock()
        self._traces: list[dict] = []
        self._max_traces = max_traces

    def start_trace(self, job_id: str, prompt: str) -> dict:
        trace = {
            "trace_id": job_id,
            "prompt": prompt[:200],
            "started_at": datetime.now(timezone.utc).isoformat(),
            "completed_at": None,
            "status": "running",
            "spans": [],
            "total_duration_ms": 0,
        }
        with self._lock:
            self._traces.append(trace)
            if len(self._traces) > self._max_traces:
                self._traces = self._traces[-self._max_traces:]
        return trace

    def add_span(
        self,
        job_id: str,
        span_type: str,
        agent_name: str,
        duration_ms: float,
        tokens_prompt: int = 0,
        tokens_completion: int = 0,
        tool_calls: int = 0,
        status: str = "ok",
        error: Optional[str] = None,
        metadata: Optional[dict] = None,
    ):
        span = {
            "span_type": span_type,
            "agent": agent_name,
            "duration_ms": round(duration_ms, 1),
            "tokens_prompt": tokens_prompt,
            "tokens_completion": tokens_completion,
            "tool_calls": tool_calls,
            "status": status,
            "error": error,
            "metadata": metadata or {},
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        with self._lock:
            for t in reversed(self._traces):
                if t["trace_id"] == job_id:
                    t["spans"].append(span)
                    break

    def complete_trace(self, job_id: str, status: str = "completed"):
        now = datetime.now(timezone.utc).isoformat()
        with self._lock:
            for t in reversed(self._traces):
                if t["trace_id"] == job_id:
                    t["completed_at"] = now
                    t["status"] = status
                    # Calculate total duration from spans
                    t["total_duration_ms"] = sum(s["duration_ms"] for s in t["spans"])
                    break

    def get_trace(self, job_id: str) -> Optional[dict]:
        with self._lock:
            for t in reversed(self._traces):
                if t["trace_id"] == job_id:
                    return dict(t)
        return None

    def get_recent_traces(self, limit: int = 50) -> list[dict]:
        with self._lock:
            return [dict(t) for t in self._traces[-limit:]]


# ---------------------------------------------------------------------------
# Cost Calculator
# ---------------------------------------------------------------------------

# Pricing per 1K tokens (approximate Azure OpenAI GPT-4o pricing)
_DEFAULT_PRICING = {
    "gpt-4o": {"prompt": 0.005, "completion": 0.015},
    "gpt-4o-mini": {"prompt": 0.00015, "completion": 0.0006},
    "gpt-4": {"prompt": 0.03, "completion": 0.06},
    "gpt-35-turbo": {"prompt": 0.0005, "completion": 0.0015},
    "default": {"prompt": 0.005, "completion": 0.015},
}


class CostCalculator:
    """Token-based cost estimation per model."""

    def __init__(self, pricing: Optional[dict] = None):
        self._lock = threading.Lock()
        self._pricing = pricing or _DEFAULT_PRICING
        self._cost_records: list[dict] = []

    def estimate_cost(self, model: str, tokens_prompt: int, tokens_completion: int) -> dict:
        """Estimate token cost without persisting a usage record."""
        rates = self._pricing.get(model)
        if not rates:
            for key in sorted(self._pricing.keys(), key=len, reverse=True):
                if key != "default" and model.startswith(key):
                    rates = self._pricing[key]
                    break
        if not rates:
            rates = self._pricing.get("default", {"prompt": 0.005, "completion": 0.015})

        cost_prompt = (tokens_prompt / 1000) * rates["prompt"]
        cost_completion = (tokens_completion / 1000) * rates["completion"]
        total = round(cost_prompt + cost_completion, 6)
        return {
            "cost_prompt": round(cost_prompt, 6),
            "cost_completion": round(cost_completion, 6),
            "cost_total": total,
        }

    def record_usage(
        self,
        agent_name: str,
        job_id: str,
        model: str,
        tokens_prompt: int,
        tokens_completion: int,
    ):
        estimate = self.estimate_cost(model, tokens_prompt, tokens_completion)
        cost_prompt = estimate["cost_prompt"]
        cost_completion = estimate["cost_completion"]
        total = estimate["cost_total"]

        record = {
            "agent": agent_name,
            "job_id": job_id,
            "model": model,
            "tokens_prompt": tokens_prompt,
            "tokens_completion": tokens_completion,
            "cost_prompt": round(cost_prompt, 6),
            "cost_completion": round(cost_completion, 6),
            "cost_total": total,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        with self._lock:
            self._cost_records.append(record)
            if len(self._cost_records) > 2000:
                self._cost_records = self._cost_records[-2000:]

    def get_cost_summary(self) -> dict:
        with self._lock:
            total_cost = sum(r["cost_total"] for r in self._cost_records)
            total_tokens = sum(r["tokens_prompt"] + r["tokens_completion"] for r in self._cost_records)

            by_agent: dict[str, float] = defaultdict(float)
            by_model: dict[str, float] = defaultdict(float)
            for r in self._cost_records:
                by_agent[r["agent"]] += r["cost_total"]
                by_model[r["model"]] += r["cost_total"]

            return {
                "total_cost_usd": round(total_cost, 4),
                "total_tokens": total_tokens,
                "total_records": len(self._cost_records),
                "by_agent": {k: round(v, 4) for k, v in by_agent.items()},
                "by_model": {k: round(v, 4) for k, v in by_model.items()},
            }

    def get_cost_records(self, limit: int = 100) -> list[dict]:
        with self._lock:
            return list(self._cost_records[-limit:])


# ---------------------------------------------------------------------------
# Retry Tracker
# ---------------------------------------------------------------------------

class RetryTracker:
    """Tracks retry attempts with exponential backoff metadata."""

    def __init__(self):
        self._lock = threading.Lock()
        self._retries: list[dict] = []

    def record_retry(
        self,
        agent_name: str,
        job_id: str,
        attempt: int,
        max_attempts: int,
        delay_ms: float,
        reason: str,
    ):
        entry = {
            "agent": agent_name,
            "job_id": job_id,
            "attempt": attempt,
            "max_attempts": max_attempts,
            "delay_ms": round(delay_ms, 1),
            "reason": reason,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        with self._lock:
            self._retries.append(entry)
            if len(self._retries) > 1000:
                self._retries = self._retries[-1000:]

    def get_retries(self, limit: int = 100) -> list[dict]:
        with self._lock:
            return list(self._retries[-limit:])

    def get_summary(self) -> dict:
        with self._lock:
            total = len(self._retries)
            by_agent: dict[str, int] = defaultdict(int)
            by_reason: dict[str, int] = defaultdict(int)
            for r in self._retries:
                by_agent[r["agent"]] += 1
                by_reason[r["reason"]] += 1
            return {
                "total_retries": total,
                "by_agent": dict(by_agent),
                "by_reason": dict(by_reason),
            }


# ---------------------------------------------------------------------------
# Throughput Tracker
# ---------------------------------------------------------------------------

class ThroughputTracker:
    """Tracks request throughput per minute for rate-limit awareness."""

    def __init__(self, window_seconds: int = 60):
        self._lock = threading.Lock()
        self._window = window_seconds
        self._timestamps: list[float] = []

    def record_request(self):
        now = time.time()
        with self._lock:
            self._timestamps.append(now)
            cutoff = now - self._window
            self._timestamps = [t for t in self._timestamps if t > cutoff]

    def get_rpm(self) -> int:
        now = time.time()
        with self._lock:
            cutoff = now - self._window
            return len([t for t in self._timestamps if t > cutoff])

    def get_summary(self) -> dict:
        return {
            "requests_per_minute": self.get_rpm(),
            "window_seconds": self._window,
        }


# ---------------------------------------------------------------------------
# Singletons
# ---------------------------------------------------------------------------

metrics_collector = MetricsCollector()
trace_store = TraceStore()
cost_calculator = CostCalculator()
retry_tracker = RetryTracker()
throughput_tracker = ThroughputTracker()
