'use client';

import { useApp } from '@/context/AppContext';
import CategoryCard from '@/components/Cards/CategoryCard';
import ProductCard from '@/components/Cards/ProductCard';
import { LineChart, DoughnutChart, BarChart } from '@/components/Charts';
import { 
  ShieldCheckIcon, 
  CloudIcon, 
  CogIcon,
  ChartBarIcon,
} from '@heroicons/react/24/outline';

export default function DashboardPage() {
  const { categories, getVisibleProducts } = useApp();

  const overviewStats = [
    { label: 'Active Agents', value: '12' },
    { label: 'Total Products', value: '24' },
    { label: 'Uptime', value: '99.9%' },
    { label: 'Alerts', value: '3' },
  ];

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
          Dashboard
        </h1>
        <p className="text-gray-600 dark:text-gray-400">
          Monitor and manage your GenAI agents and automation workflows
        </p>
      </div>

      {/* Overview Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        {overviewStats.map((stat, index) => (
          <div
            key={index}
            className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6"
          >
            <p className="text-sm text-gray-600 dark:text-gray-400 mb-2">
              {stat.label}
            </p>
            <p className="text-3xl font-bold text-gray-900 dark:text-white">
              {stat.value}
            </p>
          </div>
        ))}
      </div>

      {/* Charts Section */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
            Agent Activity (7 Days)
          </h3>
          <LineChart 
            title="Activity" 
            data={[45, 52, 38, 65, 72, 68, 80]}
            labels={['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']}
          />
        </div>

        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
            Agent Status Distribution
          </h3>
          <DoughnutChart 
            title="Status" 
            data={[85, 10, 5]}
            labels={['Active', 'Idle', 'Warning']}
          />
        </div>
      </div>

      {/* Cybersecurity Agent */}
      {categories.cybersecurity.visible && (
        <CategoryCard
          title={categories.cybersecurity.name}
          description="AI-powered security monitoring and threat detection"
          icon={ShieldCheckIcon}
          stats={[
            { label: 'Threats Detected', value: '23' },
            { label: 'Blocked', value: '21' },
            { label: 'Investigating', value: '2' },
          ]}
        >
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {getVisibleProducts('cybersecurity').map((product) => (
              <ProductCard key={product.id} product={product} status="active" />
            ))}
          </div>
        </CategoryCard>
      )}

      {/* Cloud Automation Agent */}
      {categories.cloudAutomation.visible && (
        <CategoryCard
          title={categories.cloudAutomation.name}
          description="Intelligent cloud resource management and optimization"
          icon={CloudIcon}
          stats={[
            { label: 'Resources', value: '156' },
            { label: 'Cost Saved', value: '$2.3K' },
            { label: 'Optimized', value: '89%' },
          ]}
        >
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {getVisibleProducts('cloudAutomation').map((product) => (
              <ProductCard key={product.id} product={product} status="active" />
            ))}
          </div>
        </CategoryCard>
      )}

      {/* Workflow Builder */}
      {categories.workflowBuilder.visible && (
        <CategoryCard
          title={categories.workflowBuilder.name}
          description="Design and orchestrate multi-agent workflows"
          icon={CogIcon}
          stats={[
            { label: 'Workflows', value: '45' },
            { label: 'Active', value: '32' },
            { label: 'Executions', value: '1.2K' },
          ]}
        >
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {getVisibleProducts('workflowBuilder').map((product) => (
              <ProductCard key={product.id} product={product} status="active" />
            ))}
          </div>
        </CategoryCard>
      )}

      {/* Integration Note */}
      <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
        <p className="text-sm text-blue-800 dark:text-blue-300">
          <strong>Developer Note:</strong> This dashboard is ready for GenAI backend integration. 
          Connect to your agentic orchestration workflows and real-time data streams to enable live monitoring.
        </p>
      </div>
    </div>
  );
}
