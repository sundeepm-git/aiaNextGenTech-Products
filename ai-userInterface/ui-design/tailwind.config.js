/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: {
          light: 'var(--color-accent)',
          DEFAULT: 'var(--color-accent)',
          dark: 'var(--color-accent)',
        },
        secondary: {
          light: 'var(--color-secondary)',
          DEFAULT: 'var(--color-secondary)',
          dark: 'var(--color-secondary)',
        },
      },
      animation: {
        'blob': 'blob 7s infinite',
        'pulse-slow': 'pulse 6s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'float': 'float 6s ease-in-out infinite',
        'float-delayed': 'float 6s ease-in-out 3s infinite',
        'ping-slow': 'ping 3s cubic-bezier(0, 0, 0.2, 1) infinite',
        'spin-slow': 'spin 15s linear infinite',
        'spin-reverse-slower': 'spin-reverse 20s linear infinite',
        'scan': 'scan 15s linear infinite',
        'shine': 'shine 8s ease-in-out infinite',
      },
      keyframes: {
        blob: {
          '0%': { transform: 'translate(0px, 0px) scale(1)' },
          '33%': { transform: 'translate(30px, -50px) scale(1.1)' },
          '66%': { transform: 'translate(-20px, 20px) scale(0.9)' },
          '100%': { transform: 'translate(0px, 0px) scale(1)' },
        },
        float: {
          '0%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-20px)' },
          '100%': { transform: 'translateY(0px)' },
        },
        'spin-reverse': {
            '0%': { transform: 'rotate(0deg)' },
            '100%': { transform: 'rotate(-360deg)' },
        },
        scan: {
            '0%': { top: '-10%', opacity: 0 },
            '5%': { opacity: 1 },
            '25%': { top: '110%', opacity: 0 }, /* Scans across in ~3-4 seconds */
            '100%': { top: '110%', opacity: 0 }, /* Waits hidden for rest of 15s */
        },
        shine: {
            '0%': { left: '-100%', opacity: 0 },
            '20%': { left: '100%', opacity: 0.5 },
            '100%': { left: '100%', opacity: 0 },
        },
      },
    },
  },
  plugins: [],
}
