from datetime import datetime, timezone
from typing import Literal
from pydantic import BaseModel, Field


class Shipment(BaseModel):
    order_id: str
    user_id: str
    status: Literal["pending", "shipped", "delivered"] = "pending"
    tracking_number: str = Field(default_factory=lambda: f"TRK-{__import__('uuid').uuid4().hex[:12].upper()}")
    created_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
