import time, uuid, threading
from datetime import datetime, UTC
from pathlib import Path
from fastapi import FastAPI
import uvicorn
import os

PORT = int(os.getenv("PORT", 8000))

app = FastAPI()

STATUS_FILE = Path("/tmp/status.txt")

def status_updater():
    while True:
        now = datetime.now(UTC)
        timestamp = now.strftime('%Y-%m-%dT%H:%M:%S.') + f"{now.microsecond // 1000:03d}Z"
        random_string = str(uuid.uuid4())
        status = f"{timestamp}: {random_string}"
        print(status)
        with STATUS_FILE.open("w") as f:
            f.write(status)
        time.sleep(5)

@app.on_event("startup")
def startup():
    thread = threading.Thread(target=status_updater, daemon=True)
    thread.start()

@app.get("/")
def root():
    return {"message": "Hello World"}

@app.get("/status")
def status():
    if STATUS_FILE.exists():
        with STATUS_FILE.open("r") as f:
            return {"current_status": f.read()}
    else:
        return {"current_status": "Status file not found"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)