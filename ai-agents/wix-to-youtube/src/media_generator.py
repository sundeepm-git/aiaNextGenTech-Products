import asyncio
import edge_tts
import os
from moviepy.editor import TextClip, AudioFileClip, ColorClip, CompositeVideoClip

def create_video(post):
    audio_path = "temp/voice.mp3"
    video_output = "temp/output.mp4"
    voice = os.getenv("TTS_VOICE", "en-US-AvaNeural")

    # 1. Generate High-Quality Neural TTS
    async def generate_audio():
        communicate = edge_tts.Communicate(post['content'], voice)
        await communicate.save(audio_path)
    asyncio.run(generate_audio())

    # 2. Build Video
    audio = AudioFileClip(audio_path)
    bg = ColorClip(size=(1920, 1080), color=(15, 15, 15)).set_duration(audio.duration)
    
    txt = TextClip(
        post['title'], 
        fontsize=70, 
        color='white', 
        size=(1700, 800), 
        method='caption'
    ).set_position('center').set_duration(audio.duration)

    final_video = CompositeVideoClip([bg, txt]).set_audio(audio)
    final_video.write_videofile(video_output, fps=24, codec="libx264", audio_codec="aac")
    
    return video_output
