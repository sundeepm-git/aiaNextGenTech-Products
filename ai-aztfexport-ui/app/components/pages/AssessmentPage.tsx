'use client';

import { useState, useRef, useEffect } from 'react';
import { ArrowRight, Sparkles, Loader2, CheckCircle2, AlertCircle, Download } from 'lucide-react';
import { cn } from '@/lib/utils';
import { config } from '@/app/services/config';

interface LogEntry {
  level: string;
  message: string;
  agent?: string;
  timestamp: string;
}

// Regex to extract subscription ID (UUID) and resource group from free-text prompt
const SUB_RE = /(?:subscription\s*(?:id)?[:\-–]?\s*)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;
const SUB_RE_BARE = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;
const RG_RE = /(?:resource\s*group\s*[:\-–]?\s*)([^\s,]+)/i;

function extractParams(prompt: string): { subscriptionId: string | null; resourceGroup: string | null } {
  const subMatch = prompt.match(SUB_RE) || prompt.match(SUB_RE_BARE);
  const rgMatch = prompt.match(RG_RE);
  return {
    subscriptionId: subMatch ? subMatch[1] : null,
    resourceGroup: rgMatch ? rgMatch[1] : null,
  };
}

const SUGGESTIONS = [
  { label: "🔍 Assess Default", value: "Assess subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 and resource group rg-mcp-servers" },
  { label: "Assess Infra RG", value: "Run assessment for subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 resource group rg-genai-infra-0014" },
];

export default function AssessmentPage() {
  const [input, setInput] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const [jobId, setJobId] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [extractedSub, setExtractedSub] = useState<string | null>(null);
  const [extractedRg, setExtractedRg] = useState<string | null>(null);
  const logEndRef = useRef<HTMLDivElement>(null);
  const eventSourceRef = useRef<EventSource | null>(null);

  // Auto-scroll logs
  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [logs]);

  // Cleanup SSE on unmount
  useEffect(() => {
    return () => {
      eventSourceRef.current?.close();
    };
  }, []);

  const handleSubmit = async (e?: React.FormEvent) => {
    e?.preventDefault();
    if (!input.trim() || isRunning) return;

    const { subscriptionId, resourceGroup } = extractParams(input);

    // Validate both are present
    const missing: string[] = [];
    if (!subscriptionId) missing.push('Subscription ID');
    if (!resourceGroup) missing.push('Resource Group');
    if (missing.length > 0) {
      setError(`${missing.join(' and ')} is missing from your prompt. Please include both a subscription ID (UUID) and resource group name.\n\nExample: "Assess subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 and resource group rg-mcp-servers"`);
      return;
    }

    setExtractedSub(subscriptionId);
    setExtractedRg(resourceGroup);
    setIsRunning(true);
    setError(null);
    setLogs([]);
    setStatus(null);
    setJobId(null);

    try {
      const res = await fetch(config.assessment.endpoints.start, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ subscriptionId, resourceGroup }),
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.detail || `API error: ${res.status}`);
      }

      const data = await res.json();
      const newJobId = data.jobId;
      setJobId(newJobId);
      setStatus('running');

      // Connect to SSE for real-time logs
      const es = new EventSource(config.assessment.endpoints.jobProgress(newJobId));
      eventSourceRef.current = es;

      es.addEventListener('log', (e) => {
        const entry: LogEntry = JSON.parse(e.data);
        setLogs((prev) => [...prev, entry]);
      });

      es.addEventListener('status', (e) => {
        const d = JSON.parse(e.data);
        setStatus(d.status);
      });

      es.addEventListener('complete', (e) => {
        const d = JSON.parse(e.data);
        setStatus(d.status);
        if (d.error) setError(d.error);
        setIsRunning(false);
        es.close();
      });

      es.onerror = () => {
        fetch(config.assessment.endpoints.jobStatus(newJobId))
          .then((r) => r.json())
          .then((d) => {
            setStatus(d.status);
            if (d.status === 'failed') setError(d.error || 'Assessment failed');
          })
          .catch(() => setError('Lost connection to server'));
        setIsRunning(false);
        es.close();
      };
    } catch (err: any) {
      setError(err.message || 'Failed to start assessment');
      setIsRunning(false);
    }
  };

  const handleDownloadReport = async () => {
    if (!jobId || !extractedSub || !extractedRg) return;
    const url = config.assessment.endpoints.report(jobId, extractedSub, extractedRg);
    window.open(url, '_blank');
  };

  return (
    <div className="flex-1 p-8 space-y-8 overflow-auto">
      {/* Header */}
      <div className="text-center">
        <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-2">
          Azure Subscription Assessment
        </h1>
        <p className="text-muted text-lg max-w-2xl mx-auto">
          Runs the assessment for your subscription and resource group to classify resources, check Terraform migration readiness, and generate a downloadable HTML report.
        </p>
      </div>

      {/* Prompt Input — same style as FoundryCommandCenter */}
      <div className="w-full max-w-4xl mx-auto space-y-6">
        <div className="relative group">
          <div className="absolute -inset-0.5 bg-gradient-to-r from-primary to-secondary rounded-lg blur opacity-30 group-hover:opacity-75 transition duration-1000 group-hover:duration-200"></div>
          <form onSubmit={handleSubmit} className="relative bg-white/80 backdrop-blur-md rounded-lg p-4 border border-sky-100 shadow-xl shadow-sky-100/50">
            <div className="relative">
              <textarea
                value={input}
                onChange={(e) => { setInput(e.target.value); setError(null); }}
                onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSubmit(); } }}
                disabled={isRunning}
                placeholder="Describe your assessment task, e.g. Assess subscription d0f1884d-... and resource group rg-mcp-servers"
                className="w-full h-32 px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent resize-none font-mono text-sm"
              />
            </div>
            <div className="flex items-center justify-between mt-3">
              <p className="text-xs text-muted">Press Enter to submit, Shift+Enter for new line</p>
              <button
                type="submit"
                disabled={!input.trim() || isRunning}
                className="px-6 py-2.5 bg-gradient-to-r from-primary to-secondary text-white rounded-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed hover:shadow-lg flex items-center gap-2 font-medium"
              >
                {isRunning ? (
                  <><Sparkles className="w-4 h-4 animate-spin" /> Running...</>
                ) : (
                  <><ArrowRight className="w-4 h-4" /> Run Assessment</>
                )}
              </button>
            </div>
          </form>
        </div>

        {/* Help Text */}
        <div className="bg-primary/5 border border-primary/20 rounded-lg p-4">
          <p className="text-xs text-muted font-semibold mb-2">💡 Prompt Help:</p>
          <p className="text-sm text-text font-mono">
            Assess subscription - &lt;subscriptionId&gt; and resource group &lt;resourceGroupName&gt;
          </p>
          <p className="text-sm text-text font-mono mt-1">
            Run assessment for subscription &lt;subscriptionId&gt; resource group &lt;resourceGroupName&gt;
          </p>
          <p className="text-xs text-muted mt-3">
            The prompt must include both a <strong>Subscription ID</strong> (UUID) and a <strong>Resource Group</strong> name.
            Once the assessment completes, the HTML report is uploaded to Azure Blob Storage and can be downloaded below.
          </p>
        </div>

        {/* Suggestion Chips */}
        {!isRunning && !status && (
          <div className="flex flex-wrap gap-2 justify-center">
            {SUGGESTIONS.map((sug, i) => (
              <button
                key={i}
                onClick={() => setInput(sug.value)}
                className="px-3 py-1.5 rounded-full bg-white border border-sky-200 text-sm text-slate-600 hover:text-primary hover:border-primary/50 hover:shadow-md transition-all shadow-sm"
              >
                {sug.label}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Error */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3 max-w-4xl mx-auto">
          <AlertCircle className="w-5 h-5 text-red-600 mt-0.5 flex-shrink-0" />
          <div>
            <h3 className="font-semibold text-red-900">Error</h3>
            <p className="text-red-700 text-sm whitespace-pre-line">{error}</p>
          </div>
        </div>
      )}

      {/* Live Logs */}
      {logs.length > 0 && (
        <div className="bg-gray-900 rounded-xl border border-gray-700 overflow-hidden">
          <div className="flex items-center justify-between px-4 py-2 bg-gray-800 border-b border-gray-700">
            <span className="text-sm font-medium text-gray-300">
              Assessment Logs {isRunning && <Loader2 className="inline w-3 h-3 animate-spin ml-2" />}
            </span>
            <span className={cn(
              "text-xs font-mono px-2 py-0.5 rounded",
              status === 'completed' ? 'bg-green-900 text-green-300' :
              status === 'failed' ? 'bg-red-900 text-red-300' :
              'bg-yellow-900 text-yellow-300'
            )}>
              {status}
            </span>
          </div>
          <div className="p-4 max-h-80 overflow-y-auto font-mono text-xs space-y-1">
            {logs.map((log, i) => (
              <div key={i} className={cn(
                log.level === 'error' ? 'text-red-400' :
                log.level === 'success' ? 'text-green-400' :
                log.level === 'warn' ? 'text-yellow-400' :
                'text-gray-300'
              )}>
                <span className="text-gray-500">[{new Date(log.timestamp).toLocaleTimeString()}]</span>{' '}
                {log.agent && <span className="text-cyan-400">[{log.agent}]</span>}{' '}
                {log.message}
              </div>
            ))}
            <div ref={logEndRef} />
          </div>
        </div>
      )}

      {/* Download Report */}
      {status === 'completed' && jobId && (
        <div className="bg-gradient-to-br from-green-50 to-emerald-50 border border-green-200 rounded-xl p-6 space-y-3">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-6 h-6 text-green-600" />
            <h2 className="text-xl font-bold text-green-900">Assessment Complete</h2>
          </div>
          <p className="text-green-800 text-sm">
            HTML report generated and uploaded to Azure Blob Storage:
            <span className="font-mono block mt-1 text-xs">
              assessment-reports/{extractedSub}/Assessment-Report-Latest.html
            </span>
          </p>
          <button
            onClick={handleDownloadReport}
            className="flex items-center gap-2 px-5 py-2.5 bg-green-600 text-white rounded-lg font-medium hover:bg-green-700 transition-colors"
          >
            <Download className="w-4 h-4" />
            Download HTML Report
          </button>
        </div>
      )}
    </div>
  );
}
