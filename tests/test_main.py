import pytest
from fastapi.testclient import TestClient

import main
from main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def reset_state():
    # main.tasks/next_id are module-level globals shared across the whole
    # test run — without this, tests would leak state into each other.
    main.tasks.clear()
    main.next_id = 1
    yield


def test_health_check():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_list_tasks_empty():
    response = client.get("/tasks")
    assert response.status_code == 200
    assert response.json() == {}


def test_create_task():
    response = client.post("/tasks", json={"title": "Buy milk"})
    assert response.status_code == 200
    assert response.json() == {"id": 1, "title": "Buy milk", "done": False}


def test_create_task_respects_done_flag():
    response = client.post("/tasks", json={"title": "Test", "done": True})
    assert response.json()["done"] is True


def test_create_task_missing_title_returns_422():
    response = client.post("/tasks", json={})
    assert response.status_code == 422


def test_list_tasks_after_create():
    client.post("/tasks", json={"title": "Task A"})
    client.post("/tasks", json={"title": "Task B"})
    response = client.get("/tasks")
    assert response.status_code == 200
    assert len(response.json()) == 2


def test_get_task_found():
    created = client.post("/tasks", json={"title": "Find me"}).json()
    response = client.get(f"/tasks/{created['id']}")
    assert response.status_code == 200
    assert response.json()["title"] == "Find me"


def test_get_task_not_found():
    response = client.get("/tasks/999")
    assert response.status_code == 404
    assert response.json() == {"detail": "Task not found"}
