from fastapi import APIRouter
from fastapi.responses import Response

from app.models.auth import LoginRequest, RefreshRequest, LogoutRequest, TokenResponse
from app.services import auth_service

router = APIRouter()


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest) -> TokenResponse:
    result = auth_service.login(body.email, body.password)
    return TokenResponse(**result)


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest) -> TokenResponse:
    result = auth_service.refresh(body.refresh_token)
    return TokenResponse(**result)


@router.post("/logout", status_code=204)
def logout(body: LogoutRequest) -> Response:
    auth_service.logout(body.access_token)
    return Response(status_code=204)
