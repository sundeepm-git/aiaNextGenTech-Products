# GenAI Agent Dashboard

A modern, responsive Next.js application for GenAI and Agentic AI product dashboard.

## Features

- 🎨 Dynamic theme switching (light/dark/custom)
- 🔒 Cybersecurity Agent dashboard
- ☁️ Cloud Automation Agent monitoring
- 🔄 Workflow Builder with drag-and-drop interface
- 📊 Real-time charts and visualizations
- 🎯 Dynamic visibility controls for categories and products
- 🏷️ Customizable branding (logo, header, theme)
- 📱 Fully responsive design
- ♿ Accessibility compliant (ARIA, keyboard navigation)

## Tech Stack

- **Framework**: Next.js 14 (App Router)
- **Styling**: Tailwind CSS
- **Icons**: Heroicons
- **Charts**: Chart.js & react-chartjs-2
- **100% Open Source** - No paid or proprietary components

## Getting Started

1. Install dependencies:
   ```bash
   npm install
   ```

2. Run the development server:
   ```bash
   npm run dev
   ```

3. Open [http://localhost:3000](http://localhost:3000) in your browser.

## Project Structure

```
ui-design/
├── app/                    # Next.js App Router
│   ├── layout.js          # Root layout with AppProvider
│   ├── page.js            # Dashboard home
│   ├── cybersecurity/     # Cybersecurity Agent pages
│   ├── cloud-automation/  # Cloud Automation Agent pages
│   ├── workflow-builder/  # Workflow Builder pages
│   ├── settings/          # Settings page
│   └── branding/          # Theme & Branding page
├── components/            # Reusable components
│   ├── Layout/           # Sidebar, Navbar
│   ├── Cards/            # ProductCard, CategoryCard
│   └── Charts/           # Chart components
├── context/              # State management
│   └── AppContext.js     # Global app state
├── styles/               # Global styles
│   └── globals.css       # Tailwind directives
└── public/               # Static assets
```

## Customization

### Theme Switching
Navigate to **Theme & Branding** to switch between light, dark, and custom themes.

### Branding
- Upload custom logo or choose from predefined options
- Change header text dynamically
- Customize color schemes

### Visibility Controls
Use **Settings** page to toggle visibility of:
- Entire agent categories
- Individual products within each category

## Future Integration

The codebase includes comments to guide integration with:
- GenAI backend services
- Agentic orchestration workflows
- Real-time data streaming
- Authentication and authorization
- Multi-tenant architecture

## License

Open Source - MIT License
