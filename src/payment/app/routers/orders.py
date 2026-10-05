from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from app.models.order import Order, OrderCreate
from app.services import order_service

router = APIRouter()


@router.post("", response_model=Order, status_code=201)
def create_order(data: OrderCreate):
    return order_service.create_order(data)


@router.get("/{order_id}", response_model=Order)
def get_order(order_id: str):
    order = order_service.get_order(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order


@router.get("", response_model=list[Order])
def list_orders(user_id: str = Query(...)):
    return order_service.list_orders_by_user(user_id)
