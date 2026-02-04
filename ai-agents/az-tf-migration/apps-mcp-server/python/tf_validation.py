# =============================================================
# Name: sundeep k maheshwari
# Date: 2026-01-21
# Description: Module for validating refactored Terraform code using terraform CLI (fmt, validate, plan) and reporting drift or errors.
# =============================================================

"""
Auto-generated via Enterprise Terraform Refactoring Engine
Handles terraform init/validate/plan and drift reporting.
"""

from pathlib import Path
import subprocess


class TerraformValidator:
    def __init__(self, output_dir, verbose=False):
        self.output_dir = Path(output_dir)
        self.verbose = verbose

    def log(self, msg):
        if self.verbose:
            print(f"[VALIDATION] {msg}")

    def run_plan(self):
        errors = {}
        try:
            self.log("Running terraform init...")
            result_init = subprocess.run(["terraform", "init"], cwd=self.output_dir, check=False)
            if result_init.returncode != 0:
                errors['init'] = f"terraform init failed with code {result_init.returncode}"
        except Exception as e:
            errors['init'] = str(e)

        try:
            self.log("Running terraform validate...")
            result_validate = subprocess.run(["terraform", "validate"], cwd=self.output_dir, check=False)
            if result_validate.returncode != 0:
                errors['validate'] = f"terraform validate failed with code {result_validate.returncode}"
        except Exception as e:
            errors['validate'] = str(e)

        try:
            self.log("Running terraform plan...")
            result_plan = subprocess.run(
                ["terraform", "plan", "-detailed-exitcode"],
                cwd=self.output_dir,
                check=False
            )
            if result_plan.returncode == 2:
                self.log("DRIFT DETECTED – generating DRIFT_REPORT.md")
                with open(self.output_dir / "DRIFT_REPORT.md", "w") as f:
                    f.write("# Drift Detected\nTerraform reported differences.\n")
            elif result_plan.returncode not in (0, 2):
                errors['plan'] = f"terraform plan failed with code {result_plan.returncode}"
        except Exception as e:
            errors['plan'] = str(e)

        if errors:
            raise RuntimeError(f"Terraform validation errors: {errors}")
