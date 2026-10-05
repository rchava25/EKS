import json
import logging
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional

import boto3
from boto3.dynamodb.conditions import Key

from app.config import AWS_REGION, ORDERS_TABLE, PAYMENT_EVENTS_QUEUE, SHIPPING_DISPATCH_QUEUE
from app.models.order import Order, OrderCreate

logger = logging.getLogger(__name__)

_ddb = boto3.resource("dynamodb", region_name=AWS_REGION)
_table = _ddb.Table(ORDERS_TABLE)
_sqs = boto3.client("sqs", region_name=AWS_REGION)


def _to_dict(item: dict) -> dict:
    return {k: float(v) if isinstance(v, Decimal) else v for k, v in item.items()}


def get_order(order_id: str) -> Optional[Order]:
    resp = _table.get_item(Key={"id": order_id})
    item = resp.get("Item")
    return Order(**_to_dict(item)) if item else None


def list_orders_by_user(user_id: str) -> list[Order]:
    resp = _table.query(
        IndexName="user-index",
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    return [Order(**_to_dict(item)) for item in resp.get("Items", [])]


def create_order(data: OrderCreate) -> Order:
    total = sum(item.price * item.quantity for item in data.items)
    order = Order(user_id=data.user_id, items=data.items, total=total)

    # Persist as pending
    _table.put_item(Item=json.loads(order.model_dump_json()))

    # Simulate payment (always succeeds in this mock)
    order.status = "paid"
    order.updated_at = datetime.now(timezone.utc).isoformat()
    _table.put_item(Item=json.loads(order.model_dump_json()))

    # Publish to shipping-dispatch so shipping-service picks it up
    payload = {
        "order_id": order.id,
        "user_id":  order.user_id,
        "items":    [i.model_dump(mode="json") for i in order.items],
        "total":    str(order.total),
        "status":   order.status,
    }
    _sqs.send_message(QueueUrl=SHIPPING_DISPATCH_QUEUE, MessageBody=json.dumps(payload))
    _sqs.send_message(QueueUrl=PAYMENT_EVENTS_QUEUE,    MessageBody=json.dumps(payload))

    logger.info("order_id=%s status=%s total=%s", order.id, order.status, order.total)
    return order
