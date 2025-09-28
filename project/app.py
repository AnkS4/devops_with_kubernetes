from fastapi import FastAPI, HTTPException, Request
import httpx
import time
from pathlib import Path
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

app = FastAPI()

# Set up templates
templates = Jinja2Templates(directory="templates")

IMAGE_PATH = Path("/app/shared/cache/image.jpg")
FALLBACK_PATH = Path("/tmp/fallback.jpg")
CACHE_DURATION = 600  # 10 minutes

async def get_image():
    """Get cached image or fetch new one"""
    try:
        # Create cache directory
        IMAGE_PATH.parent.mkdir(parents=True, exist_ok=True)
        
        # Check cache
        if IMAGE_PATH.exists():
            age = time.time() - IMAGE_PATH.stat().st_mtime
            if age < CACHE_DURATION:
                return IMAGE_PATH
        
        # Fetch new image
        seed = int(time.time() // CACHE_DURATION)
        url = f"https://picsum.photos/seed/{seed}/800"
        
        async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
            response = await client.get(url)
            response.raise_for_status()
            
            # Save current image as fallback before replacing it
            if IMAGE_PATH.exists():
                IMAGE_PATH.rename(FALLBACK_PATH)
            
            # Save new image atomically
            temp_path = IMAGE_PATH.with_suffix('.tmp')
            temp_path.write_bytes(response.content)
            temp_path.rename(IMAGE_PATH)
            
        return IMAGE_PATH
        
    except Exception:
        return None

@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/image")
async def image():
    image_path = await get_image()
    if image_path and image_path.exists():
        return FileResponse(image_path, media_type='image/jpeg')
    elif FALLBACK_PATH.exists():
        # Return saved fallback image (previous working image)
        return FileResponse(FALLBACK_PATH, media_type='image/jpeg')
    else:
        # No image available, throw standard error
        raise HTTPException(status_code=503, detail="Image service temporarily unavailable")
