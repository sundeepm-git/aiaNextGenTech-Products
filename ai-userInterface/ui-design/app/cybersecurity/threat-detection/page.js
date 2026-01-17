'use client';

import { useState, useEffect } from 'react';
import { useApp } from '@/context/AppContext';
import {
  ShieldCheckIcon,
  ExclamationTriangleIcon,
  CheckCircleIcon,
  MicrophoneIcon,
  PlayIcon,
  StopIcon,
  CloudArrowUpIcon,
  BoltIcon,
  ChartBarIcon,
  DocumentMagnifyingGlassIcon,
  ShieldExclamationIcon,
  BugAntIcon,
  MagnifyingGlassIcon,
  UserGroupIcon,
  FireIcon,
} from '@heroicons/react/24/outline';
import { LineChart, BarChart } from '@/components/Charts';

export default function ThreatDetectionPage() {
  const { theme } = useApp();

  // Product state management
  const [productEnabled, setProductEnabled] = useState(true);
  const [activeAgent, setActiveAgent] = useState('all'); // all, threat-detection, vulnerability, analytics, incident-response

  // Azure connection state
  const [azureConnected, setAzureConnected] = useState(false);
  const [azureConfig, setAzureConfig] = useState({
    subscriptionId: '',
    tenantId: '',
    resourceGroup: '',
  });

  // NLP Input and Voice state
  const [nlpInput, setNlpInput] = useState('');
  const [isListening, setIsListening] = useState(false);
  const [recognition, setRecognition] = useState(null);

  // Scan state
  const [scanInProgress, setScanInProgress] = useState(false);
  const [scanProgress, setScanProgress] = useState(0);
  const [scanResults, setScanResults] = useState(null);

  // Agent configurations
  const agents = [
    {
      id: 'threat-detection',
      name: 'Threat Detection Pro',
      description: 'AI-powered real-time threat detection with anomaly analysis',
      icon: ShieldCheckIcon,
      color: 'blue',
      capabilities: ['Anomaly Detection', 'Pattern Recognition', 'Behavioral Analysis', 'Real-time Monitoring']
    },
    {
      id: 'vulnerability',
      name: 'Vulnerability Scanner',
      description: 'Automated security vulnerability assessment and CVE tracking',
      icon: BugAntIcon,
      color: 'yellow',
      capabilities: ['CVE Detection', 'Patch Management', 'Security Scoring', 'Compliance Checks']
    },
    {
      id: 'analytics',
      name: 'Security Analytics',
      description: 'Advanced security data analytics and threat intelligence',
      icon: ChartBarIcon,
      color: 'purple',
      capabilities: ['Log Analysis', 'Threat Intelligence', 'Forensics', 'Reporting']
    },
    {
      id: 'incident-response',
      name: 'Incident Response Agent',
      description: 'Automated incident response and mitigation workflows',
      icon: FireIcon,
      color: 'red',
      capabilities: ['Auto-Remediation', 'Playbook Execution', 'Alert Management', 'Containment']
    }
  ];

  // Initialize Web Speech API
  useEffect(() => {
    if (typeof window !== 'undefined' && 'webkitSpeechRecognition' in window) {
      const SpeechRecognition = window.webkitSpeechRecognition || window.SpeechRecognition;
      const recognitionInstance = new SpeechRecognition();
      recognitionInstance.continuous = false;
      recognitionInstance.interimResults = false;
      recognitionInstance.lang = 'en-US';

      recognitionInstance.onresult = (event) => {
        const transcript = event.results[0][0].transcript;
        setNlpInput((prev) => prev + ' ' + transcript);
        setIsListening(false);
      };

      recognitionInstance.onerror = (event) => {
        console.error('Speech recognition error:', event.error);
        setIsListening(false);
      };

      recognitionInstance.onend = () => {
        setIsListening(false);
      };

      setRecognition(recognitionInstance);
    }
  }, []);

  // Handle voice input
  const handleVoiceInput = () => {
    if (!recognition) {
      alert('Speech recognition is not supported in your browser.');
      return;
    }

    if (isListening) {
      recognition.stop();
      setIsListening(false);
    } else {
      recognition.start();
      setIsListening(true);
    }
  };

  // Handle Azure connection
  const handleAzureConnect = async () => {
    // TODO: Backend integration - Connect to Azure using Azure SDK
    // This will validate credentials and establish connection
    try {
      const response = await fetch('/api/cybersecurity/threat-detection/azure-connect', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(azureConfig),
      });
      const data = await response.json();
      if (data.success) {
        setAzureConnected(true);
      }
    } catch (error) {
      console.error('Azure connection failed:', error);
    }
  };

  // Handle threat scan
  const handleStartScan = async () => {
    if (!azureConnected) {
      alert('Please connect to Azure first.');
      return;
    }

    if (!nlpInput.trim()) {
      alert('Please provide a security concern or instruction.');
      return;
    }

    // TODO: Backend integration - Trigger GenAI agentic workflow
    // This will orchestrate multiple agents: Anomaly Detection, Malware Scanning, etc.
    setScanInProgress(true);
    setScanProgress(0);

    try {
      // Simulate scan progress
      const progressInterval = setInterval(() => {
        setScanProgress((prev) => {
          if (prev >= 100) {
            clearInterval(progressInterval);
            return 100;
          }
          return prev + 10;
        });
      }, 500);

      const response = await fetch('/api/cybersecurity/threat-detection/scan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nlpInput, azureConfig, activeAgent }),
      });

      const data = await response.json();
      setScanResults(data);
      setScanInProgress(false);
    } catch (error) {
      console.error('Scan failed:', error);
      setScanInProgress(false);
    }
  };

  // Handle stop scan
  const handleStopScan = () => {
    setScanInProgress(false);
    setScanProgress(0);
  };

  const getColorClasses = (color) => {
    const colors = {
      blue: 'from-blue-500 to-blue-600',
      yellow: 'from-yellow-500 to-orange-600',
      purple: 'from-purple-500 to-purple-600',
      red: 'from-red-500 to-red-600',
    };
    return colors[color] || colors.blue;
  };

  return (
    <div className="space-y-6">
      {/* Page Header with Product Controls */}
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
            nextGen-ThreatDetection
          </h1>
          <p className="text-gray-600 dark:text-gray-400">
            Enterprise Cybersecurity Suite - Unified AI-Powered Security Platform for Azure
          </p>
        </div>
        <div className="flex items-center gap-4">
          <label className="flex items-center gap-2">
            <span className="text-sm text-gray-600 dark:text-gray-400">Enable Suite</span>
            <input
              type="checkbox"
              checked={productEnabled}
              onChange={(e) => setProductEnabled(e.target.checked)}
              className="w-12 h-6 rounded-full appearance-none bg-gray-300 dark:bg-gray-600 checked:bg-blue-600 relative cursor-pointer transition-colors"
            />
          </label>
        </div>
      </div>

      {/* Product Overview Section */}
      <div className="bg-gradient-to-r from-blue-600 via-purple-600 to-red-600 rounded-xl p-8 text-white shadow-2xl">
        <div className="flex items-start gap-6">
          <ShieldCheckIcon className="h-16 w-16 flex-shrink-0 opacity-90" />
          <div className="flex-1">
            <h2 className="text-3xl font-bold mb-3">Unified Cybersecurity Platform</h2>
            <p className="text-blue-100 mb-6 text-lg">
              nextGen-ThreatDetection combines four powerful AI agents into one comprehensive security suite.
              Detect threats, scan vulnerabilities, analyze security data, and automate incident response - all from a single interface.
            </p>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="bg-white/10 backdrop-blur rounded-lg p-4">
                <p className="text-sm opacity-90">Agents Active</p>
                <p className="text-2xl font-bold">4/4</p>
              </div>
              <div className="bg-white/10 backdrop-blur rounded-lg p-4">
                <p className="text-sm opacity-90">Coverage</p>
                <p className="text-2xl font-bold">100%</p>
              </div>
              <div className="bg-white/10 backdrop-blur rounded-lg p-4">
                <p className="text-sm opacity-90">Response Time</p>
                <p className="text-2xl font-bold">&lt; 2s</p>
              </div>
              <div className="bg-white/10 backdrop-blur rounded-lg p-4">
                <p className="text-sm opacity-90">Uptime</p>
                <p className="text-2xl font-bold">99.9%</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Integrated Agent Capabilities */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h3 className="text-xl font-semibold text-gray-900 dark:text-white mb-6">
          Integrated Security Agents
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          {agents.map((agent) => {
            const Icon = agent.icon;
            const isActive = activeAgent === agent.id || activeAgent === 'all';
            return (
              <button
                key={agent.id}
                onClick={() => setActiveAgent(activeAgent === agent.id ? 'all' : agent.id)}
                disabled={!productEnabled}
                className={`p-5 rounded-xl border-2 transition-all text-left ${
                  isActive
                    ? `border-${agent.color}-500 bg-${agent.color}-50 dark:bg-${agent.color}-900/20 shadow-lg scale-105`
                    : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
                } disabled:opacity-50 disabled:cursor-not-allowed`}
              >
                <div className="flex items-start gap-3 mb-3">
                  <div className={`p-2 rounded-lg bg-gradient-to-br ${getColorClasses(agent.color)} text-white`}>
                    <Icon className="h-6 w-6" />
                  </div>
                  <div className="flex-1">
                    <h4 className="font-semibold text-gray-900 dark:text-white text-sm mb-1">
                      {agent.name}
                    </h4>
                    {isActive && (
                      <span className="text-xs px-2 py-1 bg-green-500 text-white rounded-full">
                        Active
                      </span>
                    )}
                  </div>
                </div>
                <p className="text-xs text-gray-600 dark:text-gray-400 mb-3">
                  {agent.description}
                </p>
                <div className="flex flex-wrap gap-1">
                  {agent.capabilities.slice(0, 2).map((cap, idx) => (
                    <span
                      key={idx}
                      className="text-xs px-2 py-1 bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded"
                    >
                      {cap}
                    </span>
                  ))}
                </div>
              </button>
            );
          })}
        </div>
        <p className="text-sm text-gray-500 dark:text-gray-400 text-center">
          Click an agent to focus on specific capabilities, or keep all agents active for comprehensive scanning
        </p>
      </div>

      {/* Azure Connection Panel */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <div className="flex items-center gap-3 mb-4">
          <CloudArrowUpIcon className="h-6 w-6 text-blue-500" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Azure Connection Status
          </h3>
          {azureConnected && (
            <span className="px-3 py-1 bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200 rounded-full text-sm font-medium">
              Connected
            </span>
          )}
        </div>

        {!azureConnected ? (
          <div className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Subscription ID
                </label>
                <input
                  type="text"
                  value={azureConfig.subscriptionId}
                  onChange={(e) => setAzureConfig({ ...azureConfig, subscriptionId: e.target.value })}
                  placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
                  aria-label="Azure Subscription ID"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Tenant ID
                </label>
                <input
                  type="text"
                  value={azureConfig.tenantId}
                  onChange={(e) => setAzureConfig({ ...azureConfig, tenantId: e.target.value })}
                  placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
                  aria-label="Azure Tenant ID"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Resource Group
                </label>
                <input
                  type="text"
                  value={azureConfig.resourceGroup}
                  onChange={(e) => setAzureConfig({ ...azureConfig, resourceGroup: e.target.value })}
                  placeholder="my-resource-group"
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
                  aria-label="Azure Resource Group"
                />
              </div>
            </div>
            <button
              onClick={handleAzureConnect}
              disabled={!azureConfig.subscriptionId || !azureConfig.tenantId}
              className="px-6 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Connect to Azure
            </button>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {/* TODO: Backend - Use Azure Identity SDK for authentication */}
              Secure connection using Azure AD authentication. Your credentials are encrypted.
            </p>
          </div>
        ) : (
          <div className="flex items-center gap-4">
            <CheckCircleIcon className="h-8 w-8 text-green-500" />
            <div>
              <p className="text-gray-900 dark:text-white font-medium">
                Connected to Azure Subscription
              </p>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {azureConfig.subscriptionId.substring(0, 8)}... | {azureConfig.resourceGroup}
              </p>
            </div>
            <button
              onClick={() => setAzureConnected(false)}
              className="ml-auto px-4 py-2 text-red-600 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 font-medium"
            >
              Disconnect
            </button>
          </div>
        )}
      </div>

      {/* NLP Input Box with Voice Support */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <div className="flex items-center gap-3 mb-4">
          <DocumentMagnifyingGlassIcon className="h-6 w-6 text-purple-500" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Natural Language Security Command Center
          </h3>
        </div>

        <div className="space-y-4">
          <div className="relative">
            <textarea
              value={nlpInput}
              onChange={(e) => setNlpInput(e.target.value)}
              placeholder="Describe your security concern or command in natural language...&#10;&#10;Examples:&#10;• Scan all VMs in production for vulnerabilities and malware&#10;• Analyze security logs for suspicious activity in the last 24 hours&#10;• Check IAM permissions for over-privileged accounts&#10;• Run comprehensive threat detection across all Azure resources&#10;• Investigate unusual network traffic patterns&#10;• Execute incident response playbook for detected threats"
              rows={10}
              disabled={!productEnabled || !azureConnected}
              className="w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-purple-500 dark:bg-gray-700 dark:text-white resize-none text-sm"
              aria-label="Natural language security input"
            />
            <button
              onClick={handleVoiceInput}
              disabled={!productEnabled || !azureConnected}
              className={`absolute bottom-4 right-4 p-3 rounded-full transition-all ${
                isListening
                  ? 'bg-red-500 hover:bg-red-600 text-white animate-pulse'
                  : 'bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700 text-white'
              } disabled:opacity-50 disabled:cursor-not-allowed shadow-lg`}
              aria-label={isListening ? 'Stop voice input' : 'Start voice input'}
            >
              <MicrophoneIcon className="h-6 w-6" />
            </button>
          </div>

          <div className="flex items-center gap-4 flex-wrap">
            {!scanInProgress ? (
              <button
                onClick={handleStartScan}
                disabled={!productEnabled || !azureConnected || !nlpInput.trim()}
                className="px-8 py-3 bg-gradient-to-r from-blue-600 via-purple-600 to-red-600 hover:from-blue-700 hover:via-purple-700 hover:to-red-700 text-white rounded-lg font-semibold flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg hover:shadow-xl"
              >
                <PlayIcon className="h-5 w-5" />
                Execute Security Scan
              </button>
            ) : (
              <button
                onClick={handleStopScan}
                className="px-8 py-3 bg-red-600 hover:bg-red-700 text-white rounded-lg font-semibold flex items-center gap-2 transition-colors shadow-lg"
              >
                <StopIcon className="h-5 w-5" />
                Stop Scan
              </button>
            )}

            {isListening && (
              <div className="flex items-center gap-2 text-red-600 dark:text-red-400">
                <div className="animate-pulse">🔴</div>
                <span className="font-medium">Listening...</span>
              </div>
            )}

            <div className="text-sm text-gray-500 dark:text-gray-400">
              Active Agents: <span className="font-semibold">{activeAgent === 'all' ? 'All (4)' : agents.find(a => a.id === activeAgent)?.name || 'All (4)'}</span>
            </div>
          </div>

          <p className="text-sm text-gray-500 dark:text-gray-400">
            {/* TODO: Backend - Integrate Azure OpenAI for NLP processing */}
            Our AI interprets your natural language commands and orchestrates the appropriate security agents automatically.
          </p>
        </div>
      </div>

      {/* Workflow Visualization */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-6">
          Multi-Agent Security Pipeline
        </h3>

        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
          {/* Step 1: Input */}
          <div className={`text-center p-4 rounded-lg border-2 ${
            nlpInput ? 'border-green-500 bg-green-50 dark:bg-green-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-2">
              <DocumentMagnifyingGlassIcon className={`h-8 w-8 ${nlpInput ? 'text-green-600' : 'text-gray-400'}`} />
            </div>
            <p className="font-semibold text-sm text-gray-900 dark:text-white">NLP Input</p>
            <p className="text-xs text-gray-600 dark:text-gray-400">Voice/Text</p>
          </div>

          {/* Step 2: Azure Auth */}
          <div className={`text-center p-4 rounded-lg border-2 ${
            azureConnected ? 'border-green-500 bg-green-50 dark:bg-green-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-2">
              <CloudArrowUpIcon className={`h-8 w-8 ${azureConnected ? 'text-green-600' : 'text-gray-400'}`} />
            </div>
            <p className="font-semibold text-sm text-gray-900 dark:text-white">Azure Auth</p>
            <p className="text-xs text-gray-600 dark:text-gray-400">Connection</p>
          </div>

          {/* Step 3: Threat Detection */}
          <div className={`text-center p-4 rounded-lg border-2 ${
            scanInProgress || scanResults ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-2">
              <ShieldCheckIcon className={`h-8 w-8 ${scanInProgress || scanResults ? 'text-blue-600' : 'text-gray-400'}`} />
            </div>
            <p className="font-semibold text-sm text-gray-900 dark:text-white">Threat Detect</p>
            <p className="text-xs text-gray-600 dark:text-gray-400">Agent 1</p>
          </div>

          {/* Step 4: Vulnerability */}
          <div className={`text-center p-4 rounded-lg border-2 ${
            scanInProgress || scanResults ? 'border-yellow-500 bg-yellow-50 dark:bg-yellow-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-2">
              <BugAntIcon className={`h-8 w-8 ${scanInProgress || scanResults ? 'text-yellow-600' : 'text-gray-400'}`} />
            </div>
            <p className="font-semibold text-sm text-gray-900 dark:text-white">Vuln Scan</p>
            <p className="text-xs text-gray-600 dark:text-gray-400">Agent 2</p>
          </div>

          {/* Step 5: Analytics */}
          <div className={`text-center p-4 rounded-lg border-2 ${
            scanInProgress || scanResults ? 'border-purple-500 bg-purple-50 dark:bg-purple-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-2">
              <ChartBarIcon className={`h-8 w-8 ${scanInProgress || scanResults ? 'text-purple-600' : 'text-gray-400'}`} />
            </div>
            <p className="font-semibold text-sm text-gray-900 dark:text-white">Analytics</p>
            <p className="text-xs text-gray-600 dark:text-gray-400">Agent 3</p>
          </div>

          {/* Step 6: Incident Response */}
          <div className={`text-center p-4 rounded-lg border-2 ${
            scanResults ? 'border-red-500 bg-red-50 dark:bg-red-900/20' : 'border-gray-300 dark:border-gray-600'
          }`}>
            <div className="flex justify-center mb-2">
              <FireIcon className={`h-8 w-8 ${scanResults ? 'text-red-600' : 'text-gray-400'}`} />
            </div>
            <p className="font-semibold text-sm text-gray-900 dark:text-white">Response</p>
            <p className="text-xs text-gray-600 dark:text-gray-400">Agent 4</p>
          </div>
        </div>

        <p className="text-sm text-gray-500 dark:text-gray-400 mt-4 text-center">
          {/* TODO: Backend - Implement agent orchestration using Azure AI Agent Service */}
          All four security agents work in parallel to provide comprehensive protection
        </p>
      </div>

      {/* Scan Progress */}
      {scanInProgress && (
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center gap-3 mb-4">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-purple-600"></div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Multi-Agent Security Scan in Progress...
            </h3>
          </div>
          <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-6 overflow-hidden shadow-inner">
            <div
              className="h-full bg-gradient-to-r from-blue-600 via-purple-600 to-red-600 transition-all duration-500 flex items-center justify-end pr-2"
              style={{ width: `${scanProgress}%` }}
            >
              <span className="text-white text-xs font-bold">{scanProgress}%</span>
            </div>
          </div>
          <p className="text-sm text-gray-600 dark:text-gray-400 mt-2">
            Executing: Threat Detection → Vulnerability Scanning → Security Analytics → Incident Response
          </p>
        </div>
      )}

      {/* Scan Results */}
      {scanResults && (
        <>
          {/* Overall Security Score */}
          <div className="grid grid-cols-1 md:grid-cols-5 gap-6">
            <div className="bg-white dark:bg-gray-800 rounded-lg border-2 border-red-500 p-6 shadow-lg">
              <div className="flex items-center justify-between mb-2">
                <p className="text-sm text-gray-600 dark:text-gray-400">Overall Threat Score</p>
                <ShieldExclamationIcon className="h-6 w-6 text-red-500" />
              </div>
              <p className="text-4xl font-bold text-gray-900 dark:text-white">
                {scanResults.threatScore}<span className="text-2xl text-gray-500">/100</span>
              </p>
              <p className="text-sm text-red-600 dark:text-red-400 mt-1 font-semibold">
                {scanResults.threatLevel}
              </p>
            </div>

            <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
              <div className="flex items-center justify-between mb-2">
                <p className="text-sm text-gray-600 dark:text-gray-400">Anomalies</p>
                <ExclamationTriangleIcon className="h-6 w-6 text-yellow-500" />
              </div>
              <p className="text-4xl font-bold text-gray-900 dark:text-white">
                {scanResults.anomaliesCount}
              </p>
              <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
                Detected
              </p>
            </div>

            <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
              <div className="flex items-center justify-between mb-2">
                <p className="text-sm text-gray-600 dark:text-gray-400">Vulnerabilities</p>
                <BugAntIcon className="h-6 w-6 text-orange-500" />
              </div>
              <p className="text-4xl font-bold text-gray-900 dark:text-white">
                {scanResults.malwareCount}
              </p>
              <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
                Found
              </p>
            </div>

            <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
              <div className="flex items-center justify-between mb-2">
                <p className="text-sm text-gray-600 dark:text-gray-400">Resources</p>
                <CloudArrowUpIcon className="h-6 w-6 text-blue-500" />
              </div>
              <p className="text-4xl font-bold text-gray-900 dark:text-white">
                {scanResults.resourcesScanned}
              </p>
              <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
                Scanned
              </p>
            </div>

            <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
              <div className="flex items-center justify-between mb-2">
                <p className="text-sm text-gray-600 dark:text-gray-400">Incidents</p>
                <FireIcon className="h-6 w-6 text-red-500" />
              </div>
              <p className="text-4xl font-bold text-gray-900 dark:text-white">
                {Math.floor(scanResults.malwareCount / 2)}
              </p>
              <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
                Active
              </p>
            </div>
          </div>

          {/* Detailed Results by Agent */}
          <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
            <h3 className="text-xl font-semibold text-gray-900 dark:text-white mb-6">
              Agent-Specific Findings
            </h3>
            
            {/* Threat Detection Results */}
            <div className="mb-6">
              <div className="flex items-center gap-3 mb-4 p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
                <ShieldCheckIcon className="h-6 w-6 text-blue-600" />
                <h4 className="font-semibold text-gray-900 dark:text-white">Threat Detection Pro - Anomaly Analysis</h4>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-gray-200 dark:border-gray-700">
                      <th className="text-left py-3 px-4 text-sm font-semibold text-gray-900 dark:text-white">
                        Resource
                      </th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-gray-900 dark:text-white">
                        Anomaly Type
                      </th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-gray-900 dark:text-white">
                        Severity
                      </th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-gray-900 dark:text-white">
                        Confidence
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {scanResults.anomalies.map((anomaly, index) => (
                      <tr key={index} className="border-b border-gray-100 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-750">
                        <td className="py-3 px-4 text-sm text-gray-900 dark:text-white font-mono">
                          {anomaly.resource}
                        </td>
                        <td className="py-3 px-4 text-sm text-gray-700 dark:text-gray-300">
                          {anomaly.type}
                        </td>
                        <td className="py-3 px-4">
                          <span className={`px-3 py-1 rounded-full text-xs font-semibold ${
                            anomaly.severity === 'Critical' ? 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200' :
                            anomaly.severity === 'High' ? 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200' :
                            anomaly.severity === 'Medium' ? 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200' :
                            'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'
                          }`}>
                            {anomaly.severity}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-sm text-gray-700 dark:text-gray-300">
                          <div className="flex items-center gap-2">
                            <div className="flex-1 bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                              <div className="bg-blue-600 h-2 rounded-full" style={{ width: `${anomaly.confidence}%` }}></div>
                            </div>
                            <span className="text-xs font-semibold">{anomaly.confidence}%</span>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Vulnerability Scanner Results */}
            <div className="mb-6">
              <div className="flex items-center gap-3 mb-4 p-3 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg">
                <BugAntIcon className="h-6 w-6 text-yellow-600" />
                <h4 className="font-semibold text-gray-900 dark:text-white">Vulnerability Scanner - CVE & Malware Detection</h4>
              </div>
              <div className="space-y-3">
                {scanResults.malwareFindings.map((finding, index) => (
                  <div key={index} className="border-l-4 border-red-500 bg-red-50 dark:bg-red-900/20 rounded-r-lg p-4">
                    <div className="flex items-start gap-3">
                      <ExclamationTriangleIcon className="h-6 w-6 text-red-600 flex-shrink-0 mt-1" />
                      <div className="flex-1">
                        <div className="flex items-center justify-between mb-2 flex-wrap gap-2">
                          <h5 className="font-semibold text-gray-900 dark:text-white">
                            {finding.signature}
                          </h5>
                          <span className="px-3 py-1 bg-red-600 text-white rounded-full text-xs font-semibold">
                            {finding.risk} Risk
                          </span>
                        </div>
                        <p className="text-sm text-gray-700 dark:text-gray-300 mb-2">
                          <strong className="text-gray-900 dark:text-white">Location:</strong> 
                          <code className="ml-2 px-2 py-1 bg-gray-100 dark:bg-gray-800 rounded text-xs">
                            {finding.location}
                          </code>
                        </p>
                        <p className="text-sm text-gray-600 dark:text-gray-400">
                          {finding.description}
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Security Analytics */}
            <div className="mb-6">
              <div className="flex items-center gap-3 mb-4 p-3 bg-purple-50 dark:bg-purple-900/20 rounded-lg">
                <ChartBarIcon className="h-6 w-6 text-purple-600" />
                <h4 className="font-semibold text-gray-900 dark:text-white">Security Analytics - Threat Intelligence & Patterns</h4>
              </div>
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div className="bg-gray-50 dark:bg-gray-900 rounded-lg p-4">
                  <h5 className="text-sm font-semibold text-gray-900 dark:text-white mb-3">Threat Timeline (7 Days)</h5>
                  <LineChart
                    title="Threats"
                    data={scanResults.threatTimeline}
                    labels={['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']}
                  />
                </div>
                <div className="bg-gray-50 dark:bg-gray-900 rounded-lg p-4">
                  <h5 className="text-sm font-semibold text-gray-900 dark:text-white mb-3">Threat Distribution</h5>
                  <BarChart
                    title="Types"
                    data={scanResults.threatDistribution}
                    labels={['Malware', 'Anomaly', 'IAM', 'Network', 'Data', 'Config']}
                  />
                </div>
              </div>
            </div>

            {/* Incident Response */}
            <div>
              <div className="flex items-center gap-3 mb-4 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg">
                <FireIcon className="h-6 w-6 text-red-600" />
                <h4 className="font-semibold text-gray-900 dark:text-white">Incident Response Agent - Automated Recommendations</h4>
              </div>
              <div className="space-y-3">
                {scanResults.recommendations.map((rec, index) => (
                  <div key={index} className="flex items-start gap-4 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800">
                    <CheckCircleIcon className="h-6 w-6 text-blue-600 flex-shrink-0 mt-1" />
                    <div className="flex-1">
                      <div className="flex items-start justify-between gap-4 mb-2">
                        <h5 className="font-semibold text-gray-900 dark:text-white">
                          {rec.title}
                        </h5>
                        <span className={`px-3 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${
                          rec.priority === 'High' ? 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200' :
                          rec.priority === 'Medium' ? 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200' :
                          'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                        }`}>
                          {rec.priority} Priority
                        </span>
                      </div>
                      <p className="text-sm text-gray-700 dark:text-gray-300">
                        {rec.description}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
