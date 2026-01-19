'use client';

import { useState } from 'react';
import { useApp } from '@/context/AppContext';
import {
  HomeIcon,
  ShieldCheckIcon,
  CloudIcon,
  CpuChipIcon,
  CogIcon,
  PaintBrushIcon,
  Bars3Icon,
  XMarkIcon,
  ChevronDownIcon,
  ChevronRightIcon,
} from '@heroicons/react/24/outline';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const Sidebar = () => {
  const { sidebarOpen, toggleSidebar, categories, products } = useApp();
  const pathname = usePathname();
  const [expandedCategories, setExpandedCategories] = useState({
    cybersecurity: false,
    cloudAutomation: false,
    workflowBuilder: false,
  });

  const toggleCategory = (categoryKey) => {
    setExpandedCategories({
      ...expandedCategories,
      [categoryKey]: !expandedCategories[categoryKey],
    });
  };

  const navItems = [
    { name: 'Dashboard', href: '/', icon: HomeIcon, visible: true },
    { 
      name: categories.cybersecurity.name, 
      href: '/cybersecurity', 
      icon: ShieldCheckIcon,
      visible: categories.cybersecurity.visible,
      categoryKey: 'cybersecurity',
      hasSubmenu: true,
    },
    { 
      name: categories.cloudAutomation.name, 
      href: '/cloud-automation', 
      icon: CloudIcon,
      visible: categories.cloudAutomation.visible,
      categoryKey: 'cloudAutomation',
      hasSubmenu: true,
    },
    { 
      name: categories.workflowBuilder.name, 
      href: '/workflow-builder', 
      icon: CpuChipIcon,
      visible: categories.workflowBuilder.visible,
      categoryKey: 'workflowBuilder',
      hasSubmenu: false,
    },
    { name: 'Settings', href: '/settings', icon: CogIcon, visible: true },
    { name: 'Theme & Branding', href: '/branding', icon: PaintBrushIcon, visible: true },
  ];

  const visibleNavItems = navItems.filter(item => item.visible);

  return (
    <>
      {/* Mobile sidebar backdrop */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-gray-900 bg-opacity-50 z-20 lg:hidden"
          onClick={toggleSidebar}
          aria-hidden="true"
        />
      )}

      {/* Sidebar */}
      <aside
        className={`fixed top-0 left-0 h-full bg-white dark:bg-gray-900 border-r border-gray-200 dark:border-gray-700 z-30 transition-all duration-300 ${
          sidebarOpen ? 'translate-x-0 w-64' : '-translate-x-full lg:translate-x-0 lg:w-16'
        }`}
        role="navigation"
        aria-label="Main navigation"
      >
        <div className="flex flex-col h-full">
          {/* Header with collapse button */}
          <div className="flex items-center justify-between p-4">
            {sidebarOpen ? (
              <>
                <div className="flex items-center justify-center p-1">
                  <Bars3Icon className="h-6 w-6 text-gray-900 dark:text-white" />
                </div>
                <button
                  onClick={toggleSidebar}
                  className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
                  aria-label="Collapse sidebar"
                >
                  <ChevronDownIcon className="h-5 w-5 transform rotate-[-90deg]" />
                </button>
              </>
            ) : (
              <button
                onClick={toggleSidebar}
                className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors mx-auto"
                aria-label="Expand sidebar"
              >
                <ChevronRightIcon className="h-5 w-5" />
              </button>
            )}
          </div>

          {/* Navigation links */}
          <nav className="flex-1 px-4 py-6 space-y-2 overflow-y-auto">
            {visibleNavItems.map((item) => {
              const Icon = item.icon;
              const isActive = pathname === item.href;
              const isExpanded = item.categoryKey && expandedCategories[item.categoryKey];

              return (
                <div key={item.name}>
                  <div className="flex items-center">
                    <Link
                      href={item.href}
                      className={`flex-1 flex items-center gap-3 px-4 py-3 rounded-lg transition-colors ${
                        isActive
                          ? (item.categoryKey === 'cybersecurity' 
                              ? 'bg-gradient-to-r from-red-400 to-yellow-400 text-white' 
                              : item.categoryKey === 'cloudAutomation'
                              ? 'bg-gradient-to-r from-blue-400 to-cyan-400 text-white'
                              : 'bg-primary text-white')
                          : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800'
                      }`}
                      aria-current={isActive ? 'page' : undefined}
                      title={!sidebarOpen ? item.name : undefined}
                    >
                      <Icon className="h-6 w-6 flex-shrink-0" aria-hidden="true" />
                      {sidebarOpen && <span className="font-medium">{item.name}</span>}
                    </Link>
                    {item.hasSubmenu && sidebarOpen && (
                      <button
                        onClick={() => toggleCategory(item.categoryKey)}
                        className="p-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg"
                        aria-label={`Toggle ${item.name} submenu`}
                      >
                        {isExpanded ? (
                          <ChevronDownIcon className="h-4 w-4" />
                        ) : (
                          <ChevronRightIcon className="h-4 w-4" />
                        )}
                      </button>
                    )}
                  </div>

                  {/* Submenu for products */}
                  {item.hasSubmenu && isExpanded && item.categoryKey && sidebarOpen && (
                    <div className="ml-6 mt-1 space-y-1">
                      {item.categoryKey === 'cloudAutomation' ? (
                        <>
                          {/* Azure Products */}
                          <div className="flex items-center gap-2 px-4 py-2 mt-4 mb-2">
                             <div className="h-0.5 flex-1 rounded-full opacity-30" style={{ backgroundColor: 'var(--color-accent)' }}></div>
                             <span className="text-base font-bold uppercase tracking-wider whitespace-nowrap" style={{ color: 'var(--color-accent)' }}>Azure Cloud</span>
                             <div className="h-0.5 flex-1 rounded-full opacity-30" style={{ backgroundColor: 'var(--color-accent)' }}></div>
                          </div>
                          {products[item.categoryKey]
                            ?.filter(product => product.visible && (!product.provider || product.provider === 'azure'))
                            .map(product => {
                              const productRoute = product.route || `/${item.categoryKey}/${product.id}`;
                              const isProductActive = pathname === productRoute;
                              
                              return (
                                <Link
                                  key={product.id}
                                  href={productRoute}
                                  style={isProductActive ? { backgroundColor: 'var(--bg-hover)', color: 'var(--color-accent)' } : {}}
                                  className={`block px-4 py-2 text-sm rounded-lg transition-colors ${
                                    isProductActive
                                      ? 'font-bold'
                                      : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
                                  }`}
                                >
                                  {product.name}
                                </Link>
                              );
                            })}

                          {/* GCP Products */}
                          <div className="flex items-center gap-2 px-4 py-2 mt-6 mb-2">
                             <div className="h-0.5 flex-1 rounded-full opacity-30" style={{ backgroundColor: 'var(--color-accent)' }}></div>
                             <span className="text-base font-bold uppercase tracking-wider whitespace-nowrap" style={{ color: 'var(--color-accent)' }}>GCP Cloud</span>
                             <div className="h-0.5 flex-1 rounded-full opacity-30" style={{ backgroundColor: 'var(--color-accent)' }}></div>
                          </div>
                          {products[item.categoryKey]
                            ?.filter(product => product.visible && product.provider === 'gcp')
                            .map(product => {
                              const productRoute = product.route || `/${item.categoryKey}/${product.id}`;
                              const isProductActive = pathname === productRoute;
                              
                              return (
                                <Link
                                  key={product.id}
                                  href={productRoute}
                                  style={isProductActive ? { backgroundColor: 'var(--bg-hover)', color: 'var(--color-accent)' } : {}}
                                  className={`block px-4 py-2 text-sm rounded-lg transition-colors ${
                                    isProductActive
                                      ? 'font-bold'
                                      : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
                                  }`}
                                >
                                  {product.name}
                                </Link>
                              );
                            })}
                        </>
                      ) : (
                        products[item.categoryKey]
                          ?.filter(product => product.visible)
                          .map(product => {
                            const productRoute = product.route || `/${item.categoryKey}/${product.id}`;
                            const isProductActive = pathname === productRoute;
                            
                            return (
                              <Link
                                key={product.id}
                                href={productRoute}
                                style={isProductActive ? { backgroundColor: 'var(--bg-hover)', color: 'var(--color-accent)' } : {}}
                                className={`block px-4 py-2 text-sm rounded-lg transition-colors ${
                                  isProductActive
                                    ? 'font-bold'
                                    : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
                                }`}
                              >
                                {product.name}
                              </Link>
                            );
                          })
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </nav>

          {/* Footer */}
          {sidebarOpen && (
            <div className="p-4 border-t border-gray-200 dark:border-gray-700">
              <p className="text-xs text-gray-500 dark:text-gray-400 text-center">
                © 2026 AI-a NextGenTech
                <br />
                Open Source Dashboard
              </p>
            </div>
          )}
        </div>
      </aside>

      {/* Mobile menu button */}
      <button
        onClick={toggleSidebar}
        className="fixed top-4 left-4 z-40 lg:hidden p-2 rounded-lg bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 shadow-lg"
        aria-label="Open sidebar"
      >
        <Bars3Icon className="h-6 w-6" />
      </button>
    </>
  );
};

export default Sidebar;
