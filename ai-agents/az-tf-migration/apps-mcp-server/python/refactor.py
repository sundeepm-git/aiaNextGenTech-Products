# =============================================================
# Name: sundeep k maheshwari
# Date: 2026-01-21
# Description: Main entrypoint for the Terraform refactoring engine. Orchestrates loading, refactoring, writing, backup, and validation of Terraform code as per enterprise standards.
# =============================================================

#!/usr/bin/env python3
"""
Auto-generated via Enterprise Terraform Refactoring Engine
Main entrypoint for refactoring Azure-exported Terraform.
"""


import argparse
from pathlib import Path
from tf_refactor_variable import TerraformRefactorEngine
import sys
import os
import subprocess
try:
    import tkinter as tk
    from tkinter import messagebox
except ImportError:
    tk = None


def main():
    import argparse
    import subprocess
    import sys
    from pathlib import Path
    
    # Set UTF-8 encoding for stdout to handle Unicode characters
    if sys.stdout.encoding != 'utf-8':
        try:
            import io
            sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
            sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
        except:
            pass  # Fallback if reconfiguration fails

    parser = argparse.ArgumentParser(description="Terraform Refactoring Engine")
    parser.add_argument("subscription_id", help="Azure subscription ID")
    parser.add_argument("resource_group_name", help="Azure resource group name")
    parser.add_argument("--dry-run", action="store_true", help="Simulate only")
    parser.add_argument("--verbose", action="store_true", help="Verbose logging")

    args = parser.parse_args()

    # Display warning before running the refactor engine (auto-proceed enabled)
    print("\n[WARNING] Refactor Engine Execution Notice")
    print("Proceeding with refactor engine for the following scope:\n")
    print(f"Subscription ID: {args.subscription_id}")
    print(f"Resource Group: {args.resource_group_name}\n")
    print("[NOTE] This operation will overwrite any existing refactored files.\n")

    engine = TerraformRefactorEngine(
        subscription_id=args.subscription_id,
        resource_group_name=args.resource_group_name,
        dry_run=args.dry_run,
        verbose=args.verbose
    )
    engine.run()

    # tfvars generation is now handled inside engine.run() before uploading to blob storage

if __name__ == "__main__":
    main()
