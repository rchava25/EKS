from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, Field
import uuid


class ProductCreate(BaseModel):
    name: str
    description: str = ""
    price: Decimal
    category: str
    stock: int = 0


class ProductUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    price: Optional[Decimal] = None
    category: Optional[str] = None
    stock: Optional[int] = None


class Product(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    description: str
    price: Decimal
    category: str
    stock: int
    created_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
