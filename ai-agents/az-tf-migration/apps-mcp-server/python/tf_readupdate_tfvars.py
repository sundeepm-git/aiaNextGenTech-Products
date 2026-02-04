"""
tf_readupdate_tfvars.py

Reads main.tf, extracts all variable references (var.<name>), and ensures all such variables are present in terraform.tfvars, adding any missing ones with blank values.
"""
import re
import sys
import os
from pathlib import Path


# Extract all var.<name> references from main.tf
def extract_var_names_from_main(main_tf_path):
    var_pattern = re.compile(r'var\.([a-zA-Z0-9_]+)')
    var_names = set()
    with open(main_tf_path, 'r', encoding='utf-8') as f:
        for line in f:
            for match in var_pattern.findall(line):
                var_names.add(match)
    return sorted(var_names)

# Extract hardcoded assignments from main.tf (simple assignments only)
def extract_hardcoded_assignments(main_tf_path):
    assignments = {}
    block_var_pattern = re.compile(r'^(\s*)([a-zA-Z0-9_]+)\s*=\s*(.+)$')
    current_block = None
    with open(main_tf_path, 'r', encoding='utf-8') as f:
        for line in f:
            m = block_var_pattern.match(line)
            if m and not line.strip().startswith('depends_on'):
                var = m.group(2)
                val = m.group(3).strip()
                # Remove trailing comments
                val = val.split('#')[0].strip()
                # Remove trailing commas or brackets
                val = val.rstrip(',')
                # Only assign if value is a literal (string, number, bool)
                if (val.startswith('"') and val.endswith('"')) or (val.replace('.', '', 1).isdigit()) or val in ['true', 'false']:
                    assignments[var] = val
    return assignments

def read_tfvars(tfvars_path):
    """Read existing tfvars and return a dict of variable names to values."""
    tfvars = {}
    if not os.path.exists(tfvars_path):
        return tfvars
    with open(tfvars_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            name, value = line.split('=', 1)
            tfvars[name.strip()] = value.strip()
    return tfvars

def write_tfvars(tfvars_path, tfvars_dict):
    """Write the tfvars dict to file."""
    with open(tfvars_path, 'w', encoding='utf-8') as f:
        for name in sorted(tfvars_dict):
            f.write(f'{name} = {tfvars_dict[name] if tfvars_dict[name] else '""'}\n')

def main():
    if len(sys.argv) < 3:
        print("Usage: python tf_readupdate_tfvars.py <main.tf path> <terraform.tfvars path>")
        sys.exit(1)
    main_tf_path = sys.argv[1]
    tfvars_path = sys.argv[2]
    if not os.path.isfile(main_tf_path):
        print(f"main.tf not found: {main_tf_path}")
        sys.exit(1)
    var_names = extract_var_names_from_main(main_tf_path)
    assignments = extract_hardcoded_assignments(main_tf_path)
    tfvars = read_tfvars(tfvars_path)
    updated = False
    # For each tfvars variable, try to match by suffix to a main.tf assignment
    for tfvar in tfvars:
        # Find the property name as the last part after the last underscore
        # Or, for more robust matching, try all possible suffixes
        tfvar_parts = tfvar.split('_')
        matched = False
        for i in range(len(tfvar_parts)):
            suffix = '_'.join(tfvar_parts[i:])
            if suffix in assignments:
                if tfvars[tfvar] != assignments[suffix]:
                    tfvars[tfvar] = assignments[suffix]
                    updated = True
                matched = True
                break
        if not matched and tfvars[tfvar] == '""':
            # Leave as blank if no match
            continue
    # Also ensure all var.<name> references are present
    for var in var_names:
        if var not in tfvars:
            tfvars[var] = '""'
            updated = True
    if updated or not os.path.exists(tfvars_path):
        write_tfvars(tfvars_path, tfvars)
        print(f"Updated tfvars file: {tfvars_path}")
    else:
        print("No new variables found. tfvars file unchanged.")

if __name__ == "__main__":
    main()
