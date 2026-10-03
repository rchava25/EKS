import pytest


def _create_users(client, count, prefix="listuser"):
    ids = []
    for i in range(count):
        r = client.post(
            "/users", json={"email": f"{prefix}{i}@example.com", "name": f"User{i}"}
        )
        assert r.status_code == 201
        ids.append(r.json()["user_id"])
    return ids


def test_list_users_empty(users_client):
    resp = users_client.get("/users")
    assert resp.status_code == 200
    body = resp.json()
    assert body["items"] == []
    assert body["count"] == 0


def test_list_users_with_data(users_client):
    _create_users(users_client, 3)
    resp = users_client.get("/users")
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 3
    assert len(body["items"]) == 3


def test_list_users_bad_limit(users_client):
    resp = users_client.get("/users?limit=0")
    assert resp.status_code == 422


def test_list_users_pagination(users_client):
    _create_users(users_client, 5, prefix="page")

    page1 = users_client.get("/users?limit=2")
    assert page1.status_code == 200
    body1 = page1.json()
    assert body1["count"] == 2
    assert "next_token" in body1

    next_token = body1["next_token"]
    page2 = users_client.get(f"/users?limit=2&next_token={next_token}")
    assert page2.status_code == 200
    body2 = page2.json()
    assert body2["count"] == 2

    all_ids = {u["user_id"] for u in body1["items"]} | {u["user_id"] for u in body2["items"]}
    assert len(all_ids) == 4
