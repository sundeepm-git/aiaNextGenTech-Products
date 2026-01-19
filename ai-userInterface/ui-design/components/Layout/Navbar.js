'use client';

import { useApp } from '@/context/AppContext';
import { SunIcon, MoonIcon, SwatchIcon, CubeTransparentIcon } from '@heroicons/react/24/outline';
import { useState } from 'react';
import Image from 'next/image';

const Navbar = () => {
  const { theme, toggleTheme, branding, updateBranding } = useApp();
  const [showThemeMenu, setShowThemeMenu] = useState(false);

  // File upload handler
  const handleLogoUpload = async (e) => {
    const file = e.target.files[0];
    if (file) {
      if (file.size > 2 * 1024 * 1024) { // 2MB limit
        alert("File is too large! Please upload a logo smaller than 2MB.");
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
          updateBranding({ ...branding, logoUrl: data.path });
        } else {
          alert('Failed to upload logo.');
        }
      } catch (error) {
        console.error('Error uploading logo:', error);
        alert('An error occurred while uploading the logo.');
      }
    }
  };

  const themes = [
    { id: 'light', name: 'Light Mode' },
    { id: 'dark', name: 'Dark Mode' },
    { id: 'amazon', name: 'Espresso Warm' },
    { id: 'meta', name: 'Ocean Blue' },
    { id: 'corporate', name: 'Metro Charcoal' },
    { id: 'slate-pro', name: 'Deep Slate' },
    { id: 'teal-tech', name: 'Cyber Teal' },
    { id: 'purple-enterprise', name: 'Royal Velvet' },
    { id: 'olive-moss', name: 'Forest Green' },
    { id: 'navy-pro', name: 'Midnight Navy' },
    { id: 'charcoal', name: 'High Contrast' },
    { id: 'warm-beige', name: 'Burgundy Red' },
  ];

  return (
    <header
      className="sticky top-0 z-50 border-b border-gray-200 dark:border-gray-700 shadow-md transition-all duration-300 bg-cover bg-center bg-no-repeat group/header"
      style={{
        backgroundImage: branding.headerUrl ? `url(${branding.headerUrl})` : 'none',
        backgroundColor: 'var(--bg-page-start)',
        backgroundBlendMode: branding.headerUrl ? 'overlay' : 'normal'
      }}
      role="banner"
    >
      {/* Interactive Background Graphics Container */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <>
            {/* Animated Gradient Orbs */}
            <div className="absolute top-[-20%] right-[-10%] w-[500px] h-[500px] bg-gradient-to-br from-[var(--color-accent)] to-transparent opacity-20 dark:opacity-30 rounded-full blur-[100px] animate-pulse-slow mix-blend-screen" />
            <div className="absolute bottom-[-20%] left-[-10%] w-[400px] h-[400px] bg-gradient-to-tr from-[var(--color-secondary)] to-transparent opacity-20 dark:opacity-30 rounded-full blur-[80px] animate-blob mix-blend-screen" />
            
            {/* Geometric Grid Overlay - Always Visible */}
            <div 
              className="absolute inset-0 opacity-[0.1] dark:opacity-[0.15]"
              style={{ 
                backgroundImage: `linear-gradient(to right, var(--text-muted) 1px, transparent 1px), linear-gradient(to bottom, var(--text-muted) 1px, transparent 1px)`,
                backgroundSize: '40px 40px',
                maskImage: 'linear-gradient(to bottom, black 40%, transparent 100%)'
              }}
            />

            {/* AI Scanner Line (Header Background) - Always Visible */}
            <div className="absolute inset-0 overflow-hidden pointer-events-none z-10">
              <div className="w-full h-[2px] bg-gradient-to-r from-transparent via-[var(--color-accent)] to-transparent opacity-40 animate-scan blur-[1px]" />
            </div>

            {/* Digital Liquid Wave */}
            <div className="absolute bottom-0 left-0 right-0 h-48 overflow-hidden pointer-events-none opacity-30 dark:opacity-40">
                {/* Wave 1 */}
                <div className="absolute bottom-[-180%] left-[-20%] w-[140%] h-[350%] rounded-[38%] bg-gradient-to-tr from-[var(--color-accent)] via-[var(--color-accent)]/50 to-transparent animate-spin-slow blur-3xl mix-blend-screen" />
                {/* Wave 2 */}
                <div className="absolute bottom-[-180%] right-[-20%] w-[140%] h-[350%] rounded-[42%] bg-gradient-to-tl from-[var(--color-secondary)] via-[var(--color-secondary)]/50 to-transparent animate-spin-reverse-slower blur-3xl mix-blend-screen" />
            </div>

            {/* Floating Particles */}
            <div className="absolute inset-0 overflow-hidden">
               <div className="absolute top-1/4 left-1/4 w-2 h-2 bg-[var(--color-accent)] rounded-full animate-float-delayed opacity-50" />
               <div className="absolute top-3/4 right-1/3 w-3 h-3 bg-[var(--color-secondary)] rounded-full animate-float opacity-40" />
               <div className="absolute top-1/3 right-1/4 w-1.5 h-1.5 bg-[var(--text-main)] rounded-full animate-ping-slow opacity-30" />
            </div>
          </>
        {branding.headerUrl && <div className="absolute inset-0 bg-black/5 dark:bg-black/30 backdrop-blur-[0px] z-0 transition-opacity duration-300 group-hover/header:bg-black/0" />}
      </div>
      
      <div className="relative z-[60] flex items-center justify-between px-8 py-5">
        {/* Branding */}
        <div className="flex items-center gap-8">
          <label className="cursor-pointer relative group" title="Click to upload logo">
            <input 
              type="file" 
              accept="image/png, image/jpeg, image/svg+xml" 
              className="hidden" 
              onChange={handleLogoUpload} 
            />
            {branding.logoUrl && branding.logoUrl !== '/logo-placeholder.svg' ? (
              <div className="relative">
                 {/* Rotating Tech Ring */}
                 <div className="absolute inset-0 -m-1 border border-dashed border-[var(--color-accent)]/30 rounded-full animate-spin-slow w-[calc(100%+8px)] h-[calc(100%+8px)] -top-1 -left-1 opacity-0 group-hover:opacity-100 transition-opacity duration-500 pointer-events-none" />
                 <div className="absolute inset-0 -m-1 border border-dotted border-[var(--color-secondary)]/30 rounded-full animate-spin-reverse-slower w-[calc(100%+12px)] h-[calc(100%+12px)] -top-1.5 -left-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-500 pointer-events-none" />
                 
                 {/* Logo Glow */}
                 <div className="absolute inset-0 bg-[var(--color-accent)]/20 blur-xl rounded-full opacity-0 group-hover:opacity-40 transition-opacity duration-300 animate-pulse-slow pointer-events-none" />

                 <img 
                   src={branding.logoUrl} 
                   alt="Company Logo" 
                   className="h-28 w-auto min-w-[3.5rem] object-contain rounded-xl relative z-10 transition-all duration-300 group-hover:scale-105 drop-shadow-sm" 
                 />
                 
                 {/* Scanner Beam Effect on Logo */}
                 <div className="absolute inset-0 z-20 pointer-events-none overflow-hidden rounded-xl">
                   <div className="absolute top-0 bottom-0 w-[10px] bg-gradient-to-r from-transparent via-white/40 to-transparent skew-x-[-20deg] animate-shine" />
                 </div>
              </div>
            ) : (
              <div 
                className="w-28 h-28 rounded-xl flex items-center justify-center group-hover:opacity-95 transition-all duration-300 group-hover:scale-105 shadow-xl relative overflow-hidden ring-1 ring-white/20"
                style={{ 
                  background: 'linear-gradient(135deg, var(--color-accent), var(--color-secondary))',
                  boxShadow: '0 8px 16px -4px var(--color-accent-shadow, rgba(0,0,0,0.2))'
                }}
              >
                {/* Logo Graphics */}
                <div className="absolute top-0 right-0 w-20 h-20 bg-white/20 blur-xl rounded-full -translate-y-1/2 translate-x-1/2 animate-pulse" />
                <div className="absolute bottom-0 left-0 w-16 h-16 bg-black/10 blur-xl rounded-full translate-y-1/3 -translate-x-1/3" />
                
                <CubeTransparentIcon className="h-14 w-14 text-white drop-shadow-md relative z-10 transition-transform duration-700 group-hover:rotate-180" />
              </div>
            )}
            <div className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 bg-black/40 rounded-xl transition-all duration-300 backdrop-blur-sm">
                <span className="text-white text-xs font-bold bg-black/60 px-3 py-1.5 rounded-full border border-white/20 shadow-lg transform translate-y-2 group-hover:translate-y-0 transition-transform">Update</span>
            </div>
          </label>
          
          <div className="flex flex-col justify-center gap-1 group/text relative pl-2">
             {/* Text Background Glow */}
             <div className="absolute inset-0 bg-gradient-to-r from-[var(--color-accent)]/0 via-[var(--color-accent)]/5 to-[var(--color-secondary)]/0 blur-xl opacity-0 group-hover/text:opacity-100 transition-opacity duration-500 pointer-events-none -z-10" />

            {branding.showCompanyName && (
              <h1 className="text-4xl font-extrabold leading-none tracking-tight transition-all duration-300 transform group-hover/text:tracking-wide origin-left flex relative overflow-hidden pb-1">
                {/* Data Stream Effect (Subtle background scan) */}
                <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent skew-x-[-20deg] w-[20%] animate-shine opacity-0 group-hover/text:opacity-100 pointer-events-none" />
                
                {branding.companyName.match(/.{1,3}/g)?.map((chunk, i) => (
                  <span 
                    key={i}
                    className="relative inline-block transition-transform duration-300 hover:-translate-y-1"
                    style={{ 
                      color: i % 2 === 0 ? 'var(--color-accent)' : 'var(--color-secondary)',
                      textShadow: i % 2 === 0 
                        ? '0 0 20px var(--color-accent), 0 0 10px var(--color-accent)' 
                        : '0 0 20px var(--color-secondary), 0 0 10px var(--color-secondary)',
                    }}
                  >
                    {chunk}
                  </span>
                )) || branding.companyName}
              </h1>
            )}
            
            {branding.showTagline && (
              <div className="relative overflow-hidden group/tag">
                <p 
                  className="text-lg font-medium opacity-80 group-hover/text:opacity-100 transition-all duration-300 group-hover/text:translate-x-1"
                  style={{ color: 'var(--text-main)' }}
                >
                  <span className="inline-block animate-pulse-slow">
                    {branding.tagline}
                  </span>
                </p>
                {/* Tagline Underline Scanner */}
                <div className="absolute bottom-0 left-0 h-[2px] bg-gradient-to-r from-transparent via-[var(--color-accent)] to-transparent w-full -translate-x-full group-hover/text:animate-[shine_3s_ease-in-out_infinite]" />
              </div>
            )}
          </div>
        </div>

        {/* Theme selector */}
        <div className="flex items-center gap-4 relative">
          <button
            type="button"
            onClick={() => setShowThemeMenu(!showThemeMenu)}
            className="p-2 rounded-lg bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
            aria-label="Select theme"
          >
            <SwatchIcon className="h-6 w-6 text-gray-700 dark:text-gray-300" aria-hidden="true" />
          </button>

          {/* Theme dropdown menu */}
          {showThemeMenu && (
            <div className="absolute right-0 top-14 w-56 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-lg p-2 z-50">
              <div className="text-xs font-semibold text-gray-500 dark:text-gray-400 px-3 py-2 uppercase tracking-wide">
                Select Interface Theme
              </div>
              <div className="max-h-96 overflow-y-auto">
              {themes.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    console.log('Switching theme to:', t.id);
                    toggleTheme(t.id);
                    setShowThemeMenu(false);
                  }}
                  className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-md transition-colors ${
                    theme === t.id
                      ? 'bg-primary text-white'
                      : 'hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-900 dark:text-white'
                  }`}
                >
                  <div className={`h-5 w-5 rounded border border-gray-300 dark:border-gray-600 flex items-center justify-center ${t.id === 'light' ? 'bg-white text-black' : t.id === 'dark' ? 'bg-gray-900 text-white' : ''} theme-preview-${t.id}`}>
                    {t.id === 'light' && <SunIcon className="h-4 w-4" />}
                    {t.id === 'dark' && <MoonIcon className="h-4 w-4" />}
                  </div>
                  <span className="font-medium">{t.name}</span>
                  {theme === t.id && (
                    <span className="ml-auto text-xs">✓</span>
                  )}
                </button>
              ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Overlay to close menu when clicking outside */}
      {showThemeMenu && (
        <div
          className="fixed inset-0 z-[55]"
          onClick={() => setShowThemeMenu(false)}
        />
      )}
    </header>
  );
};

export default Navbar;
