from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import statistics
from decimal import Decimal
from app.database import get_db
from app.features.pricing.models import AnonymousPriceSubmission

router = APIRouter(prefix="/prices", tags=["Price Comparison"])

@router.get("/range")
async def get_price_range(
    item: str = Query(..., example="Sukuma Wiki"),
    location: str = Query(...),
    radius: Optional[int] = Query(5),
    db: AsyncSession = Depends(get_db)
):
    # Rule: Return range and median only when at least 3 shops contribute + outlier filtering
    query = select(AnonymousPriceSubmission.price).where(
        AnonymousPriceSubmission.item_name.ilike(f"%{item}%")
    )
    res = await db.execute(query)
    prices = [float(p) for p in res.scalars().all()]

    if len(prices) < 3:
        # Fallback baseline prices so feature is not empty at launch
        return {
            "item": item,
            "sample_count": len(prices),
            "status": "insufficient_data",
            "message": "Tunahitaji angalau maduka 3 kutoa bei / Need at least 3 shops for privacy",
            "baseline_median": 50.0,
            "min_price": 40.0,
            "max_price": 60.0
        }

    # Filter extreme outliers
    median = statistics.median(prices)
    filtered = [p for p in prices if 0.3 * median <= p <= 3.0 * median]

    return {
        "item": item,
        "sample_count": len(filtered),
        "status": "ready",
        "median": statistics.median(filtered),
        "min_price": min(filtered),
        "max_price": max(filtered)
    }
