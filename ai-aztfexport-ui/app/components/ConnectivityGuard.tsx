import { Wifi, WifiOff, RefreshCcw, AlertTriangle } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import type { StreamStatus } from '@/app/types/agent';

interface ConnectivityGuardProps {
  status: StreamStatus;
  onReconnect: () => void;
}

export default function ConnectivityGuard({ status, onReconnect }: ConnectivityGuardProps) {
  const isOnline = status === 'connected';
  const isOffline = status === 'offline' || status === 'disconnected';
  const isReconnecting = status === 'reconnecting';

  return (
    <>
      {/* Permanent Status Indicator */}
      <div className="fixed bottom-4 right-4 z-50 flex items-center gap-3 bg-surface border border-white/10 px-4 py-2 rounded-full shadow-2xl backdrop-blur-md">
        <div className="relative flex items-center justify-center">
            {isOnline && <span className="absolute w-full h-full bg-secondary/30 rounded-full animate-ping" />}
            <div className={`w-2.5 h-2.5 rounded-full ${
                isOnline ? 'bg-secondary' : isReconnecting ? 'bg-yellow-500' : 'bg-error'
            }`} />
        </div>
        
        <span className="text-xs font-mono font-medium text-muted uppercase">
            {isOnline ? 'MCP Server Online' : isReconnecting ? 'Connecting...' : 'System Offline'}
        </span>

        {isOffline && (
            <button 
                onClick={onReconnect}
                className="p-1 hover:bg-white/10 rounded-full transition-colors ml-1"
                title="Reconnect"
            >
                <RefreshCcw className="w-3.5 h-3.5 text-primary" />
            </button>
        )}
      </div>

      {/* Critical Error Toast */}
      <AnimatePresence>
        {isOffline && (
            <motion.div 
                initial={{ opacity: 0, y: 50, x: '-50%' }}
                animate={{ opacity: 1, y: 0, x: '-50%' }}
                exit={{ opacity: 0, y: 50, x: '-50%' }}
                className="fixed bottom-8 left-1/2 -translate-x-1/2 z-50 w-full max-w-md"
            >
                <div className="bg-error/10 backdrop-blur-xl border border-error/50 p-4 rounded-xl shadow-2xl flex items-start gap-4">
                    <div className="p-2 bg-error/20 rounded-lg">
                        <AlertTriangle className="w-6 h-6 text-error" />
                    </div>
                    <div className="flex-1">
                        <h3 className="text-[#4b5563] font-bold text-sm mb-1">Critical Connection Failure</h3>
                        <p className="text-gray-300 text-xs mb-3">
                            The Local MCP Server heartbeat has been lost. The orchestration pipeline is halted.
                        </p>
                        <div className="flex gap-2">
                            <button 
                                onClick={onReconnect}
                                className="px-3 py-1.5 bg-error text-[#f9fafb] text-xs font-bold rounded hover:bg-error/90 transition-colors"
                            >
                                Reconnect via ngrok
                            </button>
                            <button className="px-3 py-1.5 hover:bg-white/5 text-gray-400 text-xs rounded transition-colors">
                                View Logs
                            </button>
                        </div>
                    </div>
                </div>
            </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
