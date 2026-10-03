import uuid
import pytest


def test_update_user_success(users_client):
    create_resp = users_client.post(
        "/users", json={"email": "dave@example.com", "name": "Dave"}
    )
    user = create_resp.json()
    user_id = user["user_id"]
    original_updated_at = user["updated_at"]

    resp = users_client.put(f"/users/{user_id}", json={"name": "David"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "David"
    assert body["updated_at"] >= original_updated_at


def test_update_user_no_fields(users_client):
    random_id = str(uuid.uuid4())
    resp = users_client.put(f"/users/{random_id}", json={})
    assert resp.status_code == 400


def test_update_user_not_found(users_client):
    missing_id = str(uuid.uuid4())
    resp = users_client.put(f"/users/{missing_id}", json={"name": "Ghost"})
    assert resp.status_code == 404


def test_update_user_duplicate_email(users_client):
    users_client.post("/users", json={"email": "user1@example.com", "name": "User1"})
    r2 = users_client.post("/users", json={"email": "user2@example.com", "name": "User2"})
    user2_id = r2.json()["user_id"]

    resp = users_client.put(f"/users/{user2_id}", json={"email": "user1@example.com"})
    assert resp.status_code == 409
