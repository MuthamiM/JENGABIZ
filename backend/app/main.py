from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.gzip import GZipMiddleware
from app.config import settings
from app.database import engine, Base
from app.middleware.rate_limiter import RateLimiterMiddleware
from app.middleware.idempotency import IdempotencyMiddleware

# Feature Routers
from app.features.auth.router import router as auth_router
from app.features.shop.router import router as shop_router
from app.features.catalog.router import router as catalog_router
from app.features.credit.router import router as credit_router
from app.features.sales.router import router as sales_router
from app.features.sync.router import router as sync_router
from app.features.location.router import router as location_router
from app.features.pricing.router import router as pricing_router
from app.features.buyer.router import router as buyer_router
from app.features.messaging.router import router as messaging_router
from app.features.summary.router import router as summary_router

app = FastAPI(
    title=settings.PROJECT_NAME,
    version="1.0.0",
    description="Scalable Feature-First Backend for Kenyan Dukas and Mama Mbogas",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Compression & Resilience Middlewares
app.add_middleware(GZipMiddleware, minimum_size=500)
app.add_middleware(RateLimiterMiddleware)
app.add_middleware(IdempotencyMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register Feature Routers
app.include_router(auth_router)
app.include_router(shop_router)
app.include_router(catalog_router)
app.include_router(credit_router)
app.include_router(sales_router)
app.include_router(sync_router)
app.include_router(location_router)
app.include_router(pricing_router)
app.include_router(buyer_router)
app.include_router(messaging_router)
app.include_router(summary_router)

@app.on_event("startup")
async def on_startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

@app.get("/health", tags=["Health"])
async def health_check():
    return {
        "status": "healthy",
        "app": settings.PROJECT_NAME,
        "environment": settings.ENVIRONMENT,
        "features_loaded": [
            "auth", "shop", "catalog", "credit", "sales", 
            "sync", "location", "pricing", "buyer", "messaging", "summary"
        ]
    }
