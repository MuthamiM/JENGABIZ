from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID
from app.database import get_db
from app.features.sync.schemas import SyncPushRequest, SyncPullResponse
from app.features.catalog.models import Item
from app.features.credit.models import Customer, Payment
from app.features.sales.models import Sale

router = APIRouter(prefix="/sync", tags=["Sync Engine"])

@router.post("/push")
async def sync_push(data: SyncPushRequest, db: AsyncSession = Depends(get_db)):
    # Batch upsert with Latest-Write-Wins (LWW) conflict strategy
    shop_uuid = UUID(data.shop_id)
    
    # Process items
    for item_data in data.items:
        if item_data.id:
            res = await db.execute(select(Item).where(Item.id == item_data.id))
            existing = res.scalars().first()
            if existing:
                for k, v in item_data.model_dump(exclude_unset=True).items():
                    setattr(existing, k, v)
            else:
                db.add(Item(shop_id=shop_uuid, **item_data.model_dump()))

    # Process customers
    for cust_data in data.customers:
        if cust_data.id:
            res = await db.execute(select(Customer).where(Customer.id == cust_data.id))
            existing = res.scalars().first()
            if existing:
                for k, v in cust_data.model_dump(exclude_unset=True).items():
                    setattr(existing, k, v)
            else:
                db.add(Customer(shop_id=shop_uuid, **cust_data.model_dump()))

    await db.commit()
    return {"status": "success", "processed_at": datetime.now(timezone.utc)}

@router.get("/pull", response_model=SyncPullResponse)
async def sync_pull(
    shop_id: UUID,
    since: Optional[datetime] = Query(None),
    db: AsyncSession = Depends(get_db)
):
    query_items = select(Item).where(Item.shop_id == shop_id)
    query_customers = select(Customer).where(Customer.shop_id == shop_id)
    query_sales = select(Sale).where(Sale.shop_id == shop_id)

    if since:
        query_items = query_items.where(Item.updated_at > since)
        query_customers = query_customers.where(Customer.updated_at > since)
        query_sales = query_sales.where(Sale.created_at > since)

    items = (await db.execute(query_items)).scalars().all()
    customers = (await db.execute(query_customers)).scalars().all()
    sales = (await db.execute(query_sales)).scalars().all()

    return SyncPullResponse(
        server_timestamp=datetime.now(timezone.utc),
        items=items,
        customers=customers,
        sales=sales,
        payments=[]
    )
