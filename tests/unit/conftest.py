import os
import sys

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

_LOGIN_SRC = "/workshop/src/login"
_USERS_SRC = "/workshop/src/users"
_AUTHORIZER_SRC = "/workshop/src/authorizer"

# Add authorizer src at module load time so test_authorizer.py can import lambda_authorizer
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
