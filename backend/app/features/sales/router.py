from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
from uuid import UUID
from app.database import get_db
from app.features.sales.models import Sale
from app.features.sales.schemas import SaleCreate, SaleResponse
from app.features.catalog.models import Item
from app.features.credit.models import Customer

router = APIRouter(prefix="/sales", tags=["Sales"])

@router.post("", response_model=SaleResponse)
async def record_sale(data: SaleCreate, db: AsyncSession = Depends(get_db)):
    sale = Sale(
        id=data.id,
        shop_id=data.shop_id,
        customer_id=data.customer_id,
        type=data.type,
        total=data.total,
        items=[item.model_dump(mode="json") for item in data.items]
    )
    db.add(sale)

    # Automatic stock deduction
    for line in data.items:
        res = await db.execute(select(Item).where(Item.id == line.item_id))
        item = res.scalars().first()
        if item:
            item.quantity -= line.quantity

    # If credit sale, increment customer debt
    if data.type == "credit" and data.customer_id:
        cust_res = await db.execute(select(Customer).where(Customer.id == data.customer_id))
        customer = cust_res.scalars().first()
        if customer:
            customer.current_balance += data.total

    await db.commit()
    await db.refresh(sale)
    return sale
