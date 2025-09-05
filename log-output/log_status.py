from pathlib import Path
from fastapi import FastAPI, HTTPException


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
            lines = f.readlines()
            # Return last line
            recent = lines[-1] if len(lines) > 0 else ""
            return {"current_status": recent}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Status not available yet.")
