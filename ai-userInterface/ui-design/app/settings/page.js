'use client';

import { useApp } from '@/context/AppContext';
import { CogIcon } from '@heroicons/react/24/outline';

export default function SettingsPage() {
  const { categories, toggleCategoryVisibility, products, toggleProductVisibility } = useApp();

  const categoryList = [
    { key: 'cybersecurity', name: categories.cybersecurity.name },
    { key: 'cloudAutomation', name: categories.cloudAutomation.name },
    { key: 'workflowBuilder', name: categories.workflowBuilder.name },
  ];

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
          Settings
        </h1>
        <p className="text-gray-600 dark:text-gray-400">
          Manage visibility and configuration for categories and products
        </p>
      </div>

      {/* Category Visibility */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <div className="flex items-center gap-3 mb-6">
          <CogIcon className="h-8 w-8 text-primary" aria-hidden="true" />
          <h2 className="text-2xl font-bold text-gray-900 dark:text-white">
            Category Visibility
          </h2>
        </div>

        <p className="text-sm text-gray-600 dark:text-gray-400 mb-6">
          Toggle visibility for entire agent categories. Hidden categories will not appear in the dashboard or navigation.
        </p>

        <div className="space-y-4">
          {categoryList.map((category) => (
            <div
              key={category.key}
              className="flex items-center justify-between p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg"
            >
              <div>
                <h3 className="font-semibold text-gray-900 dark:text-white">
                  {category.name}
                </h3>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  {products[category.key].length} products
                </p>
              </div>

              <button
                onClick={() => toggleCategoryVisibility(category.key)}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 ${
                  categories[category.key].visible
                    ? 'bg-primary'
                    : 'bg-gray-300 dark:bg-gray-600'
                }`}
                role="switch"
                aria-checked={categories[category.key].visible}
                aria-label={`Toggle ${category.name} visibility`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    categories[category.key].visible ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>
          ))}
        </div>
      </div>

      {/* Product Visibility */}
      {categoryList.map((category) => (
        <div
          key={category.key}
          className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6"
        >
          <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-4">
            {category.name} - Product Visibility
          </h2>

          <p className="text-sm text-gray-600 dark:text-gray-400 mb-6">
            Toggle visibility for individual products within this category.
          </p>

          <div className="space-y-3">
            {products[category.key].map((product) => (
              <div
                key={product.id}
                className="flex items-center justify-between p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg"
              >
                <div>
                  <h3 className="font-semibold text-gray-900 dark:text-white">
                    {product.name}
                  </h3>
                  <p className="text-sm text-gray-600 dark:text-gray-400">
                    {product.description}
                  </p>
                </div>

                <button
                  onClick={() => toggleProductVisibility(category.key, product.id)}
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 ${
                    product.visible
                      ? 'bg-primary'
                      : 'bg-gray-300 dark:bg-gray-600'
                  }`}
                  role="switch"
                  aria-checked={product.visible}
                  aria-label={`Toggle ${product.name} visibility`}
                >
                  <span
                    className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                      product.visible ? 'translate-x-6' : 'translate-x-1'
                    }`}
                  />
                </button>
              </div>
            ))}
          </div>
        </div>
      ))}

      {/* Save Notice */}
      <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg p-4">
        <p className="text-sm text-green-800 dark:text-green-300">
          ✓ All changes are automatically saved to your browser's local storage
        </p>
      </div>
    </div>
  );
}
