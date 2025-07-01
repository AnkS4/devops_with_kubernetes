import time
import uuid
from datetime import datetime, UTC

# Generate a random UUID at startup
random_string = str(uuid.uuid4())

while True:
    now = datetime.now(UTC)
    # Format with ISO 8601 and milliseconds
    timestamp = now.strftime('%Y-%m-%dT%H:%M:%S.') + f"{now.microsecond // 1000:03d}Z"
    print(f"{timestamp}: {random_string}")
    time.sleep(5)
