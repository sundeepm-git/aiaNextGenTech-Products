'use client';

import { useState } from 'react';
import { useApp } from '@/context/AppContext';
import { CogIcon, PlusIcon, PencilIcon, TrashIcon, XMarkIcon } from '@heroicons/react/24/outline';

export default function SettingsPage() {
  const { categories, toggleCategoryVisibility, products, toggleProductVisibility, addProduct, updateProduct, deleteProduct } = useApp();
  const [modalOpen, setModalOpen] = useState(false);
  const [modalMode, setModalMode] = useState('add'); // 'add' or 'edit'
  const [currentCategory, setCurrentCategory] = useState(null);
  const [currentProduct, setCurrentProduct] = useState(null);
  const [formData, setFormData] = useState({ name: '', description: '' });

  const categoryList = [
    { key: 'cybersecurity', name: categories.cybersecurity.name },
    { key: 'cloudAutomation', name: categories.cloudAutomation.name },
    { key: 'workflowBuilder', name: categories.workflowBuilder.name },
  ];

  const handleAddClick = (categoryKey) => {
    setModalMode('add');
    setCurrentCategory(categoryKey);
    setFormData({ name: '', description: '', provider: 'azure' });
    setModalOpen(true);
  };

  const handleEditClick = (categoryKey, product) => {
    setModalMode('edit');
    setCurrentCategory(categoryKey);
    setCurrentProduct(product);
    setFormData({ 
      name: product.name, 
      description: product.description,
      provider: product.provider || 'azure' 
    });
    setModalOpen(true);
  };

  const handleDeleteClick = (categoryKey, product) => {
    setModalMode('delete');
    setCurrentCategory(categoryKey);
    setCurrentProduct(product);
    setModalOpen(true);
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (modalMode === 'add') {
      addProduct(currentCategory, formData);
    } else if (modalMode === 'edit') {
      updateProduct(currentCategory, currentProduct.id, formData);
    } else if (modalMode === 'delete') {
      deleteProduct(currentCategory, currentProduct.id);
    }
    setModalOpen(false);
  };

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
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-bold text-gray-900 dark:text-white">
              {category.name} - Product Management
            </h2>
            <button
              onClick={() => handleAddClick(category.key)}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors"
            >
              <PlusIcon className="h-4 w-4" />
              Add Product
            </button>
          </div>

          <p className="text-sm text-gray-600 dark:text-gray-400 mb-6">
            Manage products within this category. Added products will appear on the dashboard.
          </p>

          <div className="space-y-3">
            {products[category.key].map((product) => (
              <div
                key={product.id}
                className="flex items-center justify-between p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg"
              >
                <div className="flex-1 mr-4">
                  <h3 className="font-semibold text-gray-900 dark:text-white">
                    {product.name}
                  </h3>
                  <p className="text-sm text-gray-600 dark:text-gray-400">
                    {product.description}
                  </p>
                </div>

                <div className="flex items-center gap-3">
                  <button
                    onClick={() => handleEditClick(category.key, product)}
                    className="p-2 text-gray-500 hover:text-primary hover:bg-gray-200 dark:hover:bg-gray-600 rounded-lg transition-colors"
                    title="Edit Product"
                  >
                    <PencilIcon className="h-5 w-5" />
                  </button>
                  <button
                    onClick={() => handleDeleteClick(category.key, product)}
                    className="p-2 text-gray-500 hover:text-red-500 hover:bg-red-100 dark:hover:bg-red-900/30 rounded-lg transition-colors"
                    title="Delete Product"
                  >
                    <TrashIcon className="h-5 w-5" />
                  </button>
                  <div className="h-6 w-px bg-gray-300 dark:bg-gray-600 mx-1"></div>
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
              </div>
            ))}
          </div>
        </div>
      ))}

      {/* Product Modal */}
      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <div className="bg-white dark:bg-gray-800 rounded-xl shadow-xl w-full max-w-md p-6">
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-xl font-bold text-gray-900 dark:text-white">
                {modalMode === 'add' ? 'Add New Product' : (modalMode === 'edit' ? 'Edit Product' : 'Delete Product')}
              </h3>
              <button
                onClick={() => setModalOpen(false)}
                className="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
              >
                <XMarkIcon className="h-6 w-6" />
              </button>
            </div>
            
            {modalMode === 'delete' ? (
              <div className="space-y-4">
                <p className="text-gray-600 dark:text-gray-300">
                  Are you sure you want to delete <strong>{currentProduct?.name}</strong>? This action cannot be undone.
                </p>
                <div className="flex justify-end gap-3 mt-6">
                  <button
                    type="button"
                    onClick={() => setModalOpen(false)}
                    className="px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleSubmit}
                    className="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors font-medium"
                  >
                    Delete Product
                  </button>
                </div>
              </div>
            ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Product Name
                </label>
                <input
                  type="text"
                  required
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary focus:border-transparent outline-none"
                  placeholder="e.g. Network Scanner"
                />
              </div>
              
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Description
                </label>
                <textarea
                  required
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary focus:border-transparent outline-none h-24 resize-none"
                  placeholder="Describe the product's function..."
                />
              </div>

              {currentCategory === 'cloudAutomation' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Cloud Provider
                  </label>
                  <select
                    value={formData.provider}
                    onChange={(e) => setFormData({ ...formData, provider: e.target.value })}
                    className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary focus:border-transparent outline-none"
                  >
                    <option value="azure">Azure Cloud</option>
                    <option value="gcp">Google Cloud Platform (GCP)</option>
                  </select>
                </div>
              )}

              <div className="flex justify-end gap-3 mt-6">
                <button
                  type="button"
                  onClick={() => setModalOpen(false)}
                  className="px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors font-medium"
                >
                  {modalMode === 'add' ? 'Create Product' : 'Save Changes'}
                </button>
              </div>
            </form>
            )}
          </div>
        </div>
      )}

      {/* Save Notice */}
      <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg p-4">
        <p className="text-sm text-green-800 dark:text-green-300">
          ✓ All changes are automatically saved to your browser's local storage
        </p>
      </div>
    </div>
  );
}
