"""
tf_refactor_tfvars.py

Reads a variables.tf file and updates the corresponding terraform.tfvars file with blank values for each variable.
This script should be run after tf_refactor_engine.py has completed processing.
"""
import os
import re
import sys

VARIABLE_BLOCK_RE = re.compile(r'variable\s+"([^"]+)"\s*{', re.MULTILINE)


def parse_variables_tf(variables_tf_path):
    """Parse variables.tf and return a list of variable names."""
    variables = []
    with open(variables_tf_path, 'r', encoding='utf-8') as f:
        content = f.read()
    for match in VARIABLE_BLOCK_RE.finditer(content):
        variables.append(match.group(1))
    return variables


def write_tfvars(tfvars_path, variables):
    """Write blank tfvars entries for each variable name."""
    with open(tfvars_path, 'w', encoding='utf-8') as f:
        for var in variables:
            f.write(f'{var} = ""\n')


def main():
    if len(sys.argv) < 2:
        print("Usage: python tf_refactor_tfvars.py <path_to_variables.tf> [<path_to_terraform.tfvars>]")
        sys.exit(1)
    variables_tf_path = sys.argv[1]
    if not os.path.isfile(variables_tf_path):
        print(f"variables.tf not found: {variables_tf_path}")
        sys.exit(1)
    if len(sys.argv) > 2:
        tfvars_path = sys.argv[2]
    else:
        tfvars_path = os.path.join(os.path.dirname(variables_tf_path), 'terraform.tfvars')

    variables = parse_variables_tf(variables_tf_path)
    write_tfvars(tfvars_path, variables)
    print(f"Updated tfvars file: {tfvars_path}")

    # Step 4: Update tfvars with all variables from main.tf
    main_tf_path = os.path.join(os.path.dirname(variables_tf_path), 'main.tf')
    tf_readupdate_path = os.path.join(os.path.dirname(__file__), 'tf_readupdate_tfvars.py')
    import subprocess
    import sys as _sys
    if os.path.isfile(main_tf_path) and os.path.isfile(tf_readupdate_path):
        try:
            subprocess.run([
                _sys.executable,
                tf_readupdate_path,
                main_tf_path,
                tfvars_path
            ], check=True)
            print("\033[92mStep 4 - tfvars file updated with all variables from main.tf successfully\033[0m")
        except Exception as e:
            print(f"\033[91m[ERROR] Step 4 failed: {e}\033[0m")
    else:
        print("\033[93m[WARNING] Step 4 skipped: main.tf or tf_readupdate_tfvars.py not found\033[0m")

if __name__ == "__main__":
    main()
