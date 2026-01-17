'use client';

import { useState } from 'react';
import { useApp } from '@/context/AppContext';
import {
  HomeIcon,
  ShieldCheckIcon,
  CloudIcon,
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
      hasSubmenu: false,
    },
    { 
      name: categories.workflowBuilder.name, 
      href: '/workflow-builder', 
      icon: CogIcon,
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
        className={`fixed top-0 left-0 h-full bg-white dark:bg-gray-900 border-r border-gray-200 dark:border-gray-700 z-30 transition-transform duration-300 ${
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        } lg:translate-x-0 w-64`}
        role="navigation"
        aria-label="Main navigation"
      >
        <div className="flex flex-col h-full">
          {/* Close button for mobile */}
          <div className="flex items-center justify-between p-4 lg:hidden">
            <span className="text-lg font-semibold text-gray-900 dark:text-white">
              Menu
            </span>
            <button
              onClick={toggleSidebar}
              className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800"
              aria-label="Close sidebar"
            >
              <XMarkIcon className="h-6 w-6" />
            </button>
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
                          ? 'bg-primary text-white'
                          : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800'
                      }`}
                      aria-current={isActive ? 'page' : undefined}
                    >
                      <Icon className="h-6 w-6 flex-shrink-0" aria-hidden="true" />
                      <span className="font-medium">{item.name}</span>
                    </Link>
                    {item.hasSubmenu && (
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
                  {item.hasSubmenu && isExpanded && item.categoryKey && (
                    <div className="ml-6 mt-1 space-y-1">
                      {products[item.categoryKey]
                        ?.filter(product => product.visible)
                        .map(product => {
                          const productRoute = product.route || `/${item.categoryKey}/${product.id}`;
                          const isProductActive = pathname === productRoute;
                          
                          return (
                            <Link
                              key={product.id}
                              href={productRoute}
                              className={`block px-4 py-2 text-sm rounded-lg transition-colors ${
                                isProductActive
                                  ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300'
                                  : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
                              }`}
                            >
                              {product.name}
                            </Link>
                          );
                        })}
                    </div>
                  )}
                </div>
              );
            })}
          </nav>

          {/* Footer */}
          <div className="p-4 border-t border-gray-200 dark:border-gray-700">
            <p className="text-xs text-gray-500 dark:text-gray-400 text-center">
              © 2026 AI-a NextGenTech
              <br />
              Open Source Dashboard
            </p>
          </div>
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
