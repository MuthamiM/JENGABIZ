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
const MAX_STOCK_IMAGE_BODY_BYTES = 1400 * 1024;
const MAX_STOCK_IMAGE_BYTES = 1024 * 1024;
const MAX_LOGIN_FAILURES = 10;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;

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

function parseStockImage(payload) {
  const mimeType = payload?.mimeType;
  const encoded = payload?.imageBase64;
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(mimeType) ||
      typeof encoded !== 'string' || encoded.length > 1_400_000 ||
      encoded.length % 4 !== 0 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
    return null;
  }
  const imageData = Buffer.from(encoded, 'base64');
  if (!imageData.length || imageData.length > MAX_STOCK_IMAGE_BYTES) return null;
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
  now = Date.now,
  makeOtp = () => String(randomInt(100000, 1000000)),
  database = new DatabaseSync(':memory:'),
} = {}) {
  const accounts = createAccountStore(database, { now });
  const challenges = new Map();
  const sendsByIp = new Map();
  const loginFailures = new Map();
  const verificationGrants = new Map();
  const digestOtp = (email, otp) =>
    createHash('sha256')
      .update(`${hashSecret}\0${email}\0${otp}`)
      .digest('hex');
  const digestGrant = (token) => createHash('sha256').update(token).digest('hex');

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
      if (request.method === 'GET' && path === '/health') {
        return json(response, 200, { status: 'ok' });
      }

      const otpPaths = [
        '/email-auth/request-otp',
        '/email-auth/verify-otp',
        '/email-auth/reset-password',
      ];
      const accountPaths = [
        '/email-auth/register',
        '/email-auth/migrate',
        '/email-auth/login',
        '/email-auth/me',
        '/email-auth/logout',
        '/email-auth/stock/items',
        '/email-auth/notifications/device',
        '/email-auth/referrals',
        '/email-auth/referrals/location',
      ];
      const isAccountPath = accountPaths.includes(path) || stockImageMatch !== null;
      const allowed = otpPaths.includes(path) || isAccountPath;
      const allowedMethod = stockImageMatch
        ? ['GET', 'PUT'].includes(request.method)
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
        : request.method === 'POST';
      if (!allowed || !allowedMethod) {
        return json(response, 404, { success: false, message: 'Not found.' });
      }

      let payload;
      if (request.method !== 'GET') {
        try {
          const bodyLimit = path === '/email-auth/stock/items'
            ? MAX_STOCK_BODY_BYTES
            : stockImageMatch
              ? MAX_STOCK_IMAGE_BODY_BYTES
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

        if (path === '/email-auth/logout') {
          const session = accounts.authenticate(bearer);
          if (!session) return json(response, 401, { success: false, message: 'Sign in again to continue.' });
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
          accounts.saveNotificationDevice(session.id, deviceToken, platform, now());
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
          const uploadedImage = parseStockImage(payload);
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
              data: { itemId: item.id, stockRemaining: String(item.stockRemaining) },
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
        const existing = challenges.get(email);
        const currentTime = now();
        for (const [key, record] of challenges) {
          if (record.expiresAt <= currentTime) challenges.delete(key);
        }
        for (const [key, record] of sendsByIp) {
          if (record.windowStartedAt <= currentTime - 60 * 60 * 1000) sendsByIp.delete(key);
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

        const sourceIp = requestIp(request);
        const ipRecord = sendsByIp.get(sourceIp);
        if (ipRecord && ipRecord.windowStartedAt > currentTime - 60 * 60 * 1000 && ipRecord.sendCount >= MAX_SENDS_PER_IP_PER_HOUR) {
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
