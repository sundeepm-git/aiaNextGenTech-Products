'use client';

import { useState, useEffect, useRef } from 'react';
import Header from './components/Header';
import Sidebar, { PageType } from './components/Sidebar';
import FoundryCommandCenter from './components/FoundryCommandCenter';
import AgentPipeline from './components/AgentPipeline';
import LiveTerminal from './components/LiveTerminal';
import StorageInsightDashboard from './components/StorageInsightDashboard';
import ConnectivityGuard from './components/ConnectivityGuard';
import AssessmentPage from './components/pages/AssessmentPage';
import MigrationPage from './components/pages/MigrationPage';
import RefactoringPage from './components/pages/RefactoringPage';
import SummaryPage from './components/pages/SummaryPage';
import SettingsPage from './components/pages/SettingsPage';
import ReportPage from './components/pages/ReportPage';
import ObservabilityPage from './components/pages/ObservabilityPage';
import { useAgentStream, AgentType } from './hooks/useAgentStream';
import { useExportProgress } from './hooks/useExportProgress';
import { useAgenticWorkflow } from './hooks/useAgenticWorkflow';
import { config } from './services/config';

const SUBSCRIPTION_ID_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;
const RESOURCE_GROUP_RE = /resource\s*group\s*['\"]?([A-Za-z0-9._-]+)['\"]?/i;

// Map SSE agent names from the API to AgentType IDs used by AgentPipeline
const AGENT_NAME_MAP: Record<string, AgentType> = {
  'Orchestrator': 'orchestrator',
  'Assessment': 'assessment',
  'Export': 'migration',
  'Refactor': 'refactoring',
};

export default function Home() {
  const { 
    agents, 
    activeAgent, 
    streamStatus, 
    startOrchestration, 
    reconnect, 
    updateAgent,
    resetAgents,
    setActiveAgent,
    terminalLogs 
  } = useAgentStream();

  // Real-time migration progress hook
  const {
    logs: migrationLogs,
    status: migrationStatus,
    isRunning: migrationRunning,
    startExport,
    reconnect: reconnectMigration,
    clearLogs: clearMigrationLogs
  } = useExportProgress();

  // Agentic workflow hook
  const {
    logs: agenticLogs,
    status: agenticStatus,
    isRunning: agenticRunning,
    currentAgent: agenticCurrentAgent,
    progress: agenticProgress,
    startWorkflow,
    clearLogs: clearAgenticLogs,
  } = useAgenticWorkflow();

  // Page navigation state
  const [currentPage, setCurrentPage] = useState<PageType>('workflow');
  
  // Sidebar visibility state
  const [isSidebarVisible, setIsSidebarVisible] = useState(true);

  // State for which agent logs the user wants to see
  const [selectedView, setSelectedView] = useState<AgentType | 'global'>('global');
  
  // State to track if we're showing real migration progress
  const [showRealMigration, setShowRealMigration] = useState(false);
  const [workflowTarget, setWorkflowTarget] = useState<{ subscriptionId?: string; resourceGroup?: string }>({});

  // Auto-switch view to the active agent unless user selected something specific
  useEffect(() => {
    if (activeAgent) {
      setSelectedView(activeAgent);
    }
  }, [activeAgent]);

  // ── Drive AgentPipeline visuals from real agentic workflow events ──
  // Track how many logs we've already processed so we don't re-process old ones
  const processedLogCount = useRef(0);

  useEffect(() => {
    const newLogs = agenticLogs.slice(processedLogCount.current);
    processedLogCount.current = agenticLogs.length;

    for (const log of newLogs) {
      // Detect agent started → set to 'processing'
      if (log.message.startsWith('Agent started:') && log.agent) {
        const agentType = AGENT_NAME_MAP[log.agent];
        if (agentType) {
          setActiveAgent(agentType);
          updateAgent(agentType, { status: 'processing' });
        }
      }

      // Detect SUCCESS → set current agent to 'success' (green)
      if (log.type === 'success' && log.message.includes('SUCCESS') && log.agent) {
        const agentType = AGENT_NAME_MAP[log.agent];
        if (agentType) {
          updateAgent(agentType, { status: 'success' });
        }
      }

      // Detect errors/failures → set current agent to 'failed' (red)
      if (log.type === 'error' && log.agent) {
        const agentType = AGENT_NAME_MAP[log.agent];
        if (agentType) {
          updateAgent(agentType, { status: 'failed' });
        }
      }
    }

    // When the whole pipeline completes, mark summary as success
    if (agenticStatus === 'completed') {
      updateAgent('summary', { status: 'success' });
    }

    // When the pipeline fails, mark summary as failed (red)
    if (agenticStatus === 'failed') {
      updateAgent('summary', { status: 'failed' });
    }
  }, [agenticLogs, agenticStatus, setActiveAgent, updateAgent]);

  const handleCommand = (cmd: string) => {
    // Send the NLP prompt directly to the agentic workflow pipeline
    // The Orchestrator agent will extract subscriptionId and resourceGroup from the prompt
    setShowRealMigration(true);
    setSelectedView('migration');
    clearAgenticLogs();
    processedLogCount.current = 0;

    // Reset pipeline visuals to idle before starting
    resetAgents();

    const subMatch = cmd.match(SUBSCRIPTION_ID_RE);
    const rgMatch = cmd.match(RESOURCE_GROUP_RE);
    setWorkflowTarget({
      subscriptionId: subMatch?.[0],
      resourceGroup: rgMatch?.[1],
    });

    // Start the real agentic workflow — AgentPipeline will update via the useEffect above
    startWorkflow(cmd);
  };

  const handleAgentClick = (id: AgentType) => {
    setSelectedView(id);
  };

  const handleRerun = (id: AgentType) => {
    // Logic to trigger rerun for specific agent
    console.log(`Rerunning ${id}...`);
    // fetch('/api/rerun', { body: JSON.stringify({ agent: id }) })
  };

  // Determine which logs to show
  const logsToShow = selectedView === 'global' 
    ? terminalLogs 
    : agents[selectedView].logs.length > 0 
        ? agents[selectedView].logs 
        : [`[SYSTEM] Waiting for ${selectedView} logs...`];

  const processing = agenticRunning || (activeAgent ? agents[activeAgent].status === 'processing' : false);

  // Render different page content based on navigation
  const renderPageContent = () => {
    switch (currentPage) {
      case 'assessment':
        return <AssessmentPage />;
      case 'migration':
        return <MigrationPage />;
      case 'refactoring':
        return <RefactoringPage />;
      case 'summary':
        return (
          <SummaryPage
            agents={agents}
            subscriptionId={workflowTarget.subscriptionId}
            resourceGroup={workflowTarget.resourceGroup}
          />
        );
      case 'report':
        return <ReportPage />;
      case 'observability':
        return <ObservabilityPage />;
      case 'settings':
        return <SettingsPage />;
      case 'workflow':
      default:
        return (
          <div className="flex-1 w-full max-w-7xl mx-auto p-6 space-y-8 pb-24 bg-surface">
        
            {/* Section 1: Command Center */}
            <section className="py-8">
                <div className="text-center mb-10">
                  <h2 className="text-4xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-4">
                        Orchestrate Azure To Terraform Migration
                    </h2>
                  <p className="text-muted text-lg max-w-2xl mx-auto">
                        Azure to Terraform Export uses a sequential AI agentic workflow to assess, export, and refactor your Azure infrastructure into clean, reusable templates.
                    </p>
                </div>
                
                <FoundryCommandCenter 
                    onCommandSubmit={handleCommand} 
                    isProcessing={processing}
                    intentPreview={agents.orchestrator.data}
                />
            </section>

            {/* Section 2: Agent Pipeline */}
            <section>
                <AgentPipeline 
                    agents={agents}
                    activeAgent={activeAgent}
                    onAgentClick={handleAgentClick}
                    onRerun={handleRerun}
                />
            </section>

            {/* Section 3: Split View (Terminal & Storage) */}
            <section className="grid grid-cols-1 lg:grid-cols-3 gap-6 h-[600px]">
                
                {/* Live Terminal (Takes 2/3 width on large screens) */}
                <div className="lg:col-span-2 h-full">
                    {/* Agentic Pipeline Status Badge */}
                    {showRealMigration && (agenticRunning || agenticStatus === 'completed' || agenticStatus === 'failed') && (
                      <div className={`mb-4 p-3 bg-gradient-to-r ${agenticStatus === 'completed' ? 'from-green-50 to-emerald-50 border-green-200' : agenticStatus === 'failed' ? 'from-red-50 to-orange-50 border-red-200' : 'from-purple-50 to-blue-50 border-purple-200'} border rounded-lg flex items-center gap-3`}>
                        <div className="flex items-center gap-2">
                          <span className={`w-2 h-2 rounded-full ${agenticStatus === 'completed' ? 'bg-green-500' : agenticStatus === 'failed' ? 'bg-red-500' : 'bg-purple-500 animate-pulse'}`}></span>
                          <span className={`text-sm font-semibold ${agenticStatus === 'completed' ? 'text-green-700' : agenticStatus === 'failed' ? 'text-red-700' : 'text-purple-700'}`}>
                            Agentic Pipeline: {agenticCurrentAgent || agenticStatus} — {agenticProgress}%
                          </span>
                        </div>
                        {agenticStatus === 'completed' && (
                          <span className="ml-auto text-xs text-green-600 font-mono">✓ Pipeline Complete</span>
                        )}
                        {agenticStatus === 'failed' && (
                          <span className="ml-auto text-xs text-red-600 font-mono">✗ Pipeline Failed</span>
                        )}
                      </div>
                    )}
                    
                    {/* Endpoint URLs Info Bar */}
                    <div className="mb-2 px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-md flex flex-wrap items-center gap-x-4 gap-y-1 text-[11px] font-mono text-gray-500">
                      <span className="flex items-center gap-1">
                        <span className="w-1.5 h-1.5 rounded-full bg-blue-400"></span>
                        API: <span className="text-gray-700">{config.workflow.baseUrl}</span>
                      </span>
                      <span className="flex items-center gap-1">
                        <span className="w-1.5 h-1.5 rounded-full bg-amber-400"></span>
                        MCP: <span className="text-gray-700">{config.mcpServer.baseUrl}</span>
                      </span>
                    </div>

                    <LiveTerminal 
                        logs={showRealMigration && agenticLogs.length > 0 ? agenticLogs.map(l => `[${l.agent || 'SYSTEM'}] ${l.message}`) : logsToShow} 
                        title={showRealMigration && agenticLogs.length > 0 ? 'Agentic Pipeline Progress' : selectedView === 'global' ? 'Global Event Stream' : `Agent Context: ${selectedView.toUpperCase()}`}
                    />
                </div>

                {/* Storage Insights (Takes 1/3 width) */}
                <div className="lg:col-span-1 h-full overflow-y-auto">
                  <div className="bg-white rounded-xl border border-border p-6 h-full flex flex-col shadow-sm">
                    <h3 className="text-sm font-bold text-text uppercase tracking-wider mb-6 flex items-center gap-2">
                      <span className="w-1.5 h-1.5 rounded-full bg-primary"></span>
                      Storage Insights
                    </h3>
                        <StorageInsightDashboard />
                        
                        {/* Context Specific Data Display */}
                        {selectedView === 'assessment' && agents.assessment.data && (
                      <div className="mt-6 p-4 bg-primary/5 rounded-lg border border-primary/20">
                        <h4 className="text-primary font-mono text-xs mb-2 uppercase">Report Available</h4>
                        <a href="#" className="text-sm underline text-text hover:text-primary break-all">
                                    {agents.assessment.data}
                                </a>
                            </div>
                        )}
                    </div>
                </div>
            </section>

            {/* Disconnection Fallback */}
            {streamStatus === 'offline' && (
                <ConnectivityGuard status={streamStatus} onReconnect={reconnect} />
            )}
          </div>
        );
    }
  };

  return (
    <main className="min-h-screen flex flex-col bg-white selection:bg-primary/20">
      <Header onToggleSidebar={() => setIsSidebarVisible(!isSidebarVisible)} />
      
      <div className="flex flex-1">
        <Sidebar 
          currentPage={currentPage} 
          onPageChange={setCurrentPage} 
          isVisible={isSidebarVisible}
        />
        {renderPageContent()}
      </div>
    </main>
  );
}
