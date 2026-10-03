import pytest
from botocore.exceptions import ClientError
from unittest.mock import MagicMock, patch


def _client_error(code):
    return ClientError(
        {"Error": {"Code": code, "Message": "error"}},
        "InitiateAuth",
    )


def test_refresh_success(login_client):
    with patch("boto3.client") as mock_boto3:
        mock_cognito = MagicMock()
        mock_boto3.return_value = mock_cognito
        mock_cognito.initiate_auth.return_value = {
            "AuthenticationResult": {
                "AccessToken": "new-access-token",
                "ExpiresIn": 3600,
            }
        }

        resp = login_client.post(
            "/auth/refresh",
            json={"refresh_token": "valid-refresh-token"},
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["access_token"] == "new-access-token"
    assert body["refresh_token"] == "valid-refresh-token"
    assert body["expires_in"] == 3600


def test_refresh_expired_token(login_client):
    with patch("boto3.client") as mock_boto3:
        mock_cognito = MagicMock()
        mock_boto3.return_value = mock_cognito
        mock_cognito.initiate_auth.side_effect = _client_error("NotAuthorizedException")

        resp = login_client.post(
            "/auth/refresh",
            json={"refresh_token": "expired-token"},
        )

    assert resp.status_code == 401
