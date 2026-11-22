# JengaBiz Dart QA

## Automated coverage

Run from `flutter_app/`:

```sh
flutter test
flutter analyze
```

The Dart tests check home and stock rendering, horizontal scrolling, stock back navigation, immediate welcome-screen display after the native splash, password hashing, HTTPS enforcement, email-only OTP routes, secure-session API routing, consent policy links, and referral-link visibility and URL.

The email verification API has focused server tests. Run from the project root:

```sh
node --test backend/email-otp/server.test.mjs
```

The phone keeps an offline profile and inventory cache. The production account service stores profiles, scrypt password hashes, revocable sessions, and per-account stock rows in the persistent `jengabiz_account_data` SQLite volume. Passwords are never sent to the C# catalog API or written in plaintext. New accounts require a short-lived, single-use email verification grant; older phone-only accounts can migrate after verifying the same email. Email codes expire after 10 minutes, resend is throttled, and verification allows at most five attempts. Phone number is optional and is never used for verification.

## Release smoke checks

- Launch with a clean install and confirm the welcome page appears immediately after the Android splash screen.
- Create an account with a valid email and password; confirm a 6-digit verification code arrives by email. Phone is optional.
- Enter an incorrect or expired code and confirm access is denied.
- Resend a code, confirm the prior code no longer works, then verify the newest code and confirm the dashboard opens.
- Sign out, then test email/password sign-in and fingerprint sign-in separately; confirm fingerprint sign-in is an underlined link below the main button.
- Create an account and sign in from a second device; confirm the same profile and stock are returned from the server database.
- Sign in to an existing phone-only account, verify the email code, and confirm the local profile and inventory migrate without replacing existing server records.
- Adjust stock while online, sign in on another device, and confirm each user's items stay isolated. Repeat an adjustment offline and confirm it syncs after sign-in.
- Open Terms of Use and Privacy Policy from the consent links.
- Open Home, Analytics, Stock, Notifications, and Profile; verify navigation and scrolling.
- Add or adjust stock and confirm the dashboard totals update.
- Add the JengaBiz Stock widget from the Android home-screen widget picker; verify item, unit, and low-stock counts update after changing stock, and tapping the widget opens the app.
- Disable network access during startup and verify the app remains usable with cached inventory or presents the startup retry screen.
- Download the APK from `https://jengabiz.mftechnologies.org/` and from the GitHub release. Confirm both responses are APK bytes with `application/vnd.android.package-archive`, and compare the SHA-256 file.
- Check the public landing and API hostnames from outside the local network. They must have a trusted HTTPS certificate; users do not install a self-signed certificate.

## Android release

Version `1.0.1+2` is signed with the dedicated local Android release keystore. Keep `flutter_app/android/key.properties` and `flutter_app/android/app/jengabiz-release.jks` backed up securely; both are ignored by Git and must be reused to sign future updates. Do not publish either file. The APK itself is signed, and visitors use the site's trusted HTTPS certificate without installing anything.

## Deployment dependency

The production API URL defaults to `https://jengabiz-api.mftechnologies.org`. The marketing page is served at `https://jengabiz.mftechnologies.org/`. Email OTP, account, and account-scoped stock endpoints use `/email-auth/*` and route to the account service on port 5081; the existing C# API remains on port 5080.

The landing, API, and email OTP routes are live. Server-side Resend credentials and a sender address on the configured custom domain are stored in the ignored root `.env`; never place them in Flutter code or a mobile build. The email container uses IPv4 DNS resolution for Resend because the host's Docker network has no usable IPv6 route. Keep the sender domain's sending records verified; receive-only MX records are not required by this app. For local development, set `JENGABIZ_API_BASE_URL` with `--dart-define` to a local API URL.

## Current verification (2026-11-22)

- Flutter analysis reported no issues; all 11 Flutter tests passed.
- All 5 email, account, and SQLite stock service tests passed.
- `git diff --check` passed.
- An unauthenticated request to the public `/email-auth/stock/items` route returned HTTP 401, confirming the tunnel forwards to the protected account service.
- The public landing page's versioned APK URL returned HTTP 206 with `application/vnd.android.package-archive`, an attachment filename ending in `.apk`, and APK ZIP signature bytes (`PK`). The binary and published checksum match SHA-256 `e155a69f255845976d5f219a4abb2fec74be767f07addb80eacb57f801d04736`.
- The landing page and API host use valid Cloudflare HTTPS certificates with HSTS. Public visitors do not need an origin certificate installed on their devices.
