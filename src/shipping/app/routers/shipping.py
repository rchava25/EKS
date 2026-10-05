from fastapi import APIRouter, HTTPException
from app.models.shipment import Shipment
from app.services import shipping_service

router = APIRouter()


@router.get("/{order_id}", response_model=Shipment)
def get_shipment(order_id: str):
    shipment = shipping_service.get_shipment(order_id)
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    return shipment


@router.patch("/{order_id}/status")
def update_status(order_id: str, status: str):
    shipment = shipping_service.update_status(order_id, status)
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    return shipment
