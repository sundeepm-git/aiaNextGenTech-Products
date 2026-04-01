import os
from dotenv import load_dotenv
from src.wix_fetcher import get_all_posts
from src.media_generator import create_video
from src.yt_uploader import upload_to_youtube

load_dotenv()

def is_already_uploaded(post_title):
    if not os.path.exists('uploaded_posts.log'): return False
    with open('uploaded_posts.log', 'r') as f:
        return post_title in f.read()

def log_upload(post_title):
    with open('uploaded_posts.log', 'a') as f:
        f.write(post_title + "\n")

def main():
    if not os.path.exists('temp'): os.makedirs('temp')
    
    print("--- Fetching all available Wix posts ---")
    posts = get_all_posts(os.getenv("WIX_RSS_URL"))
    
    for post in posts:
        if is_already_uploaded(post['title']):
            print(f"Skipping: {post['title']} (Already Uploaded)")
            continue

        print(f"Processing: {post['title']}...")
        try:
            video_path = create_video(post)
            upload_to_youtube(video_path, post['title'], post['description'])
            log_upload(post['title'])
            print(f"Successfully uploaded: {post['title']}")
        except Exception as e:
            print(f"Failed to process {post['title']}: {e}")

if __name__ == "__main__":
    main()
