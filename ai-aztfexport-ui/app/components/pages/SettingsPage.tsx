'use client';

import { useState, useEffect } from 'react';
import { CheckCircle2, XCircle, AlertCircle, RefreshCw, Terminal, Cloud, Database, FileCode } from 'lucide-react';
import { cn } from '@/lib/utils';

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
    {
      name: 'Azure CLI',
      description: 'Azure Command-Line Interface for resource management',
      status: 'checking',
      icon: Cloud
    },
    {
      name: 'Terraform',
      description: 'Infrastructure as Code tool for Azure resources',
      status: 'checking',
      icon: FileCode
    },
    {
      name: 'aztfexport',
      description: 'Tool for exporting Azure resources to Terraform',
      status: 'checking',
      icon: Terminal
    },
    {
      name: 'Azure Storage',
      description: 'Storage account for migration artifacts',
      status: 'checking',
      icon: Database
    }
  ]);

  const runEnvironmentCheck = async () => {
    setIsChecking(true);
    
    // Simulate checking each environment requirement
    const updatedChecks = [...checks];
    
    for (let i = 0; i < updatedChecks.length; i++) {
      await new Promise(resolve => setTimeout(resolve, 800));
      
      // Simulate check results (in real implementation, call actual verification APIs)
      const randomStatus = Math.random();
      if (randomStatus > 0.7) {
        updatedChecks[i] = {
          ...updatedChecks[i],
          status: 'success',
          message: 'Installed and configured correctly'
        };
      } else if (randomStatus > 0.4) {
        updatedChecks[i] = {
          ...updatedChecks[i],
          status: 'warning',
          message: 'Installed but configuration may need updates'
        };
      } else {
        updatedChecks[i] = {
          ...updatedChecks[i],
          status: 'error',
          message: 'Not found or not configured'
        };
      }
      
      setChecks([...updatedChecks]);
    }
    
    setIsChecking(false);
  };

  useEffect(() => {
    runEnvironmentCheck();
  }, []);

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'success':
        return <CheckCircle2 className="w-6 h-6 text-green-600" />;
      case 'error':
        return <XCircle className="w-6 h-6 text-red-600" />;
      case 'warning':
        return <AlertCircle className="w-6 h-6 text-yellow-600" />;
      case 'checking':
        return <RefreshCw className="w-6 h-6 text-blue-600 animate-spin" />;
      default:
        return null;
    }
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
          Verify your environment configuration and tool installations
        </p>
      </div>

      {/* Summary Card */}
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

        <div className="grid grid-cols-3 gap-4">
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
      </div>

      {/* Environment Checks */}
      <div className="space-y-4">
        <h2 className="text-xl font-bold text-text">Environment Checks</h2>
        
        {checks.map((check, index) => {
          const Icon = check.icon;
          return (
            <div
              key={index}
              className={cn(
                "bg-white rounded-xl border p-6 shadow-sm transition-all",
                check.status === 'success' && "border-green-200",
                check.status === 'error' && "border-red-200",
                check.status === 'warning' && "border-yellow-200",
                check.status === 'checking' && "border-blue-200"
              )}
            >
              <div className="flex items-start gap-4">
                <div className={cn(
                  "p-3 rounded-lg",
                  check.status === 'success' && "bg-green-50",
                  check.status === 'error' && "bg-red-50",
                  check.status === 'warning' && "bg-yellow-50",
                  check.status === 'checking' && "bg-blue-50"
                )}>
                  <Icon className={cn(
                    "w-6 h-6",
                    check.status === 'success' && "text-green-600",
                    check.status === 'error' && "text-red-600",
                    check.status === 'warning' && "text-yellow-600",
                    check.status === 'checking' && "text-blue-600"
                  )} />
                </div>
                
                <div className="flex-1">
                  <div className="flex items-center justify-between mb-2">
                    <h3 className="text-lg font-bold text-text">{check.name}</h3>
                    {getStatusIcon(check.status)}
                  </div>
                  <p className="text-sm text-muted mb-2">{check.description}</p>
                  {check.message && (
                    <p className={cn(
                      "text-sm font-medium",
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

      {/* Configuration Settings */}
      <div className="bg-white rounded-xl border border-border p-6 shadow-sm space-y-4">
        <h2 className="text-xl font-bold text-text">Configuration</h2>
        
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-text mb-2">
              Storage Account Name
            </label>
            <input
              type="text"
              placeholder="aztfexport-storage"
              className="w-full px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent text-sm"
            />
          </div>
          
          <div>
            <label className="block text-sm font-medium text-text mb-2">
              Storage Container
            </label>
            <input
              type="text"
              placeholder="aztf-coderefactor"
              className="w-full px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent text-sm"
            />
          </div>
          
          <div>
            <label className="block text-sm font-medium text-text mb-2">
              MCP Server URL
            </label>
            <input
              type="text"
              placeholder="http://localhost:8080"
              className="w-full px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent text-sm"
            />
          </div>
          
          <button className="bg-gradient-to-r from-primary to-secondary text-white px-6 py-3 rounded-lg font-semibold hover:shadow-lg transition-all">
            Save Configuration
          </button>
        </div>
      </div>
    </div>
  );
}
