# JengaBiz Dart QA

## Automated coverage

Run from `flutter_app/`:

```sh
flutter test
flutter analyze
```

The Dart tests check home and stock rendering, horizontal scrolling, stock back navigation, the keyboard-resized product form and widget teardown, immediate welcome-screen display after the native splash, password hashing, HTTPS enforcement, email-only OTP routes, secure-session API routing, consent policy links, and referral-link visibility and URL.

The email verification API has focused server tests. Run from the project root:

```sh
node --test backend/email-otp/server.test.mjs
```

The phone keeps an offline profile and inventory cache. The production account service stores profiles, scrypt password hashes, revocable sessions, and per-account stock rows in the persistent `jengabiz_account_data` SQLite volume. Passwords are never sent to the C# catalog API or written in plaintext. New accounts require a short-lived, single-use email verification grant; older phone-only accounts can migrate after verifying the same email. Email codes expire after 10 minutes, resend is throttled, and verification allows at most five attempts. Phone number is optional and is never used for verification. Signed-in sessions resume after closing the app; authenticated activity renews the session for up to 90 days. Sign out explicitly to end a session. Fingerprint/face sign-in remains available as an optional method after sign-out.

## Release smoke checks

- Launch with a clean install and confirm the welcome page appears immediately after the Android splash screen.
- Create an account with a valid email and password; confirm a 6-digit verification code arrives by email. Phone is optional.
- Enter an incorrect or expired code and confirm access is denied.
- Resend a code, confirm the prior code no longer works, then verify the newest code and confirm the dashboard opens.
- Sign out, then test email/password sign-in and fingerprint sign-in separately; confirm fingerprint sign-in is an underlined link below the main button.
- Sign in, close and reopen the app, and confirm the secure session returns directly to the shop dashboard without another password prompt. Confirm a lost connection still opens the locally cached inventory and synchronizes later.
- Create an account and sign in from a second device; confirm the same profile and stock are returned from the server database.
- Sign in to an existing phone-only account, verify the email code, and confirm the local profile and inventory migrate without replacing existing server records.
- Adjust stock while online, sign in on another device, and confirm each user's items stay isolated. Repeat an adjustment offline and confirm it syncs after sign-in.
- During sign-up, confirm account creation is blocked until the Terms/Privacy and essential app-storage checkbox is selected, then verify the acceptance timestamp is recorded. Confirm no cookie banner appears in the app.
- Open Terms, Privacy, and Cookies & App Storage from sign-up; Profile > Privacy & Legal contains Terms and Privacy only.
- Confirm Profile > App updates checks the latest-version manifest, shows the JengaBiz-colored update page, and presents the Android installer only after the APK checksum passes. Android must ask the user to confirm installation.
- Expand Refer & Earn and allow device location; confirm there are no editable country/county fields and the invite URL contains an opaque code rather than account email. Verify the app accepts Kenya and blocks other countries. Open the link, enter the displayed code during signup, and verify by email. Confirm same-county signups add 50 JengaBiz points, different Kenyan counties add 75, each referred account counts once, and no international referral rate is offered.
- Open Home, Analytics, Stock, Notifications, and Profile; verify navigation and scrolling.
- Open Stock and confirm there is no inventory-metrics card, title, or dispatch banner; the PDF/add/sort icons remain, search stays visible, and status/category filters scroll away with the inventory.
- Add or adjust stock and confirm the dashboard totals update.
- Add a product with name, category, SKU, buying and selling prices, quantity, and low-stock threshold. Edit its details, restock with `+`, record a sale with `−`, remove it, and confirm each change syncs to the account and appears on a second device.
- Add a category from the product form and filter inventory by category. Upload a product photo, then verify its preview and that the image appears in the inventory card.
- With network disabled, add a product photo, close and reopen the app, and confirm both the photo and product remain available. Re-enable network, wait for sync, and confirm the photo appears on a second signed-in device. Confirm previously viewed photos load from the local cache while offline.
- Export a stock PDF from Stock & Inventory and Analytics. Confirm the JengaBiz logo, shop name, current totals, item ID/name/category/SKU, buying and selling prices, on-hand and sold quantities, reorder point, image URL, and MF Technologies email/phone details appear in the shareable PDF.
- Confirm Biometric login, Push notifications, and Weekly email report default to on, remain saved after app restart, and preserve a user's explicit off selection.
- On Android 13 or later, allow notification permission. Sell through 50% of a product's starting stock, reduce another item from above its reorder point to low stock, and then to zero; confirm local alerts appear. With Firebase configured, repeat from another signed-in phone and confirm server-delivered FCM alerts arrive. Turn notifications off and confirm the device is deregistered and receives no more remote stock alerts.
- Add the JengaBiz Stock widget from the Android home-screen widget picker; verify item, unit, and low-stock counts update after changing stock, and tapping the widget opens the app.
- Disable network access during startup and verify the app remains usable with cached inventory or presents the startup retry screen.
- Download the APK from `https://jengabiz.mftechnologies.org/` and from the GitHub release. Confirm both responses are APK bytes with `application/vnd.android.package-archive`, and compare the SHA-256 file.
- Check the public landing and API hostnames from outside the local network. They must have a trusted HTTPS certificate; users do not install a self-signed certificate.
- Open the landing page, Terms, Privacy, and Cookies & App Storage pages. Confirm they use the app's blue/neutral palette and each page has the cookie notice controls.
- Choose Accept all, Reject all non-essential, and custom cookie preferences. Confirm the choice persists across pages and that footer Cookie settings reopens the preferences dialog. Confirm no analytics or advertising cookies are set by the current site.

## Android release

Version `1.0.6+7` is signed with the dedicated local Android release keystore. Keep `flutter_app/android/key.properties` and `flutter_app/android/app/jengabiz-release.jks` backed up securely; both are ignored by Git and must be reused to sign future updates. Do not publish either file. The APK itself is signed, and visitors use the site's trusted HTTPS certificate without installing anything.

Versions through v1.0.5 need one manual install of v1.0.6 because they do not contain the updater. From v1.0.6 onward, the app checks `/downloads/latest.json` on startup and from Profile > App updates. It downloads only HTTPS APKs from `jengabiz.mftechnologies.org`, verifies the SHA-256 from the manifest, then opens Android's package installer. Android still requires the user to approve installation. The landing-page download uses `/downloads/latest/JengaBiz.apk`; future app versions can update that APK and the manifest while keeping the same link.

## Deployment dependency

The production API URL defaults to `https://jengabiz-api.mftechnologies.org`. The marketing page is served at `https://jengabiz.mftechnologies.org/`. Email OTP, account, and account-scoped stock endpoints use `/email-auth/*` and route to the account service on port 5081; the existing C# API remains on port 5080.

The landing, API, and email OTP routes are live. Server-side Resend credentials and a sender address on the configured custom domain are stored in the ignored root `.env`; never place them in Flutter code or a mobile build. The email container uses IPv4 DNS resolution for Resend because the host's Docker network has no usable IPv6 route. Keep the sender domain's sending records verified; receive-only MX records are not required by this app. For local development, set `JENGABIZ_API_BASE_URL` with `--dart-define` to a local API URL.

Firebase Cloud Messaging uses project `jengabiz-mftechnologies` and the Android package `com.dukaledger.duka_ledger`. The API container reads the sender credential from the Git-ignored `deployment/secrets/jengabiz-fcm-service-account.json` file mounted read-only. Its service account has only the `cloudmessaging.messages.create` permission. Keep this private key on the server; the Android config and `firebase_options.dart` contain client configuration only.

## Verification history (2026-11-22; v1.0.3+4)

- All 14 Flutter tests pass, Flutter analysis reports no issues, and all 9 account API tests pass, including 50 same-county points, 75 different-Kenyan-county points, and rejection of unsupported county names.
- Release `1.0.3+4` built successfully as `com.dukaledger.duka_ledger` and passed APK v1/v2 signature verification with the existing release certificate. APK size is 27,389,539 bytes; SHA-256 is `6a438076218b62a6b2b894fccba538215d23947a6157a8a64df70df4beaf0ecd`.
- The signed APK installed over the connected phone's existing package without an uninstall. JengaBiz opened to its welcome screen; no account was signed in during the check.
- The account API restarted healthy after the additive county-detection migration. Existing accounts and stock rows were left intact; the pre-migration SQLite snapshot passed `PRAGMA integrity_check`.
- The local and public HTTPS landing download endpoints return HTTP 200 with `application/vnd.android.package-archive`, the 1.0.3 attachment name, and the expected APK size.
- `git diff --check` passed.

## Previous release (2026-11-23; v1.0.4+5)

- Release `1.0.4+5` built as `com.dukaledger.duka_ledger`, passed APK v1/v2 signature verification, and matches the v1.0.3 release certificate.
- APK size is 27,375,312 bytes; SHA-256 is `05d0f0d0b1cd3c0669dc6a63e031c4a324b6947fcdc5c5698548d901f617fdb0`.
- The home Total Revenue card now uses the bottom navigation blue. Refer & Earn shows a plain total-points value and referral link.

## Previous release (2026-11-23; v1.0.5+6)

- Added a required sign-up agreement for Terms, Privacy, and essential app storage; saved its version and timestamp locally. Added the full policies to sign-up and Profile; the native app has no cookie banner.
- Rebuilt the JengaBiz landing page using the app palette, with feature, setup, privacy, FAQ, About, and contact sections; added Terms, Privacy, and Cookies & App Storage pages.
- Expanded the product-record information and changed marketing sections to a full-width, flat layout without content cards. Reduced the logo size, made legal pages responsive on phone screens, prevented horizontal overflow, and hid the browser scrollbar while keeping touch/keyboard scrolling available.
- Added persistent website cookie preferences for accepting all, rejecting non-essential categories, or saving custom Analytics and Marketing choices. The current site has no analytics or advertising tools enabled.
- Release `1.0.5+6` built as `com.dukaledger.duka_ledger` and passed APK v1/v2 signature verification with the existing release certificate. APK size is 27,447,257 bytes; SHA-256 is `17f740b24180468128a587bf40392a804cd92c05491667f11f87deb94526fd47`.

## Current release (2026-11-23; v1.0.6+7)

- Profile > Privacy & Legal now contains Terms of Use and Privacy Policy only. Sign-up still explains and records acceptance of essential app storage.
- Added a JengaBiz-blue update screen, startup version check, Profile > App updates entry, checksum-verified APK download, and Android installer handoff.
- Added a stable latest APK path and version manifest so updater-enabled versions can install the latest release directly.
- Release `1.0.6+7` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,525,470 bytes; SHA-256 is `9bc42be00a7e1530418e30b7b2e04fe4ff7a17cc13a16f4b103a60bc1299cb4f`.
