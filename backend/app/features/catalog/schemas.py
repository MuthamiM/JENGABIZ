from pydantic import BaseModel
from uuid import UUID
from datetime import datetime
from typing import Optional
from decimal import Decimal

class ItemBase(BaseModel):
    name: str
    unit: str = "pcs"
    buy_price: Decimal
    sell_price: Decimal
    quantity: int = 0
    low_stock_level: int = 5

class ItemCreate(ItemBase):
    id: Optional[UUID] = None

class ItemUpdate(BaseModel):
    name: Optional[str] = None
    unit: Optional[str] = None
    buy_price: Optional[Decimal] = None
    sell_price: Optional[Decimal] = None
    quantity: Optional[int] = None
    low_stock_level: Optional[int] = None
    is_deleted: Optional[bool] = None

class ItemResponse(ItemBase):
    id: UUID
    shop_id: UUID
    is_deleted: bool
    updated_at: datetime

    class Config:
        from_attributes = True
