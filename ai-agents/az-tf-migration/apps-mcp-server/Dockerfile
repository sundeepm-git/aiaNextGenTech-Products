# =============================================
# MCP Server Dockerfile (Node.js)
# =============================================
FROM mcr.microsoft.com/azure-cli:latest

# Set working directory
WORKDIR /app

# 1. Install System Dependencies
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
COPY python/requirements.txt ./python/requirements.txt
RUN wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py && \
    python3 /tmp/get-pip.py && \
    python3 -m pip install --no-cache-dir -r ./python/requirements.txt && \
    rm /tmp/get-pip.py

# 4. Install Node.js (Manual Install)
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
RUN npm install --omit=dev
COPY index.js ./
COPY *.js ./
COPY tools/ ./tools/
COPY python/ ./python/
COPY ps/ ./ps/

# 7. Set Permissions and Workspace
RUN chmod +x ./python/Export-Container-AzToTerraform.py && \
    mkdir -p /app/azure-export && \
    chmod -R 777 /app/azure-export

# 8. Environment Setup
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
ENV PORT=3000
ENV RUNNING_IN_CONTAINER=true
ENV PYTHONUNBUFFERED=1
ENV AZTFEXPORT_PLAIN_UI=true

EXPOSE 3000

CMD ["node", "index.js"]