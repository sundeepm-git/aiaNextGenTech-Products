import { useState, useMemo } from 'react';
import { ArrowRight, Sparkles } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { maskSensitiveValues } from '@/app/services/maskService';

interface FoundryCommandCenterProps {
  onCommandSubmit: (command: string) => void;
  isProcessing: boolean;
  intentPreview?: any; // The parsed JSON data
}

const SUGGESTIONS = [
  { label: "🚀 Real Migration", value: "Migrate subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 and resource group rg-mcp-servers" },
  { label: "Assess Subscription", value: "Assess subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 and resource group rg-mcp-servers" },
  { label: "Refactor Codebase", value: "Do code refactoring for subscription d0f1884d-1f98-4bf1-9e15-e2986fc1bca2 and resource group rg-mcp-servers" }
];

export default function FoundryCommandCenter({ 
  onCommandSubmit, 
  isProcessing,
  intentPreview 
}: FoundryCommandCenterProps) {
  const [input, setInput] = useState('');

  // Masked version shown in the overlay (hides subscription IDs & resource groups)
  const maskedInput = useMemo(() => maskSensitiveValues(input), [input]);

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
        <form onSubmit={handleSubmit} className="relative bg-white/80 backdrop-blur-md rounded-lg p-4 border border-sky-100 shadow-xl shadow-sky-100/50">
          <div className="relative">
            {/* Masked display overlay — mirrors textarea layout exactly */}
            <div
              aria-hidden="true"
              className="absolute inset-0 w-full h-32 px-4 py-3 border border-transparent rounded-lg font-mono text-sm whitespace-pre-wrap break-words overflow-hidden pointer-events-none z-10"
            >
              {maskedInput || <span className="text-muted/50">Describe your Azure migration task...</span>}
            </div>
            {/* Real textarea — text is transparent so overlay shows; caret remains visible */}
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSubmit(e); } }}
              disabled={isProcessing}
              placeholder=""
              className="w-full h-32 px-4 py-3 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent resize-none font-mono text-sm text-transparent caret-black relative z-20 bg-transparent"
            />
          </div>
          <div className="flex items-center justify-between mt-3">
            <p className="text-xs text-muted">Press Enter to submit, Shift+Enter for new line</p>
            <button 
              type="submit" 
              disabled={!input.trim() || isProcessing}
              className="px-6 py-2.5 bg-gradient-to-r from-primary to-secondary text-white rounded-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed hover:shadow-lg flex items-center gap-2 font-medium"
            >
              {isProcessing ? (
                <><Sparkles className="w-4 h-4 animate-spin" /> Processing...</>
              ) : (
                <><ArrowRight className="w-4 h-4" /> Run Migration</>
              )}
            </button>
          </div>
        </form>
      </div>

      {/* Help Text */}
      <div className="bg-primary/5 border border-primary/20 rounded-lg p-4">
        <p className="text-xs text-muted font-semibold mb-2">💡 Prompt Help:</p>
        <p className="text-sm text-text font-mono">
          Migrate subscription - &lt;subscriptionId&gt; and Resource Group &lt;resourceGroupName&gt;
        </p>
        <p className="text-sm text-text font-mono mt-1">
          Do migration for subscription &lt;subscriptionId&gt; and resource group &lt;resourceGroupName&gt;
        </p>
      </div>

      {/* Suggestion Chips */}
      {!intentPreview && (
        <div className="flex flex-wrap gap-2 justify-center">
            {SUGGESTIONS.map((sug, i) => (
                <button
                    key={i}
                    onClick={() => setInput(sug.value)}
                    className="px-3 py-1.5 rounded-full bg-white border border-sky-200 text-sm text-slate-600 hover:text-primary hover:border-primary/50 hover:shadow-md transition-all shadow-sm"
                    title={maskSensitiveValues(sug.value)}
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
