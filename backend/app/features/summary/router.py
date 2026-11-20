from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from uuid import UUID
from datetime import datetime, timezone
from app.database import get_db
from app.features.sales.models import Sale
from app.features.credit.models import Customer
from app.features.catalog.models import Item

router = APIRouter(prefix="/summary", tags=["Daily Summary"])

@router.get("/daily")
async def get_daily_summary(shop_id: UUID, db: AsyncSession = Depends(get_db)):
    sales_res = await db.execute(select(func.sum(Sale.total)).where(Sale.shop_id == shop_id))
    total_sales = sales_res.scalar() or 0.0

    debt_res = await db.execute(select(func.sum(Customer.current_balance)).where(Customer.shop_id == shop_id))
    total_credit = debt_res.scalar() or 0.0

    low_stock_res = await db.execute(
        select(Item).where(Item.shop_id == shop_id, Item.quantity <= Item.low_stock_level, Item.is_deleted == False)
    )
    low_stock_items = low_stock_res.scalars().all()

    return {
        "date": datetime.now(timezone.utc).date(),
        "total_sales": float(total_sales),
        "total_credit_owed": float(total_credit),
        "low_stock_count": len(low_stock_items),
        "low_stock_items": [{"id": str(i.id), "name": i.name, "quantity": i.quantity} for i in low_stock_items]
    }
