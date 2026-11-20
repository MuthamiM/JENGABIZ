from pydantic import BaseModel
from uuid import UUID
from datetime import datetime
from typing import Optional, List, Any
from decimal import Decimal

class SaleItemSchema(BaseModel):
    item_id: UUID
    name: str
    quantity: int
    price: Decimal

class SaleCreate(BaseModel):
    id: Optional[UUID] = None
    shop_id: UUID
    customer_id: Optional[UUID] = None
    type: str = "cash"
    total: Decimal
    items: List[SaleItemSchema]

class SaleResponse(BaseModel):
    id: UUID
    shop_id: UUID
    customer_id: Optional[UUID] = None
    type: str
    total: Decimal
    items: Any
    created_at: datetime

    class Config:
        from_attributes = True
