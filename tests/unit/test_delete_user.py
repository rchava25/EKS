import uuid
import pytest


def test_delete_user_success(users_client):
    create_resp = users_client.post(
        "/users", json={"email": "eve@example.com", "name": "Eve"}
    )
    user_id = create_resp.json()["user_id"]

    resp = users_client.delete(f"/users/{user_id}")
    assert resp.status_code == 204

    get_resp = users_client.get(f"/users/{user_id}")
    assert get_resp.status_code == 404


def test_delete_user_not_found(users_client):
    missing_id = str(uuid.uuid4())
    resp = users_client.delete(f"/users/{missing_id}")
    assert resp.status_code == 404
