# Build Instructions:
# docker build --no-cache -t aztf-mcp-server .

# 1. Base image with Node
FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bullseye

# 2. Install System Dependencies (Consolidated for reliability)
RUN apt-get update && \
    apt-get install -y wget apt-transport-https software-properties-common unzip curl gnupg lsb-release jq && \
    # PowerShell 7
    wget -q https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y powershell && \
    # Terraform
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install -y terraform && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2.2 Install aztfexport (Dynamic Link Fetcher to avoid 404s)
# This queries GitHub API for the latest release URL matching 'linux_amd64.zip'
RUN export DOWNLOAD_URL=$(curl -s https://api.github.com/repos/Azure/aztfexport/releases/latest | grep "browser_download_url.*linux_amd64.zip" | cut -d '"' -f 4) && \
    echo "Downloading from: $DOWNLOAD_URL" && \
    curl -fL "$DOWNLOAD_URL" -o aztfexport.zip && \
    unzip aztfexport.zip && \
    # Use find to locate the binary inside the zip (handles nested or versioned filenames)
    find . -name "aztfexport*" -type f -exec chmod +x {} + && \
    find . -name "aztfexport*" -type f -exec mv {} /usr/local/bin/aztfexport \; && \
    rm -f aztfexport.zip

# 2.5. Install Python 3 and pip for refactor engine
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2.6. Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && az --version

# 3. Install Azure PowerShell Modules
RUN pwsh -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted" && \
    pwsh -Command "Install-Module -Name Az.Accounts -Force -AllowClobber -Scope AllUsers" && \
    pwsh -Command "Install-Module -Name Az.Resources -Force -AllowClobber -Scope AllUsers"

# 4. Create app directory
WORKDIR /app

# 5. Copy package files and install deps
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts && \
    npm cache clean --force

# 6. Copy the rest of the app
COPY . .

# 6.1. Verify critical files and Tools
RUN echo "=== Verifying Binaries ===" && \
    terraform -version && \
    aztfexport --version && \
    echo "=== Verifying File Structure ===" && \
    ls -la /app/ps/

# 6.5. Install Python dependencies
RUN if [ -f python/requirements.txt ]; then \
    pip3 install --no-cache-dir -r python/requirements.txt; \
    fi

# Ensure ps folder structure is flat
RUN if [ -d "/app/ps/ps" ]; then mv /app/ps/ps/* /app/ps/ && rmdir /app/ps/ps; fi

# 7. Create report and temp directories
RUN mkdir -p /app/ps/report /app/report /tmp/aztf-export && \
    chmod 777 /tmp/aztf-export /app/report /app/ps/report

# 8. Expose port
EXPOSE 8080

# 9. Environment Variables
ENV PORT=8080 \
    NODE_ENV=production \
    TEMP=/tmp \
    TMP=/tmp \
    AZURE_CLIENT_ID="" \
    AZURE_CLIENT_SECRET="" \
    AZURE_TENANT_ID="" \
    AZURE_SUBSCRIPTION_ID="" \
    AZURE_STORAGE_ACCOUNT="" \
    AZURE_STORAGE_CONTAINER=""

# 10. Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (r) => { r.statusCode === 200 ? process.exit(0) : process.exit(1) })"

# 11. Start server
CMD ["node", "index.js"]