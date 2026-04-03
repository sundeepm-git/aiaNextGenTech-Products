'use client';

import { useState } from 'react';
import {
  FolderOpen,
  FileText,
  Download,
  Loader2,
  AlertCircle,
  CheckCircle2,
  ChevronRight,
  ChevronDown,
  Search,
  RefreshCw,
  Eye,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { config } from '@/app/services/config';
import { maskSensitiveValues } from '@/app/services/maskService';

interface BlobFile {
  name: string;
  size: number;
  last_modified: string;
  content_type: string;
}

interface ReportSection {
  available: boolean;
  files: BlobFile[];
  display_name: string;
  container: string;
  file_count: number;
}

interface ReportTree {
  subscription_id: string;
  resource_group: string;
  reports: {
    assessment: ReportSection;
    export: ReportSection;
    refactor: ReportSection;
  };
}

export default function ReportPage() {
  const [subscriptionId, setSubscriptionId] = useState('');
  const [resourceGroup, setResourceGroup] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reportTree, setReportTree] = useState<ReportTree | null>(null);
  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>({
    assessment: true,
    export: true,
    refactor: true,
  });
  const [downloading, setDownloading] = useState<string | null>(null);

  const DEFAULT_SUB = 'd0f1884d-1f98-4bf1-9e15-e2986fc1bca2';
  const DEFAULT_RG = 'rg-mcp-servers';

  const fillDefaults = () => {
    setSubscriptionId(DEFAULT_SUB);
    setResourceGroup(DEFAULT_RG);
  };

  const handleSearch = async () => {
    if (!subscriptionId || !resourceGroup) return;
    setIsLoading(true);
    setError(null);
    setReportTree(null);

    try {
      const res = await fetch(config.reports.endpoints.tree(subscriptionId, resourceGroup));
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.detail || `API error: ${res.status}`);
      }
      const tree: ReportTree = await res.json();
      setReportTree(tree);
    } catch (err: any) {
      setError(err.message || 'Failed to fetch reports');
    } finally {
      setIsLoading(false);
    }
  };

  const handleDownload = async (container: string, blobName: string) => {
    setDownloading(blobName);
    try {
      const url = config.reports.endpoints.download(container, blobName);
      window.open(url, '_blank');
    } finally {
      setTimeout(() => setDownloading(null), 1000);
    }
  };

  const handlePreview = async (container: string, blobName: string) => {
    const url = config.reports.endpoints.download(container, blobName);
    // Open in a new tab for HTML preview
    const win = window.open('', '_blank');
    if (!win) return;
    try {
      const res = await fetch(url);
      const html = await res.text();
      win.document.write(html);
      win.document.close();
    } catch {
      win.document.write('<p>Failed to load report</p>');
      win.document.close();
    }
  };

  const toggleSection = (key: string) => {
    setExpandedSections((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  const formatSize = (bytes: number) => {
    if (bytes === 0) return '—';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  const sectionColors: Record<string, { bg: string; border: string; icon: string; badge: string }> = {
    assessment: { bg: 'from-blue-50 to-indigo-50', border: 'border-blue-200', icon: 'text-blue-600', badge: 'bg-blue-100 text-blue-700' },
    export: { bg: 'from-emerald-50 to-teal-50', border: 'border-emerald-200', icon: 'text-emerald-600', badge: 'bg-emerald-100 text-emerald-700' },
    refactor: { bg: 'from-purple-50 to-fuchsia-50', border: 'border-purple-200', icon: 'text-purple-600', badge: 'bg-purple-100 text-purple-700' },
  };

  return (
    <div className="flex-1 p-8 space-y-8 overflow-auto">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-2">
          Reports
        </h1>
        <p className="text-muted text-lg">
          Browse and download assessment, export, and refactor reports from Azure Blob Storage
        </p>
      </div>

      {/* Search Section */}
      <div className="bg-white rounded-xl border border-border p-6 space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-text mb-2">Subscription ID</label>
            <div className="relative">
              <div className="absolute inset-0 flex items-center px-4 pointer-events-none z-10 font-mono text-sm">
                {subscriptionId ? maskSensitiveValues(subscriptionId) : <span className="text-gray-400">Enter subscription ID</span>}
              </div>
              <input
                type="text"
                value={subscriptionId}
                onChange={(e) => setSubscriptionId(e.target.value)}
                placeholder=""
                className="w-full px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent font-mono text-sm text-transparent caret-black bg-transparent relative z-20"
                disabled={isLoading}
              />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-text mb-2">Resource Group</label>
            <div className="relative">
              <div className="absolute inset-0 flex items-center px-4 pointer-events-none z-10 font-mono text-sm">
                {resourceGroup ? maskSensitiveValues(resourceGroup) : <span className="text-gray-400">e.g. rg-production</span>}
              </div>
              <input
                type="text"
                value={resourceGroup}
                onChange={(e) => setResourceGroup(e.target.value)}
                placeholder=""
                className="w-full px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent font-mono text-sm text-transparent caret-black bg-transparent relative z-20"
                disabled={isLoading}
              />
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={fillDefaults}
            disabled={isLoading}
            className="px-4 py-2 text-sm text-primary border border-primary/30 rounded-lg hover:bg-primary/5 transition-colors disabled:opacity-50"
          >
            Use Default Values
          </button>

          <button
            onClick={handleSearch}
            disabled={isLoading || !subscriptionId || !resourceGroup}
            className={cn(
              "flex items-center gap-2 px-6 py-3 rounded-lg font-medium transition-all duration-200",
              isLoading || !subscriptionId || !resourceGroup
                ? "bg-gray-300 text-gray-500 cursor-not-allowed"
                : "bg-gradient-to-r from-primary to-secondary text-white hover:shadow-lg"
            )}
          >
            {isLoading ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                Loading Reports...
              </>
            ) : (
              <>
                <Search className="w-5 h-5" />
                Fetch Reports
              </>
            )}
          </button>

          {reportTree && (
            <button
              onClick={handleSearch}
              disabled={isLoading}
              className="flex items-center gap-1 px-3 py-2 text-sm text-muted hover:text-primary transition-colors"
            >
              <RefreshCw className="w-4 h-4" />
              Refresh
            </button>
          )}
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-red-600 mt-0.5" />
          <div>
            <h3 className="font-semibold text-red-900">Error</h3>
            <p className="text-red-700 text-sm">{error}</p>
          </div>
        </div>
      )}

      {/* Report Tree */}
      {reportTree && (
        <div className="space-y-4">
          {/* Folder Header */}
          <div className="flex items-center gap-3 bg-gray-50 rounded-lg p-4 border border-border">
            <FolderOpen className="w-6 h-6 text-primary" />
            <div>
              <p className="font-semibold text-text">
                {maskSensitiveValues(reportTree.subscription_id)}
              </p>
              <p className="text-sm text-muted">
                Resource Group: <span className="font-mono font-medium text-text">{maskSensitiveValues(reportTree.resource_group)}</span>
              </p>
            </div>
          </div>

          {/* Report Sections */}
          {(Object.entries(reportTree.reports) as [string, ReportSection][]).map(([key, section]) => {
            const colors = sectionColors[key] || sectionColors.assessment;
            const isExpanded = expandedSections[key];

            return (
              <div
                key={key}
                className={cn('rounded-xl border overflow-hidden', colors.border)}
              >
                {/* Section Header */}
                <button
                  onClick={() => toggleSection(key)}
                  className={cn(
                    'w-full flex items-center justify-between px-5 py-4 bg-gradient-to-r',
                    colors.bg
                  )}
                >
                  <div className="flex items-center gap-3">
                    {isExpanded ? (
                      <ChevronDown className={cn('w-5 h-5', colors.icon)} />
                    ) : (
                      <ChevronRight className={cn('w-5 h-5', colors.icon)} />
                    )}
                    <FolderOpen className={cn('w-5 h-5', colors.icon)} />
                    <span className="font-semibold text-text">{section.display_name}</span>
                    <span className={cn('text-xs font-mono px-2 py-0.5 rounded-full', colors.badge)}>
                      {section.file_count} file{section.file_count !== 1 ? 's' : ''}
                    </span>
                  </div>
                  {section.available ? (
                    <CheckCircle2 className="w-5 h-5 text-green-500" />
                  ) : (
                    <span className="text-xs text-muted">No files</span>
                  )}
                </button>

                {/* File List */}
                {isExpanded && section.available && (
                  <div className="bg-white divide-y divide-gray-100">
                    {section.files.map((file, idx) => {
                      const fileName = file.name.split('/').pop() || file.name;
                      const isHtml = fileName.endsWith('.html');

                      return (
                        <div
                          key={idx}
                          className="flex items-center justify-between px-5 py-3 hover:bg-gray-50 transition-colors"
                        >
                          <div className="flex items-center gap-3 min-w-0">
                            <FileText className="w-4 h-4 text-muted flex-shrink-0" />
                            <div className="min-w-0">
                              <p className="text-sm font-medium text-text truncate" title={file.name}>
                                {fileName}
                              </p>
                              <p className="text-xs text-muted">
                                {formatSize(file.size)}
                                {file.last_modified && ` · ${new Date(file.last_modified).toLocaleDateString()}`}
                              </p>
                            </div>
                          </div>
                          <div className="flex items-center gap-2 flex-shrink-0">
                            {isHtml && (
                              <button
                                onClick={() => handlePreview(section.container, file.name)}
                                className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-blue-600 border border-blue-200 rounded-lg hover:bg-blue-50 transition-colors"
                              >
                                <Eye className="w-3.5 h-3.5" />
                                Preview
                              </button>
                            )}
                            <button
                              onClick={() => handleDownload(section.container, file.name)}
                              disabled={downloading === file.name}
                              className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-primary border border-primary/30 rounded-lg hover:bg-primary/5 transition-colors disabled:opacity-50"
                            >
                              {downloading === file.name ? (
                                <Loader2 className="w-3.5 h-3.5 animate-spin" />
                              ) : (
                                <Download className="w-3.5 h-3.5" />
                              )}
                              Download
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}

                {/* Empty State */}
                {isExpanded && !section.available && (
                  <div className="bg-white px-5 py-6 text-center">
                    <p className="text-sm text-muted">
                      No {section.display_name.toLowerCase()} files found for this subscription/resource group.
                    </p>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
