from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from app.models.product import Product, ProductCreate, ProductUpdate
from app.services import product_service

router = APIRouter()


@router.get("", response_model=list[Product])
def list_products(
    category: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
):
    return product_service.list_products(category=category, limit=limit)


@router.get("/{product_id}", response_model=Product)
def get_product(product_id: str):
    product = product_service.get_product(product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.post("", response_model=Product, status_code=201)
def create_product(data: ProductCreate):
    return product_service.create_product(data)


@router.put("/{product_id}", response_model=Product)
def update_product(product_id: str, data: ProductUpdate):
    product = product_service.update_product(product_id, data)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.delete("/{product_id}", status_code=204)
def delete_product(product_id: str):
    if not product_service.delete_product(product_id):
        raise HTTPException(status_code=404, detail="Product not found")
