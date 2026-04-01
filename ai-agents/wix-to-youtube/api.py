"""
FastAPI layer for the Wix-to-YouTube automation pipeline.

Run:  uvicorn api:app --reload --port 8000
Docs: http://localhost:8000/docs
"""

import os
import uuid
from datetime import datetime
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI, BackgroundTasks, HTTPException
from pydantic import BaseModel, Field

from src.wix_fetcher import get_all_posts
from src.media_generator import create_video
from src.yt_uploader import upload_to_youtube

load_dotenv()

# ── App ──────────────────────────────────────────────────────────────
app = FastAPI(
    title="Wix-to-YouTube API",
    description="Convert Wix blog posts into narrated YouTube videos via REST endpoints.",
    version="1.0.0",
)

# ── In-memory job store ──────────────────────────────────────────────
jobs: dict[str, dict] = {}

UPLOAD_LOG = "uploaded_posts.log"


# ── Helpers ──────────────────────────────────────────────────────────
def _is_already_uploaded(post_title: str) -> bool:
    if not os.path.exists(UPLOAD_LOG):
        return False
    with open(UPLOAD_LOG, "r") as f:
        return post_title in f.read()


def _log_upload(post_title: str) -> None:
    with open(UPLOAD_LOG, "a") as f:
        f.write(post_title + "\n")


# ── Pydantic models ─────────────────────────────────────────────────
class PostItem(BaseModel):
    title: str
    content: str
    description: str = ""


class SinglePostRequest(BaseModel):
    """Process a single custom post (not from RSS)."""
    title: str = Field(..., min_length=1, max_length=100)
    content: str = Field(..., min_length=1)
    description: Optional[str] = ""
    privacy: Optional[str] = Field("public", pattern="^(public|unlisted|private)$")


class BulkRequest(BaseModel):
    """Trigger bulk processing of all RSS posts."""
    rss_url: Optional[str] = None  # override .env value


class JobStatus(BaseModel):
    job_id: str
    status: str  # queued | processing | completed | failed
    created_at: str
    detail: Optional[str] = None
    results: Optional[list] = None


# ── Background workers ───────────────────────────────────────────────
def _process_single(job_id: str, post: dict, privacy: str):
    """Background task: generate video + upload for one post."""
    jobs[job_id]["status"] = "processing"
    try:
        os.makedirs("temp", exist_ok=True)
        video_path = create_video(post)
        video_id = upload_to_youtube(
            video_path, post["title"], post.get("description", ""), privacy=privacy,
        )
        _log_upload(post["title"])
        jobs[job_id]["status"] = "completed"
        jobs[job_id]["detail"] = f"https://www.youtube.com/watch?v={video_id}"
    except Exception as exc:
        jobs[job_id]["status"] = "failed"
        jobs[job_id]["detail"] = str(exc)


def _process_bulk(job_id: str, rss_url: str):
    """Background task: fetch all RSS posts, skip duplicates, process each."""
    jobs[job_id]["status"] = "processing"
    results = []
    try:
        os.makedirs("temp", exist_ok=True)
        posts = get_all_posts(rss_url)
        for post in posts:
            if _is_already_uploaded(post["title"]):
                results.append({"title": post["title"], "status": "skipped"})
                continue
            try:
                video_path = create_video(post)
                video_id = upload_to_youtube(
                    video_path, post["title"], post["description"],
                )
                _log_upload(post["title"])
                results.append({
                    "title": post["title"],
                    "status": "uploaded",
                    "url": f"https://www.youtube.com/watch?v={video_id}",
                })
            except Exception as exc:
                results.append({"title": post["title"], "status": "failed", "error": str(exc)})

        jobs[job_id]["status"] = "completed"
        jobs[job_id]["results"] = results
    except Exception as exc:
        jobs[job_id]["status"] = "failed"
        jobs[job_id]["detail"] = str(exc)


# ── Endpoints ────────────────────────────────────────────────────────
@app.get("/", tags=["Health"])
def root():
    return {"service": "Wix-to-YouTube API", "status": "running"}


@app.get("/health", tags=["Health"])
def health():
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}


# ── Posts ────────────────────────────────────────────────────────────
@app.get("/posts", tags=["Posts"], summary="Fetch all blog posts from Wix RSS")
def list_posts(rss_url: Optional[str] = None):
    """Return all posts from the configured (or overridden) RSS feed."""
    url = rss_url or os.getenv("WIX_RSS_URL")
    if not url:
        raise HTTPException(status_code=400, detail="No RSS URL configured. Set WIX_RSS_URL in .env or pass ?rss_url=")
    posts = get_all_posts(url)
    return {"count": len(posts), "posts": posts}


@app.get("/posts/uploaded", tags=["Posts"], summary="List already-uploaded post titles")
def uploaded_posts():
    if not os.path.exists(UPLOAD_LOG):
        return {"count": 0, "titles": []}
    with open(UPLOAD_LOG, "r") as f:
        titles = [line.strip() for line in f if line.strip()]
    return {"count": len(titles), "titles": titles}


# ── Process single post ─────────────────────────────────────────────
@app.post("/process", tags=["Process"], summary="Process a single custom post (async)")
def process_single(req: SinglePostRequest, background_tasks: BackgroundTasks):
    """Queue a single post for TTS, video generation, and YouTube upload."""
    if _is_already_uploaded(req.title):
        return {"message": f"'{req.title}' was already uploaded.", "skipped": True}

    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "created_at": datetime.utcnow().isoformat()}

    post = {"title": req.title, "content": req.content, "description": req.description or ""}
    background_tasks.add_task(_process_single, job_id, post, req.privacy)

    return {"job_id": job_id, "status": "queued"}


# ── Bulk process ─────────────────────────────────────────────────────
@app.post("/process/bulk", tags=["Process"], summary="Bulk-process all RSS posts (async)")
def process_bulk(req: BulkRequest, background_tasks: BackgroundTasks):
    """Fetch every post from the RSS feed and process them in the background."""
    rss_url = req.rss_url or os.getenv("WIX_RSS_URL")
    if not rss_url:
        raise HTTPException(status_code=400, detail="No RSS URL configured.")

    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "created_at": datetime.utcnow().isoformat()}
    background_tasks.add_task(_process_bulk, job_id, rss_url)

    return {"job_id": job_id, "status": "queued"}


# ── Job status ───────────────────────────────────────────────────────
@app.get("/jobs/{job_id}", tags=["Jobs"], summary="Check job status", response_model=JobStatus)
def get_job(job_id: str):
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    entry = jobs[job_id]
    return JobStatus(
        job_id=job_id,
        status=entry["status"],
        created_at=entry["created_at"],
        detail=entry.get("detail"),
        results=entry.get("results"),
    )


@app.get("/jobs", tags=["Jobs"], summary="List all jobs")
def list_jobs():
    return {
        "count": len(jobs),
        "jobs": [
            {"job_id": jid, "status": j["status"], "created_at": j["created_at"]}
            for jid, j in jobs.items()
        ],
    }
