import os
from fastapi import FastAPI
import uvicorn    


PORT = int(os.getenv("PORT", 8002))
count = 0

app = FastAPI()

@app.get("/")
def root():
    return {"message": "Hello World"}

@app.get("/pingpong")
def pingpong():
    global count
    count += 1
    return {"message": f"pong {count}"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
