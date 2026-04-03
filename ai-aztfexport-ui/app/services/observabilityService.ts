/**
 * Observability Service — API calls for metrics, traces, costs, retries, throughput, and health.
 */

import { config } from './config';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface AgentMetrics {
  agent_name: string;
  total_calls: number;
  total_failures: number;
  total_retries: number;
  total_tokens_prompt: number;
  total_tokens_completion: number;
  total_tokens: number;
  total_latency_ms: number;
  total_tool_calls: number;
  avg_latency_ms: number;
  p50_latency_ms: number;
  p95_latency_ms: number;
  p99_latency_ms: number;
  failure_rate: number;
  last_called: string | null;
  errors: Array<{ error: string; timestamp: string }>;
}

export interface MetricsSummary {
  total_calls: number;
  total_failures: number;
  total_retries: number;
  total_tokens: number;
  failure_rate: number;
  retry_rate: number;
  latency_p50_ms: number;
  latency_p95_ms: number;
  latency_p99_ms: number;
  avg_latency_ms: number;
  agents_tracked: number;
  jobs_tracked: number;
}

export interface MetricsResponse {
  summary: MetricsSummary;
  agents: Record<string, AgentMetrics>;
}

export interface TraceSpan {
  span_type: string;
  agent: string;
  duration_ms: number;
  tokens_prompt: number;
  tokens_completion: number;
  tool_calls: number;
  status: string;
  error: string | null;
  metadata: Record<string, unknown>;
  timestamp: string;
}

export interface Trace {
  trace_id: string;
  prompt: string;
  started_at: string;
  completed_at: string | null;
  status: string;
  spans: TraceSpan[];
  total_duration_ms: number;
}

export interface CostSummary {
  total_cost_usd: number;
  total_tokens: number;
  total_records: number;
  by_agent: Record<string, number>;
  by_model: Record<string, number>;
}

export interface CostRecord {
  agent: string;
  job_id: string;
  model: string;
  tokens_prompt: number;
  tokens_completion: number;
  cost_prompt: number;
  cost_completion: number;
  cost_total: number;
  timestamp: string;
}

export interface RetryEntry {
  agent: string;
  job_id: string;
  attempt: number;
  max_attempts: number;
  delay_ms: number;
  reason: string;
  timestamp: string;
}

export interface RetrySummary {
  total_retries: number;
  by_agent: Record<string, number>;
  by_reason: Record<string, number>;
}

export interface ThroughputSummary {
  requests_per_minute: number;
  window_seconds: number;
}

export interface HealthSummary {
  health: 'healthy' | 'degraded' | 'unhealthy';
  issues: string[];
  metrics: MetricsSummary;
  cost: CostSummary;
  retries: RetrySummary;
  throughput: ThroughputSummary;
}

export interface ObservabilitySource {
  source: string;
  project_endpoint: string;
  foundry_connection_configured: boolean;
  individual_agent_metrics: boolean;
}

// ---------------------------------------------------------------------------
// API Calls
// ---------------------------------------------------------------------------

export const fetchMetrics = async (agent?: string): Promise<MetricsResponse> => {
  const url = agent
    ? `${config.observability.endpoints.metrics}?agent=${encodeURIComponent(agent)}`
    : config.observability.endpoints.metrics;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch metrics: ${res.status}`);
  return res.json();
};

export const fetchAgentMetrics = async (agentName: string): Promise<AgentMetrics> => {
  const url = config.observability.endpoints.agentMetrics(agentName);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch agent metrics: ${res.status}`);
  return res.json();
};

export const fetchTraces = async (limit: number = 50): Promise<{ traces: Trace[] }> => {
  const url = `${config.observability.endpoints.traces}?limit=${limit}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch traces: ${res.status}`);
  return res.json();
};

export const fetchTraceDetail = async (jobId: string): Promise<Trace> => {
  const url = config.observability.endpoints.traceDetail(jobId);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch trace: ${res.status}`);
  return res.json();
};

export const fetchCosts = async (limit: number = 100): Promise<{ summary: CostSummary; records: CostRecord[] }> => {
  const url = `${config.observability.endpoints.costs}?limit=${limit}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch costs: ${res.status}`);
  return res.json();
};

export const fetchRetries = async (limit: number = 100): Promise<{ summary: RetrySummary; retries: RetryEntry[] }> => {
  const url = `${config.observability.endpoints.retries}?limit=${limit}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch retries: ${res.status}`);
  return res.json();
};

export const fetchThroughput = async (): Promise<ThroughputSummary> => {
  const url = config.observability.endpoints.throughput;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch throughput: ${res.status}`);
  return res.json();
};

export const fetchHealthSummary = async (): Promise<HealthSummary> => {
  const url = config.observability.endpoints.healthSummary;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch health summary: ${res.status}`);
  return res.json();
};

export const fetchObservabilitySource = async (): Promise<ObservabilitySource> => {
  const url = `${config.observability.baseUrl}/api/observability/source`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch observability source: ${res.status}`);
  return res.json();
};
