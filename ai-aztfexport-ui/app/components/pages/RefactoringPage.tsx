'use client';

import { useState } from 'react';
import { Play, Loader2, CheckCircle2, AlertCircle, Copy, Folder, File, ChevronRight, ChevronDown } from 'lucide-react';
import { cn } from '@/lib/utils';

interface CodeFile {
  name: string;
  type: 'folder' | 'file';
  content?: string;
  children?: CodeFile[];
}

export default function RefactoringPage() {
  const [prompt, setPrompt] = useState('');
  const [isRunning, setIsRunning] = useState(false);
  const [result, setResult] = useState<CodeFile | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set());

  const predefinedPrompt = "Refactor Terraform code from 'aztf-coderefactor/rg-production' for subscription 'Production' (d0f1884d-1f98-4bf1-9e15-e2986fc1bca2)";

  const handleRefactor = async () => {
    setIsRunning(true);
    setError(null);
    
    try {
      await new Promise(resolve => setTimeout(resolve, 3000));
      
      setResult({
        name: 'refactored-terraform',
        type: 'folder',
        children: [
          {
            name: 'main.tf',
            type: 'file',
            content: '# Refactored Main Configuration\nterraform {\n  required_version = ">= 1.0"\n}'
          },
          {
            name: 'variables.tf',
            type: 'file',
            content: '# Refactored Variables\nvariable "location" {\n  type = string\n}'
          },
          {
            name: 'modules',
            type: 'folder',
            children: [
              {
                name: 'app-service',
                type: 'folder',
                children: [
                  { name: 'main.tf', type: 'file', content: '# App Service Module' },
                  { name: 'variables.tf', type: 'file', content: '# Module Variables' },
                  { name: 'outputs.tf', type: 'file', content: '# Module Outputs' }
                ]
              },
              {
                name: 'networking',
                type: 'folder',
                children: [
                  { name: 'main.tf', type: 'file', content: '# Networking Module' },
                  { name: 'variables.tf', type: 'file', content: '# Network Variables' }
                ]
              }
            ]
          },
          {
            name: 'environments',
            type: 'folder',
            children: [
              { name: 'prod.tfvars', type: 'file', content: '# Production Variables' },
              { name: 'dev.tfvars', type: 'file', content: '# Development Variables' }
            ]
          }
        ]
      });
      
      setExpandedFolders(new Set(['refactored-terraform', 'modules', 'environments', 'modules/app-service', 'modules/networking']));
    } catch (err) {
      setError('Failed to refactor code');
    } finally {
      setIsRunning(false);
    }
  };

  const toggleFolder = (path: string) => {
    setExpandedFolders(prev => {
      const next = new Set(prev);
      if (next.has(path)) {
        next.delete(path);
      } else {
        next.add(path);
      }
      return next;
    });
  };

  const renderTree = (node: CodeFile, path: string = '', level: number = 0) => {
    const currentPath = path ? `${path}/${node.name}` : node.name;
    const isExpanded = expandedFolders.has(currentPath);

    return (
      <div key={currentPath}>
        <div
          className={cn(
            "flex items-center gap-2 px-3 py-2 rounded hover:bg-primary/5 cursor-pointer transition-colors",
            level > 0 && "ml-4"
          )}
          onClick={() => node.type === 'folder' && toggleFolder(currentPath)}
        >
          {node.type === 'folder' && (
            isExpanded ? <ChevronDown className="w-4 h-4 text-primary" /> : <ChevronRight className="w-4 h-4 text-muted" />
          )}
          {node.type === 'folder' ? (
            <Folder className="w-4 h-4 text-primary" />
          ) : (
            <File className="w-4 h-4 text-secondary" />
          )}
          <span className="text-sm font-mono text-text">{node.name}</span>
        </div>
        {node.type === 'folder' && isExpanded && node.children && (
          <div>
            {node.children.map(child => renderTree(child, currentPath, level + 1))}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="flex-1 p-8 space-y-8 overflow-auto">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-2">
          Terraform Code Refactoring
        </h1>
        <p className="text-muted text-lg">
          Optimize and modularize your exported Terraform configuration
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

        <button
          onClick={handleRefactor}
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
              Refactoring...
            </>
          ) : (
            <>
              <Play className="w-5 h-5" />
              Start Refactoring
            </>
          )}
        </button>
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

      {/* Results - Refactored Code Structure */}
      {result && (
        <div className="space-y-4">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-6 h-6 text-secondary" />
            <h2 className="text-2xl font-bold text-text">Refactoring Complete</h2>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="bg-white rounded-xl border border-border p-4">
              <h3 className="font-semibold text-text mb-3">Refactored Structure</h3>
              <div className="bg-gray-50 rounded-lg p-4 max-h-[500px] overflow-auto">
                {renderTree(result)}
              </div>
            </div>

            <div className="bg-white rounded-xl border border-border p-4 space-y-4">
              <h3 className="font-semibold text-text">Refactoring Summary</h3>
              
              <div className="space-y-3">
                <div className="bg-gradient-to-br from-primary/5 to-secondary/5 rounded-lg p-3">
                  <p className="text-xs text-muted mb-1">Modules Created</p>
                  <p className="text-2xl font-bold text-primary">3</p>
                </div>
                
                <div className="bg-gradient-to-br from-primary/5 to-secondary/5 rounded-lg p-3">
                  <p className="text-xs text-muted mb-1">Files Optimized</p>
                  <p className="text-2xl font-bold text-secondary">12</p>
                </div>
                
                <div className="bg-gradient-to-br from-primary/5 to-secondary/5 rounded-lg p-3">
                  <p className="text-xs text-muted mb-1">Lines Reduced</p>
                  <p className="text-2xl font-bold text-text">847 → 423</p>
                </div>
              </div>

              <div className="bg-green-50 border border-green-200 rounded-lg p-3">
                <h4 className="text-sm font-semibold text-green-900 mb-2">✅ Improvements</h4>
                <ul className="text-xs text-green-800 space-y-1">
                  <li>• Modularized infrastructure components</li>
                  <li>• Standardized naming conventions</li>
                  <li>• Added environment-specific variables</li>
                  <li>• Optimized resource dependencies</li>
                </ul>
              </div>
            </div>
          </div>

          <div className="bg-gradient-to-br from-primary/5 to-secondary/5 rounded-xl border border-primary/20 p-4">
            <p className="text-sm text-text">
              ✅ Refactored code saved to <span className="font-mono font-semibold">aztf-refactored/rg-production</span>
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
