from fastapi import FastAPI
import uvicorn

app = FastAPI()

PORT = 8000

@app.on_event("startup")
def startup_event():
    print(f"Server started in port {PORT}")

@app.get("/")
def root():
    return {"message": "Hello World"}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=PORT)
