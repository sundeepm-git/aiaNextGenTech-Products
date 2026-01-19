# ai-userInterface / ui-design

This project is a Next.js web application with custom branding, AI-themed animations, and a modern sidebar navigation. It uses Tailwind CSS for styling and supports persistent logo/header uploads.

## Features
- Next.js app with file-based routing
- Tailwind CSS with custom keyframes/animations
- Dynamic branding (logo, header, company name)
- AI-inspired animated header and logo
- Sidebar with expandable/collapsible menus
- Persistent branding via localStorage and file upload
- Cross-browser compatibility (Chrome, Firefox, Edge)

## Getting Started

### Prerequisites
- Node.js (v16 or higher recommended)
- npm (comes with Node.js)
- Git

### Installation
1. **Clone the repository:**
    ```
    git clone <repository-url>
    cd ai-userInterface/ui-design
    ```
2. **Install dependencies:**
    ```
    npm install
    ```

### Running the App
- **Development mode:**
   ```
   npm run dev
   ```
   Open [http://localhost:3000](http://localhost:3000) in your browser.

- **Production build:**
   ```
   npm run build
   npm start
   ```

### Project Structure
- `app/` - Next.js app directory (pages, API routes, branding, etc.)
- `components/` - Reusable React components (Navbar, Sidebar, Cards, Charts)
- `context/` - React context for global state (branding, etc.)
- `public/img/` - Static images (logo, header)
- `styles/` - Global CSS (Tailwind, custom styles)
- `prompts/` - Prompt YAML files for AI workflows

### Key Dependencies
- next
- react
- react-dom
- tailwindcss
- postcss
- autoprefixer

See `package.json` for the full list.

### Useful Commands
- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm start` - Start production server
- `npm install <package>` - Add a new dependency
- `npm uninstall <package>` - Remove a dependency

### Troubleshooting
- Delete `node_modules` and `package-lock.json` if you have install issues, then run `npm install` again.
- Ensure your Node.js version matches the required version.

---

For detailed Git and npm command usage, see [GIT_NPM_COMMANDS.md](GIT_NPM_COMMANDS.md).
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
