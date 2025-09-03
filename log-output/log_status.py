from pathlib import Path
import os
from fastapi import FastAPI, HTTPException
import uvicorn


PORT = int(os.getenv("PORT", 8000))

app = FastAPI()

# Use the same shared volume path as the generator
STATUS_FILE = Path("/app/shared/status.txt")

@app.get("/")
def root():
    return {"message": "Log Server is running. Check /status for the latest log."}

@app.get("/status")
def status():
    try:
        with STATUS_FILE.open("r") as f:
            return {"current_status": f.read()}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Status not available yet. The log generator may be starting up.")

if __name__ == "__main__":
    # Ensure the shared directory exists
    STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
    uvicorn.run(app, host="0.0.0.0", port=PORT)
