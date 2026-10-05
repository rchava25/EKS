from datetime import datetime, timezone
from decimal import Decimal
from typing import Literal, Optional
from pydantic import BaseModel, Field
import uuid


class OrderItem(BaseModel):
    product_id: str
    quantity: int
    price: Decimal


class OrderCreate(BaseModel):
    user_id: str
    items: list[OrderItem]


class Order(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    items: list[OrderItem]
    total: Decimal
    status: Literal["pending", "paid", "failed"] = "pending"
    created_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
