# Running the Website: Git & NPM Commands

This guide provides essential commands for cloning, installing dependencies, and running the website locally using Git and npm.

## Prerequisites
- [Node.js](https://nodejs.org/) (v16 or higher recommended)
- [npm](https://www.npmjs.com/) (comes with Node.js)
- [Git](https://git-scm.com/)

## 1. Clone the Repository

```
git clone <repository-url>
cd ai-userInterface/ui-design
```

Replace `<repository-url>` with your repository's actual URL.

## 2. Install Dependencies

```
npm install
```

This will install all required dependencies listed in `package.json`.

## 3. Run the Development Server

```
npm run dev
```

The website will be available at [http://localhost:3000](http://localhost:3000).

## 4. Build for Production

```
npm run build
```

## 5. Start the Production Server

```
npm start
```

## 6. Additional Useful Commands

- **Check installed dependencies:**
  ```
  npm list --depth=0
  ```
- **Update dependencies:**
  ```
  npm update
  ```
- **Install a new package:**
  ```
  npm install <package-name>
  ```
- **Remove a package:**
  ```
  npm uninstall <package-name>
  ```

## 7. Troubleshooting
- If you encounter issues, try deleting `node_modules` and `package-lock.json`, then run `npm install` again.
- Ensure your Node.js version matches the required version in `package.json` (if specified).

---

For more details, see the main [README.md](README.md) in this directory.
