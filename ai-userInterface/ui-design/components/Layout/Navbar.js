'use client';

import { useApp } from '@/context/AppContext';
import { SunIcon, MoonIcon } from '@heroicons/react/24/outline';
import Image from 'next/image';

const Navbar = () => {
  const { theme, toggleTheme, branding } = useApp();

  return (
    <header
      className="sticky top-0 z-10 bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-700 shadow-sm"
      role="banner"
    >
      <div className="flex items-center justify-between px-6 py-4">
        {/* Branding */}
        <div className="flex items-center gap-4">
          <div className="w-10 h-10 bg-gradient-to-br from-primary to-secondary rounded-lg flex items-center justify-center">
            <span className="text-white font-bold text-xl">AI</span>
          </div>
          <div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              {branding.companyName}
            </h1>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              {branding.tagline}
            </p>
          </div>
        </div>

        {/* Theme toggle */}
        <div className="flex items-center gap-4">
          <button
            onClick={() => toggleTheme(theme === 'light' ? 'dark' : 'light')}
            className="p-2 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
            aria-label={`Switch to ${theme === 'light' ? 'dark' : 'light'} mode`}
          >
            {theme === 'light' ? (
              <MoonIcon className="h-6 w-6 text-gray-700" aria-hidden="true" />
            ) : (
              <SunIcon className="h-6 w-6 text-yellow-400" aria-hidden="true" />
            )}
          </button>
        </div>
      </div>
    </header>
  );
};

export default Navbar;
