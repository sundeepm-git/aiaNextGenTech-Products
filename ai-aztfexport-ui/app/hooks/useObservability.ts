'use client';

import { useState, useCallback, useEffect, useRef } from 'react';
import {
  fetchMetrics,
  fetchTraces,
  fetchCosts,
  fetchRetries,
  fetchThroughput,
  fetchHealthSummary,
} from '@/app/services/observabilityService';
import type {
  MetricsResponse,
  Trace,
  CostSummary,
  CostRecord,
  RetrySummary,
  RetryEntry,
  ThroughputSummary,
  HealthSummary,
} from '@/app/services/observabilityService';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ObservabilityTab = 'health' | 'metrics' | 'traces' | 'costs' | 'retries' | 'throughput';

export interface UseObservabilityReturn {
  activeTab: ObservabilityTab;
  setActiveTab: (tab: ObservabilityTab) => void;
  loading: boolean;
  error: string | null;
  health: HealthSummary | null;
  metrics: MetricsResponse | null;
  traces: Trace[];
  costSummary: CostSummary | null;
  costRecords: CostRecord[];
  retrySummary: RetrySummary | null;
  retryEntries: RetryEntry[];
  throughput: ThroughputSummary | null;
  refresh: () => Promise<void>;
  autoRefresh: boolean;
  setAutoRefresh: (v: boolean) => void;
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export const useObservability = (): UseObservabilityReturn => {
  const [activeTab, setActiveTab] = useState<ObservabilityTab>('health');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [health, setHealth] = useState<HealthSummary | null>(null);
  const [metrics, setMetrics] = useState<MetricsResponse | null>(null);
  const [traces, setTraces] = useState<Trace[]>([]);
  const [costSummary, setCostSummary] = useState<CostSummary | null>(null);
  const [costRecords, setCostRecords] = useState<CostRecord[]>([]);
  const [retrySummary, setRetrySummary] = useState<RetrySummary | null>(null);
  const [retryEntries, setRetryEntries] = useState<RetryEntry[]>([]);
  const [throughput, setThroughput] = useState<ThroughputSummary | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [h, m, t, c, r, tp] = await Promise.all([
        fetchHealthSummary(),
        fetchMetrics(),
        fetchTraces(50),
        fetchCosts(100),
        fetchRetries(100),
        fetchThroughput(),
      ]);
      setHealth(h);
      setMetrics(m);
      setTraces(t.traces);
      setCostSummary(c.summary);
      setCostRecords(c.records);
      setRetrySummary(r.summary);
      setRetryEntries(r.retries);
      setThroughput(tp);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to fetch observability data';
      setError(msg);
    } finally {
      setLoading(false);
    }
  }, []);

  // Initial load
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Auto-refresh every 15 seconds
  useEffect(() => {
    if (autoRefresh) {
      intervalRef.current = setInterval(refresh, 15000);
    }
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [autoRefresh, refresh]);

  return {
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
  };
};
