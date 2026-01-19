# Azure to Terraform Migration Product

## Overview

The **Azure to Terraform Migrate** product is an enterprise-grade solution that automates the conversion of existing Azure infrastructure into fully-functional Terraform code. This tool streamlines the Infrastructure as Code (IaC) adoption process by discovering Azure resources and generating production-ready Terraform configurations.

## Key Features

### 1. **Azure Connection**
- Secure authentication using Azure AD
- Support for multiple Azure subscriptions
- Connection validation and health checks
- Read-only permissions for safe resource scanning

### 2. **Resource Discovery**
- Automatic discovery of Azure resources across multiple resource groups
- Support for 50+ Azure resource types including:
  - Virtual Machines
  - Storage Accounts
  - Virtual Networks
  - Network Security Groups
  - SQL Servers
  - Web Apps
  - Key Vaults
  - Container Registries
  - And many more...

### 3. **Multi-Resource Group Support**
- Migrate one or multiple resource groups simultaneously
- Dynamic resource group input fields
- Flexible resource group management (add/remove)

### 4. **Selective Migration**
- Choose specific resources to migrate
- Visual resource selection interface
- Resource type filtering
- Location-based grouping

### 5. **Terraform Code Generation**
- Clean, production-ready HCL 2.0 code
- Best practices compliance
- Proper resource dependencies
- Terraform version compatibility (>= 1.0)
- Azure Provider version (~> 3.0)

### 6. **Download & Deploy**
- Instant download of generated Terraform files
- Complete project structure
- State file generation
- Output variables for easy reference

## User Interface

### Migration Workflow

The product follows a 4-step workflow:

1. **Connect** - Authenticate with Azure subscription
2. **Discover** - Scan and identify Azure resources
3. **Generate** - Convert resources to Terraform code
4. **Download** - Export Terraform configuration files

### Key UI Components

#### Azure Connection Panel
- Subscription ID input
- Dynamic resource group inputs with add/remove functionality
- Connection status indicator
- Disconnect option

#### Resource Discovery Dashboard
- Grid view of discovered resources
- Resource type icons and metadata
- Click-to-select functionality
- Statistics overview (total resources, types, locations)

#### Code Preview
- Syntax-highlighted Terraform code
- Line count and file statistics
- Version information
- Download button

## API Endpoints

### 1. Azure Connection
**POST** `/api/cloud-automation/azure-terraform/connect`

**Request Body:**
```json
{
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "resourceGroups": ["rg-prod-001", "rg-dev-002"]
}
```

**Response:**
```json
{
  "success": true,
  "message": "Successfully connected to Azure",
  "subscriptionId": "...",
  "resourceGroups": ["..."],
  "timestamp": "2026-01-17T..."
}
```

### 2. Resource Discovery
**POST** `/api/cloud-automation/azure-terraform/discover`

**Request Body:**
```json
{
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "resourceGroups": ["rg-prod-001"]
}
```

**Response:**
```json
{
  "success": true,
  "resources": [
    {
      "id": "/subscriptions/.../resourceGroups/.../providers/...",
      "name": "vm-prod-001",
      "type": "Microsoft.Compute/virtualMachines",
      "resourceGroup": "rg-prod-001",
      "location": "eastus",
      "tags": {...}
    }
  ],
  "statistics": {
    "totalResources": 15,
    "resourceTypes": 8,
    "resourceGroups": 1,
    "locations": 2
  }
}
```

### 3. Terraform Generation
**POST** `/api/cloud-automation/azure-terraform/generate`

**Request Body:**
```json
{
  "subscriptionId": "...",
  "resourceGroups": ["..."],
  "resourceIds": ["/subscriptions/..."]
}
```

**Response:**
```json
{
  "success": true,
  "code": "# Terraform configuration...",
  "filesGenerated": 5,
  "linesOfCode": 250,
  "terraformVersion": "~> 1.0",
  "providerVersion": "azurerm ~> 3.0",
  "resourcesMigrated": 15
}
```

## Technical Architecture

### Frontend Stack
- **Framework**: Next.js 14 (App Router)
- **Styling**: Tailwind CSS with custom gradients
- **Icons**: Heroicons
- **State Management**: React Context (AppContext)

### Backend Integration (TODO)

The current implementation uses mock APIs. For production deployment, integrate with:

1. **Azure SDK for JavaScript**
   ```bash
   npm install @azure/identity @azure/arm-resources
   ```

2. **Authentication**
   - Use `DefaultAzureCredential` for authentication
   - Implement role-based access control (RBAC)
   - Require read-only permissions

3. **Resource Discovery**
   - Use `ResourceManagementClient` to list resources
   - Implement pagination for large resource sets
   - Cache discovered resources

4. **Terraform Generation**
   - Use Azure2Terraform or Terraformer tools
   - Implement resource dependency graph analysis
   - Generate modular Terraform code structure

## Installation & Setup

### Prerequisites
- Node.js 18+ and npm
- Azure subscription with appropriate permissions
- Azure CLI (for local development)

### Local Development

1. Navigate to the project directory:
   ```bash
   cd ui-design
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Run the development server:
   ```bash
   npm run dev
   ```

4. Open http://localhost:3000/cloud-automation/azure-terraform-migrate

### Environment Variables

Create a `.env.local` file:

```env
# Azure Configuration
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_TENANT_ID=your-tenant-id
AZURE_CLIENT_ID=your-client-id
AZURE_CLIENT_SECRET=your-client-secret
```

## Usage Guide

### Step 1: Connect to Azure

1. Enter your Azure Subscription ID
2. Add one or more resource groups to scan
3. Click "Connect to Azure"
4. Wait for connection validation

### Step 2: Discover Resources

1. Click "Discover Resources" after successful connection
2. Wait for the discovery process to complete
3. Review the list of discovered resources
4. Select resources you want to migrate (all selected by default)

### Step 3: Generate Terraform Code

1. Click "Generate Terraform Code"
2. Wait for code generation to complete
3. Review the generated Terraform configuration in the preview

### Step 4: Download & Deploy

1. Click "Download Terraform Files"
2. Extract the downloaded files
3. Initialize Terraform: `terraform init`
4. Review the plan: `terraform plan`
5. Apply if satisfied: `terraform apply`

## Security Considerations

- **Authentication**: Uses Azure AD with read-only permissions
- **Data Privacy**: No resource data is stored on the server
- **Secure Transport**: All API calls use HTTPS
- **Input Validation**: Subscription IDs and resource groups are validated
- **RBAC**: Requires appropriate Azure RBAC permissions

## Supported Azure Resource Types

Currently supports 50+ Azure resource types including:

- Compute (VMs, VM Scale Sets, Container Instances)
- Storage (Storage Accounts, Disks, File Shares)
- Networking (VNets, Subnets, NSGs, Load Balancers)
- Databases (SQL Servers, Cosmos DB, PostgreSQL, MySQL)
- Web Services (App Services, Function Apps, API Management)
- Security (Key Vaults, Managed Identities)
- Containers (AKS, Container Registry)
- AI/ML (Cognitive Services, Machine Learning)

## Best Practices

1. **Resource Selection**: Only select resources you need to migrate
2. **Review Generated Code**: Always review Terraform code before applying
3. **State Management**: Use remote state storage (Azure Storage, Terraform Cloud)
4. **Version Control**: Commit generated Terraform code to Git
5. **Testing**: Test in a development environment before production
6. **Backup**: Create backups of your Azure resources before migration

## Troubleshooting

### Connection Issues
- Verify Azure subscription ID is correct
- Ensure Azure CLI is authenticated: `az login`
- Check network connectivity to Azure
- Verify RBAC permissions

### Discovery Issues
- Ensure resource groups exist in the subscription
- Check for resources with unsupported types
- Verify read permissions on resource groups

### Generation Issues
- Review selected resources for compatibility
- Check for circular dependencies
- Ensure resource names are valid Terraform identifiers

## Future Enhancements

- [ ] Support for Azure Blueprints
- [ ] Automated state file import
- [ ] Multi-subscription migration
- [ ] Terraform module generation
- [ ] CI/CD pipeline integration
- [ ] Cost estimation before migration
- [ ] Resource tagging recommendations
- [ ] Compliance checking

## Support & Documentation

- **Product Route**: `/cloud-automation/azure-terraform-migrate`
- **Category**: Cloud Automation
- **Gradient Theme**: Blue to Cyan
- **Product ID**: `ca-terraform`

## Contributing

When contributing to this product:

1. Follow Next.js App Router conventions
2. Use Tailwind CSS for styling
3. Maintain consistent gradient theme (blue-cyan)
4. Add comprehensive error handling
5. Include inline TODO comments for backend integration
6. Update this README with new features

## License

Enterprise product - Internal use only

---

**Last Updated**: January 17, 2026  
**Version**: 1.0.0  
**Status**: Active Development
