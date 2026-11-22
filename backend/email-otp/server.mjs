import { createHash, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import { resolve4 } from 'node:dns/promises';
import { request as httpsRequest } from 'node:https';
import { createServer } from 'node:http';
import { mkdirSync, chmodSync } from 'node:fs';
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
    const password = typeof payload.password === 'string' ? payload.password : '';
    if (!name || name.length > 120 || !shopName || shopName.length > 120 || phone.length > 40) {
      return null;
    }
    if (password.length < 8 || Buffer.byteLength(password) > 1024) return null;
    const items = validateStockItems(payload.items ?? []);
    if (!items) return null;
    return { name, shopName, phone, password, items };
  }

  function requestIp(request) {
    const forwarded = request.headers['cf-connecting-ip'];
    return (typeof forwarded === 'string' ? forwarded : request.socket.remoteAddress || 'unknown')
      .slice(0, 64);
  }

  return async (request, response) => {
    try {
      const path = new URL(request.url || '/', 'http://localhost').pathname;
      if (request.method === 'GET' && path === '/health') {
        return json(response, 200, { status: 'ok' });
      }

      const otpPaths = ['/email-auth/request-otp', '/email-auth/verify-otp'];
      const accountPaths = [
        '/email-auth/register',
        '/email-auth/migrate',
        '/email-auth/login',
        '/email-auth/logout',
        '/email-auth/stock/items',
      ];
      const allowed = otpPaths.includes(path) || accountPaths.includes(path);
      const allowedMethod = path === '/email-auth/stock/items'
        ? ['GET', 'PUT'].includes(request.method)
        : request.method === 'POST';
      if (!allowed || !allowedMethod) {
        return json(response, 404, { success: false, message: 'Not found.' });
      }

      let payload;
      if (request.method !== 'GET') {
        try {
          payload = await readJson(request, path === '/email-auth/stock/items'
            ? MAX_STOCK_BODY_BYTES
            : MAX_BODY_BYTES);
        } catch (error) {
          const status = error.statusCode || 400;
          return json(response, status, {
            success: false,
            message: status === 413 ? 'Request is too large.' : 'Invalid request.',
          });
        }
      }

      if (accountPaths.includes(path)) {
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
        if (request.method === 'GET') {
          return json(response, 200, { success: true, items: accounts.listStock(session.id) });
        }
        const items = validateStockItems(payload?.items);
        if (!items) {
          return json(response, 400, { success: false, message: 'Stock data is invalid or too large.' });
        }
        const savedCount = accounts.replaceStock(session.id, items);
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
