import { useRef, useEffect } from 'react';
import { Terminal as TerminalIcon, Download, Trash2, Maximize2 } from 'lucide-react';
import { motion } from 'framer-motion';
import { maskSensitiveValues } from '@/app/services/maskService';

interface LiveTerminalProps {
  logs: string[];
  title?: string;
}

export default function LiveTerminal({ logs, title = "Aztra Neural Core >_ Terminal" }: LiveTerminalProps) {
  const scrollRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom on new logs
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs]);

  const handleDownloadLogs = () => {
    const maskedLogs = logs.map(l => maskSensitiveValues(l));
    const blob = new Blob([maskedLogs.join('\n')], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `aztra-logs-${new Date().toISOString()}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="w-full h-full bg-white rounded-xl border border-border shadow-lg flex flex-col font-mono overflow-hidden">
      
      {/* Terminal Header */}
      <div className="flex items-center justify-between px-4 py-2 bg-primary/10 border-b border-border">
        <div className="flex items-center gap-2">
          <TerminalIcon className="w-4 h-4 text-primary" />
          <span className="text-xs text-muted font-medium uppercase tracking-wider">{title}</span>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={handleDownloadLogs} className="p-1.5 hover:bg-primary/10 rounded text-muted hover:text-[#4b5563] transition-colors" title="Download Logs">
            <Download className="w-3.5 h-3.5" />
          </button>
          <button className="p-1.5 hover:bg-primary/10 rounded text-muted hover:text-[#4b5563] transition-colors" title="Clear">
            <Trash2 className="w-3.5 h-3.5" />
          </button>
          <button className="p-1.5 hover:bg-primary/10 rounded text-muted hover:text-[#4b5563] transition-colors" title="Expand">
            <Maximize2 className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* Terminal Content */}
      <div 
        ref={scrollRef}
        className="flex-1 overflow-y-auto p-4 space-y-1 scrollbar-thin scroll-smooth bg-white"
      >
        {logs.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center text-muted/60">
            <TerminalIcon className="w-12 h-12 mb-2 opacity-40" />
            <span>Ready for command input...</span>
          </div>
        ) : (
          logs.map((log, i) => (
            <motion.div 
              key={i}
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              className="text-sm break-all font-mono"
            >
              <span className="text-slate-400 mr-2 select-none">
                {String(i + 1).padStart(3, '0')}
              </span>
              <span dangerouslySetInnerHTML={{ 
                __html: formatLogColor(log) 
              }} />
            </motion.div>
          ))
        )}
      </div>

      {/* Terminal Footer / Status Line */}
      <div className="px-4 py-1 bg-primary/5 border-t border-border flex justify-between items-center text-[10px] text-muted">
        <span>Ln {logs.length}, Col 1</span>
        <div className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-secondary animate-pulse"></span>
            <span>LIVE STREAM</span>
        </div>
      </div>
    </div>
  );
}

// Simple helper to colorize logs (Could be more robust with full ANSI handling)
function formatLogColor(text: string) {
  // Mask sensitive values first, then colorize
  let formatted = maskSensitiveValues(text)
    .replace(/\[ERROR\]/g, '<span class="text-error font-bold">[ERROR]</span>')
    .replace(/\[SUCCESS\]/g, '<span class="text-secondary font-bold">[SUCCESS]</span>')
    .replace(/\[WARNING\]/g, '<span class="text-yellow-500 font-bold">[WARNING]</span>')
    .replace(/\[INFO\]/g, '<span class="text-blue-400">[INFO]</span>')
    .replace(/\[ORCHESTRATOR\]/g, '<span class="text-purple-400 font-bold">[ORCHESTRATOR]</span>')
    .replace(/\[MIGRATION\]/g, '<span class="text-primary font-bold">[MIGRATION]</span>');
    
  return formatted;
}
