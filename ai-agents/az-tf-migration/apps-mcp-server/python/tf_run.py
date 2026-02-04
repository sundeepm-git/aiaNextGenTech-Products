"""
tf_run.py

Runs the final workflow:
1. Waits for step 4 (tfvars update) to be complete (user should run this after step 4).
2. Waits 30 seconds.
3. Runs 'terraform init'.
4. Runs 'terraform validate'.
5. Runs 'terraform plan'.
6. Prints success message if all steps succeed.

Usage:
    python tf_run.py <terraform working dir> <terraform.tfvars file>
"""
import subprocess
import sys
import time
from pathlib import Path

def run_command(cmd, cwd=None):
    print(f"\n[RUNNING] {' '.join(cmd)} (in {cwd or Path.cwd()})")
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    print(result.stdout)
    if result.stderr:
        print(result.stderr)
    if result.returncode != 0:
        print(f"[ERROR] Command failed: {' '.join(cmd)}")
        sys.exit(result.returncode)

def main():
    if len(sys.argv) < 3:
        print("Usage: python tf_run.py <terraform working dir> <terraform.tfvars file>")
        sys.exit(1)
    tf_dir = sys.argv[1]
    tfvars = sys.argv[2]
    # 1. Wait 30 seconds
    print("[INFO] Waiting 6 seconds before running Terraform commands...")
    time.sleep(6)
    # 2. terraform init
    run_command(["terraform", "init"], cwd=tf_dir)
    # 3. terraform validate
    run_command(["terraform", "validate"], cwd=tf_dir)
    # 4. terraform plan -out=tfplan
    run_command(["terraform", "plan", "-out=tfplan"], cwd=tf_dir)
    print("\nStep 5 - Terraform plan saved to tfplan.")

if __name__ == "__main__":
    main()
