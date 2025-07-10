from contextlib import asynccontextmanager
from fastapi import FastAPI
import uvicorn
import os

PORT = int(os.getenv("PORT", 8001))

@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"Server started in port {PORT}")
    yield

app = FastAPI(lifespan=lifespan)

@app.get("/")
def root():
    return {"message": "Hello World"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
