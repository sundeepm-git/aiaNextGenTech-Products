# Microsoft Foundry – Naming Standards for Agentic Workflows & Agents

## Version
1.0

## Author
Sundeep Kumar Maheshwari

## Date
19 January 2026

## Purpose
This document defines a standardized naming convention for agents, workflows, nodes, and variables within Microsoft Foundry.

## Background
Microsoft Foundry workflows orchestrate multiple agents, tools, and logic blocks in visual or YAML form.

## 1. Agent Naming Standard
**Format:**
```
<Domain><Role>Agent-v<Version>
```
**Examples:**
- FinanceReconciliationAgent-v1
- HRLeaveApprovalAgent-v2
- CustomerSupportSummarizerAgent-v1

## 2. Workflow Naming Standard
**Format:**
```
<Domain>-<BusinessProcess>-Workflow
```
**Examples:**
- Finance-InvoiceProcessing-Workflow
- ITSM-TicketTriage-Workflow

## 3. Node Naming Convention
**Format:**
```
<StepNumber>_<ActionDescription>
```
**Examples:**
- 01_CollectInput
- 02_ValidateData
- 03_InvokeStudentAgent

## 4. Variable Naming Standard
**Format:**
```
Local.<Name>
System.<Name>
```
**Examples:**
- Local.CustomerAddress
- Local.ValidationStatus
- Local.ApprovalDecision

## 5. Tool Naming Convention
**Format:**
```
<Domain><Function>Tool
```
**Examples:**
- FinanceLookupTool
- DocumentExtractionTool

## 6. Versioning Standards
**Agents:**
```
AgentName-v1
AgentName-v1.1
```
**Workflows:**
```
WorkflowName-v1
```

## 7. Example Structure
| Component | Name |
|----------|------|
| Workflow | Banking-AddressUpdate-Workflow |
| Agent 1 | CustomerDataRetrievalAgent-v1 |
| Agent 2 | AddressValidationAgent-v1 |
| Node 1 | 01_GetCustomerRequest |
| Node 2 | 02_InvokeDataRetrievalAgent |
| Variable | Local.UpdatedAddress |

