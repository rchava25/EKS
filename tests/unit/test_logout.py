import pytest
from botocore.exceptions import ClientError
from unittest.mock import MagicMock, patch


def _client_error(code):
    return ClientError(
        {"Error": {"Code": code, "Message": "error"}},
        "GlobalSignOut",
    )


def test_logout_success(login_client):
    with patch("boto3.client") as mock_boto3:
        mock_cognito = MagicMock()
        mock_boto3.return_value = mock_cognito
        mock_cognito.global_sign_out.return_value = {}

        resp = login_client.post(
            "/auth/logout",
            json={"access_token": "valid-access-token"},
        )

    assert resp.status_code == 204


def test_logout_invalid_token(login_client):
    with patch("boto3.client") as mock_boto3:
        mock_cognito = MagicMock()
        mock_boto3.return_value = mock_cognito
        mock_cognito.global_sign_out.side_effect = _client_error("NotAuthorizedException")

        resp = login_client.post(
            "/auth/logout",
            json={"access_token": "invalid-token"},
        )

    assert resp.status_code == 401
