import time
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
import redis.asyncio as aioredis
from app.config import settings

class RateLimiterMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.redis = None

    async def get_redis(self):
        if self.redis is None:
            self.redis = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        return self.redis

    async def dispatch(self, request: Request, call_next):
        # Exempt health and docs endpoints
        if request.url.path in ["/health", "/docs", "/openapi.json"]:
            return await call_next(request)

        client_ip = request.client.host if request.client else "unknown"
        user_key = f"rate_limit:{client_ip}"
        
        try:
            r = await self.get_redis()
            current_minute = int(time.time() // 60)
            key = f"{user_key}:{current_minute}"
            
            count = await r.incr(key)
            if count == 1:
                await r.expire(key, 60)
                
            if count > settings.RATE_LIMIT_PER_MINUTE:
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Tafadhali subiri kidogo / Too many requests. Rate limit exceeded."}
                )
        except Exception:
            # Degrade gracefully if Redis is temporarily unreachable
            pass

        return await call_next(request)
