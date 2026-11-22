# JENGABIZ Backend API Documentation

The JENGABIZ backend is built on **C# ASP.NET Core 8.0** with **Entity Framework Core**, **SQLite**, and **Redis caching**. It runs inside Docker and provides RESTful endpoints with OpenAPI / Swagger documentation.

---

## 1. Environment & Base URLs

| Environment | Base URL |
| :--- | :--- |
| **Public Landing Page** | `https://jengabiz.mftechnologies.org` |
| **Production API** | `https://jengabiz-api.mftechnologies.org` |
| **Local Host / API** | `http://localhost:5080` |
| **Swagger Interactive UI** | `http://localhost:5080/swagger` |
| **Swagger OpenAPI JSON** | `http://localhost:5080/swagger/v1/swagger.json` |
| **Android Emulator** | `http://10.0.2.2:5080` |
| **Physical Phone (USB / LAN)** | `http://<HOST_IP>:5080` (or `adb reverse tcp:5080 tcp:5080`) |
| **Docker Network** | `http://jengabiz-api:5080` |

---

## 2. Docker Architecture

The services are composed via `docker-compose.yml`:
- **`jengabiz-api`**: C# .NET 8 Web API container exposed on port `5080`.
- **`jengabiz-email-otp`**: Email verification service exposed only on host loopback port `5081`.
- **`jengabiz-landing`**: Static landing page exposed only on host loopback port `5082`.
- **`jengabiz-redis`**: Redis 7 Alpine cache container exposed on port `6380` (internal `6379`).
- **Business API database**: SQLite file stored at `/app/data/duka_ledger.db` in named Docker volume `jengabiz_db_data`.
- **JengaBiz mobile account database**: SQLite file stored at `/data/jengabiz.sqlite` in named Docker volume `jengabiz_account_data`. It stores mobile account profiles, salted password hashes, sessions, and each account's stock items.

Cloudflare Tunnel sends the public landing hostname to port `5082`, sends `/email-auth/*` on the API hostname to port `5081`, and sends all other API paths to port `5080`. Keeping mobile account and stock paths under `/email-auth/` uses the existing tunnel route.

To start or restart the stack:
```bash
docker compose up -d --build
```

---

## 3. Redis Caching Layer

JengaBiz uses a **Cache-Aside Pattern**:
1. **L1 In-Memory Cache**: Zero-latency lookup (<1ms) inside the client and backend.
2. **L2 Redis Cache**: Shared distributed cache for hot inventory, top sellers, and aggregate KPIs.
3. **L3 Persistent Database**: SQLite / PostgreSQL via EF Core.

### Cache Keys & Invalidation Rules

| Key Pattern | Description | TTL | Invalidation Trigger |
| :--- | :--- | :--- | :--- |
| `items:all` | Full 500-item inventory catalog | 30 mins | On stock adjustment / item creation |
| `item:{id}` | Single item details | 30 mins | On item update or price change |
| `user:{id}` | User session and shop profile | 60 mins | On profile edit or logout |
| `api:catalog:{shopId}` | Catalog items per shop | 15 mins | On item add / delete |
| `summary:daily:{shopId}` | Daily sales and revenue summary | 5 mins | On new sale recorded |

---

## 4. API Endpoints Reference

### Authentication

#### `POST /email-auth/request-otp`
Sends a 6-digit, single-use account verification code to the supplied email address. Codes expire after 10 minutes. Resend is limited to once per minute and five sends per hour per address.
- **Request Body**:
  ```json
  {
    "email": "owner@example.com"
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "success": true,
    "message": "A verification code was sent to your email address."
  }
  ```

#### `POST /email-auth/verify-otp`
Verifies and consumes the latest email code. A successful response includes a short-lived, single-use `verificationToken` for account registration or recovery migration. It is not an API session.
- **Request Body**:
  ```json
  {
    "email": "owner@example.com",
    "otp": "123456"
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "success": true,
    "verified": true,
    "verificationToken": "<single-use-token>"
  }
  ```

Incorrect or expired codes return `400`; resend limits return `429`; missing server-side email configuration returns `503`. The email service uses Resend credentials from the host environment and does not include a mail API key in the Flutter app.

#### `POST /email-auth/register` and `POST /email-auth/migrate`
Creates a mobile account after email verification. Migration is for an account previously saved only on the phone. Both endpoints require the verification token and create the account and initial stock in one SQLite transaction. An existing email returns `409` without overwriting its account or stock.

```json
{
  "email": "owner@example.com",
  "verificationToken": "<single-use-token>",
  "name": "Shop Owner",
  "shopName": "My Shop",
  "phone": "",
  "password": "<password>",
  "items": []
}
```

Successful responses return a bearer `sessionToken` and a profile without password data. Passwords are hashed server-side with scrypt and per-account random salts; account ownership is bound to the authenticated session.

#### `POST /email-auth/login`
Signs in with email and password, returns a bearer session token and the account profile, and throttles repeated failures by IP and email. Invalid credentials share one generic response.

#### `GET /email-auth/stock/items` and `PUT /email-auth/stock/items`
Both routes require `Authorization: Bearer <sessionToken>`. GET returns only the signed-in account's inventory. PUT replaces that account's inventory in one database transaction. Payloads are capped and validated before writing.

#### `POST /email-auth/logout`
Revokes the current bearer session.

---

### Shop Management

#### `GET /shops/me`
Retrieves shop details for the authenticated user.
- **Headers**: `X-Shop-Id: <shop-uuid>` or `Authorization: Bearer <token>`
- **Response `200 OK`**:
  ```json
  {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "Nairobi Central Duka",
    "profileType": "GeneralDuka",
    "paymentNumber": "247247",
    "language": "en",
    "isPublished": true,
    "phone": "+254712345678"
  }
  ```

#### `PUT /shops/me`
Updates shop information.
- **Headers**: `X-Shop-Id: <shop-uuid>`
- **Request Body**:
  ```json
  {
    "name": "Nairobi Central Duka",
    "profileType": "GeneralDuka",
    "paymentNumber": "247247",
    "openingHours": "07:00 - 22:00",
    "isPublished": true
  }
  ```

---

### Catalog & Stock Management

#### `GET /catalog/items`
Returns all products and inventory levels for a shop.
- **Query Parameter**: `shopId=<uuid>`
- **Response `200 OK`**:
  ```json
  [
    {
      "id": "item_1",
      "shopId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "name": "Jogoo Maize Flour (2kg)",
      "unit": "packet",
      "buyPrice": "180.00",
      "sellPrice": "210.00",
      "quantity": 45,
      "lowStockLevel": 10,
      "isPerishable": false,
      "isDeleted": 0,
      "updatedAt": "2026-11-21T18:00:00Z"
    }
  ]
  ```

#### `POST /catalog/items`
Adds a product to the catalog.
- **Request Body**:
  ```json
  {
    "shopId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "Salit Cooking Oil (1L)",
    "unit": "bottle",
    "buyPrice": "280.00",
    "sellPrice": "340.00",
    "quantity": 25,
    "lowStockLevel": 5,
    "isPerishable": false
  }
  ```

---

### Credit & Customer Ledger

#### `GET /credit/customers`
Returns a list of credit customers with balance and trust scores.
- **Query Parameter**: `shopId=<uuid>`
- **Response `200 OK`**:
  ```json
  [
    {
      "id": "cust_1",
      "shopId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "name": "Mama Kevin",
      "phone": "+254701234567",
      "creditLimit": "5000.00",
      "currentBalance": "1450.00",
      "trustScore": "92",
      "notes": "Pays every Friday"
    }
  ]
  ```

#### `POST /credit/payments`
Records a debt repayment (Cash or M-Pesa).
- **Request Body**:
  ```json
  {
    "customerId": "cust_1",
    "amount": "500.00",
    "method": "Mpesa",
    "mpesaCode": "SDF382KL09"
  }
  ```

---

### Sales & Analytics

#### `POST /sales`
Records a transaction (Cash or Credit) and decrements stock.
- **Request Body**:
  ```json
  {
    "shopId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "customerId": null,
    "type": "Cash",
    "total": "420.00",
    "itemsJson": "[{\"id\":\"item_1\",\"qty\":2,\"price\":210}]"
  }
  ```

#### `GET /summary/daily`
Returns daily financial KPIs (revenue, cost, profit, total sales).
- **Query Parameter**: `shopId=<uuid>`
- **Response `200 OK`**:
  ```json
  {
    "date": "2026-11-21",
    "totalRevenue": 84900000.0,
    "totalCost": 65600000.0,
    "netProfit": 19300000.0,
    "profitMargin": 22.73,
    "unitsSold": 101318,
    "transactionsCount": 420
  }
  ```

---

### Offline Synchronization

#### `GET /sync/pull`
Synchronizes changes since the last local update timestamp.
- **Query Parameters**: `shopId=<uuid>&since=2026-11-21T00:00:00Z`
- **Response `200 OK`**:
  ```json
  {
    "items": [],
    "customers": [],
    "sales": [],
    "payments": [],
    "syncedAt": "2026-11-21T18:30:00Z"
  }
  ```

---

## 5. Mobile App Connection (Flutter)

In `flutter_app/lib/services/api_service.dart`, configure the endpoint:
```dart
// For physical Android device connected via ADB:
// Run: adb reverse tcp:5080 tcp:5080
JengaApiService.instance.configure(
  url: 'http://127.0.0.1:5080',
);

// For Android emulator:
JengaApiService.instance.configure(
  url: 'http://10.0.2.2:5080',
);
```

