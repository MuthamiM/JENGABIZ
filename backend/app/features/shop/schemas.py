from pydantic import BaseModel
from uuid import UUID
from datetime import datetime
from typing import Optional

class ShopBase(BaseModel):
    name: str
    profile_type: str = "duka"
    payment_number: Optional[str] = None
    location_id: Optional[UUID] = None
    language: str = "sw"
    opening_hours: Optional[str] = "6:00 AM - 9:00 PM"

class ShopCreate(ShopBase):
    pass

class ShopUpdate(BaseModel):
    name: Optional[str] = None
    profile_type: Optional[str] = None
    payment_number: Optional[str] = None
    location_id: Optional[UUID] = None
    language: Optional[str] = None
    opening_hours: Optional[str] = None
    is_published: Optional[bool] = None

class ShopResponse(ShopBase):
    id: UUID
    is_published: bool
    photo_url: Optional[str] = None
    updated_at: datetime

    class Config:
        from_attributes = True
