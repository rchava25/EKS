import uuid
import pytest


def test_get_user_success(users_client):
    create_resp = users_client.post(
        "/users", json={"email": "charlie@example.com", "name": "Charlie"}
    )
    user_id = create_resp.json()["user_id"]

    resp = users_client.get(f"/users/{user_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["user_id"] == user_id
    assert body["email"] == "charlie@example.com"
    assert body["name"] == "Charlie"


def test_get_user_not_found(users_client):
    missing_id = str(uuid.uuid4())
    resp = users_client.get(f"/users/{missing_id}")
    assert resp.status_code == 404


def test_get_user_invalid_uuid(users_client):
    resp = users_client.get("/users/not-a-valid-uuid")
    assert resp.status_code == 400
