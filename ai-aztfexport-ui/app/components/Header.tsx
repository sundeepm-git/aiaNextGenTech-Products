import { Zap, Brain, Menu } from 'lucide-react';

interface HeaderProps {
  onToggleSidebar?: () => void;
}

export default function Header({ onToggleSidebar }: HeaderProps) {
  return (
    <header className="border-b border-[#1f99f4] bg-[#1f99f4] text-white shadow-md sticky top-0 z-40">
      <div className="max-w-full mx-auto px-6 h-16 flex items-center justify-between">
        <div className="flex items-center gap-4">
            {/* Toggle Sidebar Button */}
            <button
              onClick={onToggleSidebar}
              className="p-2 hover:bg-white/20 rounded-lg transition-colors"
              title="Toggle Sidebar"
            >
              <Menu className="w-5 h-5 text-white" />
            </button>
            
            {/* Agentic AI Icon */}
            <div className="bg-white/20 p-2 rounded-lg">
              <Brain className="w-6 h-6 text-white" />
            </div>
            
            <h1 className="text-xl font-bold tracking-tight text-white">
              Agentic Azure to Terraform Migration <span className="text-white/80 font-normal text-sm ml-2">v2.4.0</span>
            </h1>
        </div>
        
          <div className="flex items-center gap-4 text-xs font-mono text-white/90">
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-emerald-400"></span>
                <span>Azure: Connected</span>
            </div>
            <div className="pl-4 border-l border-white/30">
              <span className="font-semibold text-white">Microsoft Foundry</span>
            </div>
        </div>
      </div>
    </header>
  );
}
