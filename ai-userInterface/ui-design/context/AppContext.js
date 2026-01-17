'use client';

import React, { createContext, useContext, useState, useEffect } from 'react';

// Initial product data structure
const initialProducts = {
  cybersecurity: [
    { 
      id: 'cs-unified', 
      name: 'nextGen-ThreatDetection', 
      description: 'Unified cybersecurity suite with 4 integrated AI agents: Threat Detection Pro, Vulnerability Scanner, Security Analytics, and Incident Response', 
      visible: true, 
      enabled: true, 
      route: '/cybersecurity/threat-detection' 
    },
  ],
  cloudAutomation: [
    { id: 'ca1', name: 'Cloud Migration Assistant', description: 'Seamless cloud migration automation', visible: true },
    { id: 'ca2', name: 'Resource Optimizer', description: 'AI-driven cloud resource optimization', visible: true },
    { id: 'ca3', name: 'Auto-Scaling Manager', description: 'Intelligent auto-scaling for cloud resources', visible: true },
    { id: 'ca4', name: 'Cost Analyzer', description: 'Real-time cloud cost analysis and prediction', visible: true },
  ],
  workflowBuilder: [
    { id: 'wb1', name: 'Visual Workflow Designer', description: 'Drag-and-drop workflow creation', visible: true },
    { id: 'wb2', name: 'Agent Orchestrator', description: 'Multi-agent workflow orchestration', visible: true },
    { id: 'wb3', name: 'Template Library', description: 'Pre-built workflow templates', visible: true },
    { id: 'wb4', name: 'Integration Hub', description: 'Connect with external services', visible: true },
  ],
};

// Initial category visibility
const initialCategories = {
  cybersecurity: { name: 'Cybersecurity Agent', visible: true },
  cloudAutomation: { name: 'Cloud Automation Agent', visible: true },
  workflowBuilder: { name: 'Workflow Builder', visible: true },
};

const AppContext = createContext();

export const useApp = () => {
  const context = useContext(AppContext);
  if (!context) {
    throw new Error('useApp must be used within an AppProvider');
  }
  return context;
};

export const AppProvider = ({ children }) => {
  // Theme state
  const [theme, setTheme] = useState('light');
  
  // Branding state
  const [branding, setBranding] = useState({
    companyName: 'AI-a NextGenTech',
    tagline: 'Where AI Meets Enterprise Innovation',
    logoUrl: '/logo-placeholder.svg',
  });

  // Category visibility state
  const [categories, setCategories] = useState(initialCategories);

  // Product visibility state
  const [products, setProducts] = useState(initialProducts);

  // Sidebar state
  const [sidebarOpen, setSidebarOpen] = useState(true);

  // Load saved preferences from localStorage
  useEffect(() => {
    if (typeof window !== 'undefined') {
      const savedTheme = localStorage.getItem('theme');
      const savedBranding = localStorage.getItem('branding');
      const savedCategories = localStorage.getItem('categories');
      const savedProducts = localStorage.getItem('products');

      if (savedTheme) setTheme(savedTheme);
      if (savedBranding) setBranding(JSON.parse(savedBranding));
      if (savedCategories) setCategories(JSON.parse(savedCategories));
      if (savedProducts) setProducts(JSON.parse(savedProducts));
    }
  }, []);

  // Apply theme to document
  useEffect(() => {
    if (typeof window !== 'undefined') {
      const root = window.document.documentElement;
      root.classList.remove('light', 'dark');
      root.classList.add(theme);
      localStorage.setItem('theme', theme);
    }
  }, [theme]);

  // Toggle theme
  const toggleTheme = (newTheme) => {
    setTheme(newTheme);
  };

  // Update branding
  const updateBranding = (newBranding) => {
    setBranding(newBranding);
    if (typeof window !== 'undefined') {
      localStorage.setItem('branding', JSON.stringify(newBranding));
    }
  };

  // Toggle category visibility
  const toggleCategoryVisibility = (categoryKey) => {
    const updatedCategories = {
      ...categories,
      [categoryKey]: {
        ...categories[categoryKey],
        visible: !categories[categoryKey].visible,
      },
    };
    setCategories(updatedCategories);
    if (typeof window !== 'undefined') {
      localStorage.setItem('categories', JSON.stringify(updatedCategories));
    }
  };

  // Toggle product visibility
  const toggleProductVisibility = (categoryKey, productId) => {
    const updatedProducts = {
      ...products,
      [categoryKey]: products[categoryKey].map((product) =>
        product.id === productId
          ? { ...product, visible: !product.visible }
          : product
      ),
    };
    setProducts(updatedProducts);
    if (typeof window !== 'undefined') {
      localStorage.setItem('products', JSON.stringify(updatedProducts));
    }
  };

  // Get visible products for a category
  const getVisibleProducts = (categoryKey) => {
    if (!categories[categoryKey]?.visible) return [];
    return products[categoryKey]?.filter((product) => product.visible) || [];
  };

  // Toggle sidebar
  const toggleSidebar = () => {
    setSidebarOpen(!sidebarOpen);
  };

  const value = {
    theme,
    toggleTheme,
    branding,
    updateBranding,
    categories,
    toggleCategoryVisibility,
    products,
    toggleProductVisibility,
    getVisibleProducts,
    sidebarOpen,
    toggleSidebar,
  };

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
};
