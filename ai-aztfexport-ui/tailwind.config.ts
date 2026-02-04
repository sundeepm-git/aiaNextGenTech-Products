import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        background: "#F3F2F1", // Azure portal light canvas
        surface: "#FFFFFF",    // White cards
        primary: "#0078D4",    // Azure blue
        secondary: "#106EBE",  // Darker azure
        error: "#D13438",      // Fluent danger red
        text: "#1F2937",       // Gray 800 text (darker for readability)
        muted: "#5E6470",      // Subdued text
        border: "#D0D7DE"      // Light border
      },
      fontFamily: {
        sans: ['var(--font-inter)'],
        mono: ['var(--font-jetbrains-mono)'],
      },
      animation: {
        'pulse-fast': 'pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      }
    },
  },
  plugins: [],
};
export default config;
