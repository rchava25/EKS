import json
import logging
import time

import boto3

from app.config import AWS_REGION, SHIPPING_DISPATCH_QUEUE
from app.services import shipping_service

logger = logging.getLogger(__name__)

_sqs = boto3.client("sqs", region_name=AWS_REGION)


def run():
    logger.info("SQS consumer started queue=%s", SHIPPING_DISPATCH_QUEUE)
    while True:
        try:
            resp = _sqs.receive_message(
                QueueUrl=SHIPPING_DISPATCH_QUEUE,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20,
            )
            for msg in resp.get("Messages", []):
                try:
                    body = json.loads(msg["Body"])
                    order_id = body["order_id"]
                    user_id  = body["user_id"]

                    if not shipping_service.get_shipment(order_id):
                        shipping_service.create_shipment(order_id, user_id)

                    _sqs.delete_message(
                        QueueUrl=SHIPPING_DISPATCH_QUEUE,
                        ReceiptHandle=msg["ReceiptHandle"],
                    )
                except Exception as e:
                    logger.error("failed to process message: %s", e)
        except Exception as e:
            logger.error("SQS receive error: %s", e)
            time.sleep(5)
