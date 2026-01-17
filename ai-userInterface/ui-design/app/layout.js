import { Inter } from 'next/font/google';
import { AppProvider } from '@/context/AppContext';
import Layout from '@/components/Layout';
import '@/styles/globals.css';

const inter = Inter({ subsets: ['latin'] });

export const metadata = {
  title: 'AI-a NextGenTech - GenAI Agent Dashboard',
  description: 'Modern GenAI and Agentic AI Product Dashboard',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={inter.className}>
        <AppProvider>
          <Layout>{children}</Layout>
        </AppProvider>
      </body>
    </html>
  );
}
