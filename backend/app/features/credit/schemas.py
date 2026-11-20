from pydantic import BaseModel
from uuid import UUID
from datetime import datetime
from typing import Optional
from decimal import Decimal

class CustomerBase(BaseModel):
    name: str
    phone: str
    credit_limit: Decimal = Decimal("1000.00")
    notes: Optional[str] = None

class CustomerCreate(CustomerBase):
    id: Optional[UUID] = None

class CustomerResponse(CustomerBase):
    id: UUID
    shop_id: UUID
    current_balance: Decimal
    trust_score: str
    updated_at: datetime

    class Config:
        from_attributes = True

class PaymentCreate(BaseModel):
    id: Optional[UUID] = None
    customer_id: UUID
    amount: Decimal
    method: str = "cash"
    mpesa_code: Optional[str] = None

class PaymentResponse(BaseModel):
    id: UUID
    customer_id: UUID
    amount: Decimal
    method: str
    mpesa_code: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
