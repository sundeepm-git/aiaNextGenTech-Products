'use client';

import { useState, useRef, useEffect } from 'react';
import { Play, Loader2, CheckCircle2, AlertCircle, Copy, Terminal, RefreshCw } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useExportProgress } from '@/app/hooks/useExportProgress';

export default function MigrationPage() {
  const [subscriptionId, setSubscriptionId] = useState('');
  const [resourceGroup, setResourceGroup] = useState('');
  const [prompt, setPrompt] = useState('');
  const logsEndRef = useRef<HTMLDivElement>(null);

  const {
    jobId,
    status,
    logs,
    isRunning,
    error: exportError,
    startExport,
    clearLogs,
    reconnect,
  } = useExportProgress();

  const predefinedPrompt = "Migrate resource group 'rg-production' from subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2";

  // Auto-scroll logs to bottom
  useEffect(() => {
    if (logsEndRef.current) {
      logsEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs]);

  const handleMigrate = async () => {
    if (!subscriptionId.trim() || !resourceGroup.trim()) {
      return;
    }

    clearLogs();
    await startExport(subscriptionId, resourceGroup, prompt);
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
      <div>
        <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-2">
          Azure to Terraform Migration
        </h1>
        <p className="text-muted text-lg">
          Export Azure resources to Terraform configuration with real-time progress
        </p>
      </div>

      {/* Input Section */}
      <div className="bg-white rounded-xl border border-border p-6 space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-text mb-2">
              Subscription ID <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={subscriptionId}
              onChange={(e) => setSubscriptionId(e.target.value)}
              placeholder="d0f1884d-1f98-4bf1-9e15-e2986fc1bca2"
              className="w-full px-4 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent font-mono text-sm"
              disabled={isRunning}
            />
          </div>
          
          <div>
            <label className="block text-sm font-medium text-text mb-2">
              Resource Group <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={resourceGroup}
              onChange={(e) => setResourceGroup(e.target.value)}
              placeholder="rg-production"
              className="w-full px-4 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent font-mono text-sm"
              disabled={isRunning}
            />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-text mb-2">
            Additional Context (Optional)
          </label>
          <div className="relative">
            <textarea
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              placeholder={predefinedPrompt}
              className="w-full h-24 px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent resize-none font-mono text-sm"
              disabled={isRunning}
            />
            <button
              onClick={() => setPrompt(predefinedPrompt)}
              className="absolute top-2 right-2 p-2 text-muted hover:text-primary transition-colors"
              title="Use predefined prompt"
              disabled={isRunning}
            >
              <Copy className="w-4 h-4" />
            </button>
          </div>
        </div>

        <div className="flex items-center justify-between">
          <button
            onClick={handleMigrate}
            disabled={isRunning || !subscriptionId || !resourceGroup}
            className={cn(
              "flex items-center gap-2 px-6 py-3 rounded-lg font-medium transition-all duration-200",
              isRunning || !subscriptionId || !resourceGroup
                ? "bg-gray-300 text-gray-500 cursor-not-allowed"
                : "bg-gradient-to-r from-primary to-secondary text-white hover:shadow-lg"
            )}
          >
            {isRunning ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                Exporting...
              </>
            ) : (
              <>
                <Play className="w-5 h-5" />
                Start Export
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
      {exportError && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-red-600 mt-0.5 flex-shrink-0" />
          <div className="flex-1">
            <h3 className="font-semibold text-red-900">Export Error</h3>
            <p className="text-red-700 text-sm mt-1">{exportError}</p>
          </div>
        </div>
      )}

      {/* Real-time Progress Logs */}
      {logs.length > 0 && (
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Terminal className="w-5 h-5 text-primary" />
            <h2 className="text-xl font-bold text-text">Export Progress</h2>
          </div>

          <div className="bg-gray-900 rounded-xl border border-gray-700 p-4 max-h-[500px] overflow-auto">
            <div className="space-y-1 font-mono text-xs">
              {logs.map((log, index) => (
                <div key={index} className="flex items-start gap-2">
                  <span className="text-gray-500 select-none">
                    {new Date(log.timestamp).toLocaleTimeString()}
                  </span>
                  <span className={cn("flex-1", getLogColor(log.type))}>
                    {log.message}
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
