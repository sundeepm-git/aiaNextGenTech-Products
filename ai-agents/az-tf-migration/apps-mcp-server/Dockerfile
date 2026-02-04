# 1. Base image with Node
FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bullseye

# 2. Install PowerShell 7
RUN apt-get update && \
    apt-get install -y wget apt-transport-https software-properties-common && \
    wget -q https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y powershell && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    pwsh -v

# 2.5. Install Python 3 and pip for refactor engine
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    python3 --version && \
    pip3 --version

# 3. Install Azure PowerShell Modules
RUN pwsh -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted" && \
    pwsh -Command "Install-Module -Name Az.Accounts -Force -AllowClobber -Scope AllUsers" && \
    pwsh -Command "Install-Module -Name Az.Resources -Force -AllowClobber -Scope AllUsers" && \
    pwsh -Command "Get-Module -ListAvailable Az.*"

# 4. Create app directory
WORKDIR /app

# 5. Copy package files and install deps
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts && \
    npm cache clean --force

# 6. Copy the rest of the app
COPY . .

# 6.5. Install Python dependencies for refactor engine
RUN if [ -f python/requirements.txt ]; then \
    pip3 install --no-cache-dir -r python/requirements.txt; \
    fi

# Ensure ps folder is at /app/ps, not /app/ps/ps
RUN if [ -d "/app/ps/ps" ]; then mv /app/ps/ps/* /app/ps/ && rmdir /app/ps/ps; fi

# 7. Create report directory for local storage fallback
RUN mkdir -p /app/ps/report /app/report && \
    chmod 755 /app/ps/report /app/report

# 8. Expose the port your Express app uses
EXPOSE 8080

# 9. Azure Container Apps will inject PORT, so set default
ENV PORT=8080 \
    NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=1536"

# 10. Health check (updated for v2.0 async job API)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (r) => {let d='';r.on('data',c=>d+=c);r.on('end',()=>{try{const j=JSON.parse(d);process.exit(j.status==='healthy'?0:1)}catch(e){process.exit(1)}})})"

# 11. Start the MCP server
CMD ["node", "index.js"]