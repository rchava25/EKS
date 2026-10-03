import base64
import sys
import time
from unittest.mock import MagicMock, patch

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from jose import jwt

# lambda_authorizer is importable because conftest.py adds src/authorizer to sys.path
import lambda_authorizer

_KID = "test-kid"
_METHOD_ARN = "arn:aws:execute-api:us-east-1:123456789012:abc/test/GET/resource"


def _generate_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _private_pem(private_key):
    return private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def _int_to_base64url(n):
    length = (n.bit_length() + 7) // 8
    return base64.urlsafe_b64encode(n.to_bytes(length, "big")).rstrip(b"=").decode()


def _build_jwks(private_key, kid=_KID):
    pub = private_key.public_key().public_numbers()
    return {
        "keys": [
            {
                "kty": "RSA",
                "kid": kid,
                "use": "sig",
                "alg": "RS256",
                "n": _int_to_base64url(pub.n),
                "e": _int_to_base64url(pub.e),
            }
        ]
    }


def _make_token(private_key, kid=_KID, exp_offset=3600):
    payload = {
        "sub": "user123",
        "exp": int(time.time()) + exp_offset,
        "iss": "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_test",
    }
    return jwt.encode(payload, _private_pem(private_key), algorithm="RS256", headers={"kid": kid})


def _mock_jwks_response(jwks):
    mock_resp = MagicMock()
    mock_resp.json.return_value = jwks
    mock_resp.raise_for_status.return_value = None
    return mock_resp


def _event(token):
    return {"authorizationToken": f"Bearer {token}", "methodArn": _METHOD_ARN}


@pytest.fixture(autouse=True)
def clear_cache():
    lambda_authorizer._jwks_cache.clear()
    yield
    lambda_authorizer._jwks_cache.clear()


def test_valid_token_allows():
    private_key = _generate_key()
    token = _make_token(private_key)
    jwks = _build_jwks(private_key)

    with patch("requests.get", return_value=_mock_jwks_response(jwks)):
        result = lambda_authorizer.handler(_event(token), None)

    assert result["policyDocument"]["Statement"][0]["Effect"] == "Allow"


def test_expired_token_raises():
    private_key = _generate_key()
    token = _make_token(private_key, exp_offset=-100)
    jwks = _build_jwks(private_key)

    with patch("requests.get", return_value=_mock_jwks_response(jwks)):
        with pytest.raises(Exception, match="Unauthorized"):
            lambda_authorizer.handler(_event(token), None)


def test_wrong_key_raises():
    signing_key = _generate_key()
    verifying_key = _generate_key()
    token = _make_token(signing_key)
    jwks = _build_jwks(verifying_key)

    with patch("requests.get", return_value=_mock_jwks_response(jwks)):
        with pytest.raises(Exception, match="Unauthorized"):
            lambda_authorizer.handler(_event(token), None)


def test_missing_bearer_raises():
    with pytest.raises(Exception, match="Unauthorized"):
        lambda_authorizer.handler(
            {"authorizationToken": "notbearer token", "methodArn": _METHOD_ARN}, None
        )


def test_jwks_cached():
    private_key = _generate_key()
    token = _make_token(private_key)
    jwks = _build_jwks(private_key)

    with patch("requests.get", return_value=_mock_jwks_response(jwks)) as mock_get:
        lambda_authorizer.handler(_event(token), None)
        lambda_authorizer.handler(_event(token), None)

    assert mock_get.call_count == 1
