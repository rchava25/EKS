import boto3
import pytest
from moto import mock_aws


def _seed_shipment(order_id="order-abc", user_id="user-123"):
    """Insert a shipment directly into the mocked DynamoDB table."""
    from app.services import shipping_service
    return shipping_service.create_shipment(order_id=order_id, user_id=user_id)


# ── get ───────────────────────────────────────────────────────────────────────

def test_get_shipment_success(shipping_client):
    _seed_shipment()
    resp = shipping_client.get("/shipping/order-abc")
    assert resp.status_code == 200
    body = resp.json()
    assert body["order_id"] == "order-abc"
    assert body["user_id"] == "user-123"
    assert body["status"] == "pending"
    assert body["tracking_number"].startswith("TRK-")


def test_get_shipment_not_found(shipping_client):
    resp = shipping_client.get("/shipping/no-such-order")
    assert resp.status_code == 404


# ── update status ─────────────────────────────────────────────────────────────

def test_update_shipment_status_shipped(shipping_client):
    _seed_shipment(order_id="order-xyz")
    resp = shipping_client.patch("/shipping/order-xyz/status?status=shipped")
    assert resp.status_code == 200
    assert resp.json()["status"] == "shipped"


def test_update_shipment_status_delivered(shipping_client):
    _seed_shipment(order_id="order-del")
    resp = shipping_client.patch("/shipping/order-del/status?status=delivered")
    assert resp.status_code == 200
    assert resp.json()["status"] == "delivered"


def test_update_shipment_status_not_found(shipping_client):
    resp = shipping_client.patch("/shipping/ghost-order/status?status=shipped")
    assert resp.status_code == 404


# ── health ────────────────────────────────────────────────────────────────────

def test_health(shipping_client):
    assert shipping_client.get("/health").status_code == 200
