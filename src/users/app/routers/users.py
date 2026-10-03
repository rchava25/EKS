import uuid

from fastapi import APIRouter, Query
from fastapi.responses import Response

from app.exceptions import BadRequestError
from app.models.user import CreateUserRequest, UpdateUserRequest, UserResponse, ListUsersResponse
from app.services import user_service

router = APIRouter()


def _validate_uuid(user_id: str) -> None:
    try:
        uuid.UUID(user_id)
    except ValueError:
        raise BadRequestError("Invalid user_id format")


@router.post("", status_code=201, response_model=UserResponse)
def create_user(body: CreateUserRequest) -> UserResponse:
    return UserResponse(**user_service.create_user(body))


@router.get("", response_model=ListUsersResponse)
def list_users(
    limit: int = Query(default=20, ge=1, le=100),
    next_token: str = Query(default=None),
) -> ListUsersResponse:
    result = user_service.list_users(limit=limit, next_token=next_token)
    return ListUsersResponse(**result)


@router.get("/{user_id}", response_model=UserResponse)
def get_user(user_id: str) -> UserResponse:
    _validate_uuid(user_id)
    return UserResponse(**user_service.get_user(user_id))


@router.put("/{user_id}", response_model=UserResponse)
def update_user(user_id: str, body: UpdateUserRequest) -> UserResponse:
    _validate_uuid(user_id)
    return UserResponse(**user_service.update_user(user_id, body))


@router.delete("/{user_id}", status_code=204)
def delete_user(user_id: str) -> Response:
    _validate_uuid(user_id)
    user_service.delete_user(user_id)
    return Response(status_code=204)
