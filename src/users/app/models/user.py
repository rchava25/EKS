from typing import Optional, List
from pydantic import BaseModel, EmailStr, Field


class CreateUserRequest(BaseModel):
    email: EmailStr
    name: str = Field(..., min_length=1, max_length=128)


class UpdateUserRequest(BaseModel):
    email: Optional[EmailStr] = None
    name: Optional[str] = Field(None, min_length=1, max_length=128)


class UserResponse(BaseModel):
    user_id: str
    email: str
    name: str
    status: str
    created_at: str
    updated_at: str


class ListUsersResponse(BaseModel):
    items: List[UserResponse]
    count: int
    next_token: Optional[str] = None
