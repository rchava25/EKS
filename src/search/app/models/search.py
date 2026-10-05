from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, Field


class SearchResult(BaseModel):
    id: str
    name: str
    description: str
    price: Decimal
    category: str
    score: float = 0.0


class SearchResponse(BaseModel):
    total: int
    page: int
    page_size: int
    results: list[SearchResult]
