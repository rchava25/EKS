import os
import sys
from unittest.mock import MagicMock, patch

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

os.environ["TABLE_NAME"] = "test-users"
os.environ["AWS_REGION"] = "us-east-1"
os.environ["COGNITO_CLIENT_ID"] = "test-client-id"
os.environ["COGNITO_USER_POOL_ID"] = "us-east-1_test"
os.environ["COGNITO_JWKS_URL"] = (
    "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_test/.well-known/jwks.json"
)
# Browse service
os.environ["REDIS_HOST"] = "localhost"
os.environ["REDIS_PORT"] = "6379"
os.environ["CACHE_TTL"] = "300"
# Payment service
os.environ["ORDERS_TABLE"] = "test-orders"
os.environ["SHIPPING_DISPATCH_QUEUE"] = "https://sqs.us-east-1.amazonaws.com/123456789/test-shipping-dispatch"
os.environ["PAYMENT_EVENTS_QUEUE"] = "https://sqs.us-east-1.amazonaws.com/123456789/test-payment-events"
# Shipping service
os.environ["SHIPMENTS_TABLE"] = "test-shipments"
# Search service
os.environ["OPENSEARCH_HOST"] = "https://test.opensearch.example.com"
os.environ["OPENSEARCH_INDEX"] = "products"

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
_LOGIN_SRC = os.path.join(_REPO_ROOT, "src/login")
_USERS_SRC = os.path.join(_REPO_ROOT, "src/users")
_BROWSE_SRC = os.path.join(_REPO_ROOT, "src/browse")
_PAYMENT_SRC = os.path.join(_REPO_ROOT, "src/payment")
_SHIPPING_SRC = os.path.join(_REPO_ROOT, "src/shipping")
_SEARCH_SRC = os.path.join(_REPO_ROOT, "src/search")
_AUTHORIZER_SRC = os.path.join(_REPO_ROOT, "src/authorizer")

if _AUTHORIZER_SRC not in sys.path:
    sys.path.insert(0, _AUTHORIZER_SRC)


def _clear_app_cache():
    for key in list(sys.modules.keys()):
        if key == "app" or key.startswith("app."):
            del sys.modules[key]


def _ensure_path_first(path):
    if path in sys.path:
        sys.path.remove(path)
    sys.path.insert(0, path)


@pytest.fixture
def login_client():
    _clear_app_cache()
    _ensure_path_first(_LOGIN_SRC)
    from app.main import app

    yield TestClient(app)
    _clear_app_cache()


@pytest.fixture
def users_client():
    _clear_app_cache()
    _ensure_path_first(_USERS_SRC)
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        dynamodb.create_table(
            TableName="test-users",
            KeySchema=[{"AttributeName": "user_id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "user_id", "AttributeType": "S"},
                {"AttributeName": "email", "AttributeType": "S"},
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "email-index",
                    "KeySchema": [{"AttributeName": "email", "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                }
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        from app.main import app

        yield TestClient(app)
    _clear_app_cache()


@pytest.fixture
def browse_client():
    _clear_app_cache()
    _ensure_path_first(_BROWSE_SRC)
    mock_redis = MagicMock()
    mock_redis.get.return_value = None  # always cache miss by default
    mock_redis.setex.return_value = True
    mock_redis.delete.return_value = True
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        dynamodb.create_table(
            TableName="test-products",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "id", "AttributeType": "S"},
                {"AttributeName": "category", "AttributeType": "S"},
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "category-index",
                    "KeySchema": [{"AttributeName": "category", "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                }
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        os.environ["TABLE_NAME"] = "test-products"
        with patch("redis.Redis", return_value=mock_redis):
            from app.main import app
            yield TestClient(app), mock_redis
    os.environ["TABLE_NAME"] = "test-users"
    _clear_app_cache()


@pytest.fixture
def payment_client():
    _clear_app_cache()
    _ensure_path_first(_PAYMENT_SRC)
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        dynamodb.create_table(
            TableName="test-orders",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "id", "AttributeType": "S"},
                {"AttributeName": "user_id", "AttributeType": "S"},
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "user-index",
                    "KeySchema": [{"AttributeName": "user_id", "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                }
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        sqs = boto3.client("sqs", region_name="us-east-1")
        sqs.create_queue(QueueName="test-payment-events")
        sqs.create_queue(QueueName="test-shipping-dispatch")
        # Override queue URLs with what moto actually creates
        pe_url = sqs.get_queue_url(QueueName="test-payment-events")["QueueUrl"]
        sd_url = sqs.get_queue_url(QueueName="test-shipping-dispatch")["QueueUrl"]
        os.environ["PAYMENT_EVENTS_QUEUE"] = pe_url
        os.environ["SHIPPING_DISPATCH_QUEUE"] = sd_url

        from app.main import app
        yield TestClient(app)
    _clear_app_cache()


@pytest.fixture
def shipping_client():
    _clear_app_cache()
    _ensure_path_first(_SHIPPING_SRC)
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        dynamodb.create_table(
            TableName="test-shipments",
            KeySchema=[{"AttributeName": "order_id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "order_id", "AttributeType": "S"},
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        sqs = boto3.client("sqs", region_name="us-east-1")
        sqs.create_queue(QueueName="test-shipping-dispatch")
        sd_url = sqs.get_queue_url(QueueName="test-shipping-dispatch")["QueueUrl"]
        os.environ["SHIPPING_DISPATCH_QUEUE"] = sd_url

        with patch("app.consumer.run"):
            from app.main import app
            yield TestClient(app)
    _clear_app_cache()


@pytest.fixture
def search_client():
    _clear_app_cache()
    _ensure_path_first(_SEARCH_SRC)
    mock_os_client = MagicMock()
    with patch("opensearchpy.OpenSearch", return_value=mock_os_client), \
         patch("requests_aws4auth.AWS4Auth"), \
         patch("boto3.Session"):
        from app.main import app
        yield TestClient(app), mock_os_client
    _clear_app_cache()
