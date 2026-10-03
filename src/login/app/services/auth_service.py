import logging

import boto3
from botocore.exceptions import ClientError

from app import config
from app.exceptions import AuthError

logger = logging.getLogger(__name__)


def login(email: str, password: str) -> dict:
    client = boto3.client("cognito-idp", region_name=config.AWS_REGION)
    try:
        resp = client.initiate_auth(
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": email, "PASSWORD": password},
            ClientId=config.COGNITO_CLIENT_ID,
        )
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code in ("NotAuthorizedException", "UserNotFoundException"):
            logger.warning("Login failed for %s: %s", email, code)
            raise AuthError("Invalid credentials")
        raise
    result = resp["AuthenticationResult"]
    return {
        "access_token": result["AccessToken"],
        "id_token": result["IdToken"],
        "refresh_token": result["RefreshToken"],
        "expires_in": result["ExpiresIn"],
    }


def refresh(refresh_token: str) -> dict:
    client = boto3.client("cognito-idp", region_name=config.AWS_REGION)
    try:
        resp = client.initiate_auth(
            AuthFlow="REFRESH_TOKEN_AUTH",
            AuthParameters={"REFRESH_TOKEN": refresh_token},
            ClientId=config.COGNITO_CLIENT_ID,
        )
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code in ("NotAuthorizedException", "UserNotFoundException"):
            logger.warning("Token refresh failed: %s", code)
            raise AuthError("Invalid or expired refresh token")
        raise
    result = resp["AuthenticationResult"]
    return {
        "access_token": result["AccessToken"],
        "id_token": result.get("IdToken", ""),
        "refresh_token": refresh_token,
        "expires_in": result["ExpiresIn"],
    }


def logout(access_token: str) -> None:
    client = boto3.client("cognito-idp", region_name=config.AWS_REGION)
    try:
        client.global_sign_out(AccessToken=access_token)
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "NotAuthorizedException":
            logger.warning("Logout failed: %s", code)
            raise AuthError("Invalid access token")
        raise
