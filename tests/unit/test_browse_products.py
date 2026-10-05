import json
import pytest


# ── helpers ──────────────────────────────────────────────────────────────────

def _create_product(client, **overrides):
    payload = {
        "name": "Widget",
        "description": "A useful widget",
        "price": "9.99",
        "category": "tools",
        "stock": 10,
        **overrides,
    }
    return client.post("/products", json=payload)


# ── create ────────────────────────────────────────────────────────────────────

def test_create_product_success(browse_client):
    client, _ = browse_client
    resp = _create_product(client)
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "Widget"
    assert body["category"] == "tools"
    assert float(body["price"]) == 9.99
    assert "id" in body


def test_create_product_missing_required_field(browse_client):
    client, _ = browse_client
    resp = client.post("/products", json={"name": "No price"})
    assert resp.status_code == 422


# ── get ───────────────────────────────────────────────────────────────────────

def test_get_product_success(browse_client):
    client, _ = browse_client
    product_id = _create_product(client).json()["id"]
    resp = client.get(f"/products/{product_id}")
    assert resp.status_code == 200
    assert resp.json()["id"] == product_id


def test_get_product_uses_cache_on_second_call(browse_client):
    client, mock_redis = browse_client
    product_id = _create_product(client).json()["id"]

    # First call — cache miss → DynamoDB, then setex
    client.get(f"/products/{product_id}")
    assert mock_redis.setex.called

    # Second call — simulate cache hit
    cached_product = {"id": product_id, "name": "Widget", "description": "A useful widget",
                      "price": "9.99", "category": "tools", "stock": 10,
                      "created_at": "2026-01-01T00:00:00+00:00"}
    mock_redis.get.return_value = json.dumps(cached_product)
    resp = client.get(f"/products/{product_id}")
    assert resp.status_code == 200
    assert resp.json()["id"] == product_id


def test_get_product_not_found(browse_client):
    client, _ = browse_client
    resp = client.get("/products/does-not-exist")
    assert resp.status_code == 404


# ── list ──────────────────────────────────────────────────────────────────────

def test_list_products_empty(browse_client):
    client, _ = browse_client
    resp = client.get("/products")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_products_returns_created(browse_client):
    client, _ = browse_client
    _create_product(client, name="A")
    _create_product(client, name="B")
    resp = client.get("/products")
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_list_products_filter_by_category(browse_client):
    client, _ = browse_client
    _create_product(client, name="Hammer", category="tools")
    _create_product(client, name="Shirt", category="clothing")
    resp = client.get("/products?category=tools")
    assert resp.status_code == 200
    names = [p["name"] for p in resp.json()]
    assert "Hammer" in names
    assert "Shirt" not in names


# ── update ────────────────────────────────────────────────────────────────────

def test_update_product_success(browse_client):
    client, _ = browse_client
    product_id = _create_product(client).json()["id"]
    resp = client.put(f"/products/{product_id}", json={"price": "19.99"})
    assert resp.status_code == 200
    assert float(resp.json()["price"]) == 19.99


def test_update_product_not_found(browse_client):
    client, _ = browse_client
    resp = client.put("/products/ghost-id", json={"price": "5.00"})
    assert resp.status_code == 404


# ── delete ────────────────────────────────────────────────────────────────────

def test_delete_product_success(browse_client):
    client, _ = browse_client
    product_id = _create_product(client).json()["id"]
    resp = client.delete(f"/products/{product_id}")
    assert resp.status_code == 204
    assert client.get(f"/products/{product_id}").status_code == 404


def test_delete_product_not_found(browse_client):
    client, _ = browse_client
    resp = client.delete("/products/ghost-id")
    assert resp.status_code == 404


# ── health ────────────────────────────────────────────────────────────────────

def test_health(browse_client):
    client, _ = browse_client
    assert client.get("/health").status_code == 200
