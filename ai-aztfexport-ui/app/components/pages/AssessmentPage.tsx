'use client';

import { useState } from 'react';
import { Play, Loader2, CheckCircle2, AlertCircle, Copy } from 'lucide-react';
import { cn } from '@/lib/utils';

export default function AssessmentPage() {
  const [prompt, setPrompt] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  const predefinedPrompt = "Generate HTML assessment report for Azure subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 and resource group rg-production";

  const handleAssess = async () => {
    setIsRunning(true);
    setError(null);
    
    try {
      // Simulate API call
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      setResult({
        subscriptionId: 'd0f1884d-1f98-4bf1-9e15-e2986fc1bca2',
        resourceGroup: 'rg-production',
        totalResources: 247,
        supported: 231,
        unsupported: 16,
        resourceGroups: 12,
        summary: 'Subscription is ready for migration with 93.5% compatibility',
        htmlReportPath: `Assessment-${subscriptionId}-${resourceGroup}.html`,
        warnings: [
          'Some App Service plans use deprecated SKUs',
          '3 Virtual Machines require manual intervention'
        ]
      });
    } catch (err) {
      setError('Failed to assess subscription');
    } finally {
      setIsRunning(false);
    }
  };

  return (
    <div className="flex-1 p-8 space-y-8 overflow-auto">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-2">
          Azure Subscription Assessment
        </h1>
        <p className="text-muted text-lg">
          Analyze your Azure subscription for Terraform migration compatibility
        </p>
      </div>

      {/* Input Section */}
      <div className="bg-white rounded-xl border border-border p-6 space-y-4">
        <div>
          <label className="block text-sm font-medium text-text mb-2">
            Natural Language Prompt
          </label>
          <div className="relative">
            <textarea
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              placeholder={predefinedPrompt}
              className="w-full h-32 px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent resize-none font-mono text-sm"
            />
            <button
              onClick={() => setPrompt(predefinedPrompt)}
              className="absolute top-2 right-2 p-2 text-muted hover:text-primary transition-colors"
              title="Use predefined prompt"
            >
              <Copy className="w-4 h-4" />
            </button>
          </div>
        </div>

        <div className="bg-primary/5 border border-primary/20 rounded-lg p-4">
          <p className="text-xs text-muted font-semibold mb-2">💡 Prompt Help:</p>
          <p className="text-sm text-text font-mono">
            {predefinedPrompt}
          </p>
        </div>

        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-3">
          <p className="text-xs text-yellow-800">
            <span className="font-semibold">Output:</span> Assessment report will be generated in HTML format and saved to the report directory.
          </p>
        </div>

        <button
          onClick={handleAssess}
          disabled={isRunning || !prompt}
          className={cn(
            "flex items-center gap-2 px-6 py-3 rounded-lg font-medium transition-all duration-200",
            isRunning || !prompt
              ? "bg-gray-300 text-gray-500 cursor-not-allowed"
              : "bg-gradient-to-r from-primary to-secondary text-white hover:shadow-lg"
          )}
        >
          {isRunning ? (
            <>
              <Loader2 className="w-5 h-5 animate-spin" />
              Assessing...
            </>
          ) : (
            <>
              <Play className="w-5 h-5" />
              Run Assessment
            </>
          )}
        </button>
      </div>

      {/* Results Section */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-red-600 mt-0.5" />
          <div>
            <h3 className="font-semibold text-red-900">Error</h3>
            <p className="text-red-700 text-sm">{error}</p>
          </div>
        </div>
      )}

      {result && (
        <div className="space-y-6">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-6 h-6 text-secondary" />
            <h2 className="text-2xl font-bold text-text">Assessment Complete</h2>
          </div>

          {/* Summary Cards */}
          <div className="grid grid-cols-4 gap-4">
            <div className="bg-white rounded-lg border border-border p-4">
              <p className="text-sm text-muted">Total Resources</p>
              <p className="text-3xl font-bold text-primary mt-1">{result.totalResources}</p>
            </div>
            <div className="bg-white rounded-lg border border-border p-4">
              <p className="text-sm text-muted">Supported</p>
              <p className="text-3xl font-bold text-secondary mt-1">{result.supported}</p>
            </div>
            <div className="bg-white rounded-lg border border-border p-4">
              <p className="text-sm text-muted">Unsupported</p>
              <p className="text-3xl font-bold text-error mt-1">{result.unsupported}</p>
            </div>
            <div className="bg-white rounded-lg border border-border p-4">
              <p className="text-sm text-muted">Resource Groups</p>
              <p className="text-3xl font-bold text-text mt-1">{result.resourceGroups}</p>
            </div>
          </div>

          {/* Summary */}
          <div className="bg-gradient-to-br from-primary/5 to-secondary/5 rounded-xl border border-primary/20 p-6">
            <h3 className="font-semibold text-text mb-2">Summary</h3>
            <p className="text-text">{result.summary}</p>
          </div>

          {/* HTML Report Link */}
          <div className="bg-blue-50 border border-blue-200 rounded-xl p-4">
            <h3 className="font-semibold text-blue-900 mb-2 flex items-center gap-2">
              📄 HTML Assessment Report
            </h3>
            <p className="text-blue-800 text-sm mb-2">
              Report generated successfully: <span className="font-mono font-semibold">{result.htmlReportPath}</span>
            </p>
            <button className="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 transition-colors">
              View HTML Report
            </button>
          </div>

          {/* Warnings */}
          {result.warnings.length > 0 && (
            <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4">
              <h3 className="font-semibold text-yellow-900 mb-2">⚠️ Warnings</h3>
              <ul className="space-y-1">
                {result.warnings.map((warning: string, idx: number) => (
                  <li key={idx} className="text-yellow-800 text-sm">• {warning}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
