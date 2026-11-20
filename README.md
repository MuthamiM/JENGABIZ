# 🏪 Duka Ledger (JENGABIZ)

> **Feature-First, Multi-Platform Architecture for Kenyan Micro-Retailers & Communities**
> Scalable to 3,000+ Concurrent Customers | Offline-First Mobile | High-Availability Distributed Backend

---

## 🌟 Overview

**Duka Ledger** is a purpose-built commerce, credit ledger, and community discovery ecosystem designed for Kenyan **Duka** (corner retail shop) owners and **Mama Mboga** (fresh produce) vendors. It bridges offline-first edge operations with cloud synchronization and a buyer-facing community directory.

### 👥 Developer Work Split

- **Developer A (Shop & Stock)**:
  - Shop Setup & Profile Selection (Duka vs. Mama Mboga)
  - Product Catalog (loose units, starter packs, quick entry)
  - Calculator (running totals, quick-tap grid, auto-deduct stock)
  - Stock Management (adjustments, restock alerts, run-out estimates, profit view)
  - Mama Mboga Extras (morning purchases, spoilage tracker, sell-first flags)
  - Nearby Price Comparison UI

- **Developer B (Credit & Community Backend)**:
  - Backend API Foundations & OpenAPI Specification
  - Phone OTP Authentication & Multi-Tenant Security
  - Offline Sync & Backup Engine (UUID + `updated_at` latest-wins conflict resolution)
  - Credit Ledger (customer debts, balances, credit limits, trust score)
  - Automated M-Pesa SMS payment reconciliation
  - Reminders & Receipts (single/bulk SMS & WhatsApp)
  - Public Shop Pages, Location Directory, Buyer Portal & Notice Board
  - Live Info (weather, crowd-sourced traffic & matatu/boda fare reports)

---

## 📁 Repository Structure

```
JENGABIZ/
├── backend/            # 🐍 Python (FastAPI, SQLAlchemy, Redis, Celery) - Primary Backend
├── backend-csharp/     # 🟣 C# (.NET 8 ASP.NET Core Web API) - Enterprise Backend
├── backend-java/       # ☕ Java (Spring Boot 3, JPA, Flyway) - Enterprise Backend
├── mobile-flutter/     # 🎯 Dart/Flutter (Android & iOS) - Offline-first Cross-Platform Client
├── android-kotlin/     # 🤖 Kotlin (Android Jetpack, Room, Hilt) - Native Android Client
├── ios-swift/          # 🍎 Swift (SwiftUI, Combine, CoreData) - Native iPhone Client
├── frontend-web/       # 🌐 TypeScript (Next.js 14, React, Tailwind) - Buyer Discovery Portal
├── docs/               # 📚 Architectural, Scaling, and API Documentation
├── docker-compose.yml  # 🐳 Multi-service orchestration for development & production
└── Makefile            # 🛠️ Unified project task runner
```

---

## 🚀 Git Branches

- `main` - Stable, production-ready releases
- `martindev` - Active feature branch for Martin
- `staging` - Pre-production integration, sync testing, and QA

---

## ⚡ Scaling to 3,000+ Concurrent Customers

The backend architecture is engineered to effortlessly sustain **3,000+ concurrent active customers**:
1. **Async Non-Blocking I/O**: FastAPI with `uvloop` & `asyncpg` / ASP.NET Core minimal APIs.
2. **Database Connection Pooling**: PostgreSQL pool sizing (25 min, 100 max) with PgBouncer.
3. **Redis Tiered Caching**:
   - Sub-millisecond OTP verification and rate limiting (Sliding window token bucket).
   - Price range and location directory distributed caching.
4. **Idempotency & Resilience**:
   - `Idempotency-Key` headers for safe offline sync replays on flaky 2G/3G networks.
   - Gzip/Brotli payload compression to preserve trader data bundles.
5. **Cursor-based Pagination**: Infinite scroll and sync without expensive `OFFSET` table scans.

---

## 🛠️ Quick Start

```bash
# Clone the repository
git clone https://github.com/cantroll/JENGABIZ.git
cd JENGABIZ

# Start the full stack with Docker Compose
docker compose up -d

# Check service health
make health-check
```
