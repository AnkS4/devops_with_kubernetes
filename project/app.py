from contextlib import asynccontextmanager
import os
from fastapi import FastAPI
import uvicorn

PORT = int(os.getenv("PORT", 8001))

app = FastAPI()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # print(f"Server started in port {PORT}")
    print("Server started")
    yield

app = FastAPI(lifespan=lifespan)

@app.get("/")
def root():
    return {"message": "Hello World"}

