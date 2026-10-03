import pytest


def test_create_user_success(users_client):
    resp = users_client.post(
        "/users",
        json={"email": "alice@example.com", "name": "Alice"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["email"] == "alice@example.com"
    assert body["name"] == "Alice"
    assert body["status"] == "ACTIVE"
    assert "user_id" in body
    assert "created_at" in body
    assert "updated_at" in body
    # user_id should be UUID-shaped (36 chars with dashes)
    assert len(body["user_id"]) == 36


def test_create_user_invalid_email(users_client):
    resp = users_client.post(
        "/users",
        json={"email": "not-an-email", "name": "Alice"},
    )
    assert resp.status_code == 422


def test_create_user_duplicate_email(users_client):
    users_client.post("/users", json={"email": "bob@example.com", "name": "Bob"})
    resp = users_client.post("/users", json={"email": "bob@example.com", "name": "Bob2"})
    assert resp.status_code == 409
