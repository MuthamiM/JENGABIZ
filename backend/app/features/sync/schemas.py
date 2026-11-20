from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from app.features.catalog.schemas import ItemResponse, ItemCreate
from app.features.credit.schemas import CustomerResponse, CustomerCreate, PaymentResponse, PaymentCreate
from app.features.sales.schemas import SaleResponse, SaleCreate

class SyncPushRequest(BaseModel):
    shop_id: str
    items: List[ItemCreate] = []
    customers: List[CustomerCreate] = []
    sales: List[SaleCreate] = []
    payments: List[PaymentCreate] = []

class SyncPullResponse(BaseModel):
    server_timestamp: datetime
    items: List[ItemResponse] = []
    customers: List[CustomerResponse] = []
    sales: List[SaleResponse] = []
    payments: List[PaymentResponse] = []
