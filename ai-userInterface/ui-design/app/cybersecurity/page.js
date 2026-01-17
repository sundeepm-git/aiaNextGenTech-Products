'use client';

import { useApp } from '@/context/AppContext';
import CategoryCard from '@/components/Cards/CategoryCard';
import ProductCard from '@/components/Cards/ProductCard';
import { LineChart, BarChart } from '@/components/Charts';
import { ShieldCheckIcon, ExclamationTriangleIcon } from '@heroicons/react/24/outline';

export default function CybersecurityPage() {
  const { getVisibleProducts } = useApp();

  const stats = [
    { label: 'Threats Detected', value: '23' },
    { label: 'Threats Blocked', value: '21' },
    { label: 'Under Investigation', value: '2' },
    { label: 'False Positives', value: '5' },
  ];

  // Placeholder data for GenAI integration
  const recentAlerts = [
    { id: 1, type: 'Critical', message: 'Unusual login attempt detected', time: '2 mins ago' },
    { id: 2, type: 'Warning', message: 'Port scan detected from unknown IP', time: '15 mins ago' },
    { id: 3, type: 'Info', message: 'Security patch applied successfully', time: '1 hour ago' },
  ];

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
          Cybersecurity Agent
        </h1>
        <p className="text-gray-600 dark:text-gray-400">
          AI-powered security monitoring and threat detection
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
            Threat Detection (Last 7 Days)
          </h3>
          <LineChart 
            title="Threats" 
            data={[5, 8, 3, 12, 7, 4, 9]}
            labels={['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']}
          />
        </div>

        <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
            Threat Types (This Month)
          </h3>
          <BarChart 
            title="Threat Types" 
            data={[45, 32, 28, 15, 12, 8]}
            labels={['Malware', 'Phishing', 'DDoS', 'Intrusion', 'Data Leak', 'Other']}
          />
        </div>
      </div>

      {/* Recent Alerts */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Recent Security Alerts
        </h3>
        <div className="space-y-3">
          {recentAlerts.map((alert) => (
            <div
              key={alert.id}
              className="flex items-start gap-4 p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg"
            >
              <ExclamationTriangleIcon 
                className={`h-6 w-6 flex-shrink-0 ${
                  alert.type === 'Critical' ? 'text-red-500' : 
                  alert.type === 'Warning' ? 'text-yellow-500' : 
                  'text-blue-500'
                }`}
                aria-hidden="true"
              />
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-1">
                  <span className={`text-xs font-semibold px-2 py-1 rounded ${
                    alert.type === 'Critical' ? 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300' : 
                    alert.type === 'Warning' ? 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300' : 
                    'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300'
                  }`}>
                    {alert.type}
                  </span>
                  <span className="text-xs text-gray-500 dark:text-gray-400">
                    {alert.time}
                  </span>
                </div>
                <p className="text-sm text-gray-700 dark:text-gray-300">
                  {alert.message}
                </p>
              </div>
            </div>
          ))}
        </div>
        {/* Future integration: Real-time alert streaming from GenAI backend */}
      </div>

      {/* Products */}
      <CategoryCard
        title="Cybersecurity Products"
        icon={ShieldCheckIcon}
      >
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {getVisibleProducts('cybersecurity').map((product) => (
            <ProductCard key={product.id} product={product} status="active" />
          ))}
        </div>
      </CategoryCard>
    </div>
  );
}
