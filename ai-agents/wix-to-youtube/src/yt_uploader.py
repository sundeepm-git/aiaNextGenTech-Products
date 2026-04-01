import os
import httplib2
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
import pickle

SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]


def _get_authenticated_service():
    """Authenticate via OAuth and return the YouTube API service."""
    credentials = None
    token_file = "token.pickle"

    # Load cached credentials
    if os.path.exists(token_file):
        with open(token_file, "rb") as token:
            credentials = pickle.load(token)

    # Refresh or start new OAuth flow
    if not credentials or not credentials.valid:
        if credentials and credentials.expired and credentials.refresh_token:
            credentials.refresh(Request())
        else:
            client_secret_file = os.getenv("YT_CLIENT_SECRET_FILE", "client_secrets.json")
            flow = InstalledAppFlow.from_client_secrets_file(client_secret_file, SCOPES)
            credentials = flow.run_local_server(port=0)

        # Save credentials for next run
        with open(token_file, "wb") as token:
            pickle.dump(credentials, token)

    service_name = os.getenv("YT_API_SERVICE_NAME", "youtube")
    api_version = os.getenv("YT_API_VERSION", "v3")
    return build(service_name, api_version, credentials=credentials)


def upload_to_youtube(video_path, title, description, category_id="22", privacy="public"):
    """
    Upload a video file to YouTube.

    Args:
        video_path: Path to the .mp4 file.
        title: Video title.
        description: Video description.
        category_id: YouTube category (default "22" = People & Blogs).
        privacy: "public", "unlisted", or "private".
    """
    youtube = _get_authenticated_service()

    body = {
        "snippet": {
            "title": title[:100],  # YouTube title max 100 chars
            "description": description,
            "tags": ["automation", "wix", "blog", "AI"],
            "categoryId": category_id,
        },
        "status": {
            "privacyStatus": privacy,
            "selfDeclaredMadeForKids": False,
        },
    }

    media = MediaFileUpload(video_path, chunksize=-1, resumable=True, mimetype="video/*")

    request = youtube.videos().insert(
        part="snippet,status",
        body=body,
        media_body=media,
    )

    print(f"Uploading '{title}' to YouTube...")
    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            print(f"  Upload progress: {int(status.progress() * 100)}%")

    video_id = response.get("id")
    print(f"Upload complete! Video ID: {video_id}")
    print(f"  URL: https://www.youtube.com/watch?v={video_id}")
    return video_id
