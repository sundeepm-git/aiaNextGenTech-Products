'use client';

import { useState, useRef, useEffect, useMemo } from 'react';
import { Play, Loader2, CheckCircle2, AlertCircle, Copy, Terminal, RefreshCw, Zap, Bot, Send } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useExportProgress } from '@/app/hooks/useExportProgress';
import { useAgenticWorkflow } from '@/app/hooks/useAgenticWorkflow';
import { maskSensitiveValues } from '@/app/services/maskService';

export default function MigrationPage() {
  const [subscriptionId, setSubscriptionId] = useState('');
  const [resourceGroup, setResourceGroup] = useState('');
  const [prompt, setPrompt] = useState('');
  const [agenticMode, setAgenticMode] = useState(false);
  const logsEndRef = useRef<HTMLDivElement>(null);

  // Standard export hook
  const {
    jobId: exportJobId,
    status: exportStatus,
    logs: exportLogs,
    isRunning: exportIsRunning,
    error: exportError,
    startExport,
    clearLogs: clearExportLogs,
    reconnect: reconnectExport,
  } = useExportProgress();

  // Agentic workflow hook
  const {
    jobId: workflowJobId,
    status: workflowStatus,
    currentAgent,
    progress: workflowProgress,
    logs: workflowLogs,
    isRunning: workflowIsRunning,
    error: workflowError,
    startWorkflow,
    clearLogs: clearWorkflowLogs,
    reconnect: reconnectWorkflow,
  } = useAgenticWorkflow();

  // Unified accessors based on active mode
  const jobId = agenticMode ? workflowJobId : exportJobId;
  const status = agenticMode ? workflowStatus : exportStatus;
  const logs = agenticMode ? workflowLogs : exportLogs;
  const isRunning = agenticMode ? workflowIsRunning : exportIsRunning;
  const activeError = agenticMode ? workflowError : exportError;
  const clearLogs = agenticMode ? clearWorkflowLogs : clearExportLogs;
  const reconnect = agenticMode ? reconnectWorkflow : reconnectExport;

  const predefinedPrompt = "Migrate resource group 'rg-mcp-servers' from subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2";

  // Auto-scroll logs to bottom
  useEffect(() => {
    if (logsEndRef.current) {
      logsEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs]);

  const handleMigrate = async () => {
    if (agenticMode) {
      if (!prompt.trim()) return;
      clearLogs();
      await startWorkflow(prompt);
    } else {
      if (!subscriptionId.trim() || !resourceGroup.trim()) return;
      clearLogs();
      await startExport(subscriptionId, resourceGroup, prompt);
    }
  };

  const getStatusBadge = () => {
    switch (status) {
      case 'connected':
        return (
          <div className="flex items-center gap-2 px-3 py-1 bg-green-50 border border-green-200 text-green-700 rounded-full text-xs font-medium">
            <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse" />
            Connected
          </div>
        );
      case 'connecting':
        return (
          <div className="flex items-center gap-2 px-3 py-1 bg-yellow-50 border border-yellow-200 text-yellow-700 rounded-full text-xs font-medium">
            <Loader2 className="w-3 h-3 animate-spin" />
            Connecting...
          </div>
        );
      case 'completed':
        return (
          <div className="flex items-center gap-2 px-3 py-1 bg-blue-50 border border-blue-200 text-blue-700 rounded-full text-xs font-medium">
            <CheckCircle2 className="w-3 h-3" />
            Completed
          </div>
        );
      case 'error':
        return (
          <div className="flex items-center gap-2 px-3 py-1 bg-red-50 border border-red-200 text-red-700 rounded-full text-xs font-medium">
            <AlertCircle className="w-3 h-3" />
            Error
          </div>
        );
      case 'disconnected':
        return (
          <div className="flex items-center gap-2 px-3 py-1 bg-gray-50 border border-gray-200 text-gray-700 rounded-full text-xs font-medium">
            <AlertCircle className="w-3 h-3" />
            Disconnected
          </div>
        );
      default:
        return (
          <div className="flex items-center gap-2 px-3 py-1 bg-gray-50 border border-gray-200 text-gray-700 rounded-full text-xs font-medium">
            Idle
          </div>
        );
    }
  };

  const getLogColor = (type: string) => {
    switch (type) {
      case 'stdout':
        return 'text-cyan-600';
      case 'stderr':
        return 'text-red-600';
      case 'success':
        return 'text-green-600';
      case 'error':
        return 'text-red-700 font-semibold';
      case 'info':
        return 'text-blue-600';
      default:
        return 'text-gray-700';
    }
  };

  return (
    <div className="flex-1 p-8 space-y-8 overflow-auto">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-2">
            Azure to Terraform Migration
          </h1>
          <p className="text-muted text-lg">
            Export Azure resources to Terraform configuration with real-time progress
          </p>
        </div>

        {/* Agentic Mode Toggle */}
        <button
          onClick={() => setAgenticMode((prev) => !prev)}
          disabled={isRunning}
          className={cn(
            'flex items-center gap-2 px-4 py-2 rounded-full text-sm font-medium border transition-all',
            agenticMode
              ? 'bg-purple-50 border-purple-300 text-purple-700'
              : 'bg-gray-50 border-gray-200 text-gray-600 hover:border-gray-300',
            isRunning && 'opacity-50 cursor-not-allowed',
          )}
        >
          {agenticMode ? <Bot className="w-4 h-4" /> : <Zap className="w-4 h-4" />}
          {agenticMode ? 'Agentic Mode' : 'Standard Export'}
        </button>
      </div>

      {/* Agent Progress Bar (agentic mode only) */}
      {agenticMode && workflowIsRunning && (
        <div className="bg-white rounded-xl border border-border p-4 space-y-3">
          <div className="flex items-center justify-between text-sm">
            <span className="font-medium text-text">Pipeline Progress</span>
            <span className="text-muted">{workflowProgress}%</span>
          </div>
          <div className="w-full h-2 bg-gray-100 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-purple-500 to-blue-500 rounded-full transition-all duration-700"
              style={{ width: `${workflowProgress}%` }}
            />
          </div>
          <div className="flex items-center gap-3">
            {['Orchestrator', 'Assessment', 'Export', 'Refactor'].map((step) => {
              const isActive = currentAgent === step;
              const isDone =
                workflowProgress >=
                ({ Orchestrator: 25, Assessment: 50, Export: 75, Refactor: 100 }[step] ?? 100);
              return (
                <div
                  key={step}
                  className={cn(
                    'flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border',
                    isActive
                      ? 'bg-purple-50 border-purple-300 text-purple-700 animate-pulse'
                      : isDone
                        ? 'bg-green-50 border-green-200 text-green-700'
                        : 'bg-gray-50 border-gray-200 text-gray-400',
                  )}
                >
                  {isDone && !isActive ? (
                    <CheckCircle2 className="w-3 h-3" />
                  ) : isActive ? (
                    <Loader2 className="w-3 h-3 animate-spin" />
                  ) : null}
                  {step}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Input Section */}
      <div className="bg-white rounded-xl border border-border p-6 space-y-4">
        {/* Standard Export Mode — structured fields */}
        {!agenticMode && (
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-text mb-2">
                Subscription ID <span className="text-red-500">*</span>
              </label>
              <div className="relative">
                <div className="absolute inset-0 flex items-center px-4 pointer-events-none z-10 font-mono text-sm">
                  {subscriptionId ? maskSensitiveValues(subscriptionId) : <span className="text-gray-400">Enter subscription ID</span>}
                </div>
                <input
                  type="text"
                  value={subscriptionId}
                  onChange={(e) => setSubscriptionId(e.target.value)}
                  placeholder=""
                  className="w-full px-4 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent font-mono text-sm text-transparent caret-black bg-transparent relative z-20"
                  disabled={isRunning}
                />
              </div>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-text mb-2">
                Resource Group <span className="text-red-500">*</span>
              </label>
              <div className="relative">
                <div className="absolute inset-0 flex items-center px-4 pointer-events-none z-10 font-mono text-sm">
                  {resourceGroup ? maskSensitiveValues(resourceGroup) : <span className="text-gray-400">rg-production</span>}
                </div>
                <input
                  type="text"
                  value={resourceGroup}
                  onChange={(e) => setResourceGroup(e.target.value)}
                  placeholder=""
                  className="w-full px-4 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent font-mono text-sm text-transparent caret-black bg-transparent relative z-20"
                  disabled={isRunning}
                />
              </div>
            </div>
          </div>
        )}

        {/* Agentic Mode — NLP prompt with help text */}
        {agenticMode && (
          <div className="bg-purple-50 border border-purple-200 rounded-lg p-4 mb-2">
            <div className="flex items-start gap-2 mb-2">
              <Bot className="w-4 h-4 text-purple-600 mt-0.5" />
              <div className="text-sm text-purple-800">
                <p className="font-medium mb-1">How to use Agentic Mode</p>
                <p>Describe your migration in natural language. Include the <strong>Azure Subscription ID</strong> (UUID) and <strong>Resource Group</strong> name in your prompt. The AI Orchestrator will extract and validate the parameters automatically.</p>
              </div>
            </div>
          </div>
        )}

        <div>
          <label className="block text-sm font-medium text-text mb-2">
            {agenticMode ? (
              <>Migration Prompt <span className="text-red-500">*</span></>
            ) : (
              'Additional Context (Optional)'
            )}
          </label>
          <div className="relative">
            {/* Masked overlay */}
            <div className={cn(
              "absolute inset-0 px-4 py-3 pr-14 pointer-events-none z-10 text-sm whitespace-pre-wrap break-words overflow-hidden",
              agenticMode ? "h-44" : "h-24"
            )}>
              {prompt ? maskSensitiveValues(prompt) : <span className="text-gray-400">{agenticMode
                ? "Describe your migration. Include subscription ID and resource group.\nPress Ctrl+Enter or click the Send button to start the pipeline."
                : maskSensitiveValues(predefinedPrompt)}</span>}
            </div>
            <textarea
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
                  e.preventDefault();
                  handleMigrate();
                }
              }}
              placeholder=""
              className={cn(
                "w-full px-4 py-3 pr-14 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent resize-none text-sm text-transparent caret-black bg-transparent relative z-20",
                agenticMode ? "h-44" : "h-24"
              )}
              disabled={isRunning}
            />
            {/* Copy example prompt button */}
            <button
              onClick={() => setPrompt(predefinedPrompt)}
              className="absolute top-2 right-2 p-2 text-muted hover:text-primary transition-colors"
              title="Paste example prompt"
              disabled={isRunning}
            >
              <Copy className="w-4 h-4" />
            </button>
            {/* Inline Send button (agentic mode only) */}
            {agenticMode && (
              <button
                onClick={handleMigrate}
                disabled={isRunning || !prompt.trim()}
                className={cn(
                  "absolute bottom-3 right-3 p-2.5 rounded-lg transition-all duration-200",
                  isRunning || !prompt.trim()
                    ? "bg-gray-200 text-gray-400 cursor-not-allowed"
                    : "bg-gradient-to-r from-primary to-secondary text-white hover:shadow-lg hover:scale-105"
                )}
                title="Start Agentic Pipeline (Ctrl+Enter)"
              >
                {isRunning ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : (
                  <Send className="w-5 h-5" />
                )}
              </button>
            )}
          </div>
        </div>

        <div className="flex items-center justify-between">
          <button
            onClick={handleMigrate}
            disabled={isRunning || (agenticMode ? !prompt.trim() : (!subscriptionId || !resourceGroup))}
            className={cn(
              "flex items-center gap-2 px-6 py-3 rounded-lg font-medium transition-all duration-200",
              isRunning || (agenticMode ? !prompt.trim() : (!subscriptionId || !resourceGroup))
                ? "bg-gray-300 text-gray-500 cursor-not-allowed"
                : "bg-gradient-to-r from-primary to-secondary text-white hover:shadow-lg"
            )}
          >
            {isRunning ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                {agenticMode ? 'Running Pipeline...' : 'Exporting...'}
              </>
            ) : (
              <>
                {agenticMode ? <Bot className="w-5 h-5" /> : <Play className="w-5 h-5" />}
                {agenticMode ? 'Start Agentic Pipeline' : 'Start Export'}
              </>
            )}
          </button>

          {status === 'disconnected' && jobId && (
            <button
              onClick={reconnect}
              className="flex items-center gap-2 px-4 py-2 border border-primary text-primary rounded-lg hover:bg-primary/5 transition-colors"
            >
              <RefreshCw className="w-4 h-4" />
              Reconnect
            </button>
          )}
        </div>
      </div>

      {/* Status Bar */}
      {jobId && (
        <div className="bg-white rounded-xl border border-border p-4">
          <div className="flex items-center justify-between">
            <div className="space-y-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium text-text">Job Status:</span>
                {getStatusBadge()}
              </div>
              <p className="text-xs text-muted font-mono">Job ID: {jobId}</p>
            </div>
            <button
              onClick={clearLogs}
              className="text-sm text-muted hover:text-primary transition-colors"
            >
              Clear Logs
            </button>
          </div>
        </div>
      )}

      {/* Error Display */}
      {activeError && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-red-600 mt-0.5 flex-shrink-0" />
          <div className="flex-1">
            <h3 className="font-semibold text-red-900">{agenticMode ? 'Workflow Error' : 'Export Error'}</h3>
            <p className="text-red-700 text-sm mt-1">{activeError}</p>
          </div>
        </div>
      )}

      {/* Real-time Progress Logs */}
      {logs.length > 0 && (
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Terminal className="w-5 h-5 text-primary" />
            <h2 className="text-xl font-bold text-text">{agenticMode ? 'Workflow Progress' : 'Export Progress'}</h2>
          </div>

          <div className="bg-gray-900 rounded-xl border border-gray-700 p-4 max-h-[500px] overflow-auto">
            <div className="space-y-1 font-mono text-xs">
              {logs.map((log, index) => (
                <div key={index} className="flex items-start gap-2">
                  <span className="text-gray-500 select-none">
                    {new Date(log.timestamp).toLocaleTimeString()}
                  </span>
                  {'agent' in log && log.agent && (
                    <span className="text-purple-400 font-semibold select-none">[{log.agent}]</span>
                  )}
                  <span className={cn("flex-1", getLogColor(log.type))}>
                    {maskSensitiveValues(log.message)}
                  </span>
                </div>
              ))}
              <div ref={logsEndRef} />
            </div>
          </div>
        </div>
      )}

      {/* Completion Message */}
      {status === 'completed' && (
        <div className="bg-gradient-to-br from-green-50 to-blue-50 rounded-xl border border-green-200 p-6">
          <div className="flex items-start gap-3">
            <CheckCircle2 className="w-6 h-6 text-green-600 mt-0.5 flex-shrink-0" />
            <div className="flex-1">
              <h3 className="text-lg font-bold text-green-900 mb-2">Export Completed Successfully!</h3>
              <div className="space-y-2 text-sm text-gray-700">
                <p>
                  ✅ Azure resources have been successfully exported to Terraform configuration
                </p>
                <div className="bg-white/50 rounded-lg p-3 font-mono text-xs">
                  <p className="text-gray-600">Storage Path:</p>
                  <p className="text-primary font-semibold mt-1">
                    aztfExport/{subscriptionId}/{resourceGroup}/
                  </p>
                </div>
                <p className="text-xs text-gray-600 mt-2">
                  Files include: main.tf, variables.tf, providers.tf, terraform.tfstate, and HTML report
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
