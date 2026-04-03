'use client';

import { Activity, BarChart3, Clock, DollarSign, RefreshCw, RotateCcw, Zap, AlertTriangle, CheckCircle2, XCircle, Eye } from 'lucide-react';
import { useObservability, ObservabilityTab } from '@/app/hooks/useObservability';
import type {
  MetricsResponse,
  AgentMetrics,
  Trace,
  CostSummary,
  CostRecord,
  RetrySummary,
  RetryEntry,
  ThroughputSummary,
  HealthSummary,
} from '@/app/services/observabilityService';

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function StatCard({ label, value, sub, icon: Icon, color = 'text-primary' }: {
  label: string; value: string | number; sub?: string; icon: React.ElementType; color?: string;
}) {
  return (
    <div className="bg-white rounded-xl border border-border p-5 flex items-start gap-4 shadow-sm">
      <div className={`p-2.5 rounded-lg bg-opacity-10 ${color.replace('text-', 'bg-')}/10`}>
        <Icon className={`w-5 h-5 ${color}`} />
      </div>
      <div>
        <p className="text-sm text-muted">{label}</p>
        <p className="text-2xl font-bold text-text">{value}</p>
        {sub && <p className="text-xs text-muted mt-0.5">{sub}</p>}
      </div>
    </div>
  );
}

function HealthBadge({ health }: { health: string }) {
  const cfg: Record<string, { bg: string; text: string; icon: React.ElementType }> = {
    healthy: { bg: 'bg-green-100', text: 'text-green-700', icon: CheckCircle2 },
    degraded: { bg: 'bg-yellow-100', text: 'text-yellow-700', icon: AlertTriangle },
    unhealthy: { bg: 'bg-red-100', text: 'text-red-700', icon: XCircle },
  };
  const c = cfg[health] || cfg.unhealthy;
  const Icon = c.icon;
  return (
    <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-sm font-semibold ${c.bg} ${c.text}`}>
      <Icon className="w-4 h-4" /> {health.charAt(0).toUpperCase() + health.slice(1)}
    </span>
  );
}

function BarSimple({ label, value, max, color = 'bg-primary' }: { label: string; value: number; max: number; color?: string }) {
  const pct = max > 0 ? Math.min((value / max) * 100, 100) : 0;
  return (
    <div className="flex items-center gap-3">
      <span className="text-sm text-muted w-28 truncate" title={label}>{label}</span>
      <div className="flex-1 bg-gray-100 rounded-full h-2.5">
        <div className={`${color} h-2.5 rounded-full transition-all`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-sm font-medium text-text w-16 text-right">{typeof value === 'number' ? value.toLocaleString() : value}</span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab panels
// ---------------------------------------------------------------------------

function HealthPanel({ health }: { health: HealthSummary }) {
  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <h3 className="text-lg font-semibold text-text">System Health</h3>
        <HealthBadge health={health.health} />
      </div>
      {health.issues.length > 0 && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 space-y-1">
          <p className="font-semibold text-yellow-800">Active Issues</p>
          {health.issues.map((issue, i) => (
            <p key={i} className="text-sm text-yellow-700">• {issue}</p>
          ))}
        </div>
      )}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard label="Total API Calls" value={health.metrics.total_calls} icon={Activity} />
        <StatCard label="Failure Rate" value={`${(health.metrics.failure_rate * 100).toFixed(1)}%`} icon={XCircle} color="text-red-500" />
        <StatCard label="Avg Latency" value={`${health.metrics.avg_latency_ms}ms`} icon={Clock} color="text-blue-500" />
        <StatCard label="Total Cost" value={`$${health.cost.total_cost_usd.toFixed(4)}`} icon={DollarSign} color="text-green-600" />
      </div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard label="Total Tokens" value={health.metrics.total_tokens.toLocaleString()} icon={Zap} color="text-purple-500" />
        <StatCard label="Retries" value={health.retries.total_retries} icon={RotateCcw} color="text-orange-500" />
        <StatCard label="Throughput" value={`${health.throughput.requests_per_minute} rpm`} icon={BarChart3} color="text-indigo-500" />
        <StatCard label="P95 Latency" value={`${health.metrics.latency_p95_ms}ms`} icon={Clock} color="text-amber-500" />
      </div>
    </div>
  );
}

function MetricsPanel({ data }: { data: MetricsResponse }) {
  const agents = Object.values(data.agents) as AgentMetrics[];
  const maxCalls = Math.max(...agents.map(a => a.total_calls), 1);
  const maxTokens = Math.max(...agents.map(a => a.total_tokens), 1);
  const maxLatency = Math.max(...agents.map(a => a.avg_latency_ms), 1);

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-semibold text-text">Agent Metrics</h3>
      {agents.length === 0 ? (
        <p className="text-muted text-sm">No agent metrics recorded yet. Run a workflow to see data.</p>
      ) : (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="bg-white rounded-xl border border-border p-5 space-y-3">
              <h4 className="text-sm font-semibold text-muted uppercase tracking-wider">Calls per Agent</h4>
              {agents.map(a => (
                <BarSimple key={a.agent_name} label={a.agent_name} value={a.total_calls} max={maxCalls} />
              ))}
            </div>
            <div className="bg-white rounded-xl border border-border p-5 space-y-3">
              <h4 className="text-sm font-semibold text-muted uppercase tracking-wider">Tokens per Agent</h4>
              {agents.map(a => (
                <BarSimple key={a.agent_name} label={a.agent_name} value={a.total_tokens} max={maxTokens} color="bg-purple-500" />
              ))}
            </div>
            <div className="bg-white rounded-xl border border-border p-5 space-y-3">
              <h4 className="text-sm font-semibold text-muted uppercase tracking-wider">Avg Latency (ms)</h4>
              {agents.map(a => (
                <BarSimple key={a.agent_name} label={a.agent_name} value={a.avg_latency_ms} max={maxLatency} color="bg-blue-500" />
              ))}
            </div>
          </div>

          {/* Detailed table */}
          <div className="bg-white rounded-xl border border-border overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-gray-50">
                  <th className="text-left px-4 py-3 font-semibold text-muted">Agent</th>
                  <th className="text-right px-4 py-3 font-semibold text-muted">Calls</th>
                  <th className="text-right px-4 py-3 font-semibold text-muted">Failures</th>
                  <th className="text-right px-4 py-3 font-semibold text-muted">Retries</th>
                  <th className="text-right px-4 py-3 font-semibold text-muted">Tokens</th>
                  <th className="text-right px-4 py-3 font-semibold text-muted">Tool Calls</th>
                  <th className="text-right px-4 py-3 font-semibold text-muted">P50</th>
                  <th className="text-right px-4 py-3 font-semibold text-muted">P95</th>
                  <th className="text-right px-4 py-3 font-semibold text-muted">P99</th>
                </tr>
              </thead>
              <tbody>
                {agents.map(a => (
                  <tr key={a.agent_name} className="border-b border-border hover:bg-gray-50/60">
                    <td className="px-4 py-3 font-medium text-text">{a.agent_name}</td>
                    <td className="text-right px-4 py-3">{a.total_calls}</td>
                    <td className="text-right px-4 py-3">
                      <span className={a.total_failures > 0 ? 'text-red-600 font-semibold' : ''}>{a.total_failures}</span>
                    </td>
                    <td className="text-right px-4 py-3">{a.total_retries}</td>
                    <td className="text-right px-4 py-3">{a.total_tokens.toLocaleString()}</td>
                    <td className="text-right px-4 py-3">{a.total_tool_calls}</td>
                    <td className="text-right px-4 py-3">{a.p50_latency_ms}ms</td>
                    <td className="text-right px-4 py-3">{a.p95_latency_ms}ms</td>
                    <td className="text-right px-4 py-3">{a.p99_latency_ms}ms</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}

function TracesPanel({ traces }: { traces: Trace[] }) {
  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-text">Recent Traces</h3>
      {traces.length === 0 ? (
        <p className="text-muted text-sm">No traces recorded yet.</p>
      ) : (
        <div className="space-y-3">
          {traces.map(t => (
            <div key={t.trace_id} className="bg-white rounded-xl border border-border p-4">
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <span className={`w-2 h-2 rounded-full ${t.status === 'completed' ? 'bg-green-500' : t.status === 'running' ? 'bg-blue-500 animate-pulse' : 'bg-red-500'}`} />
                  <span className="text-sm font-mono text-muted">{t.trace_id.slice(0, 8)}...</span>
                  <span className="text-xs text-muted">{t.status}</span>
                </div>
                <span className="text-sm font-semibold text-text">{t.total_duration_ms.toLocaleString()}ms</span>
              </div>
              <p className="text-sm text-muted mb-3 truncate">{t.prompt}</p>
              {t.spans.length > 0 && (
                <div className="flex gap-1 flex-wrap">
                  {t.spans.map((s, i) => (
                    <span
                      key={i}
                      className={`text-xs px-2 py-1 rounded-full ${s.status === 'ok' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}
                      title={`${s.agent}: ${s.duration_ms}ms, ${s.tokens_prompt + s.tokens_completion} tokens`}
                    >
                      {s.agent} ({s.duration_ms}ms)
                    </span>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function CostsPanel({ summary, records }: { summary: CostSummary; records: CostRecord[] }) {
  const maxAgentCost = Math.max(...Object.values(summary.by_agent), 0.0001);
  const maxModelCost = Math.max(...Object.values(summary.by_model), 0.0001);

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-semibold text-text">Cost Analysis</h3>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard label="Total Cost" value={`$${summary.total_cost_usd.toFixed(4)}`} icon={DollarSign} color="text-green-600" />
        <StatCard label="Total Tokens" value={summary.total_tokens.toLocaleString()} icon={Zap} color="text-purple-500" />
        <StatCard label="Requests" value={summary.total_records} icon={Activity} />
        <StatCard label="Models Used" value={Object.keys(summary.by_model).length} icon={BarChart3} color="text-indigo-500" />
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl border border-border p-5 space-y-3">
          <h4 className="text-sm font-semibold text-muted uppercase tracking-wider">Cost by Agent</h4>
          {Object.entries(summary.by_agent).length === 0 ? (
            <p className="text-sm text-muted">No data yet</p>
          ) : (
            Object.entries(summary.by_agent).map(([name, cost]) => (
              <BarSimple key={name} label={name} value={cost} max={maxAgentCost} color="bg-green-500" />
            ))
          )}
        </div>
        <div className="bg-white rounded-xl border border-border p-5 space-y-3">
          <h4 className="text-sm font-semibold text-muted uppercase tracking-wider">Cost by Model</h4>
          {Object.entries(summary.by_model).length === 0 ? (
            <p className="text-sm text-muted">No data yet</p>
          ) : (
            Object.entries(summary.by_model).map(([name, cost]) => (
              <BarSimple key={name} label={name} value={cost} max={maxModelCost} color="bg-indigo-500" />
            ))
          )}
        </div>
      </div>
      {records.length > 0 && (
        <div className="bg-white rounded-xl border border-border overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border bg-gray-50">
                <th className="text-left px-4 py-3 font-semibold text-muted">Agent</th>
                <th className="text-left px-4 py-3 font-semibold text-muted">Model</th>
                <th className="text-right px-4 py-3 font-semibold text-muted">Prompt</th>
                <th className="text-right px-4 py-3 font-semibold text-muted">Completion</th>
                <th className="text-right px-4 py-3 font-semibold text-muted">Cost</th>
                <th className="text-right px-4 py-3 font-semibold text-muted">Time</th>
              </tr>
            </thead>
            <tbody>
              {records.slice(-20).reverse().map((r, i) => (
                <tr key={i} className="border-b border-border hover:bg-gray-50/60">
                  <td className="px-4 py-3 font-medium text-text">{r.agent}</td>
                  <td className="px-4 py-3 text-muted">{r.model}</td>
                  <td className="text-right px-4 py-3">{r.tokens_prompt.toLocaleString()}</td>
                  <td className="text-right px-4 py-3">{r.tokens_completion.toLocaleString()}</td>
                  <td className="text-right px-4 py-3 font-semibold">${r.cost_total.toFixed(4)}</td>
                  <td className="text-right px-4 py-3 text-muted text-xs">{new Date(r.timestamp).toLocaleTimeString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function RetriesPanel({ summary, entries }: { summary: RetrySummary; entries: RetryEntry[] }) {
  return (
    <div className="space-y-6">
      <h3 className="text-lg font-semibold text-text">Retry Analysis</h3>
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        <StatCard label="Total Retries" value={summary.total_retries} icon={RotateCcw} color="text-orange-500" />
        <StatCard label="Agents with Retries" value={Object.keys(summary.by_agent).length} icon={Activity} />
        <StatCard label="Retry Reasons" value={Object.keys(summary.by_reason).length} icon={AlertTriangle} color="text-yellow-500" />
      </div>
      {Object.entries(summary.by_reason).length > 0 && (
        <div className="bg-white rounded-xl border border-border p-5 space-y-3">
          <h4 className="text-sm font-semibold text-muted uppercase tracking-wider">Retries by Reason</h4>
          {Object.entries(summary.by_reason).map(([reason, count]) => (
            <div key={reason} className="flex justify-between text-sm">
              <span className="text-muted">{reason}</span>
              <span className="font-semibold text-text">{count}</span>
            </div>
          ))}
        </div>
      )}
      {entries.length > 0 && (
        <div className="bg-white rounded-xl border border-border overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border bg-gray-50">
                <th className="text-left px-4 py-3 font-semibold text-muted">Agent</th>
                <th className="text-right px-4 py-3 font-semibold text-muted">Attempt</th>
                <th className="text-right px-4 py-3 font-semibold text-muted">Max</th>
                <th className="text-right px-4 py-3 font-semibold text-muted">Delay</th>
                <th className="text-left px-4 py-3 font-semibold text-muted">Reason</th>
                <th className="text-right px-4 py-3 font-semibold text-muted">Time</th>
              </tr>
            </thead>
            <tbody>
              {entries.slice(-20).reverse().map((r, i) => (
                <tr key={i} className="border-b border-border hover:bg-gray-50/60">
                  <td className="px-4 py-3 font-medium text-text">{r.agent}</td>
                  <td className="text-right px-4 py-3">{r.attempt}</td>
                  <td className="text-right px-4 py-3">{r.max_attempts}</td>
                  <td className="text-right px-4 py-3">{r.delay_ms}ms</td>
                  <td className="px-4 py-3 text-muted truncate max-w-xs">{r.reason}</td>
                  <td className="text-right px-4 py-3 text-muted text-xs">{new Date(r.timestamp).toLocaleTimeString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function ThroughputPanel({ data }: { data: ThroughputSummary }) {
  return (
    <div className="space-y-6">
      <h3 className="text-lg font-semibold text-text">Throughput</h3>
      <div className="grid grid-cols-2 gap-4">
        <StatCard label="Requests/min" value={data.requests_per_minute} icon={Zap} color="text-indigo-500" />
        <StatCard label="Window" value={`${data.window_seconds}s`} icon={Clock} color="text-blue-500" />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main Page Component
// ---------------------------------------------------------------------------

const tabs: { id: ObservabilityTab; label: string; icon: React.ElementType }[] = [
  { id: 'health', label: 'Health', icon: Activity },
  { id: 'metrics', label: 'Metrics', icon: BarChart3 },
  { id: 'traces', label: 'Traces', icon: Eye },
  { id: 'costs', label: 'Costs', icon: DollarSign },
  { id: 'retries', label: 'Retries', icon: RotateCcw },
  { id: 'throughput', label: 'Throughput', icon: Zap },
];

export default function ObservabilityPage() {
  const {
    activeTab,
    setActiveTab,
    loading,
    error,
    health,
    metrics,
    traces,
    costSummary,
    costRecords,
    retrySummary,
    retryEntries,
    throughput,
    refresh,
    autoRefresh,
    setAutoRefresh,
  } = useObservability();

  return (
    <div className="flex-1 w-full max-w-7xl mx-auto p-6 space-y-6 pb-24 bg-surface">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary">
            Observability Dashboard
          </h2>
          <p className="text-muted text-sm mt-1">
            Agent metrics, traces, costs, retries, throughput &amp; health
          </p>
        </div>
        <div className="flex items-center gap-3">
          <label className="flex items-center gap-2 text-sm text-muted cursor-pointer">
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
              className="rounded border-border text-primary focus:ring-primary"
            />
            Auto-refresh (15s)
          </label>
          <button
            onClick={refresh}
            disabled={loading}
            className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            Refresh
          </button>
        </div>
      </div>

      {/* Error Banner */}
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-3 text-sm">
          {error}
        </div>
      )}

      {/* Tab Navigation */}
      <div className="flex gap-1 bg-gray-100 rounded-lg p-1">
        {tabs.map(tab => {
          const Icon = tab.icon;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-all ${
                activeTab === tab.id
                  ? 'bg-white text-primary shadow-sm'
                  : 'text-muted hover:text-text'
              }`}
            >
              <Icon className="w-4 h-4" />
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* Tab Content */}
      <div className="min-h-[400px]">
        {activeTab === 'health' && health && <HealthPanel health={health} />}
        {activeTab === 'metrics' && metrics && <MetricsPanel data={metrics} />}
        {activeTab === 'traces' && <TracesPanel traces={traces} />}
        {activeTab === 'costs' && costSummary && <CostsPanel summary={costSummary} records={costRecords} />}
        {activeTab === 'retries' && retrySummary && <RetriesPanel summary={retrySummary} entries={retryEntries} />}
        {activeTab === 'throughput' && throughput && <ThroughputPanel data={throughput} />}

        {loading && !health && !metrics && (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-8 h-8 text-primary animate-spin" />
            <span className="ml-3 text-muted">Loading observability data...</span>
          </div>
        )}
      </div>
    </div>
  );
}
