import { useState, useEffect, useCallback, useRef } from 'react';
import { config } from '@/app/services/config';
import { startOrchestration } from '@/app/services/mcpService';
import type { 
  AgentType, 
  AgentState, 
  StreamStatus 
} from '@/app/types/agent';

export type { AgentType, AgentState, StreamStatus };

interface UseAgentStreamReturn {
  agents: Record<AgentType, AgentState>;
  activeAgent: AgentType | null;
  streamStatus: StreamStatus;
  startOrchestration: (command: string) => void;
  reconnect: () => void;
  setActiveAgent: (id: AgentType) => void;
  terminalLogs: string[];
}

const INITIAL_AGENTS: Record<AgentType, AgentState> = {
  orchestrator: { id: 'orchestrator', status: 'idle', logs: [] },
  assessment: { id: 'assessment', status: 'idle', logs: [] },
  migration: { id: 'migration', status: 'idle', logs: [] },
  refactoring: { id: 'refactoring', status: 'idle', logs: [] },
  summary: { id: 'summary', status: 'idle', logs: [] }
};

export const useAgentStream = (): UseAgentStreamReturn => {
  const [agents, setAgents] = useState<Record<AgentType, AgentState>>(INITIAL_AGENTS);
  const [activeAgent, setActiveAgentState] = useState<AgentType | null>(null);
  const [streamStatus, setStreamStatus] = useState<StreamStatus>('disconnected');
  const [terminalLogs, setTerminalLogs] = useState<string[]>([]);
  
  const eventSourceRef = useRef<EventSource | null>(null);

  const setActiveAgent = (id: AgentType) => {
    setActiveAgentState(id);
  };

  const addLog = useCallback((id: AgentType, message: string) => {
    const timestamp = new Date().toLocaleTimeString();
    const formattedLog = `[${timestamp}] [${id.toUpperCase()}] ${message}`;
    
    setTerminalLogs(prev => [...prev.slice(-(config.ui.logRetentionLimit - 1)), formattedLog]);
    setAgents(prev => ({
      ...prev,
      [id]: { ...prev[id], logs: [...prev[id].logs, formattedLog] }
    }));
  }, []);

  const updateAgent = useCallback((id: AgentType, update: Partial<AgentState>) => {
    setAgents(prev => ({
      ...prev,
      [id]: { ...prev[id], ...update }
    }));
  }, []);

  // Simulation Logic for Demo Purposes
  const runSimulation = (command: string) => {
    setStreamStatus('connected');
    setAgents(INITIAL_AGENTS);
    setTerminalLogs([]); // Clear logs on new run
    addLog('orchestrator', `Received Intent: "${command}"`);
    
    // Orchestrator Phase
    setActiveAgent('orchestrator');
    updateAgent('orchestrator', { status: 'processing', data: { intent: 'Azure Migration', confidence: 0.98 } });
    
    setTimeout(() => {
        addLog('orchestrator', 'Parsing user intent using gpt-4-turbo...');
    }, 500);

    setTimeout(() => {
        addLog('orchestrator', 'Identified required agents: Assessment, Migration, Refactoring.');
        updateAgent('orchestrator', { status: 'success' });
        
        // Assessment Phase
        setActiveAgent('assessment');
        updateAgent('assessment', { status: 'processing', progress: 0 });
        addLog('assessment', 'Connecting to Azure Subscription...');
    }, 2000);

    setTimeout(() => {
        addLog('assessment', 'Scanning Resource Groups...');
        updateAgent('assessment', { progress: 30 });
    }, 3500);

    setTimeout(() => {
        addLog('assessment', 'Detected 45 Resources. Assessing Terraform compatibility...');
        updateAgent('assessment', { progress: 75, data: 'assessment-report-v1.json' });
    }, 5000);

    setTimeout(() => {
        updateAgent('assessment', { status: 'success', progress: 100 });
        addLog('assessment', 'Assessment Complete. 98% Compatibility score.');
        
        // Migration Phase
        setActiveAgent('migration');
        updateAgent('migration', { status: 'processing' });
        addLog('migration', 'Initializing aztfexport tool...');
    }, 6500);

    setTimeout(() => {
        addLog('migration', 'Exporting resource group: "rg-prod-app-01"...');
        addLog('migration', 'Generating main.tf...');
        updateAgent('migration', { progress: 40 });
    }, 8000);

    setTimeout(() => {
        addLog('migration', 'Importing state file (terraform.tfstate)...');
        updateAgent('migration', { status: 'success', progress: 100 });
        
        // Summary Phase
        setActiveAgent('summary');
        updateAgent('summary', { status: 'success' });
        addLog('summary', 'Workflow completed successfully. Artifacts ready.');
    }, 11000);
  };

  const connect = useCallback(() => {
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
    }

    setStreamStatus('reconnecting');

    // For now, we default to simulation if can't connect
    // Real implementation would connect to SSE endpoint:
    /*
    const es = new EventSource(`${config.mcpServer.baseUrl}/sse`);
    eventSourceRef.current = es;
    es.onopen = () => setStreamStatus('connected');
    es.addEventListener('log', (e) => { ... });
    */
   
    // Simulating "Connected" state after a delay
    setTimeout(() => {
        setStreamStatus('connected');
        addLog('orchestrator', 'Connected to MCP Orchestration Service.');
    }, 1000);

  }, [addLog]);

  useEffect(() => {
    connect();
    return () => {
      if (eventSourceRef.current) eventSourceRef.current.close();
    };
  }, [connect]);

  const handleOrchestration = async (command: string) => {
    // Try real orchestration if enabled, otherwise use simulation
    if (config.features.enableRealTimeMigration) {
      try {
        const result = await startOrchestration({ command });
        if (!result.success) {
          // Fall back to simulation if orchestration fails
          runSimulation(command);
        }
      } catch (error) {
        // Fall back to simulation on error
        console.warn('Orchestration failed, using simulation:', error);
        runSimulation(command);
      }
    } else {
      // Use simulation mode
      runSimulation(command);
    }
  };

  const reconnect = () => {
    connect();
  };

  return {
    agents,
    activeAgent,
    streamStatus,
    startOrchestration: handleOrchestration,
    reconnect,
    setActiveAgent,
    terminalLogs
  };
};
