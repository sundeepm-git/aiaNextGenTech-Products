"""
tf_update_main.py

Reads terraform.tfvars and main.tf, replaces hardcoded values in main.tf with matching var.<variable_name> references based on tfvars keys.
If no matching value is found, leaves the value for manual handling.

Usage:
    python tf_update_main.py <main.tf path> <terraform.tfvars path> <output main.tf path>
"""
import re
import sys
import os
from pathlib import Path

def read_tfvars(tfvars_path):
    tfvars = {}
    with open(tfvars_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            name, value = line.split('=', 1)
            tfvars[name.strip()] = value.strip().strip('"')
    return tfvars

def update_main_tf(main_tf_path, tfvars, output_path):
    with open(main_tf_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    updated_lines = []
    for line in lines:
        match = re.match(r'\s*([a-zA-Z0-9_]+)\s*=\s*([^"]*"[^"]*"|true|false|\d+)', line)
        if match:
            key = match.group(1)
            value = match.group(2).strip('"')
            # Try to find a matching tfvars variable by suffix
            for tfvar in tfvars:
                tfvar_parts = tfvar.split('_')
                if key == tfvar_parts[-1]:
                    line = re.sub(r'=\s*([^"]*"[^"]*"|true|false|\d+)', f'= var.{tfvar}', line)
                    break
        updated_lines.append(line)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.writelines(updated_lines)
    print(f"Updated main.tf written to: {output_path}")

def main():
    if len(sys.argv) < 4:
        print("Usage: python tf_update_main.py <main.tf path> <terraform.tfvars path> <output main.tf path>")
        sys.exit(1)
    main_tf_path = sys.argv[1]
    tfvars_path = sys.argv[2]
    output_path = sys.argv[3]
    tfvars = read_tfvars(tfvars_path)
    update_main_tf(main_tf_path, tfvars, output_path)

if __name__ == "__main__":
    main()
