# 📈 Scalability Blueprint: Supporting 3,000+ Concurrent Customers

## 1. Traffic Characterization
- **Total active users**: 3,000+ concurrent shopkeepers & buyers.
- **Peak request rate**: ~1,500 requests per second (RPS) during morning opening (06:30 - 08:30) and evening market rush (17:30 - 20:30).
- **Network constraints**: Edge connections on Safaricom / Airtel 3G/4G with occasional packet drop.

## 2. Multi-Tier Scaling Strategy

### A. Non-Blocking Async Microservices
- Python backend runs under `uvicorn` with `uvloop` (high performance C-based event loop).
- Zero blocking thread operations; all database calls run over `asyncpg`.

### B. Database Tier & Connection Pooling
- PostgreSQL tuned with:
  - `max_connections = 300`
  - `shared_buffers = 1GB`
  - `effective_cache_size = 3GB`
- SQLAlchemy Async Engine configured with:
  - `pool_size = 25`
  - `max_overflow = 50`
  - `pool_recycle = 1800`

### C. Redis In-Memory Layer
1. **Sliding-Window Rate Limiter**: 100 requests/minute per authenticated user, preventing brute-force SMS OTP draining and denial-of-service.
2. **OTP & Session Cache**: Keys expire in 300s (5 minutes).
3. **Price Range Query Cache**: Cached per `(item_id, location_id)` with a 15-minute TTL.
4. **Celery Task Queue**: Async offloading of SMS reminders, WhatsApp notifications, and receipt generation.

### D. Cursor-Based Pagination
Traditional offset pagination (`LIMIT 50 OFFSET 50000`) degrades $O(N)$ with large customer tables.
Duka Ledger enforces:
```sql
SELECT * FROM customers 
WHERE shop_id = :shop_id AND updated_at < :cursor_timestamp 
ORDER BY updated_at DESC LIMIT 50;
```
Ensuring deterministic $O(1)$ index lookups.

### E. Idempotency Middleware
All mutation requests (`POST /sync/push`, `POST /sales`, `POST /payments`) require an `Idempotency-Key: <UUID>` header. Redis caches responses for 24 hours, preventing duplicate debt additions or inventory double-deductions when retrying on unstable cellular connections.
