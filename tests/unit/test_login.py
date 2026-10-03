import pytest
from botocore.exceptions import ClientError
from unittest.mock import MagicMock, patch


def _mock_auth_result():
    return {
        "AuthenticationResult": {
            "AccessToken": "access-token-abc",
            "IdToken": "id-token-def",
            "RefreshToken": "refresh-token-ghi",
            "ExpiresIn": 3600,
        }
    }


def _client_error(code):
    return ClientError(
        {"Error": {"Code": code, "Message": "error"}},
        "InitiateAuth",
    )


def test_login_success(login_client):
    with patch("boto3.client") as mock_boto3:
        mock_cognito = MagicMock()
        mock_boto3.return_value = mock_cognito
        mock_cognito.initiate_auth.return_value = _mock_auth_result()

        resp = login_client.post(
            "/auth/login",
            json={"email": "user@example.com", "password": "Pass1234!"},
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["access_token"] == "access-token-abc"
    assert body["id_token"] == "id-token-def"
    assert body["refresh_token"] == "refresh-token-ghi"
    assert body["expires_in"] == 3600


def test_login_invalid_credentials(login_client):
    with patch("boto3.client") as mock_boto3:
        mock_cognito = MagicMock()
        mock_boto3.return_value = mock_cognito
        mock_cognito.initiate_auth.side_effect = _client_error("NotAuthorizedException")

        resp = login_client.post(
            "/auth/login",
            json={"email": "user@example.com", "password": "wrong"},
        )

    assert resp.status_code == 401


def test_login_missing_password(login_client):
    resp = login_client.post("/auth/login", json={"email": "user@example.com"})
    assert resp.status_code == 422
