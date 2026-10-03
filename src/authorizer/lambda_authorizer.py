import logging
import os

import requests
from jose import jwk, jwt
from jose.exceptions import ExpiredSignatureError, JWTError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

COGNITO_JWKS_URL = os.environ["COGNITO_JWKS_URL"]

# Module-level cache keyed by kid; persists across warm Lambda invocations.
_jwks_cache: dict = {}


def _get_public_key(kid: str):
    if kid not in _jwks_cache:
        response = requests.get(COGNITO_JWKS_URL, timeout=5)
        response.raise_for_status()
        for key_data in response.json().get("keys", []):
            _jwks_cache[key_data["kid"]] = jwk.construct(key_data)
    if kid not in _jwks_cache:
        raise Exception("Unauthorized")
    return _jwks_cache[kid]


def _generate_policy(principal_id: str, effect: str, resource: str) -> dict:
    return {
        "principalId": principal_id,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": resource,
                }
            ],
        },
    }


def handler(event, context):
    try:
        auth_header = event.get("authorizationToken", "")
        if not auth_header.startswith("Bearer "):
            raise Exception("Unauthorized")
        token = auth_header[len("Bearer "):]

        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        if not kid:
            raise Exception("Unauthorized")

        public_key = _get_public_key(kid)

        jwt.decode(
            token,
            public_key,
            algorithms=["RS256"],
            options={"verify_aud": False},
        )

        logger.info("Token authorized for: %s", event.get("methodArn"))
        return _generate_policy("user", "Allow", event["methodArn"])

    except (JWTError, ExpiredSignatureError) as exc:
        logger.warning("JWT validation failed: %s", exc)
        raise Exception("Unauthorized")
    except Exception as exc:
        if str(exc) == "Unauthorized":
            raise
        logger.error("Unexpected authorizer error: %s", exc)
        raise Exception("Unauthorized")
