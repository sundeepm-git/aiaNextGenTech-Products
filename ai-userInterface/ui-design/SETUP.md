# Quick Start Guide

## Prerequisites

- Node.js 18.x or higher
- npm or yarn package manager

## Installation Steps

### 1. Navigate to the project directory

```bash
cd ui-design
```

### 2. Install dependencies

```bash
npm install
```

Or with yarn:

```bash
yarn install
```

### 3. Run the development server

```bash
npm run dev
```

Or with yarn:

```bash
yarn dev
```

### 4. Open your browser

Navigate to [http://localhost:3000](http://localhost:3000)

## Project Structure

```
ui-design/
├── app/                        # Next.js App Router
│   ├── layout.js              # Root layout with providers
│   ├── page.js                # Dashboard (home page)
│   ├── cybersecurity/         
│   │   └── page.js            # Cybersecurity Agent page
│   ├── cloud-automation/      
│   │   └── page.js            # Cloud Automation Agent page
│   ├── workflow-builder/      
│   │   └── page.js            # Workflow Builder page
│   ├── settings/              
│   │   └── page.js            # Settings page
│   └── branding/              
│       └── page.js            # Theme & Branding page
├── components/                 # Reusable components
│   ├── Layout/
│   │   ├── Sidebar.js         # Navigation sidebar
│   │   ├── Navbar.js          # Top navigation bar
│   │   └── index.js           # Layout wrapper
│   ├── Cards/
│   │   ├── ProductCard.js     # Product display card
│   │   └── CategoryCard.js    # Category container card
│   └── Charts/
│       └── index.js           # Chart.js wrappers
├── context/
│   └── AppContext.js          # Global state management
├── pages/
│   └── _app.js                # Pages Router compatibility
├── styles/
│   └── globals.css            # Global styles & Tailwind
├── public/                     # Static assets
├── package.json               # Dependencies
├── next.config.js             # Next.js configuration
├── tailwind.config.js         # Tailwind CSS configuration
└── postcss.config.js          # PostCSS configuration
```

## Key Features

### 1. Dynamic Visibility Controls
- Go to **Settings** page to toggle category and product visibility
- Changes are saved automatically to local storage
- UI updates instantly when toggles are changed

### 2. Theme Switching
- Go to **Theme & Branding** page
- Switch between light and dark themes
- Theme preference is saved automatically

### 3. Custom Branding
- Go to **Theme & Branding** page
- Change company name and tagline
- Select from preset logo styles
- Preview changes in real-time

### 4. Category Pages
- **Cybersecurity Agent**: Threat detection, security alerts, vulnerability scanning
- **Cloud Automation Agent**: Resource management, migration tracking, cost optimization
- **Workflow Builder**: Visual workflow designer, execution logs, agent orchestration

### 5. Dashboard Overview
- Real-time metrics and statistics
- Charts for agent activity and status distribution
- Aggregated view of all visible categories and products

## Technology Stack

All components are 100% open-source:

- **Next.js 14**: React framework with App Router
- **React 18**: UI library
- **Tailwind CSS**: Utility-first CSS framework
- **Chart.js**: Open-source charting library
- **Heroicons**: Open-source icon library
- **No paid or proprietary components**

## Accessibility

The application follows WCAG 2.1 guidelines:

- Semantic HTML structure
- ARIA labels and roles
- Keyboard navigation support
- Focus indicators
- Screen reader compatible
- High contrast themes

## Future Integration Points

The codebase includes comments marking integration points for:

- GenAI backend services
- Real-time data streaming
- Agentic orchestration workflows
- Authentication and authorization
- Multi-tenant architecture
- File upload functionality

## Development Commands

```bash
# Start development server
npm run dev

# Build for production
npm run build

# Start production server
npm start

# Run linting
npm run lint
```

## Browser Support

- Chrome (latest)
- Firefox (latest)
- Safari (latest)
- Edge (latest)

## Troubleshooting

### Port already in use
If port 3000 is already in use, you can specify a different port:

```bash
npm run dev -- -p 3001
```

### Dependencies installation issues
Try clearing the cache and reinstalling:

```bash
rm -rf node_modules package-lock.json
npm install
```

### Build errors
Make sure you're using Node.js 18.x or higher:

```bash
node --version
```

## Next Steps

1. Install dependencies: `npm install`
2. Start the development server: `npm run dev`
3. Explore the dashboard at `http://localhost:3000`
4. Customize branding in **Theme & Branding** page
5. Configure visibility in **Settings** page
6. Review code comments for backend integration points

## Support

This is a demonstration dashboard built with 100% open-source tools. Customize it for your specific needs and integrate it with your GenAI backend services.
