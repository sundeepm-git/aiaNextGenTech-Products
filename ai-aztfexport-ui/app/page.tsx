'use client';

import { useState, useEffect } from 'react';
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
import { useAgentStream, AgentType } from './hooks/useAgentStream';
import { useExportProgress } from './hooks/useExportProgress';

export default function Home() {
  const { 
    agents, 
    activeAgent, 
    streamStatus, 
    startOrchestration, 
    reconnect, 
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

  // Page navigation state
  const [currentPage, setCurrentPage] = useState<PageType>('workflow');
  
  // Sidebar visibility state
  const [isSidebarVisible, setIsSidebarVisible] = useState(true);

  // State for which agent logs the user wants to see
  const [selectedView, setSelectedView] = useState<AgentType | 'global'>('global');
  
  // State to track if we're showing real migration progress
  const [showRealMigration, setShowRealMigration] = useState(false);

  // Auto-switch view to the active agent unless user selected something specific
  useEffect(() => {
    if (activeAgent) {
      setSelectedView(activeAgent);
    }
  }, [activeAgent]);

  const handleCommand = (cmd: string) => {
    // Parse command for subscription ID and resource group
    const subIdMatch = cmd.match(/subscription[\s:]+(<?[a-z0-9-]+>?)/i);
    const rgMatch = cmd.match(/(?:resource\s?group|rg)[\s:]+(<?[\w-]+>?)/i);
    
    if (subIdMatch && rgMatch) {
      // Extract IDs (remove angle brackets if present)
      const subscriptionId = subIdMatch[1].replace(/[<>]/g, '');
      const resourceGroup = rgMatch[1].replace(/[<>]/g, '');
      
      // Start real migration export
      setShowRealMigration(true);
      setSelectedView('migration');
      startExport(subscriptionId, resourceGroup, cmd);
    }
    
    // Also start simulation for workflow visualization
    startOrchestration(cmd);
    if (!subIdMatch || !rgMatch) {
      setSelectedView('orchestrator');
    }
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

  const processing = activeAgent ? agents[activeAgent].status === 'processing' : false;

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
        return <SummaryPage agents={agents} />;
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
                    {/* Migration Status Badge */}
                    {showRealMigration && migrationRunning && (
                      <div className="mb-4 p-3 bg-gradient-to-r from-sky-50 to-blue-50 border border-sky-200 rounded-lg flex items-center gap-3">
                        <div className="flex items-center gap-2">
                          <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span>
                          <span className="text-sm font-semibold text-sky-700">
                            Real-time Migration: {migrationStatus}
                          </span>
                        </div>
                        {migrationStatus === 'completed' && (
                          <span className="ml-auto text-xs text-green-600 font-mono">✓ Export Complete</span>
                        )}
                      </div>
                    )}
                    
                    <LiveTerminal 
                        logs={showRealMigration && selectedView === 'migration' ? migrationLogs : logsToShow} 
                        title={selectedView === 'global' ? 'Global Event Stream' : `Agent Context: ${selectedView.toUpperCase()}`}
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
                <ConnectivityGuard onReconnect={reconnect} />
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
