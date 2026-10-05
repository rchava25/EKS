import pytest


def _create_order(client, user_id="user-123", items=None):
    if items is None:
        items = [{"product_id": "prod-1", "quantity": 2, "price": "10.00"}]
    return client.post("/orders", json={"user_id": user_id, "items": items})


# ── create ────────────────────────────────────────────────────────────────────

def test_create_order_success(payment_client):
    resp = _create_order(payment_client)
    assert resp.status_code == 201
    body = resp.json()
    assert body["user_id"] == "user-123"
    assert body["status"] == "paid"
    assert float(body["total"]) == 20.0
    assert "id" in body


def test_create_order_calculates_total(payment_client):
    items = [
        {"product_id": "p1", "quantity": 3, "price": "5.00"},
        {"product_id": "p2", "quantity": 1, "price": "15.00"},
    ]
    resp = _create_order(payment_client, items=items)
    assert resp.status_code == 201
    assert float(resp.json()["total"]) == 30.0


def test_create_order_missing_user_id(payment_client):
    resp = payment_client.post("/orders", json={
        "items": [{"product_id": "p1", "quantity": 1, "price": "5.00"}]
    })
    assert resp.status_code == 422


def test_create_order_empty_items_returns_zero_total(payment_client):
    resp = payment_client.post("/orders", json={"user_id": "u1", "items": []})
    assert resp.status_code == 201
    assert float(resp.json()["total"]) == 0.0


# ── get ───────────────────────────────────────────────────────────────────────

def test_get_order_success(payment_client):
    order_id = _create_order(payment_client).json()["id"]
    resp = payment_client.get(f"/orders/{order_id}")
    assert resp.status_code == 200
    assert resp.json()["id"] == order_id


def test_get_order_not_found(payment_client):
    resp = payment_client.get("/orders/does-not-exist")
    assert resp.status_code == 404


# ── list ──────────────────────────────────────────────────────────────────────

def test_list_orders_by_user(payment_client):
    _create_order(payment_client, user_id="alice")
    _create_order(payment_client, user_id="alice")
    _create_order(payment_client, user_id="bob")
    resp = payment_client.get("/orders?user_id=alice")
    assert resp.status_code == 200
    assert len(resp.json()) == 2
    assert all(o["user_id"] == "alice" for o in resp.json())


def test_list_orders_missing_user_id(payment_client):
    resp = payment_client.get("/orders")
    assert resp.status_code == 422


# ── health ────────────────────────────────────────────────────────────────────

def test_health(payment_client):
    assert payment_client.get("/health").status_code == 200
