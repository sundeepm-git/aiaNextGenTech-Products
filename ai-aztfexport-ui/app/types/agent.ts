/**
 * Shared TypeScript interfaces and types for agent workflow
 */

export type AgentType = 'orchestrator' | 'assessment' | 'migration' | 'refactoring' | 'summary';

export interface AgentState {
  id: AgentType;
  status: 'idle' | 'processing' | 'success' | 'failed';
  logs: string[];
  progress?: number;
  data?: any;
}

export type StreamStatus = 'connected' | 'disconnected' | 'reconnecting' | 'offline';

export interface OrchestrationRequest {
  command: string;
  context?: string;
  metadata?: Record<string, any>;
}

export interface AgentLogEvent {
  agentId: AgentType;
  message: string;
  timestamp: string;
  level: 'info' | 'warn' | 'error' | 'success';
}

export interface AgentUpdateEvent {
  agentId: AgentType;
  status?: AgentState['status'];
  progress?: number;
  data?: any;
}
