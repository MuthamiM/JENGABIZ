# JENGABIZ Backend API Documentation

The JENGABIZ backend is built on **C# ASP.NET Core 8.0** with **Entity Framework Core**, **SQLite**, and **Redis caching**. It runs inside Docker and provides RESTful endpoints with OpenAPI / Swagger documentation.

---

## 1. Environment & Base URLs

| Environment | Base URL |
| :--- | :--- |
| **Public Landing Page** | `https://jengabiz.mftechnologies.org` |
| **Production Mobile API** | `https://jengabiz.mftechnologies.org` |
| **Legacy Production API Host** | `https://jengabiz-api.mftechnologies.org` |
| **Local Host / API** | `http://localhost:5080` |
| **Swagger Interactive UI** | `http://localhost:5080/swagger` |
| **Swagger OpenAPI JSON** | `http://localhost:5080/swagger/v1/swagger.json` |
| **Android Emulator** | `http://10.0.2.2:5080` |
| **Physical Phone (USB / LAN)** | `http://<HOST_IP>:5080` (or `adb reverse tcp:5080 tcp:5080`) |
| **Docker Gateway** | `http://jengabiz-api-gateway:80` |

---

## 2. Docker Architecture

The services are composed via `docker-compose.yml`:
- **`jengabiz-api`**: C# .NET 8 Web API container on the Docker network at port `5080`.
- **`jengabiz-api-gateway`**: Nginx gateway exposed on host port `5080`; it routes `/email-auth/*` to the account service and all other paths to the C# API.
- **`jengabiz-email-otp`**: Email verification service exposed only on host loopback port `5081`.
- **`jengabiz-landing`**: Static landing page exposed only on host loopback port `5082`.
- **`jengabiz-redis`**: Redis 7 Alpine cache container exposed on port `6380` (internal `6379`).
- **Business API database**: SQLite file stored at `/app/data/duka_ledger.db` in named Docker volume `jengabiz_db_data`.
- **JengaBiz mobile account database**: SQLite file stored at `/data/jengabiz.sqlite` in named Docker volume `jengabiz_account_data`. It stores mobile account profiles, salted password hashes, sessions, stock items, and private account-scoped product images.

Cloudflare Tunnel sends the public landing hostname to port `5082` and the legacy API hostname to the gateway on port `5080`. The landing Nginx also proxies `/email-auth/*`, `/catalog/*`, `/summary/*`, `/sync/*`, and `/health` to the gateway. Mobile app requests use the landing hostname so account sync does not depend on a separate API DNS record. The gateway sends `/email-auth/*` to the Node account service on the Docker network at port `5081`, and all other API paths to the C# API. Both Nginx proxies preserve Cloudflare client IP headers for account rate limits.

The JengaBiz account service also joins the existing `mf_mf-network` Docker network and submits confirmed suspended-account review requests to the M&F Technologies contact intake. M&F creates those requests as tickets in Admin > Tickets. JengaBiz verifies the account password itself and sends only the customer's account and contact details to M&F; the password is never forwarded.

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
Sends a 6-digit, single-use account verification code to the supplied email address. Codes expire after 10 minutes. Resend is limited to once per minute and five sends per hour per address. The optional `purpose` is `account_verification` (default) or `password_reset`. Suspended accounts cannot receive verification or password-reset codes; the API returns `403 ACCOUNT_SUSPENDED` with the configured MF Technologies support contact.
- **Request Body**:
  ```json
  {
    "email": "owner@example.com",
    "purpose": "password_reset"
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
  "county": "Nairobi",
  "referralCode": "",
  "password": "<password>",
  "items": []
}
```

Referral code and county are optional. When a referral code is used, the Android app detects the device's location and reverse-geocodes the county; it sends the county only, and the service assigns the country as Kenya (`KE`). The inviter must have enabled location before the code can be applied. Successful responses return a bearer `sessionToken` and a profile without password data. Passwords are hashed server-side with scrypt and per-account random salts; account ownership is bound to the authenticated session.

#### `POST /email-auth/login`
Signs in with email and password, returns a bearer session token and the account profile, and throttles repeated failures by IP and email. Invalid credentials share one generic response. A correct password for a suspended account returns `403 ACCOUNT_SUSPENDED` and MF Technologies support details. Sessions remain valid until the user signs out or the server revokes the session. The server stores only the token hash; the Android app stores the token in secure storage.

#### `POST /email-auth/reset-password`
Public route that requires an email verification grant returned by `POST /email-auth/verify-otp`. Accepts `{ "email": "owner@example.com", "verificationToken": "<single-use-token>", "newPassword": "<password>" }`. The new password must contain at least 8 characters. Suspended accounts are rejected before a password change, including when the account is suspended after an OTP was issued. Otherwise, the server hashes it with a new random salt, consumes the verification grant, and revokes all sessions for that account. The user signs in again with the new password.

#### `POST /email-auth/support/request`
Creates a suspension-review ticket in the M&F Technologies admin ticket queue. The customer confirms this action in the app and provides the email and current password for JengaBiz to verify the suspended account. The password is never sent to M&F. The ticket contains the account name, email, optional phone, shop name, account ID, and request for review. The endpoint limits requests per source IP and caps successful tickets per account. A successful response includes the M&F ticket ID; if the M&F service is unavailable, the app continues to show the configured support email and phone numbers.

```json
{
  "email": "owner@example.com",
  "password": "<current-password>"
}
```

#### `GET /email-auth/me`
Returns the signed-in account profile and renews the active session. The app uses this route on startup to resume a saved secure session without asking for the password again.

#### `GET /email-auth/referrals` and `PUT /email-auth/referrals/location`
Both routes require a bearer session. GET returns the account's opaque referral code, referred-shop counts, total JengaBiz points, points remaining to the 200-point threshold, and whether redemption is available. PUT accepts the county detected by the Android app; the service accepts only one of Kenya's supported counties and stores the country as `KE`. The app keeps GPS coordinates on-device and sends only the detected county. A county is locked after the account earns referral points so previously issued rewards cannot be changed by editing location.

A referred shop must enter a valid code during signup, be detected in Kenya, and complete email verification. The account service awards 50 points when the inviter and new shop are in the same county, and 75 points when they are in different Kenyan counties. International referrals are not supported. A new account can earn once; the service rejects self-referrals that reuse the inviter's email or phone. Existing accounts receive an opaque referral code during database migration. At 200 points, the account is marked as having reached the future redemption threshold. Points are not cash, and redemption or payout is not implemented.

#### `GET /email-auth/stock/items` and `PUT /email-auth/stock/items`
Both routes require `Authorization: Bearer <sessionToken>`. GET returns only the signed-in account's inventory. PUT replaces that account's inventory in one database transaction. Payloads are capped and validated before writing.

#### `GET /email-auth/stock/images/:itemId` and `PUT /email-auth/stock/images/:itemId`
Both routes require the signed-in account's bearer token. PUT accepts a base64 JPEG, PNG, or WebP image up to 1 MB for an existing stock item; image bytes are stored in the account-scoped SQLite database, with a 32 MB image-storage limit per shop. GET streams the private image and disables caching at shared proxies. The stock item stores only the `stock-image:<itemId>` reference, never the image payload.

Each stock record stores its name, category, SKU, selling and cost prices, remaining quantity, units sold, low-stock threshold, and image URL in the account SQLite database. The Flutter app also keeps an account-scoped offline copy and syncs the full inventory when connected.

#### `POST /email-auth/notifications/device` and `DELETE /email-auth/notifications/device`
Register or remove the current signed-in phone's Firebase Cloud Messaging token. Requests require a bearer session. Registration accepts `deviceToken` and `platform` (`android` or `ios`). Device tokens are stored against the authenticated account and never returned to the app. On an existing item's transition to 50%-sold, low, or zero stock, the service sends a push to other registered devices if Firebase server credentials are configured.

The account service reads a Firebase service account from `FIREBASE_SERVICE_ACCOUNT_FILE` or `FIREBASE_SERVICE_ACCOUNT_JSON`. The JengaBiz server uses `deployment/secrets/jengabiz-fcm-service-account.json`, which is ignored by Git and mounted read-only into the email/account container. Its dedicated service account has only the `cloudmessaging.messages.create` permission. Never include this credential in an app build, release, or repository.

Firebase Cloud Messaging is configured for the Android app (`com.dukaledger.duka_ledger`) in project `jengabiz-mftechnologies`. `flutter_app/android/app/google-services.json` and `flutter_app/lib/firebase_options.dart` contain public client configuration; the private sender key remains server-only. Stock updates send remote alerts for 50%-sold, low-stock, and out-of-stock transitions to the account's other registered devices. The device that made the change gets its local alert instead of a duplicate push.

The app's Stock & Inventory and Analytics screens export a multi-page landscape PDF containing the JengaBiz logo, shop summary, all stock fields, and MF Technologies contact details (`info@mftechnologies.org`, `0748329410`, `0712742991`). The file opens the platform share/print sheet.

#### `POST /email-auth/logout`
Revokes the current bearer session. The optional `deviceToken` also removes that phone's push registration. The app clears its local session first and sends server revocation in the background so sign-out does not wait for a slow network.

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

