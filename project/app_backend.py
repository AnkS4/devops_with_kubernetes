from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

# Initialize with default todos
todos = [
    {"id": 1, "text": "Finish the project"},
    {"id": 2, "text": "Learn Kubernetes"},
    {"id": 3, "text": "Schedule a meeting"}
]  # In-memory storage for todos

class TodoCreate(BaseModel):
    text: str

class Todo(BaseModel):
    id: int
    text: str

@app.get("/todos")
def get_todos():
    return {"todos": todos}

@app.post("/todos", response_model=Todo)
def create_todo(todo: TodoCreate):
    new_id = len(todos) + 1
    new_todo = Todo(id=new_id, text=todo.text)
    todos.append(new_todo.model_dump())  # Use model_dump() for Pydantic v2
    return new_todo
