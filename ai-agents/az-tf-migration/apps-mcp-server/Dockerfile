# Use Azure CLI as base image (Pre-installed: Python 3, Azure CLI)
FROM mcr.microsoft.com/azure-cli:latest

# Set working directory
WORKDIR /app

# 1. Install System Dependencies (Git is required for GitHub Push)
RUN tdnf install -y \
    wget \
    unzip \
    git \
    tar \
    gzip \
    ca-certificates \
    && tdnf clean all

# 2. Install Python Dependencies
# Required for the 'load_dotenv' logic in your Python script
RUN tdnf install -y python3-pip && tdnf clean all
RUN python3 -m pip install python-dotenv

# 3. Install Node.js (Required for MCP Server)
RUN tdnf install -y nodejs npm && \
    node -v && npm -v

# 4. Install Terraform (Required for aztfexport)
RUN wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip -O terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/ && \
    chmod +x /usr/local/bin/terraform && \
    rm terraform.zip

# 5. Install aztfexport (Azure Terrafy)
RUN wget https://github.com/Azure/aztfexport/releases/download/v0.15.0/aztfexport_v0.15.0_linux_amd64.zip -O aztfexport.zip && \
    unzip aztfexport.zip && \
    mv aztfexport /usr/local/bin/ && \
    chmod +x /usr/local/bin/aztfexport && \
    rm aztfexport.zip

# 6. Copy Application Files
COPY package*.json ./
RUN npm install --omit=dev

COPY index.js .
# Note: We do NOT copy .env into the image for security. 
# Pass secrets as Container Environment Variables in Azure.
COPY tools/ ./tools/
COPY python/ ./python/

# 7. Set Permissions
RUN chmod +x ./python/Export-Container-AzToTerraform.py && \
    mkdir -p /app/azure-export && \
    chmod -R 777 /app/azure-export


# 8. Environment Setup
ENV PORT=3000
ENV RUNNING_IN_CONTAINER=true
ENV PYTHONUNBUFFERED=1
ENV AZTFEXPORT_PLAIN_UI=true

EXPOSE 3000

# 9. Start Server
CMD ["node", "index.js"]