# agent-3-AztfExportPS-Tool

## Purpose
Exports Azure resources to Terraform HCL and local tfstate using aztfexport.

## Details
- Receives assessment output and resource context
- Runs aztfexport PowerShell script/tool
- Produces Terraform HCL and tfstate files for downstream refactoring

## Example Output
```
/exports/terraform/main.tf
/exports/terraform/terraform.tfstate
```
