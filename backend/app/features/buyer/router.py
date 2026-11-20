from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional
from uuid import UUID
from app.database import get_db
from app.features.shop.models import Shop
from app.features.buyer.models import PreOrder, CommunityNotice

router = APIRouter(prefix="/buyer", tags=["Buyer & Community Portal"])

@router.get("/shops")
async def browse_shops(
    county: Optional[str] = Query(None),
    area: Optional[str] = Query(None),
    profile_type: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db)
):
    query = select(Shop).where(Shop.is_published == True, Shop.is_deleted == False)
    if profile_type:
        query = query.where(Shop.profile_type == profile_type)
    res = await db.execute(query.limit(50))
    return res.scalars().all()

@router.post("/pre-orders")
async def place_preorder(
    shop_id: UUID,
    buyer_name: str,
    buyer_phone: str,
    items_summary: str,
    db: AsyncSession = Depends(get_db)
):
    order = PreOrder(
        shop_id=shop_id,
        buyer_name=buyer_name,
        buyer_phone=buyer_phone,
        items_summary=items_summary
    )
    db.add(order)
    await db.commit()
    await db.refresh(order)
    return order

@router.get("/notices")
async def get_community_notices(location_id: UUID, db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(CommunityNotice).where(CommunityNotice.location_id == location_id))
    return res.scalars().all()
