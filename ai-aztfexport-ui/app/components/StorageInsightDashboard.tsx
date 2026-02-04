import { Server, Database, FileCode, Folder, FolderOpen } from 'lucide-react';

export default function StorageInsightDashboard() {
  return (
    <div className="space-y-6">
      
      {/* Quick Stats Header */}
      <div className="grid grid-cols-3 gap-4">
        <StatCard 
            label="Total Migrations" 
            value="142" 
            sublabel="+12 this week"
            icon={<Server className="w-4 h-4 text-primary" />}
        />
        <StatCard 
            label="Refactor Success" 
            value="98.5%" 
            sublabel="Auto-fix enabled"
            icon={<FileCode className="w-4 h-4 text-secondary" />}
        />
        <StatCard 
            label="Storage Usage" 
            value="420 MB" 
            sublabel="Container: aztf-coderefactor"
            icon={<Database className="w-4 h-4 text-purple-400" />}
        />
      </div>

      {/* File Explorer Widget */}
      <div className="bg-surface rounded-xl border border-border p-4 h-[300px] flex flex-col">
        <div className="flex items-center gap-2 mb-4 text-sm font-medium text-muted">
            <FolderOpen className="w-4 h-4 text-primary" />
            <span>aztf-coderefactor /</span>
        </div>
        
        <div className="flex-1 overflow-y-auto space-y-1 pr-2 scrollbar-thin">
            <FileItem name="main.tf" size="14 KB" type="tf" />
            <FileItem name="variables.tf" size="4 KB" type="tf" />
            <FileItem name="outputs.tf" size="2 KB" type="tf" />
            <FileItem name="provider.tf" size="1 KB" type="tf" />
            <FileItem name="migration_report_882.html" size="45 KB" type="html" />
            <FileItem name="terraform.tfstate" size="22 KB" type="json" />
            <FileItem name="backup/" size="" type="folder" />
        </div>
      </div>
    </div>
  );
}

function StatCard({ label, value, sublabel, icon }: any) {
    return (
        <div className="bg-surface p-4 rounded-xl border border-white/5 hover:border-white/10 transition-colors">
            <div className="flex justify-between items-start mb-2">
                <span className="text-muted text-xs font-medium uppercase">{label}</span>
                {icon}
            </div>
            <div className="text-2xl font-bold text-[#4b5563] mb-1">{value}</div>
            <div className="text-xs text-gray-500">{sublabel}</div>
        </div>
    );
}

function FileItem({ name, size, type }: any) {
    const isFolder = type === 'folder';
    return (
        <div className="flex items-center justify-between p-2 rounded hover:bg-white/5 group cursor-pointer text-sm">
            <div className="flex items-center gap-2 text-gray-300 group-hover:text-primary transition-colors">
                {isFolder ? <Folder className="w-4 h-4 text-blue-400" /> : <FileCode className="w-4 h-4" />}
                <span>{name}</span>
            </div>
            <span className="text-xs text-gray-600 font-mono">{size}</span>
        </div>
    );
}
