import { createHash, createSign, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import { resolve4 } from 'node:dns/promises';
import { request as httpsRequest } from 'node:https';
import { createServer } from 'node:http';
import { mkdirSync, chmodSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
import { createAccountStore, validateStockItems } from './account_store.mjs';

const PORT = Number(process.env.PORT || 5081);
const OTP_TTL_MS = 10 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_SENDS_PER_HOUR = 5;
const MAX_VERIFY_ATTEMPTS = 5;
const MAX_SENDS_PER_IP_PER_HOUR = 20;
const MAX_BODY_BYTES = 4096;
const MAX_STOCK_BODY_BYTES = 4 * 1024 * 1024;
const MAX_IMAGE_BODY_BYTES = 1400 * 1024;
const MAX_IMAGE_BYTES = 1024 * 1024;
const MAX_LOGIN_FAILURES = 10;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const SUPPORT_REQUEST_WINDOW_MS = 15 * 60 * 1000;
const MAX_SUPPORT_REQUESTS_PER_IP = 10;
const SUPPORT_TICKET_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_SUPPORT_TICKETS_PER_ACCOUNT = 3;
const ADMIN_READ_PATHS = new Set([
  '/email-auth/admin/overview',
  '/email-auth/admin/users',
  '/email-auth/admin/inventory',
  '/email-auth/admin/referrals',
  '/email-auth/admin/admins',
  '/email-auth/admin/export',
]);
const ADMIN_LOGIN_PATH = '/email-auth/admin/login';
const ADMIN_ME_PATH = '/email-auth/admin/me';
const ADMIN_LOGOUT_PATH = '/email-auth/admin/logout';

function isAdminRoute(path) {
  return ADMIN_READ_PATHS.has(path) || path === ADMIN_ME_PATH || path === ADMIN_LOGOUT_PATH ||
    /^\/email-auth\/admin\/users\/[A-Za-z0-9_-]{1,128}(?:\/status)?$/.test(path);
}

function toCsv(rows) {
  const records = Array.isArray(rows) ? rows : [];
  const columns = [...new Set(records.flatMap((record) => Object.keys(record)))];
  if (!columns.length) return '';
  const encode = (value) => {
    let text = value === null || value === undefined
      ? ''
      : typeof value === 'object'
        ? JSON.stringify(value)
        : String(value);
    if (/^[\s]*[=+\-@\t\r]/.test(text)) text = `'${text}`;
    return `"${text.replace(/"/g, '""')}"`;
  };
  return [columns.map(encode).join(','), ...records.map((record) => columns.map((key) => encode(record[key])).join(','))]
    .join('\r\n');
}

function json(response, status, payload) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
  });
  response.end(JSON.stringify(payload));
}

async function readJson(request, limit = MAX_BODY_BYTES) {
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (Buffer.byteLength(body) > limit) {
      const error = new Error('Request body too large.');
      error.statusCode = 413;
      throw error;
    }
  }
  return JSON.parse(body || '{}');
}

function parseUploadedImage(payload) {
  const mimeType = payload?.mimeType;
  const encoded = payload?.imageBase64;
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(mimeType) ||
      typeof encoded !== 'string' || encoded.length > 1_400_000 ||
      encoded.length % 4 !== 0 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
    return null;
  }
  const imageData = Buffer.from(encoded, 'base64');
  if (!imageData.length || imageData.length > MAX_IMAGE_BYTES) return null;
  const isJpeg = mimeType === 'image/jpeg' && imageData.length >= 3 &&
    imageData[0] === 0xff && imageData[1] === 0xd8 && imageData[2] === 0xff;
  const isPng = mimeType === 'image/png' && imageData.length >= 8 &&
    imageData.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const isWebp = mimeType === 'image/webp' && imageData.length >= 12 &&
    imageData.toString('ascii', 0, 4) === 'RIFF' &&
    imageData.toString('ascii', 8, 12) === 'WEBP';
  return isJpeg || isPng || isWebp ? { mimeType, imageData } : null;
}

function normalizeEmail(value) {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return null;
  }
  return email;
}

function safeEqualHex(left, right) {
  const a = Buffer.from(left, 'hex');
  const b = Buffer.from(right, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character]);
}

export function createEmailOtpHandler({
  apiKey = process.env.RESEND_API_KEY,
  fromEmail = process.env.RESEND_FROM_EMAIL,
  hashSecret = process.env.OTP_HASH_SECRET || randomBytes(32).toString('hex'),
  sendEmail = sendResendEmail,
  sendPush = sendFirebasePush,
  getLatestRelease,
  latestReleaseUrl = process.env.JENGABIZ_LATEST_MANIFEST_URL || 'http://jengabiz-landing/downloads/latest.json',
  now = Date.now,
  makeOtp = () => String(randomInt(100000, 1000000)),
  adminEmail = process.env.JENGABIZ_ADMIN_EMAIL || '',
  adminName = process.env.JENGABIZ_ADMIN_NAME || 'MF Technologies Admin',
  supportName = process.env.JENGABIZ_SUPPORT_NAME || 'MF Technologies',
  supportEmail = process.env.JENGABIZ_SUPPORT_EMAIL || adminEmail || 'info@mftechnologies.org',
  supportPhonePrimary = process.env.JENGABIZ_SUPPORT_PHONE_PRIMARY || '0748329410',
  supportPhoneSecondary = process.env.JENGABIZ_SUPPORT_PHONE_SECONDARY || '0712742991',
  mfSupportContactUrl = process.env.MF_SUPPORT_CONTACT_URL || 'http://mf-backend:4000/api/contact',
  adminPasswordSalt = process.env.JENGABIZ_ADMIN_PASSWORD_SALT || '',
  adminPasswordHash = process.env.JENGABIZ_ADMIN_PASSWORD_HASH || '',
  phoneEncryptionKey = process.env.JENGABIZ_PHONE_ENCRYPTION_KEY,
  phoneHashKey = process.env.JENGABIZ_PHONE_HASH_KEY,
  profileUploadsDir = process.env.JENGABIZ_PROFILE_UPLOADS_DIR || '',
  profileUploadsUid = process.env.JENGABIZ_PROFILE_UPLOADS_UID,
  profileUploadsGid = process.env.JENGABIZ_PROFILE_UPLOADS_GID,
  database = new DatabaseSync(':memory:'),
} = {}) {
  const accounts = createAccountStore(database, {
    now,
    adminEmail,
    adminName,
    adminPasswordSalt,
    adminPasswordHash,
    phoneEncryptionKey,
    phoneHashKey,
    profileUploadsDir,
    profileUploadsUid,
    profileUploadsGid,
  });
  const challenges = new Map();
  const sendsByIp = new Map();
  const loginFailures = new Map();
  const supportRequestsByIp = new Map();
  const supportTicketsByAccount = new Map();
  const verificationGrants = new Map();
  let cachedRelease = null;
  let cachedReleaseExpiresAt = 0;

  async function resolveLatestRelease() {
    if (typeof getLatestRelease === 'function') {
      try {
        const rel = await getLatestRelease();
        if (rel && Number.isSafeInteger(rel.versionCode) && rel.versionCode > 0 && rel.versionName) {
          return rel;
        }
      } catch {}
      return null;
    }
    const currentTime = now();
    if (cachedRelease && cachedReleaseExpiresAt > currentTime) {
      return cachedRelease;
    }
    if (!latestReleaseUrl) return null;
    try {
      const res = await fetch(latestReleaseUrl, {
        headers: { accept: 'application/json', 'cache-control': 'no-cache' },
        signal: AbortSignal.timeout(2500),
      });
      if (!res.ok) return null;
      const decoded = await res.json();
      const versionCode = Number(decoded?.version_code);
      const versionName = typeof decoded?.version_name === 'string' ? decoded.version_name.trim() : '';
      if (!Number.isSafeInteger(versionCode) || versionCode <= 0 || !versionName) {
        return null;
      }
      cachedRelease = { versionCode, versionName };
      cachedReleaseExpiresAt = currentTime + 60_000;
      return cachedRelease;
    } catch {
      return null;
    }
  }

  async function notifyAccountDevicesOfUpdate(accountId, targetToken = null) {
    const latest = await resolveLatestRelease();
    if (!latest) return;
    const devices = targetToken
      ? [accounts.getNotificationDevice(accountId, targetToken)].filter(Boolean)
      : accounts.listNotificationDevices(accountId);
    const outdated = devices.filter(
      (device) =>
        (device.appVersionCode == null || device.appVersionCode < latest.versionCode) &&
        (device.lastUpdatePushVersion || 0) < latest.versionCode,
    );
    if (outdated.length === 0) return;

    await Promise.all(
      outdated.map((device) => {
        accounts.markDeviceUpdatePushed(device.token, latest.versionCode);
        return sendPush(device.token, {
          title: `Update JengaBiz to v${latest.versionName}`,
          body: `Version ${latest.versionName} is ready. Open Profile → Check for updates to install.`,
          data: {
            type: 'update',
            route: 'update',
            versionCode: String(latest.versionCode),
            versionName: latest.versionName,
            actionLabel: 'Update now',
          },
        }).catch((error) => {
          const details = error?.response?.error?.details;
          const unregistered = Array.isArray(details) && details.some(
            (detail) => detail?.errorCode === 'UNREGISTERED',
          );
          if (error?.statusCode === 404 || unregistered) {
            accounts.removeNotificationDevice(accountId, device.token);
          }
          return false;
        });
      }),
    );
  }
  const digestOtp = (email, otp) =>
    createHash('sha256')
      .update(`${hashSecret}\0${email}\0${otp}`)
      .digest('hex');
  const digestGrant = (token) => createHash('sha256').update(token).digest('hex');

  function suspensionSupport() {
    return {
      name: supportName,
      adminName,
      email: supportEmail,
      phoneNumbers: [supportPhonePrimary, supportPhoneSecondary].filter(Boolean),
    };
  }

  function issueVerificationGrant(email) {
    const currentTime = now();
    for (const [key, grant] of verificationGrants) {
      if (grant.expiresAt <= currentTime) verificationGrants.delete(key);
    }
    if (verificationGrants.size >= 10000) return null;
    const token = randomBytes(32).toString('base64url');
    verificationGrants.set(digestGrant(token), {
      email,
      expiresAt: currentTime + OTP_TTL_MS,
    });
    return token;
  }

  function validateProfile(payload) {
    const name = typeof payload.name === 'string' ? payload.name.trim() : '';
    const shopName = typeof payload.shopName === 'string' ? payload.shopName.trim() : '';
    const phone = typeof payload.phone === 'string' ? payload.phone.trim() : '';
    const county = typeof payload.county === 'string' ? payload.county.trim() : '';
    const referralCode = typeof payload.referralCode === 'string'
      ? payload.referralCode.trim().toUpperCase()
      : '';
    const password = typeof payload.password === 'string' ? payload.password : '';
    if (!name || name.length > 120 || !shopName || shopName.length > 120 ||
        phone.length > 40 || county.length > 100 ||
        referralCode.length > 32 ||
        (referralCode && !/^[A-Z0-9-]{4,32}$/.test(referralCode))) {
      return null;
    }
    if (password.length < 8 || Buffer.byteLength(password) > 1024) return null;
    const items = validateStockItems(payload.items ?? []);
    if (!items) return null;
    return { name, shopName, phone, county, referralCode, password, items };
  }

  function requestIp(request) {
    const forwarded = request.headers['cf-connecting-ip'];
    return (typeof forwarded === 'string' ? forwarded : request.socket.remoteAddress || 'unknown')
      .slice(0, 64);
  }

  return async (request, response) => {
    try {
      const path = new URL(request.url || '/', 'http://localhost').pathname;
      const stockImageMatch = path.match(/^\/email-auth\/stock\/images\/([A-Za-z0-9_-]{1,128})$/);
      const profileImageMatch = path === '/email-auth/profile/image';
      const profileCollectionMatch = path === '/email-auth/profile/images';
      const profileCollectionItemMatch = path.match(/^\/email-auth\/profile\/images\/([A-Za-z0-9_-]{1,128})$/);
      const securityCaptureMatch = path === '/email-auth/security/camera-capture';
      const securityListMatch = path === '/email-auth/security/captures';
      const adminUserMatch = path.match(/^\/email-auth\/admin\/users\/([A-Za-z0-9_-]{1,128})$/);
      const adminStatusMatch = path.match(/^\/email-auth\/admin\/users\/([A-Za-z0-9_-]{1,128})\/status$/);
      if (request.method === 'GET' && path === '/health') {
        return json(response, 200, { status: 'ok' });
      }

      const otpPaths = [
        '/email-auth/request-otp',
        '/email-auth/verify-otp',
        '/email-auth/reset-password',
      ];
      const supportRequestPath = '/email-auth/support/request';
      const accountPaths = [
        '/email-auth/register',
        '/email-auth/migrate',
        '/email-auth/login',
        '/email-auth/me',
        '/email-auth/logout',
        '/email-auth/stock/items',
        '/email-auth/profile/image',
        '/email-auth/notifications/device',
        '/email-auth/referrals',
        '/email-auth/referrals/location',
        '/email-auth/security/camera-capture',
        '/email-auth/security/captures',
        ADMIN_LOGIN_PATH,
      ];
      const isAccountPath = accountPaths.includes(path) ||
        isAdminRoute(path) ||
        stockImageMatch !== null ||
        profileCollectionMatch ||
        profileCollectionItemMatch !== null;
      const allowed = otpPaths.includes(path) || path === supportRequestPath || isAccountPath;
      const allowedMethod = stockImageMatch || profileImageMatch
        ? (stockImageMatch
          ? ['GET', 'PUT'].includes(request.method)
          : ['GET', 'PUT', 'DELETE'].includes(request.method))
        : (profileCollectionMatch || profileCollectionItemMatch)
          ? request.method === 'GET'
        : path === ADMIN_LOGIN_PATH || path === ADMIN_LOGOUT_PATH
          ? request.method === 'POST'
        : adminStatusMatch
          ? request.method === 'PATCH'
        : isAdminRoute(path)
          ? request.method === 'GET'
        : path === '/email-auth/stock/items'
        ? ['GET', 'PUT'].includes(request.method)
        : path === '/email-auth/notifications/device'
          ? ['POST', 'DELETE'].includes(request.method)
        : path === '/email-auth/me'
          ? request.method === 'GET'
        : path === '/email-auth/referrals'
          ? request.method === 'GET'
        : path === '/email-auth/referrals/location'
          ? request.method === 'PUT'
        : securityCaptureMatch
          ? request.method === 'POST'
        : securityListMatch
          ? request.method === 'GET'
        : request.method === 'POST';
      if (!allowed || !allowedMethod) {
        return json(response, 404, { success: false, message: 'Not found.' });
      }

      let payload;
      if (request.method !== 'GET') {
        try {
          const bodyLimit = path === '/email-auth/stock/items'
            ? MAX_STOCK_BODY_BYTES
            : (stockImageMatch || (profileImageMatch && request.method === 'PUT') || securityCaptureMatch)
              ? MAX_IMAGE_BODY_BYTES
              : MAX_BODY_BYTES;
          payload = await readJson(request, bodyLimit);
        } catch (error) {
          const status = error.statusCode || 400;
          return json(response, status, {
            success: false,
            message: status === 413 ? 'Request is too large.' : 'Invalid request.',
          });
        }
      }

      if (isAccountPath) {
        const authorization = request.headers.authorization || '';
        const bearer = authorization.startsWith('Bearer ')
          ? authorization.slice(7).trim()
          : '';

        if (path === ADMIN_LOGIN_PATH) {
          const email = normalizeEmail(payload?.email);
          const password = typeof payload?.password === 'string' ? payload.password : '';
          if (!email || password.length < 8 || Buffer.byteLength(password) > 1024) {
            return json(response, 400, { success: false, message: 'Enter a valid administrator email and password.' });
          }
          const key = `admin\0${requestIp(request)}\0${email}`;
          const currentTime = now();
          for (const [attemptKey, attempts] of loginFailures) {
            if (attempts.windowStartedAt + LOGIN_WINDOW_MS <= currentTime) loginFailures.delete(attemptKey);
          }
          const failure = loginFailures.get(key);
          if (failure && failure.count >= MAX_LOGIN_FAILURES) {
            return json(response, 429, { success: false, message: 'Too many sign-in attempts. Try again later.' });
          }
          const result = accounts.adminLogin(email, password);
          if (!result) {
            loginFailures.set(key, {
              windowStartedAt: failure?.windowStartedAt ?? currentTime,
              count: failure ? failure.count + 1 : 1,
            });
            return json(response, 401, { success: false, message: 'Administrator email or password is incorrect.' });
          }
          loginFailures.delete(key);
          return json(response, 200, { success: true, ...result });
        }

        if (path === '/email-auth/login') {
          const email = normalizeEmail(payload?.email);
          const password = typeof payload?.password === 'string' ? payload.password : '';
          if (!email || password.length < 8 || Buffer.byteLength(password) > 1024) {
            return json(response, 400, { success: false, message: 'Enter a valid email and password.' });
          }
          const key = `${requestIp(request)}\0${email}`;
          const currentTime = now();
          for (const [attemptKey, attempts] of loginFailures) {
            if (attempts.windowStartedAt + LOGIN_WINDOW_MS <= currentTime) {
              loginFailures.delete(attemptKey);
            }
          }
          if (loginFailures.size >= 10000 && !loginFailures.has(key)) {
            loginFailures.delete(loginFailures.keys().next().value);
          }
          const failure = loginFailures.get(key);
          if (failure && failure.windowStartedAt + LOGIN_WINDOW_MS > currentTime && failure.count >= MAX_LOGIN_FAILURES) {
            return json(response, 429, { success: false, message: 'Too many sign-in attempts. Try again later.' });
          }
          const result = accounts.login(email, password);
          if (result?.suspended) {
            loginFailures.delete(key);
            return json(response, 403, {
              success: false,
              code: 'ACCOUNT_SUSPENDED',
              message: 'This account is suspended. Contact MF Technologies support.',
              support: suspensionSupport(),
            });
          }
          if (!result) {
            loginFailures.set(key, {
              windowStartedAt: failure && failure.windowStartedAt + LOGIN_WINDOW_MS > currentTime
                ? failure.windowStartedAt
                : currentTime,
              count: failure && failure.windowStartedAt + LOGIN_WINDOW_MS > currentTime
                ? failure.count + 1
                : 1,
            });
            return json(response, 401, { success: false, message: 'Email or password is incorrect.' });
          }
          loginFailures.delete(key);
          if (result?.user?.id) {
            void notifyAccountDevicesOfUpdate(result.user.id);
          }
          return json(response, 200, { success: true, ...result });
        }

        if (path === '/email-auth/register' || path === '/email-auth/migrate') {
          const email = normalizeEmail(payload?.email);
          const proof = typeof payload?.verificationToken === 'string'
            ? payload.verificationToken
            : '';
          const proofHash = proof ? digestGrant(proof) : '';
          const grant = verificationGrants.get(proofHash);
          const account = validateProfile(payload || {});
          if (!email || !account) {
            return json(response, 400, { success: false, message: 'Check the account details and try again.' });
          }
          if (!grant || grant.email !== email || grant.expiresAt <= now()) {
            verificationGrants.delete(proofHash);
            return json(response, 401, { success: false, message: 'Verify your email again before creating the account.' });
          }
          const created = accounts.register({ email, ...account });
          if (created.conflict) {
            return json(response, 409, { success: false, message: 'An account already exists for this email. Sign in with its current password.' });
          }
          if (created.invalidReferral) {
            return json(response, 400, { success: false, message: 'That referral code is invalid or cannot be used for this account.' });
          }
          if (created.referralLocationRequired) {
            return json(response, 400, { success: false, message: 'The inviter must enable location before this referral code can be used.' });
          }
          verificationGrants.delete(proofHash);
          return json(response, 201, {
            success: true,
            sessionToken: created.sessionToken,
            user: created.user,
          });
        }

        if (isAdminRoute(path)) {
          const adminSession = accounts.authenticateAdmin(bearer);
          if (!adminSession) {
            return json(response, 401, { success: false, message: 'Administrator sign-in is required.' });
          }
          if (path === ADMIN_ME_PATH) {
            return json(response, 200, { success: true, admin: adminSession.user });
          }
          if (path === ADMIN_LOGOUT_PATH) {
            accounts.revokeAdminSession(adminSession.tokenHash);
            return json(response, 200, { success: true });
          }
          if (path === '/email-auth/admin/overview') {
            return json(response, 200, { success: true, ...accounts.adminOverview({ nowMs: now() }) });
          }
          if (path === '/email-auth/admin/users') {
            const url = new URL(request.url || '/', 'http://localhost');
            const result = accounts.adminUsers(url.searchParams.get('q') || '', {
              status: url.searchParams.get('status') || 'all',
              limit: url.searchParams.get('limit') || 60,
              offset: url.searchParams.get('offset') || 0,
            });
            return json(response, 200, { success: true, ...result });
          }
          if (adminStatusMatch) {
            const status = typeof payload?.status === 'string' ? payload.status : '';
            if (!['active', 'suspended'].includes(status)) {
              return json(response, 400, { success: false, message: 'Choose active or suspended status.' });
            }
            const updated = accounts.setCustomerStatus(adminStatusMatch[1], status);
            if (!updated) return json(response, 404, { success: false, message: 'Customer account was not found.' });
            return json(response, 200, { success: true, status });
          }
          if (adminUserMatch) {
            const details = accounts.adminUserDetails(adminUserMatch[1]);
            return details
              ? json(response, 200, { success: true, ...details })
              : json(response, 404, { success: false, message: 'Customer account was not found.' });
          }
          if (path === '/email-auth/admin/inventory') {
            const url = new URL(request.url || '/', 'http://localhost');
            const result = accounts.adminInventory(url.searchParams.get('q') || '', {
              limit: url.searchParams.get('limit') || 25,
              offset: url.searchParams.get('offset') || 0,
            });
            return json(response, 200, {
              success: true,
              ...result,
            });
          }
          if (path === '/email-auth/admin/referrals') {
            const url = new URL(request.url || '/', 'http://localhost');
            const result = accounts.adminReferrals(url.searchParams.get('q') || '', {
              limit: url.searchParams.get('limit') || 25,
              offset: url.searchParams.get('offset') || 0,
            });
            return json(response, 200, {
              success: true,
              ...result,
            });
          }
          if (path === '/email-auth/admin/admins') {
            return json(response, 200, { success: true, admins: accounts.listAdminAccounts() });
          }
          if (path === '/email-auth/admin/export') {
            const url = new URL(request.url || '/', 'http://localhost');
            const dataset = url.searchParams.get('dataset') || 'all';
            const format = url.searchParams.get('format') || 'json';
            if (!['csv', 'json'].includes(format)) {
              return json(response, 400, { success: false, message: 'Export format must be CSV or JSON.' });
            }
            const data = accounts.adminExportData(dataset);
            if (!data) return json(response, 400, { success: false, message: 'Choose users, inventory, referrals, or all data.' });
            if (format === 'csv' && !Array.isArray(data)) {
              return json(response, 400, { success: false, message: 'CSV exports require one dataset at a time.' });
            }
            const body = format === 'csv' ? toCsv(data) : JSON.stringify(data, null, 2);
            const filename = `jengabiz-${dataset}-${new Date(now()).toISOString().slice(0, 10)}.${format}`;
            response.writeHead(200, {
              'content-type': format === 'csv' ? 'text/csv; charset=utf-8' : 'application/json; charset=utf-8',
              'content-disposition': `attachment; filename="${filename}"`,
              'cache-control': 'private, no-store',
              'x-content-type-options': 'nosniff',
              'referrer-policy': 'no-referrer',
            });
            response.end(body);
            return;
          }
        }

        if (path === '/email-auth/logout') {
          const session = accounts.authenticate(bearer);
          if (!session) return json(response, 401, { success: false, message: 'Sign in again to continue.' });
          const deviceToken = typeof payload?.deviceToken === 'string'
            ? payload.deviceToken.trim()
            : '';
          if (deviceToken.length > 0 && deviceToken.length <= 4096) {
            accounts.removeNotificationDevice(session.id, deviceToken);
          }
          accounts.revokeSession(session.tokenHash);
          return json(response, 200, { success: true });
        }

        const session = accounts.authenticate(bearer);
        if (!session) return json(response, 401, { success: false, message: 'Sign in again to continue.' });
        if (path === '/email-auth/me') {
          return json(response, 200, { success: true, user: session.user });
        }
        if (path === '/email-auth/referrals') {
          const summary = accounts.getReferralSummary(session.id);
          if (!summary) {
            return json(response, 404, { success: false, message: 'Referral account was not found.' });
          }
          return json(response, 200, { success: true, ...summary });
        }
        if (path === '/email-auth/referrals/location') {
          const county = typeof payload?.county === 'string' ? payload.county.trim() : '';
          if (!county || county.length > 100) {
            return json(response, 400, { success: false, message: 'Could not detect a supported Kenyan county from this device.' });
          }
          const user = accounts.updateReferralLocation(session.id, county);
          if (user === false) {
            return json(response, 409, { success: false, message: 'Location is locked after a referral has earned points.' });
          }
          if (!user) {
            return json(response, 400, { success: false, message: 'Could not detect a supported Kenyan county from this device.' });
          }
          return json(response, 200, { success: true, user });
        }
        if (path === '/email-auth/notifications/device') {
          const deviceToken = typeof payload?.deviceToken === 'string'
            ? payload.deviceToken.trim()
            : '';
          if (!deviceToken || deviceToken.length > 4096) {
            return json(response, 400, { success: false, message: 'A valid device token is required.' });
          }
          if (request.method === 'DELETE') {
            accounts.removeNotificationDevice(session.id, deviceToken);
            return json(response, 200, { success: true });
          }
          const platform = typeof payload?.platform === 'string'
            ? payload.platform.toLowerCase()
            : '';
          if (!['android', 'ios'].includes(platform)) {
            return json(response, 400, { success: false, message: 'Platform must be android or ios.' });
          }
          const rawVersionCode = payload?.appVersionCode;
          const appVersionCode = Number.isSafeInteger(rawVersionCode) &&
            rawVersionCode > 0 && rawVersionCode <= 1_000_000_000
            ? rawVersionCode
            : null;
          accounts.saveNotificationDevice(
            session.id,
            deviceToken,
            platform,
            now(),
            appVersionCode,
          );
          void notifyAccountDevicesOfUpdate(session.id, deviceToken);
          return json(response, 200, { success: true });
        }
        if (stockImageMatch) {
          const itemId = stockImageMatch[1];
          if (request.method === 'GET') {
            const storedImage = accounts.getStockImage(session.id, itemId);
            if (!storedImage) {
              return json(response, 404, { success: false, message: 'Product image was not found.' });
            }
            const imageData = Buffer.from(storedImage.imageData);
            response.writeHead(200, {
              'content-type': storedImage.mimeType,
              'content-length': imageData.length,
              'cache-control': 'private, no-store',
              'x-content-type-options': 'nosniff',
            });
            response.end(imageData);
            return;
          }
          const uploadedImage = parseUploadedImage(payload);
          if (!uploadedImage) {
            return json(response, 400, { success: false, message: 'Choose a valid JPEG, PNG, or WebP image up to 1 MB.' });
          }
          const saved = accounts.saveStockImage(
            session.id,
            itemId,
            uploadedImage.mimeType,
            uploadedImage.imageData,
            now(),
          );
          if (saved === 'quota') {
            return json(response, 413, {
              success: false,
              message: 'This shop has reached its 32 MB product image storage limit.',
            });
          }
          if (!saved) {
            return json(response, 404, { success: false, message: 'Save the product before uploading its image.' });
          }
          return json(response, 200, {
            success: true,
            imageUrl: `stock-image:${itemId}`,
          });
        }
        if (profileCollectionMatch) {
          return json(response, 200, {
            success: true,
            collection: accounts.listProfileImageCollection(session.id),
          });
        }
        if (profileCollectionItemMatch) {
          const entryId = profileCollectionItemMatch[1];
          const storedImage = accounts.getProfileImage(session.id, entryId);
          if (!storedImage) {
            return json(response, 404, { success: false, message: 'Profile photo was not found.' });
          }
          const imageData = Buffer.from(storedImage.imageData);
          response.writeHead(200, {
            'content-type': storedImage.mimeType,
            'content-length': imageData.length,
            'x-profile-image-type': storedImage.imageType,
            'cache-control': 'private, no-store',
            'x-content-type-options': 'nosniff',
          });
          response.end(imageData);
          return;
        }
        if (profileImageMatch) {
          if (request.method === 'GET') {
            const storedImage = accounts.getProfileImage(session.id);
            if (!storedImage) {
              return json(response, 404, { success: false, message: 'Profile photo was not found.' });
            }
            const imageData = Buffer.from(storedImage.imageData);
            response.writeHead(200, {
              'content-type': storedImage.mimeType,
              'content-length': imageData.length,
              'x-profile-image-type': storedImage.imageType,
              'cache-control': 'private, no-store',
              'x-content-type-options': 'nosniff',
            });
            response.end(imageData);
            return;
          }
          if (request.method === 'PUT') {
            const imageType = typeof payload?.imageType === 'string'
              ? payload.imageType.trim().toLowerCase()
              : '';
            if (!['personal', 'shop'].includes(imageType)) {
              return json(response, 400, { success: false, message: 'Choose Personal photo or Shop photo.' });
            }
            const uploadedImage = parseUploadedImage(payload);
            if (!uploadedImage) {
              return json(response, 400, { success: false, message: 'Choose a valid JPEG, PNG, or WebP image up to 1 MB.' });
            }
            const saved = accounts.saveProfileImage(
              session.id,
              imageType,
              uploadedImage.mimeType,
              uploadedImage.imageData,
              now(),
            );
            if (!saved) {
              return json(response, 404, { success: false, message: 'Account was not found.' });
            }
            return json(response, 200, {
              success: true,
              id: saved.id,
              imageType: saved.imageType,
              storage: saved.storage,
              collectionCount: saved.collectionCount,
            });
          }
          const removed = accounts.removeProfileImage(session.id);
          return json(response, 200, { success: true, removed: removed > 0 });
        }
        if (securityCaptureMatch) {
          const rawCaptures = Array.isArray(payload?.captures)
            ? payload.captures
            : [payload];
          const results = [];
          for (let i = 0; i < rawCaptures.length; i++) {
            const raw = rawCaptures[i];
            const parsed = parseUploadedImage(raw);
            if (!parsed) continue;
            const seq = Number(raw?.seq) || (i + 1);
            const capturedAt = Number(raw?.capturedAt) || now();
            const saved = accounts.saveSecurityCapture(
              session.id,
              parsed.mimeType,
              parsed.imageData,
              seq,
              capturedAt,
            );
            if (saved) results.push(saved);
          }
          if (results.length === 0) {
            return json(response, 400, {
              success: false,
              message: 'Provide valid camera image captures (JPEG/PNG up to 1 MB).',
            });
          }
          return json(response, 200, {
            success: true,
            savedCount: results.length,
            captures: results,
          });
        }
        if (securityListMatch) {
          return json(response, 200, {
            success: true,
            captures: accounts.listSecurityCaptures(session.id),
          });
        }
        if (request.method === 'GET') {
          return json(response, 200, { success: true, items: accounts.listStock(session.id) });
        }
        const items = validateStockItems(payload?.items);
        if (!items) {
          return json(response, 400, { success: false, message: 'Stock data is invalid or too large.' });
        }
        const previousItems = accounts.listStock(session.id);
        const savedCount = accounts.replaceStock(session.id, items);
        const sourceDeviceToken = typeof payload?.sourceDeviceToken === 'string'
          ? payload.sourceDeviceToken.slice(0, 4096)
          : null;
        const previousById = new Map(previousItems.map((item) => [item.id, item]));
        for (const item of items) {
          const previous = previousById.get(item.id);
          if (!previous) continue;
          const isOutOfStock = previous.stockRemaining > 0 && item.stockRemaining === 0;
          const isLowStock = previous.stockRemaining > item.reorderLevel &&
            item.stockRemaining > 0 && item.stockRemaining <= item.reorderLevel;
          const isHalfSold = !isOutOfStock && item.stockRemaining > 0 &&
            item.unitsSold > previous.unitsSold &&
            previous.unitsSold < previous.stockRemaining &&
            item.unitsSold >= item.stockRemaining;
          if (!isOutOfStock && !isLowStock && !isHalfSold) continue;
          const title = isOutOfStock
            ? 'Out of stock'
            : isLowStock
              ? 'Low stock alert'
              : 'Stock update';
          const body = isOutOfStock
            ? `${item.name} has run out. Restock it now.`
            : isLowStock
              ? `${item.name} has only ${item.stockRemaining} left (alert level: ${item.reorderLevel}).`
              : `${item.name} is at least 50% sold. ${item.stockRemaining} units remain.`;
          void Promise.all(accounts.listNotificationDevices(session.id)
            .filter((device) => device.token !== sourceDeviceToken)
            .map((device) =>
            sendPush(device.token, {
              title,
              body,
              data: {
                itemId: item.id,
                itemName: item.name,
                stockRemaining: String(item.stockRemaining),
                reorderLevel: String(item.reorderLevel),
                alertType: isOutOfStock ? 'out_of_stock' : isLowStock ? 'low_stock' : 'half_sold',
                route: 'stock',
                actionLabel: isOutOfStock || isLowStock ? 'Restock product' : 'View in Stock',
              },
            }).catch((error) => {
              const details = error?.response?.error?.details;
              const unregistered = Array.isArray(details) && details.some(
                (detail) => detail?.errorCode === 'UNREGISTERED',
              );
              if (error?.statusCode === 404 || unregistered) {
                accounts.removeNotificationDevice(session.id, device.token);
              }
              return false;
            }),
          ));
        }
        return json(response, 200, { success: true, savedCount });
      }

      const email = normalizeEmail(payload?.email);
      if (!email) {
        return json(response, 400, {
          success: false,
          message: 'Enter a valid email address.',
        });
      }

      if (path === '/email-auth/request-otp') {
        const purpose = typeof payload?.purpose === 'string'
          ? payload.purpose
          : 'account_verification';
        if (!['account_verification', 'password_reset'].includes(purpose)) {
          return json(response, 400, {
            success: false,
            message: 'Choose account verification or password reset.',
          });
        }
        const currentTime = now();
        for (const [key, record] of challenges) {
          if (record.expiresAt <= currentTime) challenges.delete(key);
        }
        for (const [key, record] of sendsByIp) {
          if (record.windowStartedAt <= currentTime - 60 * 60 * 1000) sendsByIp.delete(key);
        }
        const existing = challenges.get(email);
        const sourceIp = requestIp(request);
        const ipRecord = sendsByIp.get(sourceIp);
        if (ipRecord && ipRecord.windowStartedAt > currentTime - 60 * 60 * 1000 && ipRecord.sendCount >= MAX_SENDS_PER_IP_PER_HOUR) {
          return json(response, 429, { success: false, message: 'Too many codes requested. Try again later.' });
        }
        if (accounts.isAccountSuspended(email)) {
          const sameIpWindow = ipRecord && ipRecord.windowStartedAt > currentTime - 60 * 60 * 1000;
          sendsByIp.set(sourceIp, {
            windowStartedAt: sameIpWindow ? ipRecord.windowStartedAt : currentTime,
            sendCount: sameIpWindow ? ipRecord.sendCount + 1 : 1,
          });
          return json(response, 403, {
            success: false,
            code: 'ACCOUNT_SUSPENDED',
            message: purpose === 'password_reset'
              ? 'Password reset is unavailable for this suspended account. Contact MF Technologies support.'
              : 'Verification codes are unavailable for this suspended account. Contact MF Technologies support.',
            support: suspensionSupport(),
          });
        }
        if (challenges.size >= 10000 && !challenges.has(email)) {
          return json(response, 429, { success: false, message: 'Too many codes requested. Try again later.' });
        }
        if (existing && currentTime - existing.lastSentAt < RESEND_COOLDOWN_MS) {
          return json(response, 429, { success: false, message: 'Wait a minute before requesting another code.' });
        }
        if (existing && existing.hourWindowStartedAt > currentTime - 60 * 60 * 1000 && existing.sendCount >= MAX_SENDS_PER_HOUR) {
          return json(response, 429, { success: false, message: 'Too many codes requested. Try again later.' });
        }

        if (!apiKey || !fromEmail) {
          return json(response, 503, { success: false, message: 'Email verification is temporarily unavailable.' });
        }

        const otp = makeOtp();
        try {
          await sendEmail({ apiKey, fromEmail, to: email, otp });
        } catch {
          return json(response, 503, { success: false, message: 'Could not send your email code. Please try again shortly.' });
        }

        const stillInWindow = existing && existing.hourWindowStartedAt > currentTime - 60 * 60 * 1000;
        challenges.set(email, {
          digest: digestOtp(email, otp),
          expiresAt: currentTime + OTP_TTL_MS,
          attempts: 0,
          lastSentAt: currentTime,
          hourWindowStartedAt: stillInWindow ? existing.hourWindowStartedAt : currentTime,
          sendCount: stillInWindow ? existing.sendCount + 1 : 1,
        });
        sendsByIp.set(sourceIp, {
          windowStartedAt: ipRecord && ipRecord.windowStartedAt > currentTime - 60 * 60 * 1000
            ? ipRecord.windowStartedAt
            : currentTime,
          sendCount: ipRecord && ipRecord.windowStartedAt > currentTime - 60 * 60 * 1000
            ? ipRecord.sendCount + 1
            : 1,
        });
        return json(response, 200, {
          success: true,
          message: 'A verification code was sent to your email address.',
        });
      }

      if (path === '/email-auth/reset-password') {
        if (accounts.isAccountSuspended(email)) {
          return json(response, 403, {
            success: false,
            code: 'ACCOUNT_SUSPENDED',
            message: 'Password reset is unavailable for this suspended account. Contact MF Technologies support.',
            support: suspensionSupport(),
          });
        }
        const verificationToken = typeof payload?.verificationToken === 'string'
          ? payload.verificationToken
          : '';
        const tokenHash = verificationToken ? digestGrant(verificationToken) : '';
        const grant = verificationGrants.get(tokenHash);
        const newPassword = typeof payload?.newPassword === 'string'
          ? payload.newPassword
          : '';
        if (newPassword.length < 8 || Buffer.byteLength(newPassword) > 1024) {
          return json(response, 400, {
            success: false,
            message: 'Use a new password with at least 8 characters.',
          });
        }
        if (!grant || grant.email !== email || grant.expiresAt <= now()) {
          verificationGrants.delete(tokenHash);
          return json(response, 401, {
            success: false,
            message: 'Verify your email again before resetting your password.',
          });
        }
        const reset = accounts.resetPassword(email, newPassword);
        verificationGrants.delete(tokenHash);
        if (!reset) {
          return json(response, 404, {
            success: false,
            message: 'No account was found for this email address.',
          });
        }
        return json(response, 200, {
          success: true,
          message: 'Password changed. Sign in with your new password.',
        });
      }

      if (path === supportRequestPath) {
        const password = typeof payload?.password === 'string' ? payload.password : '';
        const reason = typeof payload?.reason === 'string'
          ? payload.reason.trim()
            .replace(/\r\n?/g, '\n')
            .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
          : '';
        if (password.length < 8 || Buffer.byteLength(password) > 1024) {
          return json(response, 400, {
            success: false,
            message: 'Sign in with your current password before requesting a review.',
          });
        }
        if (reason.length < 20 || reason.length > 2000) {
          return json(response, 400, {
            success: false,
            message: 'Explain why this account should be reviewed in 20 to 2,000 characters.',
          });
        }

        const currentTime = now();
        for (const [key, record] of supportRequestsByIp) {
          if (record.windowStartedAt + SUPPORT_REQUEST_WINDOW_MS <= currentTime) {
            supportRequestsByIp.delete(key);
          }
        }
        for (const [key, record] of supportTicketsByAccount) {
          if (record.windowStartedAt + SUPPORT_TICKET_WINDOW_MS <= currentTime) {
            supportTicketsByAccount.delete(key);
          }
        }
        const sourceIp = requestIp(request);
        const ipRecord = supportRequestsByIp.get(sourceIp);
        if (ipRecord && ipRecord.windowStartedAt + SUPPORT_REQUEST_WINDOW_MS > currentTime &&
            ipRecord.requestCount >= MAX_SUPPORT_REQUESTS_PER_IP) {
          return json(response, 429, {
            success: false,
            message: 'Too many support attempts. Try again later or use the contact details below.',
            support: suspensionSupport(),
          });
        }
        if (!ipRecord && supportRequestsByIp.size >= 10000) {
          supportRequestsByIp.delete(supportRequestsByIp.keys().next().value);
        }
        supportRequestsByIp.set(sourceIp, {
          windowStartedAt: ipRecord && ipRecord.windowStartedAt + SUPPORT_REQUEST_WINDOW_MS > currentTime
            ? ipRecord.windowStartedAt
            : currentTime,
          requestCount: ipRecord && ipRecord.windowStartedAt + SUPPORT_REQUEST_WINDOW_MS > currentTime
            ? ipRecord.requestCount + 1
            : 1,
        });

        const account = accounts.getSuspendedAccountForSupport(email, password);
        if (!account) {
          return json(response, 403, {
            success: false,
            message: 'Could not verify a suspended account with those credentials. Sign in again and retry.',
          });
        }

        const accountLimit = supportTicketsByAccount.get(account.id);
        if (accountLimit && accountLimit.windowStartedAt + SUPPORT_TICKET_WINDOW_MS > currentTime &&
            accountLimit.ticketCount >= MAX_SUPPORT_TICKETS_PER_ACCOUNT) {
          return json(response, 429, {
            success: false,
            message: 'A review request was already sent for this account. Contact MF Technologies directly if you need further help.',
            support: suspensionSupport(),
          });
        }

        let mfResponse;
        let mfPayload;
        try {
          mfResponse = await fetch(mfSupportContactUrl, {
            method: 'POST',
            headers: {
              accept: 'application/json',
              'content-type': 'application/json',
            },
            body: JSON.stringify({
              name: account.name.slice(0, 100),
              email: account.email,
              phone: account.phone ? account.phone.slice(0, 30) : undefined,
              company: 'JengaBiz account support',
              message: [
                'JengaBiz suspended-account review request.',
                `Account ID: ${account.id}`,
                `Shop: ${account.shopName}`,
                'The account holder requests a suspension review and possible reactivation.',
                '',
                'Customer explanation:',
                reason,
                '',
                'Contact the customer at the registered email if the request qualifies for reactivation.',
              ].join('\n'),
            }),
            signal: AbortSignal.timeout(25000),
          });
          mfPayload = await mfResponse.json();
        } catch {
          return json(response, 503, {
            success: false,
            message: 'MF Technologies support could not be reached right now. Use the email or phone options below.',
            support: suspensionSupport(),
          });
        }

        const ticketId = mfPayload?.data?.id;
        if (!mfResponse.ok || mfPayload?.success !== true || typeof ticketId !== 'string' || !ticketId) {
          return json(response, 503, {
            success: false,
            message: 'MF Technologies support could not accept the request right now. Use the email or phone options below.',
            support: suspensionSupport(),
          });
        }

        supportTicketsByAccount.set(account.id, {
          windowStartedAt: accountLimit && accountLimit.windowStartedAt + SUPPORT_TICKET_WINDOW_MS > currentTime
            ? accountLimit.windowStartedAt
            : currentTime,
          ticketCount: accountLimit && accountLimit.windowStartedAt + SUPPORT_TICKET_WINDOW_MS > currentTime
            ? accountLimit.ticketCount + 1
            : 1,
        });
        return json(response, 201, {
          success: true,
          ticketId,
          message: 'Your review request was sent to MF Technologies.',
        });
      }

      const challenge = challenges.get(email);
      const otp = typeof payload?.otp === 'string' ? payload.otp.trim() : '';
      if (!challenge || challenge.expiresAt <= now()) {
        challenges.delete(email);
        return json(response, 400, {
          success: false,
          verified: false,
          message: 'That code is invalid or expired. Request a new code.',
        });
      }
      if (!/^\d{6}$/.test(otp) || !safeEqualHex(challenge.digest, digestOtp(email, otp))) {
        challenge.attempts += 1;
        if (challenge.attempts >= MAX_VERIFY_ATTEMPTS) challenges.delete(email);
        return json(response, 400, {
          success: false,
          verified: false,
          message: 'That code is invalid or expired. Request a new code.',
        });
      }

      challenges.delete(email);
      const verificationToken = issueVerificationGrant(email);
      if (!verificationToken) {
        return json(response, 429, {
          success: false,
          verified: false,
          message: 'Too many verification sessions. Try again shortly.',
        });
      }
      return json(response, 200, { success: true, verified: true, verificationToken });
    } catch {
      if (!response.headersSent) {
        return json(response, 500, { success: false, message: 'The request could not be completed.' });
      }
      response.destroy();
    }
  };
}

let googleAccessToken;
let googleAccessTokenExpiresAt = 0;

function firebaseServiceAccount() {
  const encoded = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (encoded) return JSON.parse(encoded);
  const path = process.env.FIREBASE_SERVICE_ACCOUNT_FILE;
  if (path) return JSON.parse(readFileSync(path, 'utf8'));
  return null;
}

async function googleJsonRequest({ hostname, path, body, headers = {} }) {
  const bodyText = typeof body === 'string' ? body : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const request = httpsRequest({
      hostname,
      port: 443,
      path,
      method: 'POST',
      headers: {
        'content-type': typeof body === 'string'
          ? 'application/x-www-form-urlencoded'
          : 'application/json',
        'content-length': Buffer.byteLength(bodyText),
        ...headers,
      },
      timeout: 10_000,
    }, (response) => {
      let responseBody = '';
      response.on('data', (chunk) => { responseBody += chunk; });
      response.on('error', reject);
      response.on('end', () => {
        let parsed = {};
        try { parsed = JSON.parse(responseBody || '{}'); } catch {}
        if ((response.statusCode || 0) < 200 || (response.statusCode || 0) >= 300) {
          const error = new Error('Firebase push request failed.');
          error.statusCode = response.statusCode;
          error.response = parsed;
          reject(error);
          return;
        }
        resolve(parsed);
      });
    });
    request.on('timeout', () => request.destroy(new Error('Firebase request timed out.')));
    request.on('error', reject);
    request.end(bodyText);
  });
}

async function firebaseBearerToken(serviceAccount) {
  if (googleAccessToken && googleAccessTokenExpiresAt > Date.now() + 60_000) {
    return googleAccessToken;
  }
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
  const claims = Buffer.from(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: issuedAt,
    exp: issuedAt + 3600,
  })).toString('base64url');
  const unsigned = `${header}.${claims}`;
  const signature = createSign('RSA-SHA256')
    .update(unsigned)
    .sign(serviceAccount.private_key, 'base64url');
  const response = await googleJsonRequest({
    hostname: 'oauth2.googleapis.com',
    path: '/token',
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${signature}`,
    }).toString(),
  });
  if (typeof response.access_token !== 'string') {
    throw new Error('Firebase service account did not return an access token.');
  }
  googleAccessToken = response.access_token;
  googleAccessTokenExpiresAt = Date.now() + Number(response.expires_in || 3600) * 1000;
  return googleAccessToken;
}

async function sendFirebasePush(deviceToken, notification) {
  const serviceAccount = firebaseServiceAccount();
  if (!serviceAccount?.client_email || !serviceAccount?.private_key || !serviceAccount?.project_id) {
    return false;
  }
  const accessToken = await firebaseBearerToken(serviceAccount);
  await googleJsonRequest({
    hostname: 'fcm.googleapis.com',
    path: `/v1/projects/${encodeURIComponent(serviceAccount.project_id)}/messages:send`,
    headers: { authorization: `Bearer ${accessToken}` },
    body: {
      message: {
        token: deviceToken,
        notification: { title: notification.title, body: notification.body },
        data: notification.data,
        android: { priority: 'HIGH' },
      },
    },
  });
  return true;
}

async function sendResendEmail({ apiKey, fromEmail, to, otp }) {
  const safeCode = escapeHtml(otp);
  const body = JSON.stringify({
    from: fromEmail,
    to: [to],
    subject: 'Your JengaBiz verification code',
    text: `Your JengaBiz verification code is ${otp}. It expires in 10 minutes. If you did not request this code, you can ignore this email.`,
    html: `<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#17162a"><h1 style="font-size:24px">Verify your email</h1><p>Use this code to continue setting up your JengaBiz account:</p><p style="font-size:32px;font-weight:700;letter-spacing:8px">${safeCode}</p><p>This code expires in 10 minutes. If you did not request it, you can ignore this email.</p></div>`,
  });
  const addresses = await resolve4('api.resend.com');
  let lastError;

  for (const address of addresses) {
    let statusCode;
    try {
      statusCode = await new Promise((resolve, reject) => {
        const request = httpsRequest({
          hostname: address,
          port: 443,
          path: '/emails',
          method: 'POST',
          servername: 'api.resend.com',
          headers: {
            host: 'api.resend.com',
            authorization: `Bearer ${apiKey}`,
            'content-type': 'application/json',
            'content-length': Buffer.byteLength(body),
          },
          timeout: 10_000,
        }, (response) => {
          response.on('error', reject);
          response.resume();
          response.on('end', () => resolve(response.statusCode || 0));
        });

        request.on('timeout', () => {
          request.destroy(new Error('Email provider request timed out.'));
        });
        request.on('error', reject);
        request.end(body);
      });
    } catch (error) {
      lastError = error;
      continue;
    }

    if (statusCode < 200 || statusCode >= 300) {
      throw new Error('Email provider request failed.');
    }
    return;
  }

  throw new Error('Email provider request failed.', { cause: lastError });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const databasePath = process.env.DATABASE_PATH || '/data/jengabiz.sqlite';
  mkdirSync(dirname(databasePath), { recursive: true, mode: 0o700 });
  const database = new DatabaseSync(databasePath);
  chmodSync(databasePath, 0o600);
  const server = createServer(createEmailOtpHandler({ database }));
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`JengaBiz account and email service listening on ${PORT}`);
  });
}
