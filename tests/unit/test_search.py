from decimal import Decimal
from typing import Optional
from unittest.mock import MagicMock

import pytest


def _opensearch_response(hits: list[dict], total: Optional[int] = None) -> dict:
    """Build a minimal OpenSearch search response dict."""
    return {
        "hits": {
            "total": {"value": total if total is not None else len(hits)},
            "hits": [
                {
                    "_id": h["id"],
                    "_score": h.get("score", 1.0),
                    "_source": {k: v for k, v in h.items() if k not in ("id", "score")},
                }
                for h in hits
            ],
        }
    }


# ── search happy paths ────────────────────────────────────────────────────────

def test_search_returns_results(search_client):
    client, mock_os = search_client
    mock_os.search.return_value = _opensearch_response([
        {"id": "p1", "name": "Laptop", "description": "Fast laptop",
         "price": Decimal("999.99"), "category": "electronics"},
    ])
    resp = client.get("/search?q=laptop")
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 1
    assert body["results"][0]["name"] == "Laptop"
    assert body["page"] == 1
    assert body["page_size"] == 20


def test_search_empty_results(search_client):
    client, mock_os = search_client
    mock_os.search.return_value = _opensearch_response([])
    resp = client.get("/search?q=nonexistent")
    assert resp.status_code == 200
    assert resp.json()["total"] == 0
    assert resp.json()["results"] == []


def test_search_pagination(search_client):
    client, mock_os = search_client
    mock_os.search.return_value = _opensearch_response([], total=50)
    resp = client.get("/search?q=shoes&page=3&page_size=10")
    assert resp.status_code == 200
    assert resp.json()["page"] == 3
    assert resp.json()["page_size"] == 10
    # Verify from/size were passed to OpenSearch
    call_body = mock_os.search.call_args[1]["body"]
    assert call_body["from"] == 20   # (page-1) * page_size
    assert call_body["size"] == 10


def test_search_category_filter(search_client):
    client, mock_os = search_client
    mock_os.search.return_value = _opensearch_response([])
    client.get("/search?q=shirt&category=clothing")
    call_body = mock_os.search.call_args[1]["body"]
    filters = call_body["query"]["bool"]["filter"]
    assert any("term" in f for f in filters)


def test_search_price_range_filter(search_client):
    client, mock_os = search_client
    mock_os.search.return_value = _opensearch_response([])
    client.get("/search?q=phone&min_price=100&max_price=500")
    call_body = mock_os.search.call_args[1]["body"]
    filters = call_body["query"]["bool"]["filter"]
    range_filters = [f for f in filters if "range" in f]
    assert len(range_filters) == 1
    price_range = range_filters[0]["range"]["price"]
    assert price_range["gte"] == 100
    assert price_range["lte"] == 500


def test_search_multiple_results(search_client):
    client, mock_os = search_client
    mock_os.search.return_value = _opensearch_response([
        {"id": "p1", "name": "Running Shoes", "description": "Fast",
         "price": Decimal("80.00"), "category": "footwear", "score": 1.5},
        {"id": "p2", "name": "Hiking Boots", "description": "Durable",
         "price": Decimal("120.00"), "category": "footwear", "score": 1.0},
    ])
    resp = client.get("/search?q=shoes")
    assert resp.status_code == 200
    assert len(resp.json()["results"]) == 2


# ── validation ────────────────────────────────────────────────────────────────

def test_search_missing_query(search_client):
    client, _ = search_client
    resp = client.get("/search")
    assert resp.status_code == 422


def test_search_empty_query(search_client):
    client, _ = search_client
    resp = client.get("/search?q=")
    assert resp.status_code == 422


# ── health ────────────────────────────────────────────────────────────────────

def test_health(search_client):
    client, _ = search_client
    assert client.get("/health").status_code == 200
