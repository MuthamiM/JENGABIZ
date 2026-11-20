from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional
from app.database import get_db
from app.features.location.models import Location
from app.features.location.schemas import LocationResponse

router = APIRouter(prefix="/locations", tags=["Locations"])

@router.get("", response_model=List[LocationResponse])
async def list_locations(
    county: Optional[str] = Query(None),
    area: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db)
):
    query = select(Location)
    if county:
        query = query.where(Location.county == county)
    if area:
        query = query.where(Location.area == area)
    result = await db.execute(query.limit(200))
    return result.scalars().all()
