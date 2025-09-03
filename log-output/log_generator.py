import time, uuid
from datetime import datetime, UTC
from pathlib import Path

# Use a shared volume path
LOG_FILE = Path("/app/shared/status.txt")

def status_updater():
    # Ensure the shared directory exists
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    
    while True:
        now = datetime.now(UTC)
        timestamp = now.strftime('%Y-%m-%dT%H:%M:%S.') + f"{now.microsecond // 1000:03d}Z"
        random_string = str(uuid.uuid4())
        status = f"{timestamp}: {random_string}"
        with LOG_FILE.open("a") as f:
            f.write(status)
        time.sleep(5)

if __name__ == "__main__":
    print("Starting log generator...")
    status_updater()
