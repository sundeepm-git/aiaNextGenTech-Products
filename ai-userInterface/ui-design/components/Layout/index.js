'use client';

import Sidebar from './Sidebar';
import Navbar from './Navbar';
import { useApp } from '@/context/AppContext';

const Layout = ({ children }) => {
  const { sidebarOpen } = useApp();

  return (
    <div className="min-h-screen transition-colors duration-300">
      <Sidebar />
      <div className={`transition-all duration-300 ${sidebarOpen ? 'lg:pl-64' : 'lg:pl-16'}`}>
        <Navbar />
        <main className="p-6">
          {children}
        </main>
      </div>
    </div>
  );
};

export default Layout;
