'use client';

import { useState } from 'react';
import { useApp } from '@/context/AppContext';
import { PaintBrushIcon } from '@heroicons/react/24/outline';

export default function BrandingPage() {
  const { theme, toggleTheme, branding, updateBranding } = useApp();
  const [localBranding, setLocalBranding] = useState(branding);

  const handleUpdate = (field, value) => {
    const updated = { ...localBranding, [field]: value };
    setLocalBranding(updated);
    updateBranding(updated);
  };

  const themes = [
    { id: 'light', name: 'Light', preview: 'bg-white border-gray-300' },
    { id: 'dark', name: 'Dark', preview: 'bg-gray-900 border-gray-700' },
  ];

  const presetLogos = [
    { id: 1, name: 'AI Logo 1', color: 'from-blue-500 to-purple-500' },
    { id: 2, name: 'AI Logo 2', color: 'from-green-500 to-blue-500' },
    { id: 3, name: 'AI Logo 3', color: 'from-purple-500 to-pink-500' },
    { id: 4, name: 'AI Logo 4', color: 'from-orange-500 to-red-500' },
  ];

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
          Theme & Branding
        </h1>
        <p className="text-gray-600 dark:text-gray-400">
          Customize the appearance and branding of your dashboard
        </p>
      </div>

      {/* Theme Selection */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <div className="flex items-center gap-3 mb-6">
          <PaintBrushIcon className="h-8 w-8 text-primary" aria-hidden="true" />
          <h2 className="text-2xl font-bold text-gray-900 dark:text-white">
            Theme Selection
          </h2>
        </div>

        <p className="text-sm text-gray-600 dark:text-gray-400 mb-6">
          Choose your preferred color theme for the dashboard interface.
        </p>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {themes.map((themeOption) => (
            <button
              key={themeOption.id}
              onClick={() => toggleTheme(themeOption.id)}
              className={`p-6 rounded-lg border-2 transition-all ${
                theme === themeOption.id
                  ? 'border-primary bg-primary/10'
                  : 'border-gray-300 dark:border-gray-600 hover:border-primary/50'
              }`}
              aria-pressed={theme === themeOption.id}
            >
              <div className={`w-full h-24 rounded-lg mb-4 ${themeOption.preview} border-2`} />
              <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                {themeOption.name} Theme
              </h3>
              {theme === themeOption.id && (
                <p className="text-sm text-primary mt-2">✓ Currently Active</p>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Company Branding */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">
          Company Branding
        </h2>

        <div className="space-y-6">
          {/* Company Name */}
          <div>
            <label
              htmlFor="companyName"
              className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2"
            >
              Company Name
            </label>
            <input
              id="companyName"
              type="text"
              value={localBranding.companyName}
              onChange={(e) => handleUpdate('companyName', e.target.value)}
              className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary focus:border-transparent"
              placeholder="Enter company name"
            />
          </div>

          {/* Tagline */}
          <div>
            <label
              htmlFor="tagline"
              className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2"
            >
              Tagline
            </label>
            <input
              id="tagline"
              type="text"
              value={localBranding.tagline}
              onChange={(e) => handleUpdate('tagline', e.target.value)}
              className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary focus:border-transparent"
              placeholder="Enter tagline"
            />
          </div>

          {/* Logo Selection */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Logo Style
            </label>
            <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
              Select a preset logo style or upload your own (feature coming soon)
            </p>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              {presetLogos.map((logo) => (
                <button
                  key={logo.id}
                  className="p-4 border-2 border-gray-300 dark:border-gray-600 rounded-lg hover:border-primary transition-colors"
                  onClick={() => handleUpdate('logoUrl', `/logo-${logo.id}.svg`)}
                >
                  <div
                    className={`w-16 h-16 mx-auto rounded-lg bg-gradient-to-br ${logo.color} flex items-center justify-center`}
                  >
                    <span className="text-white font-bold text-2xl">AI</span>
                  </div>
                  <p className="text-xs text-gray-600 dark:text-gray-400 mt-2 text-center">
                    {logo.name}
                  </p>
                </button>
              ))}
            </div>
          </div>

          {/* Upload Logo (Coming Soon) */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Upload Custom Logo
            </label>
            <div className="border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-lg p-8 text-center">
              <p className="text-sm text-gray-600 dark:text-gray-400">
                Custom logo upload feature coming soon
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-500 mt-2">
                Future integration: File upload and image processing
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Preview */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">
          Preview
        </h2>

        <div className="border border-gray-300 dark:border-gray-600 rounded-lg p-4 bg-gray-50 dark:bg-gray-700/50">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 bg-gradient-to-br from-primary to-secondary rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-xl">AI</span>
            </div>
            <div>
              <h3 className="text-xl font-bold text-gray-900 dark:text-white">
                {localBranding.companyName}
              </h3>
              <p className="text-sm text-gray-600 dark:text-gray-400">
                {localBranding.tagline}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Save Notice */}
      <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg p-4">
        <p className="text-sm text-green-800 dark:text-green-300">
          ✓ All changes are automatically saved to your browser's local storage
        </p>
      </div>
    </div>
  );
}
