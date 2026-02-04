'use client';

import { AgentType, AgentState } from '@/app/hooks/useAgentStream';
import { CheckCircle2, XCircle, Clock, Activity, FileText, Download } from 'lucide-react';
import { cn } from '@/lib/utils';

interface SummaryPageProps {
  agents: Record<AgentType, AgentState>;
}

const AGENT_ORDER: AgentType[] = ['orchestrator', 'assessment', 'migration', 'refactoring', 'summary'];

const AGENT_LABELS: Record<AgentType, string> = {
  orchestrator: 'Orchestrator',
  assessment: 'Assessment',
  migration: 'Migration',
  refactoring: 'Refactoring',
  summary: 'Summary'
};

const AGENT_DESCRIPTIONS: Record<AgentType, string> = {
  orchestrator: 'Coordinates the entire migration workflow and validates prerequisites',
  assessment: 'Analyzes Azure subscription resources for migration compatibility',
  migration: 'Exports Azure resources to Terraform configuration files',
  refactoring: 'Optimizes and modularizes the generated Terraform code',
  summary: 'Generates final migration report and recommendations'
};

export default function SummaryPage({ agents }: SummaryPageProps) {
  // Calculate overall statistics
  const completedAgents = AGENT_ORDER.filter(id => agents[id].status === 'success').length;
  const failedAgents = AGENT_ORDER.filter(id => agents[id].status === 'failed').length;
  const processingAgents = AGENT_ORDER.filter(id => agents[id].status === 'processing').length;
  const idleAgents = AGENT_ORDER.filter(id => agents[id].status === 'idle').length;
  const totalAgents = AGENT_ORDER.length;
  const completionRate = Math.round((completedAgents / totalAgents) * 100);

  return (
    <div className="flex-1 p-8 space-y-8 overflow-auto bg-gray-50">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary mb-2">
          Migration Summary
        </h1>
        <p className="text-muted text-lg">
          Complete overview of all agent activities and outcomes
        </p>
      </div>

      {/* Overall Progress Card */}
      <div className="bg-white rounded-xl border border-border p-6 shadow-sm">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-bold text-text">Overall Progress</h2>
          <div className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary to-secondary">
            {completionRate}%
          </div>
        </div>

        {/* Progress Bar */}
        <div className="w-full h-3 bg-gray-200 rounded-full overflow-hidden mb-6">
          <div 
            className="h-full bg-gradient-to-r from-primary to-secondary transition-all duration-1000"
            style={{ width: `${completionRate}%` }}
          />
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-4 gap-4">
          <div className="bg-green-50 border border-green-200 rounded-lg p-4 text-center">
            <CheckCircle2 className="w-6 h-6 text-green-600 mx-auto mb-2" />
            <p className="text-2xl font-bold text-green-900">{completedAgents}</p>
            <p className="text-xs text-green-700">Completed</p>
          </div>
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 text-center">
            <Activity className="w-6 h-6 text-blue-600 mx-auto mb-2" />
            <p className="text-2xl font-bold text-blue-900">{processingAgents}</p>
            <p className="text-xs text-blue-700">Processing</p>
          </div>
          <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-center">
            <XCircle className="w-6 h-6 text-red-600 mx-auto mb-2" />
            <p className="text-2xl font-bold text-red-900">{failedAgents}</p>
            <p className="text-xs text-red-700">Failed</p>
          </div>
          <div className="bg-gray-50 border border-gray-200 rounded-lg p-4 text-center">
            <Clock className="w-6 h-6 text-gray-600 mx-auto mb-2" />
            <p className="text-2xl font-bold text-gray-900">{idleAgents}</p>
            <p className="text-xs text-gray-700">Pending</p>
          </div>
        </div>
      </div>

      {/* Agent Details Cards */}
      <div className="space-y-4">
        <h2 className="text-xl font-bold text-text">Agent Details</h2>
        
        {AGENT_ORDER.map((agentId) => {
          const agent = agents[agentId];
          const isSuccess = agent.status === 'success';
          const isFailed = agent.status === 'failed';
          const isProcessing = agent.status === 'processing';
          const isIdle = agent.status === 'idle';

          return (
            <div 
              key={agentId}
              className={cn(
                "bg-white rounded-xl border p-6 shadow-sm transition-all",
                isSuccess && "border-secondary",
                isFailed && "border-error",
                isProcessing && "border-primary",
                isIdle && "border-border"
              )}
            >
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center gap-3 mb-2">
                    {isSuccess && <CheckCircle2 className="w-6 h-6 text-secondary" />}
                    {isFailed && <XCircle className="w-6 h-6 text-error" />}
                    {isProcessing && <Activity className="w-6 h-6 text-primary animate-pulse" />}
                    {isIdle && <Clock className="w-6 h-6 text-gray-400" />}
                    
                    <div>
                      <h3 className="text-lg font-bold text-text">{AGENT_LABELS[agentId]}</h3>
                      <p className="text-sm text-muted">{AGENT_DESCRIPTIONS[agentId]}</p>
                    </div>
                  </div>

                  {/* Status Badge */}
                  <div className="flex items-center gap-2 mb-3">
                    <span className={cn(
                      "px-3 py-1 rounded-full text-xs font-semibold",
                      isSuccess && "bg-green-100 text-green-800",
                      isFailed && "bg-red-100 text-red-800",
                      isProcessing && "bg-blue-100 text-blue-800",
                      isIdle && "bg-gray-100 text-gray-800"
                    )}>
                      {agent.status.toUpperCase()}
                    </span>
                    {agent.progress > 0 && (
                      <span className="text-xs text-muted">
                        Progress: {agent.progress}%
                      </span>
                    )}
                  </div>

                  {/* Agent Data Output */}
                  {agent.data && (
                    <div className="bg-gradient-to-br from-primary/5 to-secondary/5 rounded-lg p-4 mb-3">
                      <div className="flex items-start gap-2">
                        <FileText className="w-4 h-4 text-primary mt-0.5" />
                        <div className="flex-1">
                          <p className="text-xs font-semibold text-primary mb-1">Output Data:</p>
                          <p className="text-sm text-text font-mono break-all">
                            {typeof agent.data === 'object' ? JSON.stringify(agent.data, null, 2) : agent.data}
                          </p>
                        </div>
                      </div>
                    </div>
                  )}

                  {/* Logs Preview */}
                  {agent.logs.length > 0 && (
                    <div className="bg-gray-50 rounded-lg p-3 border border-gray-200">
                      <p className="text-xs font-semibold text-muted mb-2">Recent Logs ({agent.logs.length} entries):</p>
                      <div className="space-y-1 max-h-32 overflow-auto">
                        {agent.logs.slice(-3).map((log, idx) => (
                          <p key={idx} className="text-xs font-mono text-gray-700 truncate">
                            {log}
                          </p>
                        ))}
                      </div>
                    </div>
                  )}
                </div>

                {/* Action Button */}
                {isSuccess && agent.data && (
                  <button className="ml-4 p-2 text-primary hover:text-secondary transition-colors">
                    <Download className="w-5 h-5" />
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Export Summary Button */}
      {completedAgents === totalAgents && (
        <div className="bg-gradient-to-r from-primary to-secondary rounded-xl p-6 text-white text-center">
          <h3 className="text-xl font-bold mb-2">🎉 Migration Complete!</h3>
          <p className="mb-4">All agents have successfully completed their tasks.</p>
          <button className="bg-white text-primary px-6 py-3 rounded-lg font-semibold hover:shadow-lg transition-all">
            <Download className="w-5 h-5 inline mr-2" />
            Download Full Report
          </button>
        </div>
      )}
    </div>
  );
}
