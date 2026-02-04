# =============================================================
# Name: sundeep k maheshwari
# Date: 2026-01-21
# Description: Module for loading and parsing Terraform files (HCL) from the source directory, supporting both raw text and AST representations.
# =============================================================

"""
Auto-generated via Enterprise Terraform Refactoring Engine
Module: tf_loader.py
Responsible for loading and parsing TF files.
"""

from pathlib import Path
import hcl2
import json


class TerraformLoader:
    def __init__(self, source_root, verbose=False):
        self.source_root = Path(source_root)
        self.verbose = verbose
        self.parsed_files = {}
        self.failed_files = {}

    def log(self, msg):
        if self.verbose:
            print(f"[LOADER] {msg}")

    def load(self):
        tf_files = list(self.source_root.rglob("*.tf"))

        for tf in tf_files:
            try:
                # Read file and strip BOM if present
                with open(tf, "rb") as f:
                    raw = f.read()
                # Remove UTF-8 BOM if present
                if raw.startswith(b'\xef\xbb\xbf'):
                    raw = raw[3:]
                text = raw.decode('utf-8')
                # Write to a temp file for hcl2 parsing
                import tempfile
                with tempfile.NamedTemporaryFile('w+', delete=False, suffix='.tf') as tmpf:
                    tmpf.write(text)
                    tmpf.flush()
                    tmpf.seek(0)
                    data = hcl2.load(tmpf)
                self.parsed_files[str(tf)] = data
                self.log(f"Loaded {tf}")
            except Exception as e:
                self.failed_files[str(tf)] = str(e)
                self.log(f"Failed to parse {tf}: {e}")

        return self.parsed_files, self.failed_files
