from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional
from uuid import UUID
from app.database import get_db
from app.features.catalog.models import Item
from app.features.catalog.schemas import ItemCreate, ItemUpdate, ItemResponse

router = APIRouter(prefix="/catalog", tags=["Catalog"])

@router.get("/items", response_model=List[ItemResponse])
async def list_items(
    shop_id: UUID,
    search: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db)
):
    query = select(Item).where(Item.shop_id == shop_id, Item.is_deleted == False)
    if search:
        query = query.where(Item.name.ilike(f"%{search}%"))
    result = await db.execute(query.limit(100))
    return result.scalars().all()

@router.post("/items", response_model=ItemResponse)
async def create_item(shop_id: UUID, data: ItemCreate, db: AsyncSession = Depends(get_db)):
    item = Item(shop_id=shop_id, **data.model_dump(exclude_unset=True))
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item
