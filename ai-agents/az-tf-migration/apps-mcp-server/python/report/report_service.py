"""
Report Service — Business logic for reading reports from Azure Blob Storage.

Authenticates via Service Principal using DefaultAzureCredential.
Set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID env vars for SP auth.

Containers:
    - assessment-reports : {subscriptionId}/{subscriptionId}-{resourceGroup}-assessment-report.html
  - aztfexport         : {subscriptionId}/{resourceGroup}/*.tf
  - code-refactored    : {subscriptionId}/{resourceGroup}/*.tf
"""

import os
import logging
import re
import io
import zipfile
from datetime import datetime
from html import escape
from dataclasses import dataclass, field, asdict
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

logger = logging.getLogger(__name__)

STORAGE_ACCOUNT = os.getenv("storageAccount", "samcpstorage")
ACCOUNT_URL = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net"

# Singleton credential + client (created once, reused)
_credential = DefaultAzureCredential()
_blob_service: BlobServiceClient = BlobServiceClient(ACCOUNT_URL, credential=_credential)

# Container → report file mapping
REPORT_CONTAINERS = {
    "assessment": {
        "container": "assessment-reports",
        "blob_pattern": "{subscription_id}/{subscription_id}-{resource_group}-assessment-report.html",
        "display_name": "Assessment Report",
        "filename": "{subscription_id}-{resource_group}-assessment-report.html",
    },
    "export": {
        "container": "aztfexport",
        "blob_pattern": "{subscription_id}/{resource_group}/",
        "display_name": "Export (Terraform Files)",
        "filename": "Export-Report-Latest.html",
    },
    "refactor": {
        "container": "code-refactored",
        "blob_pattern": "{subscription_id}/{resource_group}/",
        "display_name": "Code Refactor (Terraform Files)",
        "filename": "CodeRefactor-Report.html",
    },
}


def build_assessment_report_blob_name(subscription_id: str, resource_group: str) -> str:
    """Return deterministic assessment report blob path for a subscription/resource group."""
    rg_safe = re.sub(r"[^A-Za-z0-9._-]", "-", resource_group or "all-resource-groups")
    file_name = f"{subscription_id}-{rg_safe}-assessment-report.html"
    return f"{subscription_id}/{file_name}"


@dataclass
class BlobFile:
    name: str
    size: int = 0
    last_modified: str = ""
    content_type: str = ""


@dataclass
class ReportFolder:
    subscription_id: str
    resource_group: str
    reports: dict = field(default_factory=dict)  # type -> list[BlobFile]


def list_subscriptions() -> list[str]:
    """List distinct subscription folders from the assessment-reports container."""
    try:
        container_client = _blob_service.get_container_client("assessment-reports")
        subs = set()
        for blob in container_client.list_blobs():
            parts = blob.name.split("/")
            if len(parts) >= 2:
                subs.add(parts[0])
        return sorted(subs)
    except Exception as e:
        logger.error("list_subscriptions failed: %s", e)
        return []


def list_resource_groups(subscription_id: str) -> list[str]:
    """List distinct resource group folders across export and refactor containers."""
    rgs = set()
    for container_name in ["aztfexport", "code-refactored"]:
        try:
            container_client = _blob_service.get_container_client(container_name)
            for blob in container_client.list_blobs(name_starts_with=f"{subscription_id}/"):
                parts = blob.name.split("/")
                if len(parts) >= 3:
                    rgs.add(parts[1])
        except Exception as e:
            logger.error("list_resource_groups failed for %s: %s", container_name, e)
    return sorted(rgs)


def list_blobs_in_container(container: str, prefix: str) -> list[BlobFile]:
    """List blobs in a container with a given prefix."""
    try:
        container_client = _blob_service.get_container_client(container)
        results = []
        for blob in container_client.list_blobs(name_starts_with=prefix):
            results.append(BlobFile(
                name=blob.name,
                size=blob.size or 0,
                last_modified=blob.last_modified.isoformat() if blob.last_modified else "",
                content_type=blob.content_settings.content_type if blob.content_settings else "",
            ))
        return results
    except Exception as e:
        logger.error("list_blobs_in_container failed for %s/%s: %s", container, prefix, e)
        return []


def get_report_tree(subscription_id: str, resource_group: str) -> dict:
    """
    Build a report tree for a subscription/resource-group pair.
    Returns:
      {
        "subscription_id": "...",
        "resource_group": "...",
        "reports": {
          "assessment": { "available": true, "files": [...], "display_name": "..." },
          "export":     { "available": true, "files": [...], "display_name": "..." },
          "refactor":   { "available": true, "files": [...], "display_name": "..." },
        }
      }
    """
    reports = {}
    for report_type, cfg in REPORT_CONTAINERS.items():
        if report_type == "assessment":
            prefix = build_assessment_report_blob_name(subscription_id, resource_group)
        else:
            prefix = f"{subscription_id}/{resource_group}/"

        files = list_blobs_in_container(cfg["container"], prefix)
        reports[report_type] = {
            "available": len(files) > 0,
            "files": [asdict(f) for f in files],
            "display_name": cfg["display_name"],
            "container": cfg["container"],
            "file_count": len(files),
        }
    return {
        "subscription_id": subscription_id,
        "resource_group": resource_group,
        "reports": reports,
    }


def download_blob(container: str, blob_name: str) -> Optional[bytes]:
    """Download a single blob and return its bytes."""
    try:
        blob_client = _blob_service.get_blob_client(container, blob_name)
        return blob_client.download_blob().readall()
    except Exception as e:
        logger.error("download_blob failed for %s/%s: %s", container, blob_name, e)
        return None


def _generate_inventory_html(title: str, files: list[BlobFile], subscription_id: str, resource_group: str) -> str:
    """Generate a lightweight HTML report that lists files for a section."""
    rows = []
    for f in files:
        file_name = f.name.split("/")[-1]
        rows.append(
            "<tr>"
            f"<td>{escape(file_name)}</td>"
            f"<td>{f.size}</td>"
            f"<td>{escape(f.last_modified or '')}</td>"
            "</tr>"
        )
    rows_html = "".join(rows) if rows else "<tr><td colspan='3'>No files found</td></tr>"
    generated = datetime.utcnow().isoformat() + "Z"
    return (
        "<!doctype html><html><head><meta charset='utf-8'/>"
        f"<title>{escape(title)}</title>"
        "<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px}"
        "table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px;text-align:left}"
        "th{background:#f5f5f5}</style></head><body>"
        f"<h1>{escape(title)}</h1>"
        f"<p><b>Subscription:</b> {escape(subscription_id)}<br/><b>Resource Group:</b> {escape(resource_group)}<br/><b>Generated:</b> {escape(generated)}</p>"
        "<table><thead><tr><th>File</th><th>Size (bytes)</th><th>Last Modified</th></tr></thead><tbody>"
        f"{rows_html}</tbody></table></body></html>"
    )


def build_full_report_zip(subscription_id: str, resource_group: str) -> tuple[bytes, str] | None:
    """
    Build a zip containing:
      - All available HTML reports
      - Generated HTML inventories for export/refactor sections
      - All refactored code files from code-refactored container
    """
    assessment_cfg = REPORT_CONTAINERS["assessment"]
    export_cfg = REPORT_CONTAINERS["export"]
    refactor_cfg = REPORT_CONTAINERS["refactor"]

    assessment_prefix = build_assessment_report_blob_name(subscription_id, resource_group)
    export_prefix = f"{subscription_id}/{resource_group}/"
    refactor_prefix = f"{subscription_id}/{resource_group}/"

    assessment_files = list_blobs_in_container(assessment_cfg["container"], assessment_prefix)
    export_files = list_blobs_in_container(export_cfg["container"], export_prefix)
    refactor_files = list_blobs_in_container(refactor_cfg["container"], refactor_prefix)

    if not assessment_files and not export_files and not refactor_files:
        return None

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        # Include existing assessment html files if present.
        for f in assessment_files:
            content = download_blob(assessment_cfg["container"], f.name)
            if content is not None:
                out_name = f"reports/assessment/{f.name.split('/')[-1]}"
                zf.writestr(out_name, content)

        # Include generated inventories as HTML reports.
        zf.writestr(
            "reports/export/Export-Report.html",
            _generate_inventory_html("Export Report", export_files, subscription_id, resource_group).encode("utf-8"),
        )
        zf.writestr(
            "reports/refactor/CodeRefactor-Report.html",
            _generate_inventory_html("Code Refactor Report", refactor_files, subscription_id, resource_group).encode("utf-8"),
        )

        # Include all refactored code artifacts.
        for f in refactor_files:
            content = download_blob(refactor_cfg["container"], f.name)
            if content is None:
                continue
            rel_name = f.name.split(f"{subscription_id}/{resource_group}/", 1)[-1]
            if not rel_name:
                rel_name = f.name.split("/")[-1]
            zf.writestr(f"code-refactored/{rel_name}", content)

    zip_name = f"{subscription_id}-{resource_group}-full-report.zip"
    return zip_buffer.getvalue(), zip_name
