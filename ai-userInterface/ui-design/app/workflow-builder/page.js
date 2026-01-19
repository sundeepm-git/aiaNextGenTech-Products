'use client';

import { useApp } from '@/context/AppContext';
import CategoryCard from '@/components/Cards/CategoryCard';
import ProductCard from '@/components/Cards/ProductCard';
import { BarChart } from '@/components/Charts';
import { CogIcon, PlayIcon, PauseIcon } from '@heroicons/react/24/outline';

export default function WorkflowBuilderPage() {
  const { getVisibleProducts } = useApp();

  const stats = [
    { label: 'Total Workflows', value: '45' },
    { label: 'Active Workflows', value: '32' },
    { label: 'Total Executions', value: '1.2K' },
    { label: 'Success Rate', value: '96%' },
  ];

  // Placeholder data for GenAI integration
  const workflowSteps = [
    { id: 1, name: 'Data Collection', type: 'Input', status: 'Completed' },
    { id: 2, name: 'AI Analysis', type: 'Agent', status: 'Completed' },
    { id: 3, name: 'Decision Logic', type: 'Condition', status: 'Running' },
    { id: 4, name: 'Action Execution', type: 'Output', status: 'Pending' },
  ];

  const executionLogs = [
    { id: 1, workflow: 'Customer Support Bot', status: 'Success', time: '2 mins ago', duration: '1.2s' },
    { id: 2, workflow: 'Data Pipeline', status: 'Success', time: '5 mins ago', duration: '3.5s' },
    { id: 3, workflow: 'Report Generator', status: 'Failed', time: '10 mins ago', duration: '0.8s' },
    { id: 4, workflow: 'Email Automation', status: 'Success', time: '15 mins ago', duration: '2.1s' },
  ];

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
          Intelligent Automation
        </h1>
        <p className="text-gray-600 dark:text-gray-400">
          Design and orchestrate multi-agent workflows
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

      {/* Workflow Execution Chart */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Workflow Executions (Last 6 Months)
        </h3>
        <BarChart 
          title="Executions" 
          data={[180, 220, 195, 240, 280, 310]}
          labels={['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun']}
        />
      </div>

      {/* Drag-and-Drop Workflow Designer */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Visual Workflow Designer
          </h3>
          <div className="flex gap-2">
            <button className="px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary-dark transition-colors">
              <PlayIcon className="h-5 w-5 inline mr-1" aria-hidden="true" />
              Run Workflow
            </button>
          </div>
        </div>

        {/* Workflow Canvas */}
        <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-8 min-h-[300px] border-2 border-dashed border-gray-300 dark:border-gray-600">
          <div className="space-y-4">
            {workflowSteps.map((step, index) => (
              <div key={step.id}>
                <div className="flex items-center gap-4">
                  <div className={`w-12 h-12 rounded-full flex items-center justify-center font-bold text-white ${
                    step.status === 'Completed' ? 'bg-green-500' :
                    step.status === 'Running' ? 'bg-primary' :
                    'bg-gray-400'
                  }`}>
                    {index + 1}
                  </div>
                  <div className="flex-1 bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="font-semibold text-gray-900 dark:text-white">
                          {step.name}
                        </h4>
                        <p className="text-sm text-gray-600 dark:text-gray-400">
                          Type: {step.type}
                        </p>
                      </div>
                      <span className={`px-3 py-1 text-xs font-medium rounded-full ${
                        step.status === 'Completed' ? 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300' :
                        step.status === 'Running' ? 'bg-primary/20 text-primary dark:bg-primary/20 dark:text-primary' :
                        'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300'
                      }`}>
                        {step.status}
                      </span>
                    </div>
                  </div>
                </div>
                {index < workflowSteps.length - 1 && (
                  <div className="ml-6 w-0.5 h-6 bg-gray-300 dark:bg-gray-600" />
                )}
              </div>
            ))}
          </div>
        </div>
        <p className="text-sm text-gray-600 dark:text-gray-400 mt-4">
          <strong>Note:</strong> Drag-and-drop interface for agent orchestration - Future integration with visual workflow editor
        </p>
      </div>

      {/* Execution Logs */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Recent Execution Logs
        </h3>
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="text-xs uppercase bg-gray-50 dark:bg-gray-700">
              <tr>
                <th className="px-6 py-3">Workflow</th>
                <th className="px-6 py-3">Status</th>
                <th className="px-6 py-3">Time</th>
                <th className="px-6 py-3">Duration</th>
              </tr>
            </thead>
            <tbody>
              {executionLogs.map((log) => (
                <tr
                  key={log.id}
                  className="border-b border-gray-200 dark:border-gray-700"
                >
                  <td className="px-6 py-4 font-medium text-gray-900 dark:text-white">
                    {log.workflow}
                  </td>
                  <td className="px-6 py-4">
                    <span className={`px-2 py-1 text-xs font-medium rounded-full ${
                      log.status === 'Success' 
                        ? 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300'
                        : 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300'
                    }`}>
                      {log.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-gray-700 dark:text-gray-300">
                    {log.time}
                  </td>
                  <td className="px-6 py-4 text-gray-700 dark:text-gray-300">
                    {log.duration}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {/* Future integration: Real-time execution logs streaming */}
      </div>

      {/* Products */}
      <CategoryCard
        title="Intelligent Automation Products"
        icon={CogIcon}
      >
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {getVisibleProducts('workflowBuilder').map((product) => (
            <ProductCard key={product.id} product={product} status="active" />
          ))}
        </div>
      </CategoryCard>
    </div>
  );
}
