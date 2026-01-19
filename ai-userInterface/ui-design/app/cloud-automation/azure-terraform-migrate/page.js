'use client';

import { useState, useEffect } from 'react';
import { useApp } from '@/context/AppContext';
import {
  CloudArrowDownIcon,
  CloudArrowUpIcon,
  CloudIcon,
  DocumentTextIcon,
  CheckCircleIcon,
  PlayIcon,
  ArrowPathIcon,
  FolderIcon,
  CodeBracketIcon,
  ServerIcon,
  CircleStackIcon,
  CpuChipIcon,
  PlusIcon,
  XMarkIcon,
  DocumentArrowDownIcon,
} from '@heroicons/react/24/outline';
import { LineChart, BarChart } from '@/components/Charts';

export default function AzureTerraformMigratePage() {
  const { theme } = useApp();

  // Product state
  const [productEnabled, setProductEnabled] = useState(true);

  // Azure connection state
  const [azureConnected, setAzureConnected] = useState(false);
  const [subscriptionId, setSubscriptionId] = useState('');
  const [resourceGroups, setResourceGroups] = useState(['']);

  // Migration state
  const [migrationInProgress, setMigrationInProgress] = useState(false);
  const [migrationProgress, setMigrationProgress] = useState(0);
  const [discoveredResources, setDiscoveredResources] = useState(null);
  const [terraformCode, setTerraformCode] = useState(null);
  const [selectedResources, setSelectedResources] = useState([]);

  // Add/Remove resource group inputs
  const addResourceGroup = () => {
    setResourceGroups([...resourceGroups, '']);
  };

  const removeResourceGroup = (index) => {
    if (resourceGroups.length > 1) {
      setResourceGroups(resourceGroups.filter((_, i) => i !== index));
    }
  };

  const updateResourceGroup = (index, value) => {
    const updated = [...resourceGroups];
    updated[index] = value;
    setResourceGroups(updated);
  };

  // Handle Azure connection
  const handleAzureConnect = async () => {
    // TODO: Backend integration - Connect to Azure using Azure SDK
    try {
      const response = await fetch('/api/cloud-automation/azure-terraform/connect', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ subscriptionId, resourceGroups: resourceGroups.filter(rg => rg.trim()) }),
      });
      const data = await response.json();
      if (data.success) {
        setAzureConnected(true);
      }
    } catch (error) {
      console.error('Azure connection failed:', error);
    }
  };

  // Discover Azure resources
  const handleDiscoverResources = async () => {
    if (!azureConnected) {
      alert('Please connect to Azure first.');
      return;
    }

    setMigrationInProgress(true);
    setMigrationProgress(0);

    try {
      // Simulate progress
      const progressInterval = setInterval(() => {
        setMigrationProgress((prev) => {
          if (prev >= 100) {
            clearInterval(progressInterval);
            return 100;
          }
          return prev + 10;
        });
      }, 300);

      const response = await fetch('/api/cloud-automation/azure-terraform/discover', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          subscriptionId, 
          resourceGroups: resourceGroups.filter(rg => rg.trim()) 
        }),
      });

      const data = await response.json();
      setDiscoveredResources(data);
      setSelectedResources(data.resources.map(r => r.id));
      setMigrationInProgress(false);
    } catch (error) {
      console.error('Discovery failed:', error);
      setMigrationInProgress(false);
    }
  };

  // Generate Terraform code
  const handleGenerateTerraform = async () => {
    setMigrationInProgress(true);
    setMigrationProgress(0);

    try {
      const progressInterval = setInterval(() => {
        setMigrationProgress((prev) => {
          if (prev >= 100) {
            clearInterval(progressInterval);
            return 100;
          }
          return prev + 12;
        });
      }, 400);

      const response = await fetch('/api/cloud-automation/azure-terraform/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          subscriptionId,
          resourceGroups: resourceGroups.filter(rg => rg.trim()),
          resourceIds: selectedResources 
        }),
      });

      const data = await response.json();
      setTerraformCode(data);
      setMigrationInProgress(false);
    } catch (error) {
      console.error('Generation failed:', error);
      setMigrationInProgress(false);
    }
  };

  // Download Terraform files
  const handleDownloadTerraform = () => {
    if (!terraformCode) return;

    const blob = new Blob([terraformCode.code], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'main.tf';
    a.click();
    URL.revokeObjectURL(url);
  };

  const toggleResourceSelection = (resourceId) => {
    setSelectedResources(prev => 
      prev.includes(resourceId) 
        ? prev.filter(id => id !== resourceId)
        : [...prev, resourceId]
    );
  };

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
            Azure to Terraform Migration
          </h1>
          <p className="text-gray-600 dark:text-gray-400">
            Automated Infrastructure as Code generation from your Azure resources
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-sm text-gray-600 dark:text-gray-400">Enable Product</span>
          <input
            type="checkbox"
            checked={productEnabled}
            onChange={(e) => setProductEnabled(e.target.checked)}
            className="w-12 h-6 rounded-full appearance-none bg-gray-300 dark:bg-gray-600 checked:bg-primary relative cursor-pointer transition-colors"
          />
        </div>
      </div>

      {/* Product Overview */}
      <div 
        className="rounded-xl p-8 shadow-2xl border transition-all duration-300"
        style={{
          background: 'linear-gradient(135deg, var(--bg-card) 0%, var(--bg-hover) 100%)',
          borderColor: 'var(--border-main)'
        }}
      >
        <div className="flex items-start gap-6">
          <CloudArrowDownIcon className="h-16 w-16 flex-shrink-0" style={{ color: 'var(--color-accent)' }} />
          <div className="flex-1">
            <h2 className="text-3xl font-bold mb-3" style={{ color: 'var(--text-main)' }}>Seamless Cloud Infrastructure Migration</h2>
            <p className="mb-6 text-lg" style={{ color: 'var(--text-muted)' }}>
              Transform your existing Azure infrastructure into fully-functional Terraform code. 
              Discover resources, generate IaC configurations, and manage your cloud infrastructure with version control.
            </p>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="bg-white/5 backdrop-blur rounded-lg p-4 border border-gray-200/20">
                <p className="text-sm opacity-90" style={{ color: 'var(--text-muted)' }}>Resource Types</p>
                <p className="text-2xl font-bold" style={{ color: 'var(--text-main)' }}>50+</p>
              </div>
              <div className="bg-white/5 backdrop-blur rounded-lg p-4 border border-gray-200/20">
                <p className="text-sm opacity-90" style={{ color: 'var(--text-muted)' }}>Code Quality</p>
                <p className="text-2xl font-bold" style={{ color: 'var(--text-main)' }}>HCL 2.0</p>
              </div>
              <div className="bg-white/5 backdrop-blur rounded-lg p-4 border border-gray-200/20">
                <p className="text-sm opacity-90" style={{ color: 'var(--text-muted)' }}>Migration Time</p>
                <p className="text-2xl font-bold" style={{ color: 'var(--text-main)' }}>&lt; 5min</p>
              </div>
              <div className="bg-white/5 backdrop-blur rounded-lg p-4 border border-gray-200/20">
                <p className="text-sm opacity-90" style={{ color: 'var(--text-muted)' }}>Accuracy</p>
                <div className="flex items-center gap-2">
                   <div className="h-2 w-2 rounded-full bg-green-500 animate-pulse"></div>
                   <p className="text-2xl font-bold" style={{ color: 'var(--text-main)' }}>99%</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Azure Connection Panel */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <div className="flex items-center gap-3 mb-4">
          <CloudArrowUpIcon className="h-6 w-6 text-blue-500" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Azure Connection
          </h3>
          {azureConnected && (
            <span className="px-3 py-1 bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200 rounded-full text-sm font-medium">
              Connected
            </span>
          )}
        </div>

        {!azureConnected ? (
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Azure Subscription ID *
              </label>
              <input
                type="text"
                value={subscriptionId}
                onChange={(e) => setSubscriptionId(e.target.value)}
                placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
                disabled={!productEnabled}
              />
            </div>

            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  Resource Groups *
                </label>
                <button
                  onClick={addResourceGroup}
                  disabled={!productEnabled}
                  className="flex items-center gap-2 px-3 py-1 text-sm bg-primary/10 text-primary rounded-lg hover:bg-primary/20 transition-colors disabled:opacity-50"
                >
                  <PlusIcon className="h-4 w-4" />
                  Add Resource Group
                </button>
              </div>
              <div className="space-y-3">
                {resourceGroups.map((rg, index) => (
                  <div key={index} className="flex items-center gap-2">
                    <input
                      type="text"
                      value={rg}
                      onChange={(e) => updateResourceGroup(index, e.target.value)}
                      placeholder={`resource-group-${index + 1}`}
                      className="flex-1 px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-primary dark:bg-gray-700 dark:text-white"
                      disabled={!productEnabled}
                    />
                    {resourceGroups.length > 1 && (
                      <button
                        onClick={() => removeResourceGroup(index)}
                        disabled={!productEnabled}
                        className="p-2 text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors disabled:opacity-50"
                        aria-label="Remove resource group"
                      >
                        <XMarkIcon className="h-5 w-5" />
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </div>

            <button
              onClick={handleAzureConnect}
              disabled={!productEnabled || !subscriptionId || resourceGroups.filter(rg => rg.trim()).length === 0}
              className="px-6 py-2 bg-primary hover:opacity-90 text-white rounded-lg font-medium disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Connect to Azure
            </button>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {/* TODO: Backend - Use Azure Identity SDK for authentication */}
              Secure connection using Azure AD authentication with read-only permissions.
            </p>
          </div>
        ) : (
          <div className="flex items-center gap-4">
            <CheckCircleIcon className="h-8 w-8 text-green-500" />
            <div className="flex-1">
              <p className="text-gray-900 dark:text-white font-medium">
                Connected to Azure Subscription
              </p>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {subscriptionId.substring(0, 8)}... | {resourceGroups.filter(rg => rg.trim()).length} resource group(s)
              </p>
            </div>
            <button
              onClick={() => setAzureConnected(false)}
              className="px-4 py-2 text-red-600 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 font-medium"
            >
              Disconnect
            </button>
          </div>
        )}
      </div>

      {/* Migration Workflow */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-6">
          Migration Workflow
        </h3>

        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {/* Step 1 */}
          <div className={`p-5 rounded-lg border-2 ${
            azureConnected ? 'border-green-500 bg-green-50 dark:bg-green-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-3">
              <CloudArrowUpIcon className={`h-10 w-10 ${azureConnected ? 'text-green-600' : 'text-gray-400'}`} />
            </div>
            <p className="text-center font-semibold text-gray-900 dark:text-white mb-1">1. Connect</p>
            <p className="text-xs text-center text-gray-600 dark:text-gray-400">Azure Subscription</p>
          </div>

          {/* Step 2 */}
          <div className={`p-5 rounded-lg border-2 ${
            discoveredResources ? 'border-green-500 bg-green-50 dark:bg-green-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-3">
              <ServerIcon className={`h-10 w-10 ${discoveredResources ? 'text-green-600' : 'text-gray-400'}`} />
            </div>
            <p className="text-center font-semibold text-gray-900 dark:text-white mb-1">2. Discover</p>
            <p className="text-xs text-center text-gray-600 dark:text-gray-400">Azure Resources</p>
          </div>

          {/* Step 3 */}
          <div className={`p-5 rounded-lg border-2 ${
            terraformCode ? 'border-green-500 bg-green-50 dark:bg-green-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-3">
              <CodeBracketIcon className={`h-10 w-10 ${terraformCode ? 'text-green-600' : 'text-gray-400'}`} />
            </div>
            <p className="text-center font-semibold text-gray-900 dark:text-white mb-1">3. Generate</p>
            <p className="text-xs text-center text-gray-600 dark:text-gray-400">Terraform Code</p>
          </div>

          {/* Step 4 */}
          <div className={`p-5 rounded-lg border-2 ${
            terraformCode ? 'border-primary bg-primary/10' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-3">
              <DocumentArrowDownIcon className={`h-10 w-10 ${terraformCode ? 'text-primary' : 'text-gray-400'}`} />
            </div>
            <p className="text-center font-semibold text-gray-900 dark:text-white mb-1">4. Download</p>
            <p className="text-xs text-center text-gray-600 dark:text-gray-400">Terraform Files</p>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex items-center gap-4 mt-6">
          {!discoveredResources ? (
            <button
              onClick={handleDiscoverResources}
              disabled={!productEnabled || !azureConnected || migrationInProgress}
              className="px-6 py-3 bg-gradient-to-r from-primary to-primary/80 hover:opacity-90 text-white rounded-lg font-semibold flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg"
            >
              <PlayIcon className="h-5 w-5" />
              Discover Resources
            </button>
          ) : !terraformCode ? (
            <button
              onClick={handleGenerateTerraform}
              disabled={!productEnabled || selectedResources.length === 0 || migrationInProgress}
              className="px-6 py-3 bg-gradient-to-r from-primary to-primary/80 hover:opacity-90 text-white rounded-lg font-semibold flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg"
            >
              <CodeBracketIcon className="h-5 w-5" />
              Generate Terraform Code
            </button>
          ) : (
            <button
              onClick={handleDownloadTerraform}
              className="px-6 py-3 bg-gradient-to-r from-green-600 to-emerald-600 hover:from-green-700 hover:to-emerald-700 text-white rounded-lg font-semibold flex items-center gap-2 transition-all shadow-lg"
            >
              <DocumentArrowDownIcon className="h-5 w-5" />
              Download Terraform Files
            </button>
          )}

          {discoveredResources && (
            <button
              onClick={() => {
                setDiscoveredResources(null);
                setTerraformCode(null);
                setSelectedResources([]);
              }}
              className="px-6 py-3 border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 rounded-lg font-medium hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors flex items-center gap-2"
            >
              <ArrowPathIcon className="h-5 w-5" />
              Reset Discovery
            </button>
          )}
        </div>
      </div>

      {/* Progress Bar */}
      {migrationInProgress && (
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center gap-3 mb-4">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              {!discoveredResources ? 'Discovering Azure Resources...' : 'Generating Terraform Code...'}
            </h3>
          </div>
          <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-6 overflow-hidden shadow-inner">
            <div
              className="h-full bg-gradient-to-r from-blue-600 via-cyan-600 to-blue-600 transition-all duration-500 flex items-center justify-end pr-2"
              style={{ width: `${migrationProgress}%` }}
            >
              <span className="text-white text-xs font-bold">{migrationProgress}%</span>
            </div>
          </div>
          <p className="text-sm text-gray-600 dark:text-gray-400 mt-2">
            {!discoveredResources ? 'Scanning resource groups and identifying resources...' : 'Converting Azure resources to Terraform HCL format...'}
          </p>
        </div>
      )}

      {/* Discovered Resources */}
      {discoveredResources && !terraformCode && (
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Discovered Resources ({discoveredResources.resources.length})
            </h3>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              {selectedResources.length} selected for migration
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {discoveredResources.resources.map((resource) => (
              <div
                key={resource.id}
                className={`p-4 rounded-lg border-2 cursor-pointer transition-all ${
                  selectedResources.includes(resource.id)
                    ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/20'
                    : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
                }`}
                onClick={() => toggleResourceSelection(resource.id)}
              >
                <div className="flex items-start gap-3">
                  <div className="p-2 rounded-lg bg-gradient-to-br from-blue-500 to-cyan-600 text-white">
                    {resource.type.includes('VirtualMachines') ? <ServerIcon className="h-5 w-5" /> :
                     resource.type.includes('Storage') ? <CircleStackIcon className="h-5 w-5" /> :
                     resource.type.includes('Network') ? <CloudIcon className="h-5 w-5" /> :
                     <CpuChipIcon className="h-5 w-5" />}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-gray-900 dark:text-white text-sm truncate">
                      {resource.name}
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                      {resource.type}
                    </p>
                    <p className="text-xs text-gray-600 dark:text-gray-500 mt-1">
                      {resource.resourceGroup}
                    </p>
                  </div>
                  {selectedResources.includes(resource.id) && (
                    <CheckCircleIcon className="h-5 w-5 text-primary flex-shrink-0" />
                  )}
                </div>
              </div>
            ))}
          </div>

          {/* Resource Statistics */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-6 pt-6 border-t border-gray-200 dark:border-gray-700">
            <div className="text-center">
              <p className="text-2xl font-bold text-gray-900 dark:text-white">
                {discoveredResources.statistics.totalResources}
              </p>
              <p className="text-sm text-gray-600 dark:text-gray-400">Total Resources</p>
            </div>
            <div className="text-center">
              <p className="text-2xl font-bold text-gray-900 dark:text-white">
                {discoveredResources.statistics.resourceTypes}
              </p>
              <p className="text-sm text-gray-600 dark:text-gray-400">Resource Types</p>
            </div>
            <div className="text-center">
              <p className="text-2xl font-bold text-gray-900 dark:text-white">
                {discoveredResources.statistics.resourceGroups}
              </p>
              <p className="text-sm text-gray-600 dark:text-gray-400">Resource Groups</p>
            </div>
            <div className="text-center">
              <p className="text-2xl font-bold text-gray-900 dark:text-white">
                {selectedResources.length}
              </p>
              <p className="text-sm text-gray-600 dark:text-gray-400">Selected</p>
            </div>
          </div>
        </div>
      )}

      {/* Generated Terraform Code */}
      {terraformCode && (
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Generated Terraform Code
            </h3>
            <div className="flex items-center gap-2">
              <span className="px-3 py-1 bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200 rounded-full text-sm font-medium">
                {terraformCode.filesGenerated} files
              </span>
              <span className="px-3 py-1 bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200 rounded-full text-sm font-medium">
                {terraformCode.linesOfCode} lines
              </span>
            </div>
          </div>

          <div className="bg-gray-900 rounded-lg p-4 overflow-x-auto">
            <pre className="text-green-400 text-sm font-mono">
              <code>{terraformCode.code}</code>
            </pre>
          </div>

          <div className="mt-4 grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="p-4 bg-gray-50 dark:bg-gray-900 rounded-lg">
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Terraform Version</p>
              <p className="text-lg font-semibold text-gray-900 dark:text-white">{terraformCode.terraformVersion}</p>
            </div>
            <div className="p-4 bg-gray-50 dark:bg-gray-900 rounded-lg">
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Provider Version</p>
              <p className="text-lg font-semibold text-gray-900 dark:text-white">{terraformCode.providerVersion}</p>
            </div>
            <div className="p-4 bg-gray-50 dark:bg-gray-900 rounded-lg">
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Resources Migrated</p>
              <p className="text-lg font-semibold text-gray-900 dark:text-white">{terraformCode.resourcesMigrated}</p>
            </div>
          </div>
        </div>
      )}

      {/* Features */}
      {!discoveredResources && (
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-6">
            Key Features
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div className="flex items-start gap-4">
              <div className="p-3 bg-primary/10 rounded-lg">
                <ServerIcon className="h-6 w-6 text-primary" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900 dark:text-white mb-2">
                  Multi-Resource Support
                </h4>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  Supports 50+ Azure resource types including VMs, Storage, Networks, and Databases
                </p>
              </div>
            </div>

            <div className="flex items-start gap-4">
              <div className="p-3 bg-cyan-100 dark:bg-cyan-900/20 rounded-lg">
                <FolderIcon className="h-6 w-6 text-cyan-600" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900 dark:text-white mb-2">
                  Multiple Resource Groups
                </h4>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  Migrate one or multiple resource groups in a single operation
                </p>
              </div>
            </div>

            <div className="flex items-start gap-4">
              <div className="p-3 bg-green-100 dark:bg-green-900/20 rounded-lg">
                <CodeBracketIcon className="h-6 w-6 text-green-600" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900 dark:text-white mb-2">
                  Clean HCL 2.0 Code
                </h4>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  Generates production-ready Terraform code following best practices
                </p>
              </div>
            </div>

            <div className="flex items-start gap-4">
              <div className="p-3 bg-purple-100 dark:bg-purple-900/20 rounded-lg">
                <CheckCircleIcon className="h-6 w-6 text-purple-600" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900 dark:text-white mb-2">
                  Selective Migration
                </h4>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  Choose which resources to migrate with granular control
                </p>
              </div>
            </div>

            <div className="flex items-start gap-4">
              <div className="p-3 bg-yellow-100 dark:bg-yellow-900/20 rounded-lg">
                <DocumentTextIcon className="h-6 w-6 text-yellow-600" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900 dark:text-white mb-2">
                  State File Generation
                </h4>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  Automatically generates terraform.tfstate for existing infrastructure
                </p>
              </div>
            </div>

            <div className="flex items-start gap-4">
              <div className="p-3 bg-red-100 dark:bg-red-900/20 rounded-lg">
                <CloudArrowDownIcon className="h-6 w-6 text-red-600" />
              </div>
              <div>
                <h4 className="font-semibold text-gray-900 dark:text-white mb-2">
                  Instant Download
                </h4>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  Download complete Terraform project structure ready for deployment
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
