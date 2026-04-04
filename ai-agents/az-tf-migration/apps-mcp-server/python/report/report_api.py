"""
Report API Router — FastAPI endpoints for the Report feature.

Mount this router in api_server.py:
    from Report.report_api import report_router
    app.include_router(report_router)
"""

import os
import sys
from pathlib import Path
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response

# Add parent directory so we can import report_service
sys.path.insert(0, str(Path(__file__).resolve().parent))
from report_service import (
    list_subscriptions,
    list_resource_groups,
    get_report_tree,
    download_blob,
    build_full_report_zip,
    REPORT_CONTAINERS,
)

report_router = APIRouter(prefix="/api/reports", tags=["Reports"])


@report_router.get("/subscriptions")
def api_list_subscriptions():
    """List all subscription IDs that have reports in storage."""
    subs = list_subscriptions()
    return {"subscriptions": subs}


@report_router.get("/subscriptions/{subscription_id}/resource-groups")
def api_list_resource_groups(subscription_id: str):
    """List resource groups that have export/refactor reports for a subscription."""
    rgs = list_resource_groups(subscription_id)
    return {"subscription_id": subscription_id, "resource_groups": rgs}


@report_router.get("/tree")
def api_report_tree(
    subscription_id: str = Query(..., min_length=10),
    resource_group: str = Query(..., min_length=1),
):
    """Get the full report tree (assessment, export, refactor) for a subscription/RG pair."""
    tree = get_report_tree(subscription_id, resource_group)
    return tree


@report_router.get("/download")
def api_download_report(
    container: str = Query(...),
    blob_name: str = Query(...),
):
    """Download a single blob file from Azure Storage."""
    # Validate container is one of our known containers
    allowed_containers = {cfg["container"] for cfg in REPORT_CONTAINERS.values()}
    if container not in allowed_containers:
        raise HTTPException(status_code=400, detail=f"Invalid container. Allowed: {allowed_containers}")

    content = download_blob(container, blob_name)
    if content is None:
        raise HTTPException(status_code=404, detail=f"Blob not found: {container}/{blob_name}")

    # Determine content type
    if blob_name.endswith(".html"):
        media_type = "text/html"
    elif blob_name.endswith(".tf"):
        media_type = "text/plain"
    elif blob_name.endswith(".json"):
        media_type = "application/json"
    else:
        media_type = "application/octet-stream"

    filename = blob_name.split("/")[-1]
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@report_router.get("/download-full")
def api_download_full_bundle(
    subscription_id: str = Query(..., min_length=10),
    resource_group: str = Query(..., min_length=1),
):
    """Download full report bundle zip (HTML reports + refactored code artifacts)."""
    bundle = build_full_report_zip(subscription_id, resource_group)
    if bundle is None:
        raise HTTPException(status_code=404, detail="No reports or refactored code found for this subscription/resource group")

    content, filename = bundle
    return Response(
        content=content,
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
