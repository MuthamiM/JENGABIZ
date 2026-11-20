from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
import redis.asyncio as aioredis
from app.config import settings

class IdempotencyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        idempotency_key = request.headers.get("Idempotency-Key")
        if not idempotency_key or request.method not in ["POST", "PUT", "PATCH"]:
            return await call_next(request)

        try:
            r = aioredis.from_url(settings.REDIS_URL, decode_responses=False)
            cache_key = f"idempotency:{idempotency_key}"
            cached_res = await r.get(cache_key)
            if cached_res:
                return Response(content=cached_res, media_type="application/json", headers={"X-Cache": "HIT-IDEMPOTENT"})
        except Exception:
            return await call_next(request)

        response = await call_next(request)
        return response
