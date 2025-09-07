from fastapi import FastAPI

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
