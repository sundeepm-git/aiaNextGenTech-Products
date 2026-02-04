'use client';

import { Workflow, FileSearch, GitBranch, Code2, ClipboardList, LayoutDashboard, Settings } from 'lucide-react';
import { cn } from '@/lib/utils';

export type PageType = 'workflow' | 'assessment' | 'migration' | 'refactoring' | 'summary' | 'settings';

interface SidebarProps {
  currentPage: PageType;
  onPageChange: (page: PageType) => void;
  isVisible: boolean;
}

const menuItems = [
  { id: 'workflow' as PageType, label: 'Workflow', icon: Workflow },
  { id: 'assessment' as PageType, label: 'Assessment', icon: FileSearch },
  { id: 'migration' as PageType, label: 'Migration', icon: GitBranch },
  { id: 'refactoring' as PageType, label: 'Refactoring', icon: Code2 },
  { id: 'summary' as PageType, label: 'Summary', icon: ClipboardList },
];

export default function Sidebar({ currentPage, onPageChange, isVisible }: SidebarProps) {
  if (!isVisible) return null;
  
  return (
    <aside className="w-64 bg-white border-r border-border flex flex-col transition-all duration-300">
      <div className="p-6">
        <div className="flex items-center gap-2">
          <LayoutDashboard className="w-5 h-5 text-primary" />
          <h2 className="text-lg font-semibold text-text">Menu</h2>
        </div>
      </div>
      
      <nav className="flex-1 px-3 space-y-1">
        {menuItems.map((item) => {
          const Icon = item.icon;
          const isActive = currentPage === item.id;
          
          return (
            <button
              key={item.id}
              onClick={() => onPageChange(item.id)}
              className={cn(
                "w-full flex items-center gap-3 px-4 py-3 rounded-lg transition-all duration-200",
                isActive 
                  ? "bg-gradient-to-r from-primary to-secondary text-white shadow-md" 
                  : "text-muted hover:bg-primary/5 hover:text-primary"
              )}
            >
              <Icon className={cn("w-5 h-5", isActive ? "text-white" : "")} />
              <span className="font-medium">{item.label}</span>
            </button>
          );
        })}
      </nav>
      
      {/* Settings at bottom */}
      <div className="px-3 pb-3">
        <button
          onClick={() => onPageChange('settings')}
          className={cn(
            "w-full flex items-center gap-3 px-4 py-3 rounded-lg transition-all duration-200",
            currentPage === 'settings'
              ? "bg-gradient-to-r from-primary to-secondary text-white shadow-md" 
              : "text-muted hover:bg-primary/5 hover:text-primary"
          )}
        >
          <Settings className={cn("w-5 h-5", currentPage === 'settings' ? "text-white" : "")} />
          <span className="font-medium">Settings</span>
        </button>
      </div>
      
      <div className="p-4 border-t border-border">
        <p className="text-xs text-muted text-center">
          Azure to Terraform Migration
        </p>
        <p className="text-xs text-muted text-center mt-1">
          v2.4.0
        </p>
      </div>
    </aside>
  );
}
