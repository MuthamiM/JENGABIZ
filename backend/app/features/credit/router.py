from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from typing import List
from uuid import UUID
from app.database import get_db
from app.features.credit.models import Customer, Payment
from app.features.credit.schemas import CustomerCreate, CustomerResponse, PaymentCreate, PaymentResponse

router = APIRouter(prefix="/credit", tags=["Credit Ledger"])

@router.get("/customers", response_model=List[CustomerResponse])
async def list_customers(
    shop_id: UUID,
    sort_by_debt: bool = Query(True),
    db: AsyncSession = Depends(get_db)
):
    query = select(Customer).where(Customer.shop_id == shop_id, Customer.is_deleted == False)
    if sort_by_debt:
        query = query.order_by(desc(Customer.current_balance))
    result = await db.execute(query)
    return result.scalars().all()

@router.post("/customers", response_model=CustomerResponse)
async def create_customer(shop_id: UUID, data: CustomerCreate, db: AsyncSession = Depends(get_db)):
    customer = Customer(shop_id=shop_id, **data.model_dump(exclude_unset=True))
    db.add(customer)
    await db.commit()
    await db.refresh(customer)
    return customer

@router.post("/payments", response_model=PaymentResponse)
async def record_payment(data: PaymentCreate, db: AsyncSession = Depends(get_db)):
    cust_res = await db.execute(select(Customer).where(Customer.id == data.customer_id))
    customer = cust_res.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Mteja hajapatikana / Customer not found")
        
    payment = Payment(**data.model_dump(exclude_unset=True))
    customer.current_balance -= data.amount
    db.add(payment)
    await db.commit()
    await db.refresh(payment)
    return payment
