import { useState } from 'react';
import { Mic, ArrowRight, Sparkles } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

interface FoundryCommandCenterProps {
  onCommandSubmit: (command: string) => void;
  isProcessing: boolean;
  intentPreview?: any; // The parsed JSON data
}

const SUGGESTIONS = [
  { label: "🚀 Real Migration", value: "I want to migrate Subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 and ResourceGroup rg-mcp-servers" },
  { label: "Assess Subscription", value: "I just want to assess my Azure subscription for migration candidates" },
  { label: "Refactor Codebase", value: "I just want to do code refactoring based on Subscription <ID>, Name <Name>, and RG <RG>" }
];

export default function FoundryCommandCenter({ 
  onCommandSubmit, 
  isProcessing,
  intentPreview 
}: FoundryCommandCenterProps) {
  const [input, setInput] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (input.trim()) {
      onCommandSubmit(input);
    }
  };

  return (
    <div className="w-full max-w-4xl mx-auto space-y-6">
      {/* Input Area */}
      <div className="relative group">
        <div className="absolute -inset-0.5 bg-gradient-to-r from-primary to-secondary rounded-lg blur opacity-30 group-hover:opacity-75 transition duration-1000 group-hover:duration-200"></div>
        <form onSubmit={handleSubmit} className="relative bg-white/80 backdrop-blur-md rounded-lg p-2 flex items-center border border-sky-100 shadow-xl shadow-sky-100/50">
          
          {/* Voice Visualizer Mock */}
          <button type="button" className="p-3 text-primary hover:bg-sky-50 rounded-full transition-colors mr-2">
            <Mic className="w-5 h-5" />
          </button>

          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            disabled={isProcessing}
            placeholder="Describe your Azure migration task..."
            className="flex-1 bg-transparent border-none outline-none text-text placeholder-slate-400 font-mono text-xl"
          />

          <button 
            type="submit" 
            disabled={!input.trim() || isProcessing}
            className="p-3 bg-sky-50 hover:bg-sky-100 text-primary rounded-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isProcessing ? (
              <Sparkles className="w-5 h-5 animate-spin" />
            ) : (
              <ArrowRight className="w-5 h-5" />
            )}
          </button>
        </form>
      </div>

      {/* Suggestion Chips */}
      {!intentPreview && (
        <div className="flex flex-wrap gap-2 justify-center">
            {SUGGESTIONS.map((sug, i) => (
                <button
                    key={i}
                    onClick={() => setInput(sug.value)}
                    className="px-3 py-1.5 rounded-full bg-white border border-sky-200 text-sm text-slate-600 hover:text-primary hover:border-primary/50 hover:shadow-md transition-all shadow-sm"
                >
                    {sug.label}
                </button>
            ))}
        </div>
      )}

      {/* JSON Preview - Glassmorphism Card */}
      <AnimatePresence>
        {intentPreview && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95 }}
            className="rounded-xl overflow-hidden border border-sky-200 backdrop-blur-md bg-white/90 shadow-2xl"
          >
            <div className="bg-sky-50 px-4 py-2 border-b border-sky-100 flex justify-between items-center">
                <span className="text-xs text-secondary font-mono uppercase tracking-wider">Verified Intent</span>
                <span className="text-xs text-muted font-mono">JSON</span>
            </div>
            <div className="p-4 overflow-x-auto bg-slate-50">
                <pre className="font-mono text-xs text-slate-700 leading-relaxed">
                    {JSON.stringify(intentPreview, null, 2)}
                </pre>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
