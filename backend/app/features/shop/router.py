from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.dependencies import get_current_user_id
from app.features.shop.models import Shop
from app.features.shop.schemas import ShopCreate, ShopUpdate, ShopResponse

router = APIRouter(prefix="/shops", tags=["Shops"])

@router.get("/me", response_model=ShopResponse)
async def get_my_shop(user_id: str = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    query = select(Shop).where(Shop.owner_id == user_id, Shop.is_deleted == False)
    result = await db.execute(query)
    shop = result.scalars().first()
    if not shop:
        raise HTTPException(status_code=404, detail="Duka halijapatikana / Shop not found")
    return shop

@router.put("/me", response_model=ShopResponse)
async def update_my_shop(
    data: ShopUpdate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    query = select(Shop).where(Shop.owner_id == user_id, Shop.is_deleted == False)
    result = await db.execute(query)
    shop = result.scalars().first()
    if not shop:
        # Create shop if not existing
        shop = Shop(owner_id=user_id, **data.model_dump(exclude_unset=True))
        db.add(shop)
    else:
        for k, v in data.model_dump(exclude_unset=True).items():
            setattr(shop, k, v)
    await db.commit()
    await db.refresh(shop)
    return shop

@router.post("/me/publish", response_model=ShopResponse)
async def publish_my_shop(user_id: str = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    query = select(Shop).where(Shop.owner_id == user_id, Shop.is_deleted == False)
    result = await db.execute(query)
    shop = result.scalars().first()
    if not shop:
        raise HTTPException(status_code=404, detail="Duka halijapatikana")
    shop.is_published = True
    await db.commit()
    await db.refresh(shop)
    return shop
