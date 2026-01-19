'use client';

import { useState, useEffect } from 'react';
import { useApp } from '@/context/AppContext';
import { PaintBrushIcon } from '@heroicons/react/24/outline';

export default function BrandingPage() {
  const { theme, toggleTheme, branding, updateBranding } = useApp();
  const [localBranding, setLocalBranding] = useState(branding);

  // Sync state when global branding updates (e.g. from localStorage load)
  useEffect(() => {
    setLocalBranding(branding);
  }, [branding]);

  const handleUpdate = (field, value) => {
    const updated = { ...localBranding, [field]: value };
    setLocalBranding(updated);
    updateBranding(updated);
  };

  const handleFileUpload = async (e) => {
    const file = e.target.files[0];
    if (file) {
      if (file.size > 2 * 1024 * 1024) { // 2MB limit
        alert("File is too large! Please upload an image smaller than 2MB.");
        return;
      }
      
      const formData = new FormData();
      formData.append('file', file);

      try {
        const response = await fetch('/api/upload', {
          method: 'POST',
          body: formData,
        });

        if (response.ok) {
          const data = await response.json();
          handleUpdate('logoUrl', data.path);
        } else {
          alert('Failed to upload logo.');
        }
      } catch (error) {
        console.error('Error uploading logo:', error);
      }
    }
  };

  const handleHeaderUpload = async (e) => {
    const file = e.target.files[0];
    if (file) {
      if (file.size > 5 * 1024 * 1024) { // 5MB limit for headers
        alert("File is too large! Please upload a header image smaller than 5MB.");
        return;
      }
      
      const formData = new FormData();
      formData.append('file', file);

      try {
        const response = await fetch('/api/upload', {
          method: 'POST',
          body: formData,
        });

        if (response.ok) {
          const data = await response.json();
          handleUpdate('headerUrl', data.path);
        } else {
          alert('Failed to upload header image.');
        }
      } catch (error) {
        console.error('Error uploading header:', error);
      }
    }
  };

  const themes = [
    { id: 'light', name: 'Light Mode', preview: 'bg-white border-gray-300' },
    { id: 'dark', name: 'Dark Mode', preview: 'bg-gray-900 border-gray-700' },
    { id: 'amazon', name: 'Espresso Warm', preview: 'bg-[#f8f4e6] border-orange-200' },
    { id: 'meta', name: 'Ocean Blue', preview: 'bg-[#f0f9ff] border-blue-200' },
    { id: 'corporate', name: 'Metro Charcoal', preview: 'bg-slate-50 border-slate-200' },
    { id: 'slate-pro', name: 'Deep Slate', preview: 'bg-[#0f172a] border-slate-700' },
    { id: 'teal-tech', name: 'Cyber Teal', preview: 'bg-teal-50 border-teal-200' },
    { id: 'purple-enterprise', name: 'Royal Velvet', preview: 'bg-purple-50 border-purple-200' },
    { id: 'olive-moss', name: 'Forest Green', preview: 'bg-[#ecfccb] border-lime-200' },
    { id: 'navy-pro', name: 'Midnight Navy', preview: 'bg-[#0a192f] border-blue-900' },
    { id: 'charcoal', name: 'High Contrast', preview: 'bg-[#121212] border-gray-600' },
    { id: 'warm-beige', name: 'Burgundy Red', preview: 'bg-[#fff1f2] border-rose-200' },
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

        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {themes.map((themeOption) => (
            <button
              key={themeOption.id}
              onClick={() => toggleTheme(themeOption.id)}
              className={`p-4 rounded-lg border-2 transition-all text-left ${
                theme === themeOption.id
                  ? 'border-primary ring-2 ring-primary/20'
                  : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
              }`}
              aria-pressed={theme === themeOption.id}
            >
              <div className={`w-full h-16 rounded mb-3 ${themeOption.preview} border shadow-sm`} />
              <h3 className="text-sm font-semibold text-gray-900 dark:text-white">
                {themeOption.name}
              </h3>
              {theme === themeOption.id && (
                <p className="text-xs text-primary mt-1 font-medium">Active</p>
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

          {/* Visibility Toggles */}
          <div className="flex gap-8 p-4 bg-gray-50 dark:bg-gray-700/30 rounded-lg border border-gray-200 dark:border-gray-700">
             <label className="flex items-center gap-3 cursor-pointer">
                <input 
                  type="checkbox" 
                  checked={localBranding.showCompanyName ?? true} 
                  onChange={(e) => handleUpdate('showCompanyName', e.target.checked)}
                  className="w-5 h-5 rounded border-gray-300 text-primary focus:ring-primary"
                />
                <span className="text-sm font-medium text-gray-700 dark:text-gray-200">Show Company Name</span>
             </label>
             <label className="flex items-center gap-3 cursor-pointer">
                <input 
                  type="checkbox" 
                  checked={localBranding.showTagline ?? true} 
                  onChange={(e) => handleUpdate('showTagline', e.target.checked)}
                  className="w-5 h-5 rounded border-gray-300 text-primary focus:ring-primary"
                />
                <span className="text-sm font-medium text-gray-700 dark:text-gray-200">Show Tagline</span>
             </label>
          </div>

          {/* Logo URL */}
          <div>
            <label
              htmlFor="logoUrl"
              className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2"
            >
              Logo URL
            </label>
             <div className="flex gap-4 items-end">
              <div className="flex-1">
                <input
                  id="logoUrl"
                  type="text"
                  value={localBranding.logoUrl || ''}
                  onChange={(e) => handleUpdate('logoUrl', e.target.value)}
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary focus:border-transparent"
                  placeholder="https://example.com/logo.png"
                />
                <p className="text-xs text-gray-500 mt-1">Provide a direct URL to an image file (PNG, JPG, SVG)</p>
              </div>
              <div className="flex-shrink-0 w-16 h-10 border border-gray-300 dark:border-gray-600 rounded flex items-center justify-center bg-gray-50 dark:bg-gray-800 overflow-hidden">
                  {localBranding.logoUrl ? (
                       <img src={localBranding.logoUrl} alt="Preview" className="h-full w-full object-contain" />
                  ) : (
                      <span className="text-xs text-gray-400">Preview</span>
                  )}
              </div>
            </div>
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

          {/* Upload Logo */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Upload Custom Logo
            </label>
            <div className="border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-lg p-8 text-center hover:border-primary transition-colors relative">
               <input
                type="file"
                accept="image/png, image/jpeg, image/svg+xml"
                onChange={handleFileUpload}
                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
              />
              <div className="space-y-2 pointer-events-none">
                <div className="mx-auto h-12 w-12 text-gray-400">
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5" />
                  </svg>
                </div>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                  <span className="font-semibold text-primary">Click to upload</span> or drag and drop
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-500">
                  PNG, JPG or SVG (max 2MB)
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Website Header Management */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">
          Website Header Management
        </h2>

        <div className="space-y-6">
          <p className="text-sm text-gray-600 dark:text-gray-400">
            Customize the top navigation bar with a branded background image or banner.
          </p>

          {/* Header Upload */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Upload Header Background / Banner
            </label>
            <div className="border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-lg p-8 text-center hover:border-primary transition-colors relative cursor-pointer group">
               <input
                type="file"
                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-10"
                accept="image/*"
                onChange={handleHeaderUpload}
              />
              {localBranding.headerUrl ? (
                <div className="relative w-full h-32 rounded-lg overflow-hidden">
                   <img 
                      src={localBranding.headerUrl} 
                      alt="Header Preview" 
                      className="w-full h-full object-cover"
                   />
                   <div className="absolute inset-0 bg-black/50 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                      <p className="text-white font-medium">Click to change header image</p>
                   </div>
                </div>
              ) : (
                <div className="flex flex-col items-center justify-center py-4">
                   <div className="mx-auto h-12 w-12 text-gray-400 mb-2">
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909m-18 3.75h16.5a1.5 1.5 0 001.5-1.5V6a1.5 1.5 0 00-1.5-1.5H3.75A1.5 1.5 0 002.25 6v12a1.5 1.5 0 001.5 1.5zm10.5-11.25h.008v.008h-.008V8.25zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" />
                      </svg>
                   </div>
                  <p className="text-gray-600 dark:text-gray-400 mb-2 font-medium">
                    Click or drag and drop to upload
                  </p>
                  <p className="text-xs text-gray-500">
                    Recommended size: 1920x80px or larger
                  </p>
                </div>
              )}
            </div>
          </div>
          
          {localBranding.headerUrl && (
            <div className="flex justify-end">
               <button
                 onClick={() => handleUpdate('headerUrl', null)}
                 className="text-red-600 hover:text-red-700 text-sm font-medium"
               >
                 Remove Header Image
               </button>
            </div>
          )}
        </div>
      </div>

      {/* Preview */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">
          Header & Branding Preview
        </h2>

        {/* Live Preview Container */}
        <div 
          className="border border-gray-300 dark:border-gray-600 rounded-lg transition-all bg-cover bg-center overflow-hidden relative group/preview"
          style={{
            backgroundImage: localBranding.headerUrl ? `url(${localBranding.headerUrl})` : 'none',
            backgroundColor: 'var(--bg-page-start)',
            backgroundBlendMode: localBranding.headerUrl ? 'overlay' : 'normal',
            minHeight: '180px'
          }}
        >
           {/* Interactive Background Graphics (Preview Mode) */}
           {!localBranding.headerUrl && (
            <>
               {/* Animated Gradient Orbs */}
              <div className="absolute top-[-20%] right-[-10%] w-[300px] h-[300px] bg-gradient-to-br from-[var(--color-accent)] to-transparent opacity-20 rounded-full blur-[60px] animate-pulse-slow mix-blend-screen pointer-events-none" />
              <div className="absolute bottom-[-20%] left-[-10%] w-[200px] h-[200px] bg-gradient-to-tr from-[var(--color-secondary)] to-transparent opacity-20 rounded-full blur-[50px] animate-blob mix-blend-screen pointer-events-none" />
              
              {/* Geometric Grid Overlay - Preview */}
              <div 
                className="absolute inset-0 opacity-[0.05] pointer-events-none"
                style={{ 
                  backgroundImage: `linear-gradient(to right, var(--text-muted) 1px, transparent 1px), linear-gradient(to bottom, var(--text-muted) 1px, transparent 1px)`,
                  backgroundSize: '30px 30px',
                  maskImage: 'linear-gradient(to bottom, black 40%, transparent 100%)'
                }}
              />
            </>
          )}

          {localBranding.headerUrl && <div className="absolute inset-0 bg-black/10 z-0 pointer-events-none" />}
          
          <div className="relative z-10 p-8 flex items-center gap-8">
             {localBranding.logoUrl && localBranding.logoUrl !== '/logo-placeholder.svg' ? (
                <img src={localBranding.logoUrl} alt="Company Logo" className="h-28 w-auto object-contain rounded-xl drop-shadow-sm" />
             ) : (
                <div 
                   className="w-28 h-28 rounded-xl flex items-center justify-center shadow-lg relative overflow-hidden"
                   style={{ 
                     background: 'linear-gradient(135deg, var(--color-accent), var(--color-secondary))',
                     boxShadow: '0 8px 16px -4px var(--color-accent-shadow, rgba(0,0,0,0.2))'
                   }}
                >
                  <div className="absolute top-0 right-0 w-16 h-16 bg-white/20 blur-lg rounded-full -translate-y-1/2 translate-x-1/2" />
                  <svg className="h-14 w-14 text-white drop-shadow-md relative z-10" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9" />
                  </svg>
                </div>
             )}
            <div className="flex flex-col justify-center gap-1">
              {(localBranding.showCompanyName ?? true) && (
                <h3 className="text-4xl font-extrabold leading-none tracking-tight transition-all duration-300 transform origin-left flex">
                  {localBranding.companyName.match(/.{1,3}/g)?.map((chunk, i) => (
                    <span 
                      key={i}
                      style={{ 
                        color: i % 2 === 0 ? 'var(--color-accent)' : 'var(--color-secondary)',
                        filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.1))'
                      }}
                    >
                      {chunk}
                    </span>
                  )) || localBranding.companyName}
                </h3>
              )}
              {(localBranding.showTagline ?? true) && (
                <p 
                  className="text-lg font-medium opacity-90 transition-colors duration-300"
                  style={{ color: 'var(--text-main)' }}
                >
                  {localBranding.tagline}
                </p>
              )}
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
