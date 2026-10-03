import base64
import json
import logging
import uuid
from datetime import datetime

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

from app import config
from app.exceptions import BadRequestError, ConflictError, NotFoundError

logger = logging.getLogger(__name__)


def _now() -> str:
    return datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _get_table():
    dynamodb = boto3.resource("dynamodb", region_name=config.AWS_REGION)
    return dynamodb.Table(config.TABLE_NAME)


def _email_exists(table, email: str, exclude_user_id: str = None) -> bool:
    resp = table.query(
        IndexName="email-index",
        KeyConditionExpression=Key("email").eq(email),
        Limit=1,
    )
    items = resp.get("Items", [])
    if not items:
        return False
    if exclude_user_id and items[0]["user_id"] == exclude_user_id:
        return False
    return True


def create_user(body) -> dict:
    table = _get_table()
    if _email_exists(table, body.email):
        raise ConflictError("Email already exists")
    now = _now()
    item = {
        "user_id": str(uuid.uuid4()),
        "email": body.email,
        "name": body.name,
        "status": "ACTIVE",
        "created_at": now,
        "updated_at": now,
    }
    table.put_item(Item=item)
    logger.info("Created user %s", item["user_id"])
    return item


def get_user(user_id: str) -> dict:
    table = _get_table()
    resp = table.get_item(Key={"user_id": user_id})
    item = resp.get("Item")
    if not item:
        raise NotFoundError("User not found")
    return item


def update_user(user_id: str, body) -> dict:
    updates = {}
    if body.email is not None:
        updates["email"] = body.email
    if body.name is not None:
        updates["name"] = body.name
    if not updates:
        raise BadRequestError("No updatable fields provided")

    table = _get_table()
    existing = table.get_item(Key={"user_id": user_id}).get("Item")
    if not existing:
        raise NotFoundError("User not found")

    if "email" in updates:
        if _email_exists(table, updates["email"], exclude_user_id=user_id):
            raise ConflictError("Email already exists")

    updates["updated_at"] = _now()

    set_parts = []
    expr_names = {}
    expr_values = {}
    for key, val in updates.items():
        expr_names[f"#{key}"] = key
        expr_values[f":{key}"] = val
        set_parts.append(f"#{key} = :{key}")

    resp = table.update_item(
        Key={"user_id": user_id},
        UpdateExpression="SET " + ", ".join(set_parts),
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
        ReturnValues="ALL_NEW",
    )
    logger.info("Updated user %s", user_id)
    return resp["Attributes"]


def delete_user(user_id: str) -> None:
    table = _get_table()
    try:
        table.delete_item(
            Key={"user_id": user_id},
            ConditionExpression="attribute_exists(user_id)",
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise NotFoundError("User not found")
        raise
    logger.info("Deleted user %s", user_id)


def list_users(limit: int = 20, next_token: str = None) -> dict:
    table = _get_table()
    kwargs = {"Limit": limit}
    if next_token:
        kwargs["ExclusiveStartKey"] = json.loads(base64.b64decode(next_token).decode())

    resp = table.scan(**kwargs)
    items = resp.get("Items", [])
    result = {"items": items, "count": len(items)}

    if "LastEvaluatedKey" in resp:
        result["next_token"] = base64.b64encode(
            json.dumps(resp["LastEvaluatedKey"]).encode()
        ).decode()

    return result
