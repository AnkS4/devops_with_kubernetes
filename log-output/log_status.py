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
        # Return single line file
        with STATUS_FILE.open("r") as f:
            return {"current_status": f.read()}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Status not available yet.")
