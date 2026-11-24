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

The phone keeps an offline profile and inventory cache. The production account service stores profiles, scrypt password hashes, revocable sessions, and per-account stock rows in the persistent `jengabiz_account_data` SQLite volume. Passwords are never sent to the C# catalog API or written in plaintext. New accounts require a short-lived, single-use email verification grant; older phone-only accounts can migrate after verifying the same email. Email codes expire after 10 minutes, resend is throttled, and verification allows at most five attempts. Phone number is optional and is never used for verification. Signed-in sessions remain valid until sign-out or server revocation and resume after closing the app. Sign out explicitly to end the current device session. Fingerprint/face sign-in remains available as an optional method after sign-out.

## Release smoke checks

- Launch with a clean install and confirm the welcome page appears immediately after the Android splash screen.
- Reopen after first launch: go from splash directly to sign-in when signed out, or directly to the shop home when the secure session is active. Confirm Explore opens sign-in without waiting for the update check.
- From sign-in, use Forgot password, receive and verify the email OTP, enter and repeat a new password, then sign in with it. Confirm reset revokes existing sessions.
- Create an account with a valid email and password; confirm a 6-digit verification code arrives by email. Phone is optional.
- Enter an incorrect or expired code and confirm access is denied. Suspend an account in Admin > User accounts; with the correct password, sign-in shows the suspended notice and MF Technologies admin email/phones. Open Forgot password for that account and confirm no OTP is sent and the same support contacts are shown. Unsuspend the account and confirm password reset works again.
- From the suspended-account notice, choose Send support request and confirm the consent prompt. Verify the ticket appears in M&F Technologies Admin > Tickets with account details and the review request, with no password. Canceling the prompt must create no ticket; email and phone actions remain available.
- Resend a code, confirm the prior code no longer works, then verify the newest code and confirm the dashboard opens.
- Sign out and confirm the app returns to sign-in immediately while server session revocation runs in the background. In the admin console, confirm sign-out also shows the login screen without waiting for the network. Then test email/password sign-in and fingerprint sign-in separately; confirm fingerprint sign-in is an underlined link below the main button.
- Sign in, close and reopen the app, and confirm the secure session returns directly to the shop dashboard without another password prompt. Confirm a lost connection still opens the locally cached inventory and synchronizes later.
- Keep a signed-in session idle beyond 90 days, then reconnect; the session remains valid until explicit sign-out or server revocation.
- Revoke a session by resetting the account password, reopen Refer & Earn, and confirm the error offers Sign in again; signing in restores referral points and the invite link.
- Create an account and sign in from a second device; confirm the same profile and stock are returned from the server database.
- Profile always shows a camera icon. With no saved photo, it is disabled and upload remains unavailable. With an existing photo, it removes that photo after permanent-removal confirmation; after deletion the icon is disabled. Existing photos remain visible across devices until the owner removes them.
- Sign in to an existing phone-only account, verify the email code, and confirm the local profile and inventory migrate without replacing existing server records.
- Adjust stock while online, sign in on another device, and confirm each user's items stay isolated. Repeat an adjustment offline and confirm it syncs after sign-in.
- During sign-up, confirm account creation is blocked until the Terms/Privacy and essential app-storage checkbox is selected, then verify the acceptance timestamp is recorded. Confirm no cookie banner appears in the app.
- Open Terms, Privacy, and Cookies & App Storage from sign-up; Profile > Privacy & Legal contains Terms and Privacy only.
- Confirm Profile > App updates checks the latest-version manifest, shows the JengaBiz-colored update page, and presents the Android installer only after the APK checksum passes. Android must ask the user to confirm installation.
- Expand Refer & Earn and allow device location; confirm there are no editable country/county fields and the invite URL contains an opaque code rather than account email. Verify the app accepts Kenya and blocks other countries. Open the link, enter the displayed code during signup, and verify by email. Confirm same-county signups add 50 JengaBiz points, different Kenyan counties add 75, each referred account counts once, and no international referral rate is offered.
- Tap Invite a contact and confirm read-only contacts permission is requested only then, the system contact picker opens, and the chosen contact is not uploaded or saved. Denying access must leave link copy/share available.
- Open Home, Analytics, Stock, Notifications, and Profile; verify navigation and scrolling.
- Open Stock and confirm there is no inventory-metrics card, title, or dispatch banner; the PDF/add/sort icons remain, search stays visible, and status/category filters scroll away with the inventory.
- Add or adjust stock and confirm the dashboard totals update.
- Add a product with name, category, SKU, buying and selling prices, quantity, and low-stock threshold. Edit its details, restock with `+`, record a sale with `−`, remove it, and confirm each change syncs to the account and appears on a second device.
- Add a category from the product form and filter inventory by category. Upload a product photo, then verify its preview and that the image appears in the inventory card.
- Confirm the Android system media picker shares only the selected product photo and JengaBiz does not request full photo/video library access.
- With network disabled, add a product photo, close and reopen the app, and confirm both the photo and product remain available. Re-enable network, wait for sync, and confirm the photo appears on a second signed-in device. Confirm previously viewed photos load from the local cache while offline.
- Export a stock PDF from Stock & Inventory and Analytics. Confirm the JengaBiz logo, shop name, current totals, item ID/name/category/SKU, buying and selling prices, on-hand and sold quantities, reorder point, image URL, and MF Technologies email/phone details appear in the shareable PDF.
- Confirm Biometric login, Push notifications, and Weekly email report default to on, remain saved after app restart, and preserve a user's explicit off selection.
- On Android 13 or later, allow notification permission. Sell through 50% of a product's starting stock, reduce another item from above its reorder point to low stock, and then to zero; confirm local alerts appear. With Firebase configured, repeat from another signed-in phone and confirm server-delivered FCM alerts arrive. Turn notifications off and confirm the device is deregistered and receives no more remote stock alerts.
- Add the JengaBiz Stock widget from the Android home-screen widget picker; verify item, unit, and low-stock counts update after changing stock, and tapping the widget opens the app.
- Disable network access during startup and verify the app remains usable with cached inventory; restore network access and confirm it retries inventory sync automatically.
- Download the APK from `https://jengabiz.mftechnologies.org/` and from the GitHub release. Confirm both responses are APK bytes with `application/vnd.android.package-archive`, and compare the SHA-256 file.
- Check the public landing and API hostnames from outside the local network. They must have a trusted HTTPS certificate; users do not install a self-signed certificate.
- Open the landing page, Terms, Privacy, and Cookies & App Storage pages. Confirm they use the app's blue/neutral palette and each page has the cookie notice controls.
- Choose Accept all, Reject all non-essential, and custom cookie preferences. Confirm the choice persists across pages and that footer Cookie settings reopens the preferences dialog. Confirm no analytics or advertising cookies are set by the current site.

## Android release

Release versions `1.0.6+7`, `1.0.7+8`, `1.0.8+9`, `1.0.9+10`, `1.1.0+11`, `1.1.1+12`, `1.1.2+13`, and `1.1.3+14` are signed with the dedicated local Android release keystore. Keep `flutter_app/android/key.properties` and `flutter_app/android/app/jengabiz-release.jks` backed up securely; both are ignored by Git and must be reused to sign future updates. Do not publish either file. The APK itself is signed, and visitors use the site's trusted HTTPS certificate without installing anything.

Versions through v1.0.5 need one manual install of v1.0.6 because they do not contain the updater. From v1.0.6 onward, the app checks `/downloads/latest.json` on startup and from Profile > App updates. It downloads only HTTPS APKs from `jengabiz.mftechnologies.org`, verifies the SHA-256 from the manifest, then opens Android's package installer. Android still requires the user to approve installation. The landing page uses the versioned APK URL in the manifest with immutable caching; `/downloads/latest/JengaBiz.apk` remains the stable fallback path.

## Deployment dependency

The mobile API URL defaults to `https://jengabiz.mftechnologies.org`; landing Nginx proxies `/email-auth/*` to the API gateway and account service. Other mobile API paths are forwarded to the C# API. The separate `https://jengabiz-api.mftechnologies.org` hostname remains available for direct API access.

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

## Previous release (2026-11-23; v1.0.6+7)

- Profile > Privacy & Legal now contains Terms of Use and Privacy Policy only. Sign-up still explains and records acceptance of essential app storage.
- Added a JengaBiz-blue update screen, startup version check, Profile > App updates entry, checksum-verified APK download, and Android installer handoff.
- Added a stable latest APK path and version manifest so updater-enabled versions can install the latest release directly.
- Release `1.0.6+7` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,525,470 bytes; SHA-256 is `9bc42be00a7e1530418e30b7b2e04fe4ff7a17cc13a16f4b103a60bc1299cb4f`.

## Previous in-app update (2026-11-23; v1.0.7+8)

- Replaced the welcome screen's generic bar-chart and settings icons with outlined inventory and alert icons, both using one pale-blue tile style.
- Updated `/downloads/latest.json` and the stable latest APK path; v1.0.6 and newer can install this update from the in-app updater.
- APK is signed as `com.dukaledger.duka_ledger` with the existing release certificate. Size is 27,525,440 bytes; SHA-256 is `ca647ba577069066419237463faabf79507e04e276cf4daf5e8ba86a2c15d87d`.

## Previous in-app update (2026-11-23; v1.0.8+9)

- Refer & Earn now distinguishes connection failures, invalid/revoked sessions, and API errors instead of showing a generic internet message for every failure.
- Added a Retry control to reload referral points while the section is open.
- Account sessions now stay valid until sign-out or server revocation. Existing live session records are migrated in place after a verified SQLite backup.
- Redesigned stock cards to keep product name, price, category, status, units sold, and remaining quantity readable with direct sale/restock buttons and a single Edit/Remove menu.
- Versioned APK URLs use immutable caching so the landing-page and in-app downloads can reuse a verified release file.
- Add to manual QA: verify stock cards at a narrow phone width, use minus/plus and the product menu, and confirm the visible stock values update. Confirm the user can still open the app after a long idle period and that logout revokes the session.
- Release `1.0.8+9` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,574,433 bytes; SHA-256 is `44359220ec391e086fdf3387935f348c35080842d3152cb16ceaad38487acac7`.

## Previous in-app update (2026-11-23; v1.0.9+10)

- Public API gateway now forwards `/email-auth/*` to the account service while keeping the existing C# API routes available. Public unauthenticated stock requests return the expected account-service 401 response.
- Stock sync retries when a signed-in app resumes. An empty offline cache cannot replace a populated server inventory.
- Removed the Cookies & App Storage link from the app; Terms of Use and Privacy Policy remain.
- Retained the referral failure details, Retry control, persistent sessions, and compact stock cards from v1.0.8.
- Landing-page and in-app downloads point to the versioned APK path, which Cloudflare confirms as a cache hit after the first request.
- The target account's server inventory was backed up and seeded with 23 additional sample electronics/accessory products (24 rows total). Other account, session, reward, and stock counts were unchanged.
- Release `1.0.9+10` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,572,062 bytes; SHA-256 is `20f2234a20da11daa821bcc6f50e1ed91e8c6db76c9e1720f705a67bea5fd558`.

## Previous in-app update (2026-11-23; v1.1.0+11)

- Mobile account, referral, stock, and image requests now use the landing-page hostname; Nginx proxies those requests to the existing API gateway and account service.
- The stock screen automatically syncs when opened. Concurrent startup, resume, and screen-entry syncs share one request, and an empty offline cache cannot replace a populated server inventory.
- Removed the manual “Load saved stock” action. Sign-in, startup, app resume, and opening Stock trigger inventory sync automatically.
- Removed the Cookies & App Storage profile/auth links; Terms of Use and Privacy Policy remain in the app.
- Release `1.1.0+11` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,571,745 bytes; SHA-256 is `ea1cb437c54ad06716d7ff280b550e5795028de0dadf9c093d642c1ac87b251d`.

## Previous in-app update (2026-11-23; v1.1.1+12)

- First-time users see the welcome screen once. Returning users go from splash to sign-in or directly to home for a saved session. Explore opens sign-in immediately while update availability loads in the background.
- Sign-in includes a compact underlined Forgot password action next to fingerprint sign-in. Password reset uses email OTP, then a new password and confirmation; the server revokes all sessions after a successful reset.
- Refer & Earn can select one contact after requesting read-only contacts permission. The chosen name is used in the Android share sheet; the address book is not uploaded or saved.
- Stock images use Android's system media picker, which grants access only to the selected photo. The app does not request broad photo/video library access; video is not supported for stock records.
- The production `jengabiz-email-otp` service was restarted to activate `/email-auth/reset-password`; its internal health endpoint returned HTTP 200.
- Release `1.1.1+12` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,671,402 bytes; SHA-256 is `e483ab4dafc45f62f204c1039c16611a33031433ff2d9f1f440e4bb373a4602a`.

## Previous in-app update (2026-11-23; v1.1.2+13)

- Grouped the underlined Forgot password and fingerprint sign-in links together beneath the main Sign In button. They stay centered with a small gap and wrap on narrow screens.
- Release `1.1.2+13` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,671,792 bytes; SHA-256 is `1710bfe00448051a461c2d931673a1c8f76a88bfe06bf5c6f49fd28682c5c863`.

## Previous in-app update (2026-11-23; v1.1.3+14)

- A rejected referral session now offers a Sign in again action so users can refresh authentication before loading points. Sessions remain persistent until server revocation or sign-out.
- Reduced the Profile Log out button to a compact centered control.
- Release `1.1.3+14` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,673,294 bytes; SHA-256 is `4dcd00436038542c317d3c12f3634300f95210574edf3071e50a4e5e3ddb8cc0`.

## Previous in-app update (2026-11-23; v1.1.4+15)

- Saved customer sessions use a single secure-storage record and remain active until explicit logout or server revocation. App startup opens the saved local account immediately; profile and inventory refresh continue in the background. Network failures do not clear the saved session.
- The welcome screen is recorded as seen when first displayed, so it does not return after closing the app.
- Refer & Earn saves the last referral total and code per account. A failed refresh keeps the saved points and link visible and offers a retry without mislabeling the failure as an internet outage.
- Update screens show the first three release notes with a `More…` control for longer lists.
- Release `1.1.4+15` is signed as `com.dukaledger.duka_ledger` with the existing release certificate. APK size is 27,685,658 bytes; SHA-256 is `1bea7df77d2ed2da90796208ec5d7571cbfa4b9aa24e589ca04d7a1bbcab53cb`.
- The landing page and `/downloads/latest.json` now point to the v1.1.4 APK and its checksum. The public manifest shows version code 15; both versioned and stable APK URLs return HTTP 200 with APK content type, and the downloaded public file hash matches the manifest.

## Withdrawn in-app update (2026-11-23; v1.1.5+16)

- This interim build briefly enabled profile-photo uploads, then was withdrawn from the latest release after the user asked to disable uploads. The public account API now rejects new profile-image PUT requests.
- Existing uploaded account photos remain in the database and can still be read or permanently removed by their signed-in account. No photo rows were deleted.
- Landing HTML now has a five-minute browser cache. Its versioned JavaScript is immutable and Cloudflare returned a cache HIT on the follow-up request. The homepage itself still reports `DYNAMIC` at Cloudflare; full edge caching needs a matching Cloudflare Cache Rule.
- The production account service restarted healthy after creating the additive `account_profile_images` table. A consistent SQLite snapshot was made first, and its integrity check returned `ok` before and after the change.
- Release `1.1.5+16` is signed as `com.dukaledger.duka_ledger`, passed APK v1/v2 signature verification, and matches the v1.1.4 release certificate. APK size is 27,723,016 bytes; SHA-256 is `2d28e7e4aa5ca6732973f58194f93d082893ac72e81e09aad73ce58195d5a02e`.
- The v1.1.5 APK was removed from the public download directory after v1.1.6 was published.

## Previous in-app update (2026-11-23; v1.1.6+17)

- Profile has no camera icon or photo-upload control. A profile photo already saved to the account remains visible. The signed-in owner can remove it; the app confirms that removal is permanent and it cannot be restored because uploads are disabled.
- The authenticated profile-image API allows reading and deletion only. New `PUT` uploads are rejected, and an unauthenticated `DELETE` returns 401. Existing profile-image rows were not deleted.
- The short-lived v1.1.5 APK was withdrawn from public downloads; older app versions receive v1.1.6 through the existing latest-version manifest.
- Landing HTML has a five-minute browser cache and its versioned JavaScript is immutable. The version manifest remains uncached so app update checks see the latest code. Cloudflare still marks the homepage `DYNAMIC`; full edge caching needs a matching Cache Rule.
- Release `1.1.6+17` is signed as `com.dukaledger.duka_ledger`, passed APK v1/v2 signature verification, and matches the v1.1.4 release certificate. APK size is 27,713,106 bytes; SHA-256 is `df26e911f6e71d9630f1509dbb401d37c21a06b474ca401bce4a4733669f643f`.
- The landing page and `/downloads/latest.json` point to v1.1.6 (version code 17). The versioned APK returns HTTP 200 with the Android package MIME type, and the public download SHA-256 matches the signed release.

## Admin dashboard checks

- Open `https://jengabiz.mftechnologies.org/admin/` and use the separate administrator credentials configured in the private `.env`. Customer accounts cannot sign in to admin routes.
- Admin identities live in `admin_users`, separately from customer records. Admin passwords use scrypt hashes; admin sessions are stored as token hashes and expire after seven days of inactivity.
- Existing phone numbers are encrypted with AES-256-GCM in the account database and have a keyed HMAC-SHA-256 index for matching. Customer API responses decrypt the number for the existing app behavior; user exports include the number only for authenticated administrators.
- The dashboard includes overview, customer accounts, inventory, referrals, CSV/JSON exports, and administrator access. Customer, inventory, and referral pages support search and POLL-style grid/list views; customer accounts support active/suspended status.
- Inventory and referral results use responsive server-side pagination too; list/grid changes recalculate page size so large accounts remain reachable without loading every record at once.
- Grid cards now separate account identity/contact/metrics, stock level/pricing/shop, and referral parties/points/date into clear sections with JengaBiz blue accents and responsive spacing.
- Refresh updates the current records without replacing the overview with a loading placeholder; the refresh icon indicates progress and the overview scroll position is retained.
- Suspending a customer revokes their app sessions. Exports exclude passwords, password hashes, customer/admin sessions, and push tokens.
- The deployed login page omits the “Protected by your JengaBiz sign-in and server-side admin access” note. The login screen, CSS, and JS return HTTP 200; admin API login/overview/logout work through the public domain; signed-out and anonymous reads return 401.
- Admin pages use JengaBiz colors, same-origin scripts/styles, and the admin security headers configured in Nginx.


## Previous in-app update (2026-11-23; v1.1.7+18)

- Profile shows a camera icon with uploads disabled. The icon is disabled when no saved profile photo exists. When an existing photo is present, the icon opens the permanent-removal confirmation; after removal it is disabled again.
- Existing uploaded account photos remain in the database and visible unless the account owner removes them. The API continues to reject new profile-photo uploads.
- The landing page and `/downloads/latest.json` point to v1.1.7 (version code 18); older installs can receive this release through the in-app updater.
- Release `1.1.7+18` is signed as `com.dukaledger.duka_ledger`, passed APK v1/v2 signature verification, and matches the established release certificate. APK size is 27,714,639 bytes; SHA-256 is `072ac34205a99e83b1d3b5325163df387dd87bbc1b59925daf318277c2cf5eaf`.


## Current in-app update (2026-11-24; v1.1.8+19)

- App and admin-portal logout return to sign-in immediately; server session revocation and notification-device cleanup run in the background.
- A correct-password login for a suspended account returns a dedicated suspension response with contact details from the JengaBiz Docker admin/support configuration. The sign-in screen links to the configured admin email and support phone numbers.
- The suspended-account screen can submit an explicitly confirmed review request to the M&F Technologies contact intake. M&F creates a ticket visible in its Docker-hosted Admin > Tickets queue. JengaBiz verifies the current account password and sends only account profile/contact details, never the password; it rate-limits requests and displays the returned ticket reference.
- OTP requests and password resets are blocked for suspended accounts. The API rechecks suspension at reset time so an older verification code cannot change a suspended account's password.
- Admin suspension still revokes account sessions and now also removes push-notification device registrations.
- The live M&F Technologies ticket intake is reached over the shared `mf_mf-network` Docker network; only the JengaBiz account service is attached to that external network.
- Release `1.1.8+19` is signed as `com.dukaledger.duka_ledger` with the established release certificate; APK signature schemes v1 and v2 verify, and its certificate SHA-256 matches v1.1.7. APK size is 27,753,619 bytes; SHA-256 is `b3593cf4958c236c5cf8c7345d2be4be6afcfa5c5608226c80339f11687f3ee7`. The landing download and in-app updater manifest now point to this APK.
