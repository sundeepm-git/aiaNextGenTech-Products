# Use Azure CLI as base image (Built on Azure Linux)
FROM mcr.microsoft.com/azure-cli:latest

# Set working directory
WORKDIR /app

# 1. Install System Dependencies 
# We clean the cache first to avoid the HTTP/2 framing errors you encountered
RUN tdnf clean all && tdnf makecache && tdnf install -y \
    wget \
    unzip \
    git \
    tar \
    gzip \
    ca-certificates \
    && tdnf clean all

# 2. Install PowerShell (Manual Install for Reliability)
RUN wget https://github.com/PowerShell/PowerShell/releases/download/v7.4.1/powershell-7.4.1-linux-x64.tar.gz -O /tmp/powershell.tar.gz && \
    mkdir -p /opt/microsoft/powershell/7.4.1 && \
    tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7.4.1 && \
    ln -s /opt/microsoft/powershell/7.4.1/pwsh /usr/bin/pwsh && \
    rm /tmp/powershell.tar.gz

# 3. Install Pip and Python Dependencies
# We use get-pip.py because tdnf is failing to sync the pip package
COPY python/requirements.txt ./python/requirements.txt
RUN wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py && \
    python3 /tmp/get-pip.py && \
    python3 -m pip install --no-cache-dir -r ./python/requirements.txt && \
    rm /tmp/get-pip.py

# 4. Install Node.js (Manual Install)
# This bypasses the 'nodejs package not found' error in tdnf
RUN wget https://nodejs.org/dist/v18.19.0/node-v18.19.0-linux-x64.tar.xz -O node.tar.xz && \
    tar -xf node.tar.xz && \
    mv node-v18.19.0-linux-x64 /usr/local/node && \
    ln -s /usr/local/node/bin/node /usr/bin/node && \
    ln -s /usr/local/node/bin/npm /usr/bin/npm && \
    rm node.tar.xz

# 5. Install Terraform & aztfexport
RUN wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip -O terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/terraform && \
    rm terraform.zip && \
    wget https://github.com/Azure/aztfexport/releases/download/v0.15.0/aztfexport_v0.15.0_linux_amd64.zip -O aztfexport.zip && \
    unzip aztfexport.zip -d /usr/local/bin/ && rm aztfexport.zip


# 6. Copy Application Files
COPY package*.json ./
# Now that npm is linked, this will run correctly
RUN npm install --omit=dev

# IMPORTANT: Copying all JS files to avoid the ERR_MODULE_NOT_FOUND error
COPY index.js ./
# If you have an aztfexport.js file in your root, this line ensures it is included:
COPY *.js ./

COPY tools/ ./tools/
COPY python/ ./python/
COPY ps/ ./ps/

# Copy .env file for environment variables (must be present in build context root)
#COPY .env* ./
#RUN test -f .env || (echo '.env file missing!' && exit 1)

# 7. Set Permissions and Workspace
RUN chmod +x ./python/Export-Container-AzToTerraform.py && \
    mkdir -p /app/azure-export && \
    chmod -R 777 /app/azure-export

# 8. Environment Setup
# 8. Environment Setup
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
ENV PORT=3000
ENV RUNNING_IN_CONTAINER=true
ENV PYTHONUNBUFFERED=1
ENV AZTFEXPORT_PLAIN_UI=true

EXPOSE 3000

# 9. Debug Node.js crypto module before starting server
RUN node -e "console.log('[DEBUG] Node.js crypto module:', typeof require('crypto').createHash === 'function')"
CMD ["node", "index.js"]