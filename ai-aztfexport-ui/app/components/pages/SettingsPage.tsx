'use client';

import { useState, useEffect, useRef } from 'react';
import {
  CheckCircle2, XCircle, AlertCircle, RefreshCw, Terminal, Cloud, Database, FileCode,
  Rocket, ExternalLink, Copy, Server, Globe, HardDrive, Eye, EyeOff, Download, Trash2,
  Pencil, Save, X
} from 'lucide-react';
import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';
import { useDeployment } from '@/app/hooks/useDeployment';

interface EnvironmentCheck {
  name: string;
  description: string;
  status: 'checking' | 'success' | 'error' | 'warning';
  message?: string;
  icon: any;
}

export default function SettingsPage() {
  const [isChecking, setIsChecking] = useState(false);
  const [checks, setChecks] = useState<EnvironmentCheck[]>([
    { name: 'Azure CLI', description: 'Azure Command-Line Interface for resource management', status: 'checking', icon: Cloud },
    { name: 'Terraform', description: 'Infrastructure as Code tool for Azure resources', status: 'checking', icon: FileCode },
    { name: 'aztfexport', description: 'Tool for exporting Azure resources to Terraform', status: 'checking', icon: Terminal },
    { name: 'Azure Storage', description: 'Storage account for migration artifacts', status: 'checking', icon: Database },
  ]);
  const [showSecrets, setShowSecrets] = useState(false);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const [editingUrls, setEditingUrls] = useState(false);
  const [urlDraft, setUrlDraft] = useState<Record<string, string>>({});
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');

  const {
    jobId, status, progress, logs, isRunning, error, deployUrls,
    envSettings, envLoading, envSaving, startDeployment, clearLogs, loadEnvSettings, saveServiceUrls,
  } = useDeployment();

  const scrollRef = useRef<HTMLDivElement>(null);

  // Detect if running from Azure Container Apps (not local)
  const isContainerApp = typeof window !== 'undefined' && window.location.hostname.includes('azurecontainerapps.io');

  // Get UI runtime configuration
  const [runtimeConfig, setRuntimeConfig] = useState<{
    mcpServerUrl: string;
    workflowApiUrl: string;
    environment: 'local' | 'azure';
  } | null>(null);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      setRuntimeConfig({
        mcpServerUrl: process.env.NEXT_PUBLIC_MCP_SERVER_URL || 'not configured',
        workflowApiUrl: process.env.NEXT_PUBLIC_WORKFLOW_API_URL || 'not configured',
        environment: window.location.hostname.includes('azurecontainerapps.io') ? 'azure' : 'local',
      });
    }
  }, []);

  // Auto-scroll deployment logs
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs]);

  // Load env settings on mount
  useEffect(() => {
    loadEnvSettings();
  }, [loadEnvSettings]);

  const runEnvironmentCheck = async () => {
    setIsChecking(true);
    const updatedChecks = [...checks];
    for (let i = 0; i < updatedChecks.length; i++) {
      await new Promise(resolve => setTimeout(resolve, 800));
      const randomStatus = Math.random();
      if (randomStatus > 0.7) {
        updatedChecks[i] = { ...updatedChecks[i], status: 'success', message: 'Installed and configured correctly' };
      } else if (randomStatus > 0.4) {
        updatedChecks[i] = { ...updatedChecks[i], status: 'warning', message: 'Installed but configuration may need updates' };
      } else {
        updatedChecks[i] = { ...updatedChecks[i], status: 'error', message: 'Not found or not configured' };
      }
      setChecks([...updatedChecks]);
    }
    setIsChecking(false);
  };

  useEffect(() => {
    runEnvironmentCheck();
  }, []);

  const getStatusIcon = (s: string) => {
    switch (s) {
      case 'success': return <CheckCircle2 className="w-6 h-6 text-green-600" />;
      case 'error': return <XCircle className="w-6 h-6 text-red-600" />;
      case 'warning': return <AlertCircle className="w-6 h-6 text-yellow-600" />;
      case 'checking': return <RefreshCw className="w-6 h-6 text-blue-600 animate-spin" />;
      default: return null;
    }
  };

  const copyToClipboard = (key: string, value: string) => {
    navigator.clipboard.writeText(value);
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const handleDownloadLogs = () => {
    const text = logs.map(l => `[${l.timestamp}] [${l.type.toUpperCase()}] ${l.message}`).join('\n');
    const blob = new Blob([text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `deploy-logs-${new Date().toISOString()}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const formatLogColor = (text: string, type: string) => {
    const colorClass = {
      error: 'text-red-500',
      success: 'text-green-500',
      warn: 'text-yellow-500',
      info: 'text-blue-400',
    }[type] || 'text-slate-600';
    return colorClass;
  };

  const successCount = checks.filter(c => c.status === 'success').length;
  const errorCount = checks.filter(c => c.status === 'error').length;
  const warningCount = checks.filter(c => c.status === 'warning').length;

  return (
    <div className="flex-1 p-8 space-y-8 overflow-auto bg-gray-50">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-2">
          Environment Settings
        </h1>
        <p className="text-muted text-lg">
          Deploy, monitor, and configure your Azure infrastructure
        </p>
      </div>

      {/* ================================================================ */}
      {/* SECTION 0: UI RUNTIME CONFIGURATION (Current Environment) */}
      {/* ================================================================ */}
      {runtimeConfig && (
        <div className="bg-gradient-to-br from-blue-50 to-purple-50 rounded-xl border-2 border-blue-200 p-6 shadow-lg">
          <div className="flex items-center gap-3 mb-4">
            <div className="p-2 bg-white rounded-lg shadow-sm">
              <Globe className="w-6 h-6 text-blue-600" />
            </div>
            <div className="flex-1">
              <h2 className="text-xl font-bold text-blue-900">UI Runtime Configuration</h2>
              <p className="text-sm text-blue-700">URLs this UI instance is currently using</p>
            </div>
            <div className={cn(
              "px-4 py-2 rounded-full text-xs font-bold uppercase tracking-wider",
              runtimeConfig.environment === 'azure'
                ? "bg-green-100 text-green-700 border border-green-300"
                : "bg-yellow-100 text-yellow-700 border border-yellow-300"
            )}>
              {runtimeConfig.environment === 'azure' ? '☁️ Azure Production' : '💻 Local Development'}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* MCP Server URL */}
            <div className="bg-white rounded-lg border border-blue-200 p-4 shadow-sm">
              <div className="flex items-center gap-2 mb-2">
                <HardDrive className="w-4 h-4 text-purple-600" />
                <span className="text-xs font-bold text-purple-900 uppercase tracking-wider">MCP Server URL</span>
              </div>
              <div className="flex items-center gap-2">
                {runtimeConfig.mcpServerUrl.startsWith('http') ? (
                  <a 
                    href={runtimeConfig.mcpServerUrl} 
                    target="_blank" 
                    rel="noopener noreferrer"
                    className="text-sm font-mono text-primary hover:underline truncate flex-1 flex items-center gap-1"
                  >
                    {runtimeConfig.mcpServerUrl}
                    <ExternalLink className="w-3 h-3 flex-shrink-0" />
                  </a>
                ) : (
                  <span className="text-sm font-mono text-muted truncate flex-1">{runtimeConfig.mcpServerUrl}</span>
                )}
                <button
                  onClick={() => copyToClipboard('runtime-mcp', runtimeConfig.mcpServerUrl)}
                  className="p-1.5 hover:bg-blue-100 rounded transition-colors"
                  title="Copy URL"
                >
                  {copiedKey === 'runtime-mcp' ? (
                    <CheckCircle2 className="w-4 h-4 text-green-500" />
                  ) : (
                    <Copy className="w-4 h-4 text-blue-600" />
                  )}
                </button>
              </div>
            </div>

            {/* Workflow API URL */}
            <div className="bg-white rounded-lg border border-blue-200 p-4 shadow-sm">
              <div className="flex items-center gap-2 mb-2">
                <Server className="w-4 h-4 text-blue-600" />
                <span className="text-xs font-bold text-blue-900 uppercase tracking-wider">Workflow API URL</span>
              </div>
              <div className="flex items-center gap-2">
                {runtimeConfig.workflowApiUrl.startsWith('http') ? (
                  <a 
                    href={`${runtimeConfig.workflowApiUrl}/docs`} 
                    target="_blank" 
                    rel="noopener noreferrer"
                    className="text-sm font-mono text-primary hover:underline truncate flex-1 flex items-center gap-1"
                  >
                    {runtimeConfig.workflowApiUrl}
                    <ExternalLink className="w-3 h-3 flex-shrink-0" />
                  </a>
                ) : (
                  <span className="text-sm font-mono text-muted truncate flex-1">{runtimeConfig.workflowApiUrl}</span>
                )}
                <button
                  onClick={() => copyToClipboard('runtime-api', runtimeConfig.workflowApiUrl)}
                  className="p-1.5 hover:bg-blue-100 rounded transition-colors"
                  title="Copy URL"
                >
                  {copiedKey === 'runtime-api' ? (
                    <CheckCircle2 className="w-4 h-4 text-green-500" />
                  ) : (
                    <Copy className="w-4 h-4 text-blue-600" />
                  )}
                </button>
              </div>
            </div>
          </div>

          <div className="mt-4 p-3 bg-blue-100 border border-blue-300 rounded-lg">
            <div className="flex items-start gap-2">
              <AlertCircle className="w-4 h-4 text-blue-700 mt-0.5 flex-shrink-0" />
              <div className="text-xs text-blue-800 leading-relaxed">
                {runtimeConfig.environment === 'azure' ? (
                  <>
                    <strong>Production Mode:</strong> These URLs were baked into the Docker image during deployment. 
                    To update them, redeploy using <code className="bg-blue-200 px-1 rounded">deploy.ps1</code> which builds all 3 container apps with the latest URLs.
                  </>
                ) : (
                  <>
                    <strong>Local Development:</strong> These URLs are from <code className="bg-blue-200 px-1 rounded">.env.local</code>. 
                    The file uses localhost URLs and should not be changed. When deploying to Azure, backend URLs are auto-detected and baked into the production build.
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ================================================================ */}
      {/* SECTION 1: DEPLOYMENT */}
      {/* ================================================================ */}
      <div className="bg-white rounded-xl border border-border p-6 shadow-sm space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-gradient-to-br from-primary/10 to-secondary/10 rounded-lg">
              <Rocket className="w-6 h-6 text-primary" />
            </div>
            <div>
              <h2 className="text-xl font-bold text-text">Deployment</h2>
              <p className="text-sm text-muted">Deploy all 3 container apps (MCP, API, UI) to Azure</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            {status !== 'idle' && (
              <span className={cn(
                "px-3 py-1 rounded-full text-xs font-semibold",
                status === 'running' || status === 'starting' ? "bg-blue-100 text-blue-700" :
                status === 'completed' ? "bg-green-100 text-green-700" :
                status === 'failed' ? "bg-red-100 text-red-700" :
                "bg-gray-100 text-gray-700"
              )}>
                {status.toUpperCase()}
              </span>
            )}
            <button
              onClick={startDeployment}
              disabled={isRunning || isContainerApp}
              title={isContainerApp ? 'Deployment from local machine is not available when running in Azure Container Apps' : undefined}
              className={cn(
                "flex items-center gap-2 px-5 py-2.5 rounded-lg font-semibold transition-all duration-200",
                isRunning || isContainerApp
                  ? "bg-gray-300 text-gray-500 cursor-not-allowed"
                  : "bg-gradient-to-r from-primary to-secondary text-white hover:shadow-lg hover:scale-105"
              )}
            >
              <Rocket className={cn("w-4 h-4", isRunning && "animate-bounce")} />
              {isContainerApp ? 'Deploy Disabled (Container App)' : isRunning ? 'Deploying...' : 'Deploy All From Local Machine'}
            </button>
          </div>
        </div>

        {/* Progress Bar */}
        {status !== 'idle' && (
          <div className="space-y-1">
            <div className="flex justify-between text-xs text-muted">
              <span>Progress</span>
              <span>{progress}%</span>
            </div>
            <div className="h-2 bg-gray-200 rounded-full overflow-hidden">
              <motion.div
                className={cn(
                  "h-full rounded-full",
                  status === 'failed' ? "bg-red-500" :
                  status === 'completed' ? "bg-green-500" :
                  "bg-gradient-to-r from-primary to-secondary"
                )}
                initial={{ width: 0 }}
                animate={{ width: `${progress}%` }}
                transition={{ duration: 0.5 }}
              />
            </div>
          </div>
        )}

        {/* Deployment Terminal */}
        {logs.length > 0 && (
          <div className="w-full bg-white rounded-xl border border-border shadow-lg flex flex-col font-mono overflow-hidden" style={{ height: '400px' }}>
            {/* Terminal Header */}
            <div className="flex items-center justify-between px-4 py-2 bg-primary/10 border-b border-border">
              <div className="flex items-center gap-2">
                <Terminal className="w-4 h-4 text-primary" />
                <span className="text-xs text-muted font-medium uppercase tracking-wider">Deployment Stream</span>
              </div>
              <div className="flex items-center gap-2">
                <button onClick={handleDownloadLogs} className="p-1.5 hover:bg-primary/10 rounded text-muted hover:text-[#4b5563] transition-colors" title="Download Logs">
                  <Download className="w-3.5 h-3.5" />
                </button>
                <button onClick={clearLogs} className="p-1.5 hover:bg-primary/10 rounded text-muted hover:text-[#4b5563] transition-colors" title="Clear">
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            </div>

            {/* Terminal Content */}
            <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-1 scrollbar-thin scroll-smooth bg-white">
              {logs.map((log, i) => (
                <motion.div
                  key={i}
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  className="text-sm break-all font-mono"
                >
                  <span className="text-slate-400 mr-2 select-none">{String(i + 1).padStart(3, '0')}</span>
                  <span className={formatLogColor(log.message, log.type)}>{log.message}</span>
                </motion.div>
              ))}
            </div>

            {/* Terminal Footer */}
            <div className="px-4 py-1 bg-primary/5 border-t border-border flex justify-between items-center text-[10px] text-muted">
              <span>Ln {logs.length}, Col 1</span>
              <div className="flex items-center gap-2">
                {isRunning && <span className="w-2 h-2 rounded-full bg-secondary animate-pulse"></span>}
                <span>{isRunning ? 'LIVE STREAM' : status === 'completed' ? 'COMPLETE' : status === 'failed' ? 'FAILED' : 'READY'}</span>
              </div>
            </div>
          </div>
        )}

        {/* Deployed URLs */}
        {(deployUrls.ui_url || deployUrls.api_url || deployUrls.mcp_url) && (
          <div className="bg-green-50 border border-green-200 rounded-lg p-4 space-y-3">
            <h3 className="text-sm font-bold text-green-800 flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4" />
              Deployed Service URLs
            </h3>
            {deployUrls.ui_url && (
              <div className="flex items-center gap-2">
                <Globe className="w-4 h-4 text-green-600" />
                <span className="text-sm font-medium text-green-700 w-32">UI (Next.js):</span>
                <a href={deployUrls.ui_url} target="_blank" rel="noopener noreferrer" className="text-sm text-primary hover:underline flex items-center gap-1">
                  {deployUrls.ui_url} <ExternalLink className="w-3 h-3" />
                </a>
              </div>
            )}
            {deployUrls.api_url && (
              <div className="flex items-center gap-2">
                <Server className="w-4 h-4 text-green-600" />
                <span className="text-sm font-medium text-green-700 w-32">API (FastAPI):</span>
                <a href={deployUrls.api_url} target="_blank" rel="noopener noreferrer" className="text-sm text-primary hover:underline flex items-center gap-1">
                  {deployUrls.api_url} <ExternalLink className="w-3 h-3" />
                </a>
              </div>
            )}
            {deployUrls.mcp_url && (
              <div className="flex items-center gap-2">
                <HardDrive className="w-4 h-4 text-green-600" />
                <span className="text-sm font-medium text-green-700 w-32">MCP (Node.js):</span>
                <a href={deployUrls.mcp_url} target="_blank" rel="noopener noreferrer" className="text-sm text-primary hover:underline flex items-center gap-1">
                  {deployUrls.mcp_url} <ExternalLink className="w-3 h-3" />
                </a>
              </div>
            )}
          </div>
        )}
      </div>

      {/* ================================================================ */}
      {/* SECTION 2: BACKEND SERVICE CONFIGURATION & AZURE STORAGE */}
      {/* ================================================================ */}
      <div className="bg-white rounded-xl border border-border p-6 shadow-sm space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-blue-50 rounded-lg">
              <Server className="w-6 h-6 text-blue-600" />
            </div>
            <div>
              <h2 className="text-xl font-bold text-text">Backend Service Configuration</h2>
              <p className="text-sm text-muted">API server's environment variables and Azure Storage settings</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {!editingUrls ? (
              <>
                <button
                  onClick={() => {
                    setUrlDraft(envSettings?.service_urls ? { ...envSettings.service_urls } : {});
                    setEditingUrls(true);
                    setSaveStatus('idle');
                  }}
                  className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium border border-border hover:bg-gray-50 transition-colors"
                >
                  <Pencil className="w-3.5 h-3.5" />
                  Edit
                </button>
                <button
                  onClick={loadEnvSettings}
                  disabled={envLoading}
                  className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium border border-border hover:bg-gray-50 transition-colors"
                >
                  <RefreshCw className={cn("w-3.5 h-3.5", envLoading && "animate-spin")} />
                  Refresh
                </button>
              </>
            ) : (
              <>
                <button
                  onClick={async () => {
                    setSaveStatus('saving');
                    const ok = await saveServiceUrls(urlDraft);
                    if (ok) {
                      setSaveStatus('saved');
                      setTimeout(() => {
                        setEditingUrls(false);
                        setSaveStatus('idle');
                      }, 1200);
                    } else {
                      setSaveStatus('error');
                    }
                  }}
                  disabled={envSaving}
                  className={cn(
                    "flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-semibold transition-colors",
                    saveStatus === 'saved'
                      ? "bg-green-100 text-green-700 border border-green-300"
                      : saveStatus === 'error'
                      ? "bg-red-100 text-red-700 border border-red-300"
                      : "bg-gradient-to-r from-primary to-secondary text-white hover:shadow-md"
                  )}
                >
                  {saveStatus === 'saving' ? (
                    <><RefreshCw className="w-3.5 h-3.5 animate-spin" /> Saving...</>
                  ) : saveStatus === 'saved' ? (
                    <><CheckCircle2 className="w-3.5 h-3.5" /> Saved</>
                  ) : saveStatus === 'error' ? (
                    <><XCircle className="w-3.5 h-3.5" /> Failed</>
                  ) : (
                    <><Save className="w-3.5 h-3.5" /> Save</>
                  )}
                </button>
                <button
                  onClick={() => { setEditingUrls(false); setSaveStatus('idle'); }}
                  className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium border border-border hover:bg-gray-50 transition-colors"
                >
                  <X className="w-3.5 h-3.5" />
                  Cancel
                </button>
              </>
            )}
          </div>
        </div>

        {/* URL label mapping */}
        {(() => {
          const urlFields: { key: string; label: string; icon: JSX.Element; placeholder: string }[] = [
            { key: 'api_server_url', label: 'FastAPI Server URL', icon: <Server className="w-4 h-4 text-blue-500" />, placeholder: 'http://localhost:8000' },
            { key: 'mcp_server_url', label: 'MCP Server URL', icon: <HardDrive className="w-4 h-4 text-purple-500" />, placeholder: 'http://localhost:8080' },
            { key: 'ui_url', label: 'UI Server URL', icon: <Globe className="w-4 h-4 text-green-500" />, placeholder: 'http://localhost:3000' },
            { key: 'storage_account', label: 'Storage Account', icon: <Database className="w-4 h-4 text-orange-500" />, placeholder: 'samcpstorage' },
            { key: 'storage_rg', label: 'Storage Resource Group', icon: <Cloud className="w-4 h-4 text-gray-500" />, placeholder: 'rg-mcp-servers' },
            { key: 'container_name', label: 'Container Name', icon: <Database className="w-4 h-4 text-orange-500" />, placeholder: 'aztfExport' },
          ];

          const currentUrls = editingUrls ? urlDraft : (envSettings?.service_urls ?? {});

          if (!editingUrls && Object.keys(currentUrls).length === 0) {
            return (
              <div className="text-center py-6 text-muted">
                {envLoading ? 'Loading service configuration...' : 'No service URLs available. Start the API server to see live values.'}
              </div>
            );
          }

          return (
            <>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {urlFields.map(({ key, label, icon, placeholder }) => {
                  const val = currentUrls[key] ?? '';
                  const isUrl = val.startsWith('http');
                  return (
                    <div key={key} className={cn(
                      "flex items-center gap-3 p-3 rounded-lg border",
                      editingUrls ? "bg-blue-50/30 border-blue-200" : "bg-gray-50 border-gray-100"
                    )}>
                      {icon}
                      <div className="flex-1 min-w-0">
                        <p className="text-xs text-muted font-medium uppercase tracking-wider mb-1">{label}</p>
                        {editingUrls ? (
                          <input
                            type="text"
                            value={urlDraft[key] ?? ''}
                            onChange={(e) => setUrlDraft((prev) => ({ ...prev, [key]: e.target.value }))}
                            placeholder={placeholder}
                            className="w-full text-sm text-text font-medium bg-white border border-gray-200 rounded px-2 py-1 focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
                          />
                        ) : isUrl ? (
                          <a href={val} target="_blank" rel="noopener noreferrer" className="text-sm text-primary hover:underline truncate block">
                            {val}
                          </a>
                        ) : (
                          <p className="text-sm text-text font-medium truncate">{val || '—'}</p>
                        )}
                      </div>
                      {!editingUrls && val && (
                        <button onClick={() => copyToClipboard(key, val)} className="p-1 hover:bg-gray-200 rounded transition-colors" title="Copy">
                          {copiedKey === key ? <CheckCircle2 className="w-3.5 h-3.5 text-green-500" /> : <Copy className="w-3.5 h-3.5 text-muted" />}
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>

              {!editingUrls && (
                <div className="mt-3 p-3 bg-gray-100 border border-gray-200 rounded-lg">
                  <div className="flex items-start gap-2">
                    <AlertCircle className="w-4 h-4 text-gray-600 mt-0.5 flex-shrink-0" />
                    <p className="text-xs text-gray-700 leading-relaxed">
                      <strong>Backend Configuration:</strong> These values are loaded from the API server's environment variables. 
                      They represent how the backend services are configured, which may differ from the UI's runtime configuration shown above.
                    </p>
                  </div>
                </div>
              )}
            </>
          );
        })()}
      </div>

      {/* ================================================================ */}
      {/* SECTION 3: ENVIRONMENT VARIABLES */}
      {/* ================================================================ */}
      <div className="bg-white rounded-xl border border-border p-6 shadow-sm space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-purple-50 rounded-lg">
              <FileCode className="w-6 h-6 text-purple-600" />
            </div>
            <div>
              <h2 className="text-xl font-bold text-text">Environment Variables</h2>
              <p className="text-sm text-muted">Configuration values from .env file (secrets masked)</p>
            </div>
          </div>
          <button
            onClick={() => setShowSecrets(!showSecrets)}
            className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium border border-border hover:bg-gray-50 transition-colors"
          >
            {showSecrets ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
            {showSecrets ? 'Hide' : 'Show'} Secrets
          </button>
        </div>

        {envSettings?.env_variables && Object.keys(envSettings.env_variables).length > 0 ? (
          <div className="overflow-hidden rounded-lg border border-gray-200">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50">
                  <th className="text-left px-4 py-2 font-semibold text-muted text-xs uppercase tracking-wider">Variable</th>
                  <th className="text-left px-4 py-2 font-semibold text-muted text-xs uppercase tracking-wider">Value</th>
                  <th className="w-10"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {Object.entries(envSettings.env_variables).map(([key, value]) => {
                  const isMasked = value === '********';
                  return (
                    <tr key={key} className="hover:bg-gray-50 transition-colors">
                      <td className="px-4 py-2 font-mono text-xs text-text font-medium">{key}</td>
                      <td className="px-4 py-2 font-mono text-xs text-muted truncate max-w-md">
                        {isMasked && !showSecrets ? '••••••••' : value || '—'}
                      </td>
                      <td className="px-2 py-2">
                        {!isMasked && value && (
                          <button onClick={() => copyToClipboard(key, value)} className="p-1 hover:bg-gray-200 rounded transition-colors" title="Copy">
                            {copiedKey === key ? <CheckCircle2 className="w-3 h-3 text-green-500" /> : <Copy className="w-3 h-3 text-muted" />}
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="text-center py-6 text-muted">
            {envLoading ? 'Loading environment variables...' : 'No environment variables available. Ensure the API server is running.'}
          </div>
        )}
      </div>

      {/* ================================================================ */}
      {/* SECTION 4: ENVIRONMENT CHECKS (existing) */}
      {/* ================================================================ */}
      <div className="bg-white rounded-xl border border-border p-6 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-bold text-text">Environment Status</h2>
          <button
            onClick={runEnvironmentCheck}
            disabled={isChecking}
            className={cn(
              "flex items-center gap-2 px-4 py-2 rounded-lg font-medium transition-all duration-200",
              isChecking
                ? "bg-gray-300 text-gray-500 cursor-not-allowed"
                : "bg-gradient-to-r from-primary to-secondary text-white hover:shadow-lg"
            )}
          >
            <RefreshCw className={cn("w-4 h-4", isChecking && "animate-spin")} />
            {isChecking ? 'Checking...' : 'Re-check'}
          </button>
        </div>

        <div className="grid grid-cols-3 gap-4 mb-6">
          <div className="bg-green-50 border border-green-200 rounded-lg p-4 text-center">
            <CheckCircle2 className="w-6 h-6 text-green-600 mx-auto mb-2" />
            <p className="text-2xl font-bold text-green-900">{successCount}</p>
            <p className="text-xs text-green-700">Successful</p>
          </div>
          <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 text-center">
            <AlertCircle className="w-6 h-6 text-yellow-600 mx-auto mb-2" />
            <p className="text-2xl font-bold text-yellow-900">{warningCount}</p>
            <p className="text-xs text-yellow-700">Warnings</p>
          </div>
          <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-center">
            <XCircle className="w-6 h-6 text-red-600 mx-auto mb-2" />
            <p className="text-2xl font-bold text-red-900">{errorCount}</p>
            <p className="text-xs text-red-700">Errors</p>
          </div>
        </div>

        <div className="space-y-3">
          {checks.map((check, index) => {
            const Icon = check.icon;
            return (
              <div
                key={index}
                className={cn(
                  "rounded-lg border p-4 transition-all",
                  check.status === 'success' && "border-green-200 bg-green-50/50",
                  check.status === 'error' && "border-red-200 bg-red-50/50",
                  check.status === 'warning' && "border-yellow-200 bg-yellow-50/50",
                  check.status === 'checking' && "border-blue-200 bg-blue-50/50"
                )}
              >
                <div className="flex items-center gap-4">
                  <Icon className={cn(
                    "w-5 h-5",
                    check.status === 'success' && "text-green-600",
                    check.status === 'error' && "text-red-600",
                    check.status === 'warning' && "text-yellow-600",
                    check.status === 'checking' && "text-blue-600"
                  )} />
                  <div className="flex-1">
                    <div className="flex items-center justify-between">
                      <h3 className="text-sm font-bold text-text">{check.name}</h3>
                      {getStatusIcon(check.status)}
                    </div>
                    <p className="text-xs text-muted">{check.description}</p>
                    {check.message && (
                      <p className={cn(
                        "text-xs font-medium mt-1",
                        check.status === 'success' && "text-green-700",
                        check.status === 'error' && "text-red-700",
                        check.status === 'warning' && "text-yellow-700"
                      )}>
                        {check.message}
                      </p>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
