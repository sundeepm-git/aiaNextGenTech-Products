# =============================================================
# Name: sundeep k maheshwari
# Date: 2026-01-21
# Description: Module for writing refactored Terraform code blocks to the correct output files, ensuring structure and standards compliance.
# =============================================================

"""
Auto-generated via Enterprise Terraform Refactoring Engine
Handles writing output TF files.
"""

from pathlib import Path
import subprocess


class TerraformWriters:
    def __init__(self, output_dir, verbose=False):
        self.output_dir = Path(output_dir)
        self.verbose = verbose

        self.data_sources = []
        self.main_tf = []
        self.providers_tf = []
        self.locals_tf = []
        self.variables_tf = []
        self.outputs_tf = []
        self.tfvars = []

    def log(self, msg):
        if self.verbose:
            print(f"[WRITER] {msg}")

    # -------------------------
    def write_all(self):
        import re
        self.log(f"Writing output to {self.output_dir}")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        files = {
            # Never overwrite data-sources.tf, main.tf, or terraform.tfstate if they already exist (copied from export)
            "data-sources.tf": self.data_sources,
            "main.tf": self.main_tf if self.main_tf else None,
            "providers.tf": self.providers_tf,
            "locals.tf": self.locals_tf,
            "variables.tf": self.variables_tf,
            "outputs.tf": self.outputs_tf,
            "terraform.tfvars": self.tfvars,
        }
        errors = {}
        for name, content in files.items():
            if name in ["main.tf", "terraform.tfstate", "data-sources.tf"]:
                # Never overwrite these files if they already exist
                path = self.output_dir / name
                if path.exists():
                    self.log(f"Skipped writing {name} (already exists)")
                    continue
            if content is None:
                continue
            path = self.output_dir / name
            try:
                fixed_content = []
                for block in content:
                    # Remove stray parenthesis on its own line
                    block = re.sub(r'^\s*\)\s*$', '', block, flags=re.MULTILINE)
                    # Fix double double-quotes in string defaults
                    block = re.sub(r'""([^"]+)""', r'"\1"', block)
                    # Ensure each block ends with a newline
                    if not block.endswith('\n'):
                        block += '\n'
                    fixed_content.append(block)
                with open(path, "w") as f:
                    f.write("# Auto-generated via Enterprise Terraform Refactoring Engine\n\n")
                    f.write("\n\n".join(fixed_content))
                self.log(f"Wrote {name}")
            except Exception as e:
                self.log(f"Failed to write {name}: {e}")
                errors[name] = str(e)
        if errors:
            raise RuntimeError(f"File write errors: {errors}")

    # -------------------------

    def run_terraform_fmt(self):
        self.log("Running terraform fmt...")
        try:
            subprocess.run(["terraform", "fmt", str(self.output_dir)], check=False)
        except Exception as e:
            self.log(f"terraform fmt failed but not fatal: {e}")

