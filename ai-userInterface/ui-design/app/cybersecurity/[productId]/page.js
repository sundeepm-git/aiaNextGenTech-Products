'use client';

import { useApp } from '@/context/AppContext';
import { useParams } from 'next/navigation';
import { ShieldCheckIcon } from '@heroicons/react/24/outline';

export default function GenericProductPage() {
  const params = useParams();
  const { products } = useApp();
  const productId = params.productId;

  // Find the product in the cybersecurity list (or others if reused)
  const product = products.cybersecurity.find(p => p.id === productId);

  if (!product) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[50vh]">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-4">Product Not Found</h1>
        <p className="text-gray-600 dark:text-gray-400">
          The requested security product could not be found.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
          {product.name}
        </h1>
        <p className="text-gray-600 dark:text-gray-400">
          {product.description}
        </p>
      </div>

      {/* Placeholder Content */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-8 text-center">
        <div className="mx-auto w-16 h-16 bg-primary/10 dark:bg-primary/20 rounded-full flex items-center justify-center mb-4">
          <ShieldCheckIcon className="h-8 w-8 text-primary" />
        </div>
        <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-2">
          Product Dashboard
        </h2>
        <p className="text-gray-600 dark:text-gray-400 max-w-lg mx-auto">
          This is a generated dashboard for <strong>{product.name}</strong>. 
          Use the settings page to configure specific integration endpoints and agent parameters.
        </p>
        
        <div className="mt-8 grid grid-cols-1 md:grid-cols-3 gap-4 text-left">
          <div className="p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
            <h3 className="font-medium text-gray-900 dark:text-white mb-1">Status</h3>
            <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300">
              Active
            </span>
          </div>
          <div className="p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
            <h3 className="font-medium text-gray-900 dark:text-white mb-1">Last Scan</h3>
            <p className="text-sm text-gray-600 dark:text-gray-400">Never</p>
          </div>
          <div className="p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
            <h3 className="font-medium text-gray-900 dark:text-white mb-1">Configuration</h3>
            <p className="text-sm text-gray-600 dark:text-gray-400">Default</p>
          </div>
        </div>
      </div>
    </div>
  );
}
