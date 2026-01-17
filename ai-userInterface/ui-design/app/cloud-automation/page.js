'use client';

import { useApp } from '@/context/AppContext';
import CategoryCard from '@/components/Cards/CategoryCard';
import ProductCard from '@/components/Cards/ProductCard';
import { LineChart, DoughnutChart } from '@/components/Charts';
import { CloudIcon } from '@heroicons/react/24/outline';

export default function CloudAutomationPage() {
  const { getVisibleProducts } = useApp();

  const stats = [
    { label: 'Total Resources', value: '156' },
    { label: 'Cost Saved', value: '$2.3K' },
    { label: 'Optimization Rate', value: '89%' },
    { label: 'Active Automations', value: '24' },
  ];

  // Placeholder data for GenAI integration
  const migrationProgress = [
    { name: 'Database Migration', progress: 85, status: 'In Progress' },
    { name: 'Storage Migration', progress: 100, status: 'Completed' },
    { name: 'VM Migration', progress: 45, status: 'In Progress' },
  ];

  const automationTriggers = [
    { id: 1, name: 'Auto-scale on high CPU', status: 'Active', executions: 12 },
    { id: 2, name: 'Backup at midnight', status: 'Active', executions: 30 },
    { id: 3, name: 'Cost alert threshold', status: 'Active', executions: 3 },
  ];

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
          Cloud Automation Agent
        </h1>
        <p className="text-gray-600 dark:text-gray-400">
          Intelligent cloud resource management and optimization
        </p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        {stats.map((stat, index) => (
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

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
            Cloud Health Metrics (7 Days)
          </h3>
          <LineChart 
            title="Health Score" 
            data={[88, 92, 85, 90, 94, 89, 93]}
            labels={['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']}
          />
        </div>

        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
            Resource Distribution
          </h3>
          <DoughnutChart 
            title="Resources" 
            data={[65, 45, 30, 16]}
            labels={['Compute', 'Storage', 'Network', 'Database']}
          />
        </div>
      </div>

      {/* Migration Progress */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Migration Progress
        </h3>
        <div className="space-y-4">
          {migrationProgress.map((item, index) => (
            <div key={index}>
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
                  {item.name}
                </span>
                <span className="text-sm text-gray-600 dark:text-gray-400">
                  {item.progress}%
                </span>
              </div>
              <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                <div
                  className={`h-2 rounded-full ${
                    item.progress === 100 ? 'bg-green-500' : 'bg-blue-500'
                  }`}
                  style={{ width: `${item.progress}%` }}
                  role="progressbar"
                  aria-valuenow={item.progress}
                  aria-valuemin="0"
                  aria-valuemax="100"
                />
              </div>
            </div>
          ))}
        </div>
        {/* Future integration: Real-time migration status from GenAI backend */}
      </div>

      {/* Automation Triggers */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Active Automation Triggers
        </h3>
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="text-xs uppercase bg-gray-50 dark:bg-gray-700">
              <tr>
                <th className="px-6 py-3">Trigger Name</th>
                <th className="px-6 py-3">Status</th>
                <th className="px-6 py-3">Executions (30d)</th>
              </tr>
            </thead>
            <tbody>
              {automationTriggers.map((trigger) => (
                <tr
                  key={trigger.id}
                  className="border-b border-gray-200 dark:border-gray-700"
                >
                  <td className="px-6 py-4 font-medium text-gray-900 dark:text-white">
                    {trigger.name}
                  </td>
                  <td className="px-6 py-4">
                    <span className="px-2 py-1 text-xs font-medium rounded-full bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300">
                      {trigger.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-gray-700 dark:text-gray-300">
                    {trigger.executions}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {/* Future integration: Live automation execution logs */}
      </div>

      {/* Products */}
      <CategoryCard
        title="Cloud Automation Products"
        icon={CloudIcon}
      >
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {getVisibleProducts('cloudAutomation').map((product) => (
            <ProductCard key={product.id} product={product} status="active" />
          ))}
        </div>
      </CategoryCard>
    </div>
  );
}
