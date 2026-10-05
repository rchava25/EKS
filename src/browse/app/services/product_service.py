import json
import logging
from decimal import Decimal
from typing import Optional

import boto3
import redis
from boto3.dynamodb.conditions import Key

from app.config import AWS_REGION, CACHE_TTL, REDIS_HOST, REDIS_PORT, TABLE_NAME
from app.models.product import Product, ProductCreate, ProductUpdate

logger = logging.getLogger(__name__)

_ddb = boto3.resource("dynamodb", region_name=AWS_REGION)
_table = _ddb.Table(TABLE_NAME)
_cache = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def _cache_key(product_id: str) -> str:
    return f"product:{product_id}"


def _to_dict(item: dict) -> dict:
    return {k: float(v) if isinstance(v, Decimal) else v for k, v in item.items()}


def get_product(product_id: str) -> Optional[Product]:
    cached = _cache.get(_cache_key(product_id))
    if cached:
        return Product(**json.loads(cached))

    resp = _table.get_item(Key={"id": product_id})
    item = resp.get("Item")
    if not item:
        return None

    product = Product(**_to_dict(item))
    _cache.setex(_cache_key(product_id), CACHE_TTL, product.model_dump_json())
    return product


def list_products(category: Optional[str] = None, limit: int = 50) -> list[Product]:
    if category:
        resp = _table.query(
            IndexName="category-index",
            KeyConditionExpression=Key("category").eq(category),
            Limit=limit,
        )
    else:
        resp = _table.scan(Limit=limit)
    return [Product(**_to_dict(item)) for item in resp.get("Items", [])]


def create_product(data: ProductCreate) -> Product:
    product = Product(**data.model_dump())
    _table.put_item(Item=json.loads(product.model_dump_json()))
    return product


def update_product(product_id: str, data: ProductUpdate) -> Optional[Product]:
    existing = get_product(product_id)
    if not existing:
        return None
    updated = existing.model_copy(update={k: v for k, v in data.model_dump().items() if v is not None})
    _table.put_item(Item=json.loads(updated.model_dump_json()))
    _cache.delete(_cache_key(product_id))
    return updated


def delete_product(product_id: str) -> bool:
    if not get_product(product_id):
        return False
    _table.delete_item(Key={"id": product_id})
    _cache.delete(_cache_key(product_id))
    return True
