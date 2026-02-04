import type { AgentType, AgentState } from '@/app/types/agent';
import { motion } from 'framer-motion';
import { Check, Loader2, X, Circle, RefreshCw } from 'lucide-react';
import { cn } from '@/lib/utils';

interface AgentPipelineProps {
  agents: Record<AgentType, AgentState>;
  activeAgent: AgentType | null;
  onAgentClick: (id: AgentType) => void;
  onRerun: (id: AgentType) => void;
}

const AGENT_ORDER: AgentType[] = ['orchestrator', 'assessment', 'migration', 'refactoring', 'summary'];

const AGENT_LABELS: Record<AgentType, string> = {
  orchestrator: 'Orchestrator',
  assessment: 'Assessment',
  migration: 'Migration',
  refactoring: 'Refactoring',
  summary: 'Summary'
};

export default function AgentPipeline({ 
  agents, 
  activeAgent, 
  onAgentClick, 
  onRerun 
}: AgentPipelineProps) {
  // Calculate how many agents have completed successfully
  const completedCount = AGENT_ORDER.filter(id => agents[id].status === 'success').length;
  const currentProcessingIndex = AGENT_ORDER.findIndex(id => agents[id].status === 'processing');
  const progressIndex = currentProcessingIndex >= 0 ? currentProcessingIndex : completedCount;
  
  return (
    <div className="w-full py-8">
      <div className="relative flex items-center justify-between max-w-5xl mx-auto px-4">
        
        {/* Background Connection Line */}
        <div className="absolute left-0 top-1/2 -translate-y-1/2 w-full h-1 bg-border z-0"></div>
        
        {/* Animated Progress Line */}
        <div className="absolute left-0 top-1/2 -translate-y-1/2 h-1 bg-gradient-to-r from-primary to-secondary z-0 transition-all duration-1000 shadow-[0_0_8px_rgba(0,120,212,0.4)]"
            style={{ 
                width: `${(progressIndex / (AGENT_ORDER.length - 1)) * 100}%` 
            }} 
        />
        
        {/* Individual Connection Lines Between Agents */}
        {AGENT_ORDER.map((id, index) => {
          if (index === AGENT_ORDER.length - 1) return null;
          
          const currentAgent = agents[id];
          const nextAgent = agents[AGENT_ORDER[index + 1]];
          const isCompleted = currentAgent.status === 'success';
          const isProcessing = currentAgent.status === 'processing';
          const nextIsProcessing = nextAgent.status === 'processing';
          
          return (
            <div 
              key={`line-${id}`}
              className={cn(
                "absolute top-1/2 -translate-y-1/2 h-0.5 transition-all duration-500 z-[1]",
                isCompleted ? "bg-secondary" : 
                isProcessing || nextIsProcessing ? "bg-primary animate-pulse" : 
                "bg-transparent"
              )}
              style={{
                left: `${(index / (AGENT_ORDER.length - 1)) * 100}%`,
                width: `${100 / (AGENT_ORDER.length - 1)}%`
              }}
            />
          );
        })}

        {AGENT_ORDER.map((id, index) => {
          const state = agents[id];
          const isActive = activeAgent === id;
          const isProcessing = state.status === 'processing';
          const isSuccess = state.status === 'success';
          const isFailed = state.status === 'failed';
          const isIdle = state.status === 'idle';

          return (
            <div key={id} className="relative z-10 flex flex-col items-center group">
              
              {/* Node Circle */}
              <button
                onClick={() => onAgentClick(id)}
                className={cn(
                  "w-12 h-12 rounded-full flex items-center justify-center border-4 transition-all duration-300",
                  isActive ? "ring-4 ring-primary/30 scale-110" : "",
                  isProcessing ? "border-primary bg-primary/5 animate-pulse shadow-[0_0_20px_rgba(0,120,212,0.6)]" : 
                  isSuccess ? "border-secondary bg-gradient-to-br from-primary/10 to-secondary/10 shadow-[0_0_12px_rgba(16,110,190,0.4)]" :
                  isFailed ? "border-error bg-error/10 shadow-[0_0_12px_rgba(209,52,56,0.4)]" :
                  "border-border bg-white hover:border-primary hover:shadow-[0_0_8px_rgba(0,120,212,0.3)]"
                )}
              >
                {isProcessing ? (
                  <Loader2 className="w-5 h-5 text-primary animate-spin" />
                ) : isSuccess ? (
                  <Check className="w-6 h-6 text-secondary font-bold" />
                ) : isFailed ? (
                  <X className="w-5 h-5 text-error" />
                ) : (
                  <Circle className="w-5 h-5 text-primary" />
                )}
              </button>

              {/* Label */}
              <div className="mt-3 text-center">
                <p className={cn(
                    "text-sm font-medium transition-colors",
                    isActive || isProcessing ? "text-primary font-semibold" : 
                    isSuccess ? "text-secondary" :
                    isFailed ? "text-error" :
                    "text-muted"
                )}>{AGENT_LABELS[id]}</p>
                
                {/* Status Indicator */}
                {isProcessing && (
                  <p className="text-[10px] text-primary font-medium mt-0.5">Running...</p>
                )}
                {isSuccess && (
                  <p className="text-[10px] text-secondary font-medium mt-0.5">Complete</p>
                )}
                {isFailed && (
                  <p className="text-[10px] text-error font-medium mt-0.5">Failed</p>
                )}
                
                {/* Rerun Button (Only shows if previously run or failed) */}
                {(isSuccess || isFailed) && (
                  <button 
                    onClick={(e) => { e.stopPropagation(); onRerun(id); }}
                    className="mt-1 opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1 text-[10px] text-primary hover:text-secondary mx-auto"
                  >
                    <RefreshCw className="w-3 h-3" /> Re-run
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
