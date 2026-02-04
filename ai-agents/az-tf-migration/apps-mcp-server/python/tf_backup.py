# =============================================================
# Name: sundeep k maheshwari
# Date: 2026-01-21
# Description: Module for creating timestamped backups of original Terraform files before refactoring, ensuring safe rollback.
# =============================================================

"""
Auto-generated via Enterprise Terraform Refactoring Engine
Handles timestamped backup creation.
"""

from pathlib import Path
import shutil
from datetime import datetime


class BackupManager:
    def __init__(self, source_dir, verbose=False):
        self.source_dir = Path(source_dir)
        self.verbose = verbose

    def log(self, msg):
        if self.verbose:
            print(f"[BACKUP] {msg}")

    def create_backup(self):
            import shutil
            from datetime import datetime
            from pathlib import Path
            ts = datetime.now().strftime('%Y%m%d-%H%M%S')
            backup_dir = Path(self.source_dir) / f"backup_{ts}"
            backup_dir.mkdir(exist_ok=True)
            for file in Path(self.source_dir).glob('*.tf'):
                shutil.copy2(file, backup_dir / file.name)
            if self.verbose:
                print(f"[BACKUP] Created backup at {backup_dir}")
