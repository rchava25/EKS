import logging
from datetime import datetime, timezone
from typing import Optional

import boto3
from botocore.exceptions import ClientError

from app.config import AWS_REGION, SHIPMENTS_TABLE
from app.models.shipment import Shipment

logger = logging.getLogger(__name__)

_ddb = boto3.resource("dynamodb", region_name=AWS_REGION)
_table = _ddb.Table(SHIPMENTS_TABLE)


def get_shipment(order_id: str) -> Optional[Shipment]:
    resp = _table.get_item(Key={"order_id": order_id})
    item = resp.get("Item")
    return Shipment(**item) if item else None


def create_shipment(order_id: str, user_id: str) -> Shipment:
    shipment = Shipment(order_id=order_id, user_id=user_id)
    _table.put_item(Item=shipment.model_dump(mode="json"))
    logger.info("shipment created order_id=%s tracking=%s", order_id, shipment.tracking_number)
    return shipment


def update_status(order_id: str, status: str) -> Optional[Shipment]:
    now = datetime.now(timezone.utc).isoformat()
    try:
        resp = _table.update_item(
            Key={"order_id": order_id},
            UpdateExpression="SET #s = :s, updated_at = :u",
            ConditionExpression="attribute_exists(order_id)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": status, ":u": now},
            ReturnValues="ALL_NEW",
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return None
        raise
    item = resp.get("Attributes")
    return Shipment(**item) if item else None
