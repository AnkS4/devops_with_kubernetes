from pathlib import Path
import os
from fastapi import FastAPI, HTTPException

app = FastAPI()

# Use the same shared volume path as the generator
STATUS_FILE = Path("/app/shared/status.txt")
REQUEST_COUNT_FILE = Path(os.getenv('SHARED_VOLUME_PATH', '/app/shared/request_count.txt'))

def read_request_count():
    try:
        with REQUEST_COUNT_FILE.open('r') as f:
            return int(f.read().strip() or 0)
    except (FileNotFoundError, ValueError):
        return 0

@app.get("/")
def root():
    return {"message": "Log Server is running. Check /status for the latest log and ping-pong count."}

@app.get("/status")
def status():
    try:
        # Read status from log generator
        with STATUS_FILE.open("r") as f:
            status_message = f.read()
        
        # Read ping-pong request count
        request_count = read_request_count()
        
        return {
            "current_status": status_message,
            "ping_pong_requests": request_count
        }
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Status not available yet.")
