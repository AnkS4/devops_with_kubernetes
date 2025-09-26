# import os
# import json
from fastapi import FastAPI
# from pathlib import Path

app = FastAPI()

# Global counter for pongs
pong_count = 0

# # Path to the shared file
# SHARED_FILE = os.getenv('SHARED_VOLUME_PATH', '/app/shared/request_count.txt')

# # Ensure the directory exists
# Path(SHARED_FILE).parent.mkdir(parents=True, exist_ok=True)

# def read_count():
#     try:
#         with open(SHARED_FILE, 'r') as f:
#             return int(f.read().strip() or 0)
#     except (FileNotFoundError, ValueError):
#         return 0

# def write_count(count):
#     with open(SHARED_FILE, 'w') as f:
#         f.write(str(count))

@app.get("/")
def root():
    return {"message": "Hello World"}

@app.get("/pingpong")
def pingpong():
    global pong_count
    pong_count += 1
    # count = read_count() + 1
    # write_count(count)
    return {"message": f"pong {pong_count}"}

@app.get("/pongs")
def get_pongs():
    global pong_count
    # count = read_count()
    return {"pongs": pong_count}
