
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="TaskFlow API")

# Stockage en mémoire pour l'instant (pas de vraie DB à ce stade)
tasks = {}
next_id = 1

class Task(BaseModel):
    title: str
    done: bool = False

@app.get("/")
def health_check():
    return {"status": "ok"}

@app.get("/tasks")
def list_tasks():
    return tasks

@app.post("/tasks")
def create_task(task: Task):
    global next_id
    task_id = next_id
    tasks[task_id] = task
    next_id += 1
    return {"id": task_id, **task.dict()}

@app.get("/tasks/{task_id}")
def get_task(task_id: int):
    if task_id not in tasks:
        raise HTTPException(status_code=404, detail="Task not found")
    return tasks[task_id]
