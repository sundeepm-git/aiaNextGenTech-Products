'use client';

import { CheckCircleIcon, ExclamationTriangleIcon } from '@heroicons/react/24/solid';

const ProductCard = ({ product, status = 'active' }) => {
  const statusConfig = {
    active: {
      icon: CheckCircleIcon,
      color: 'text-green-500',
      bg: 'bg-green-50 dark:bg-green-900/20',
      label: 'Active',
    },
    warning: {
      icon: ExclamationTriangleIcon,
      color: 'text-yellow-500',
      bg: 'bg-yellow-50 dark:bg-yellow-900/20',
      label: 'Warning',
    },
  };

  const config = statusConfig[status] || statusConfig.active;
  const StatusIcon = config.icon;

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6 hover:shadow-lg transition-shadow">
      <div className="flex items-start justify-between mb-4">
        <div className="flex-1">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-2">
            {product.name}
          </h3>
          <p className="text-sm text-gray-600 dark:text-gray-400">
            {product.description}
          </p>
        </div>
        <div className={`flex items-center gap-2 px-3 py-1 rounded-full ${config.bg}`}>
          <StatusIcon className={`h-4 w-4 ${config.color}`} aria-hidden="true" />
          <span className={`text-xs font-medium ${config.color}`}>
            {config.label}
          </span>
        </div>
      </div>

      {/* Placeholder for future GenAI integration */}
      <div className="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <div className="flex items-center justify-between text-sm">
          <span className="text-gray-500 dark:text-gray-400">Status</span>
          <span className="font-medium text-gray-900 dark:text-white">
            Operational
          </span>
        </div>
        {/* Future integration point: Real-time metrics from GenAI backend */}
      </div>
    </div>
  );
};

export default ProductCard;
