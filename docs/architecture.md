# 🏛️ Duka Ledger System Architecture

## 1. Architectural Principles
- **Offline-First for Traders**: Mobile clients (Flutter, Kotlin, Swift) operate seamlessly without network connectivity. Local SQLite/Room/CoreData is the authoritative source of truth.
- **Eventual Consistency with Conflict Resolution**: Last-Write-Wins (LWW) based on server-verified UTC `updated_at` timestamps. Soft-deletes (`is_deleted=true`) avoid phantom resurrects.
- **Feature-First Modularity**: Every platform organizes code by functional domain rather than technical layers.
- **Extreme Network & Battery Thrift**:
  - Gzip compression on all payloads.
  - Minimalistic JSON structures.
  - Aggressive 2G/3G failure recovery with exponential backoff and idempotency tokens.

## 2. Shared Data Contract (Canonical Schema)

| Model | Primary Key | Key Attributes | Sync Attributes |
|---|---|---|---|
| **Shop** | `id: UUID` | `name`, `profile_type` (duka/mama_mboga), `payment_number`, `location_id`, `language` | `updated_at`, `is_deleted` |
| **Item** | `id: UUID` | `shop_id`, `name`, `unit`, `buy_price`, `sell_price`, `quantity`, `low_stock_level` | `updated_at`, `is_deleted` |
| **Customer** | `id: UUID` | `shop_id`, `name`, `phone`, `credit_limit`, `trust_score` | `updated_at`, `is_deleted` |
| **Sale** | `id: UUID` | `shop_id`, `customer_id` (nullable), `type` (cash/credit), `total`, `items` (JSON) | `created_at` |
| **Payment** | `id: UUID` | `customer_id`, `amount`, `method` (cash/mpesa), `mpesa_code` (optional) | `created_at` |
| **Location** | `id: UUID` | `county`, `area`, `estate` | Master Directory |

## 3. Distributed Sync Flow

```mermaid
sequenceDiagram
    participant M as Trader Mobile (Android/iOS)
    participant L as Local DB (SQLite/Room)
    participant S as Sync Worker
    participant B as Backend API (FastAPI)
    participant R as Redis Cache
    participant P as PostgreSQL

    Note over M,L: Offline Sales & Credit Record Creation
    M->>L: Insert Sale (id: UUID, created_at: now)
    M->>L: Update Item (quantity: -2, updated_at: now)

    Note over S,B: Network Restored
    S->>L: Query dirty records (updated_at > last_sync_time)
    S->>B: POST /sync/push (Items, Sales, Payments, Customers)
    B->>P: Upsert records with LWW conflict rule
    B->>R: Invalidate shop cache
    B-->>S: 200 OK (server_timestamp)
    S->>B: GET /sync/pull?since={last_sync_time}
    B-->>S: Remote changes (if multi-device)
    S->>L: Update local state & set last_sync_time
```
