import assert from 'node:assert/strict';
import { randomBytes, scryptSync } from 'node:crypto';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, unlinkSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createEmailOtpHandler } from './server.mjs';

async function withService(options, action) {
  const server = createServer(createEmailOtpHandler(options));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  try {
    await action(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function post(baseUrl, path, payload) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return { status: response.status, body: await response.json() };
}

async function request(baseUrl, path, { method = 'GET', payload, token } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(payload === undefined ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(payload === undefined ? {} : { body: JSON.stringify(payload) }),
  });
  return { status: response.status, body: await response.json() };
}

test('sends a hidden six digit email code and verifies it once', async () => {
  let sentMessage;
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    makeOtp: () => '246810',
    sendEmail: async (message) => { sentMessage = message; },
  }, async (baseUrl) => {
    const requested = await post(baseUrl, '/email-auth/request-otp', {
      email: ' Musa@example.com ',
    });
    assert.equal(requested.status, 200);
    assert.equal(requested.body.success, true);
    assert.equal(JSON.stringify(requested.body).includes('246810'), false);
    assert.equal(sentMessage.to, 'musa@example.com');

    const verified = await post(baseUrl, '/email-auth/verify-otp', {
      email: 'musa@example.com',
      otp: '246810',
    });
    assert.equal(verified.status, 200);
    assert.equal(verified.body.verified, true);
    assert.equal(typeof verified.body.verificationToken, 'string');

    const replay = await post(baseUrl, '/email-auth/verify-otp', {
      email: 'musa@example.com',
      otp: '246810',
    });
    assert.equal(replay.status, 400);
    assert.equal(replay.body.verified, false);
  });
});

test('verified account, session, and stock data persist in scoped SQLite records', async () => {
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    makeOtp: () => '246810',
    sendEmail: async () => {},
  }, async (baseUrl) => {
    await post(baseUrl, '/email-auth/request-otp', { email: 'musa@example.com' });
    const verification = await post(baseUrl, '/email-auth/verify-otp', {
      email: 'musa@example.com',
      otp: '246810',
    });
    const verificationToken = verification.body.verificationToken;
    const firstStock = [{
      id: 'item-1', name: 'Maize Flour', category: 'Food', price: 200,
      costPrice: 170, stockRemaining: 12, unitsSold: 4, sku: 'MF-1',
      imageUrl: '', reorderLevel: 5,
    }];
    const registered = await post(baseUrl, '/email-auth/register', {
      email: 'musa@example.com',
      verificationToken,
      name: 'Musa Mangi',
      shopName: 'Umoja Shop',
      phone: '',
      password: 'correct horse battery',
      items: firstStock,
    });
    assert.equal(registered.status, 201);
    assert.equal(registered.body.user.email, 'musa@example.com');
    assert.equal('passwordHash' in registered.body.user, false);
    assert.equal('password' in registered.body.user, false);

    const anonymousStock = await request(baseUrl, '/email-auth/stock/items');
    assert.equal(anonymousStock.status, 401);
    const sessionToken = registered.body.sessionToken;
    const savedStock = await request(baseUrl, '/email-auth/stock/items', {
      token: sessionToken,
    });
    assert.deepEqual(savedStock.body.items, firstStock);

    const updatedStock = [{ ...firstStock[0], stockRemaining: 9 }];
    const update = await request(baseUrl, '/email-auth/stock/items', {
      method: 'PUT',
      token: sessionToken,
      payload: { items: updatedStock },
    });
    assert.equal(update.body.savedCount, 1);

    const login = await post(baseUrl, '/email-auth/login', {
      email: 'musa@example.com',
      password: 'correct horse battery',
    });
    assert.equal(login.status, 200);
    const afterLogin = await request(baseUrl, '/email-auth/stock/items', {
      token: login.body.sessionToken,
    });
    assert.deepEqual(afterLogin.body.items, updatedStock);

    const wrongPassword = await post(baseUrl, '/email-auth/login', {
      email: 'musa@example.com',
      password: 'incorrect password',
    });
    assert.equal(wrongPassword.status, 401);
    assert.equal(JSON.stringify(wrongPassword.body).includes('incorrect password'), false);
  });
});

test('Kenya referrals use detected counties and award points by county', async () => {
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    makeOtp: () => '246810',
    sendEmail: async () => {},
  }, async (baseUrl) => {
    async function register(email, { county = '', referralCode = '' } = {}) {
      await post(baseUrl, '/email-auth/request-otp', { email });
      const verification = await post(baseUrl, '/email-auth/verify-otp', {
        email,
        otp: '246810',
      });
      return post(baseUrl, '/email-auth/register', {
        email,
        verificationToken: verification.body.verificationToken,
        name: 'QA Owner',
        shopName: 'QA Shop',
        phone: '',
        password: 'correct horse battery',
        county,
        referralCode,
        items: [],
      });
    }

    const inviter = await register('inviter@example.com');
    assert.equal(inviter.status, 201);
    const inviterToken = inviter.body.sessionToken;
    const savedLocation = await request(
      baseUrl,
      '/email-auth/referrals/location',
      {
        method: 'PUT',
        token: inviterToken,
        payload: { country: 'Uganda', county: 'Nairobi County' },
      },
    );
    assert.equal(savedLocation.status, 200);
    assert.equal(savedLocation.body.user.country, 'KE');
    assert.equal(savedLocation.body.user.county, 'Nairobi');
    assert.equal(savedLocation.body.user.countyDetected, true);

    const referralCode = inviter.body.user.referralCode;
    const sameCounty = await register('same@example.com', {
      county: 'Nairobi County',
      referralCode,
    });
    const differentCounty = await register('different@example.com', {
      county: 'Mombasa County',
      referralCode,
    });
    const invalidCounty = await register('invalid@example.com', {
      county: 'California',
      referralCode,
    });
    assert.equal(sameCounty.status, 201);
    assert.equal(differentCounty.status, 201);
    assert.equal(invalidCounty.status, 400);
    assert.match(invalidCounty.body.message, /location/i);

    const summary = await request(baseUrl, '/email-auth/referrals', {
      token: inviterToken,
    });
    assert.equal(summary.status, 200);
    assert.equal(summary.body.totalPoints, 125);
    assert.equal(summary.body.sameCountyCount, 1);
    assert.equal(summary.body.differentCountyCount, 1);
    assert.equal(summary.body.referralCount, 2);
  });
});

test('stock images require a signed-in shop and stay isolated to that account', async () => {
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    makeOtp: () => '246810',
    sendEmail: async () => {},
  }, async (baseUrl) => {
    async function register(email) {
      await post(baseUrl, '/email-auth/request-otp', { email });
      const verification = await post(baseUrl, '/email-auth/verify-otp', {
        email,
        otp: '246810',
      });
      const registered = await post(baseUrl, '/email-auth/register', {
        email,
        verificationToken: verification.body.verificationToken,
        name: 'QA Shop Owner',
        shopName: 'QA Shop',
        phone: '',
        password: 'correct horse battery',
        items: [{
          id: 'image-item', name: 'Image Item', category: 'General',
          price: 10, costPrice: 5, stockRemaining: 2, unitsSold: 0,
          sku: '', imageUrl: '', reorderLevel: 1,
        }],
      });
      return registered.body.sessionToken;
    }

    const ownerToken = await register('owner@example.com');
    const otherToken = await register('other@example.com');
    const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4]);
    const imagePath = '/email-auth/stock/images/image-item';

    const anonymous = await fetch(`${baseUrl}${imagePath}`);
    assert.equal(anonymous.status, 401);

    const invalidUpload = await request(baseUrl, imagePath, {
      method: 'PUT',
      token: ownerToken,
      payload: { mimeType: 'image/png', imageBase64: Buffer.from('bad').toString('base64') },
    });
    assert.equal(invalidUpload.status, 400);

    const uploaded = await request(baseUrl, imagePath, {
      method: 'PUT',
      token: ownerToken,
      payload: { mimeType: 'image/png', imageBase64: png.toString('base64') },
    });
    assert.equal(uploaded.status, 200);
    assert.equal(uploaded.body.imageUrl, 'stock-image:image-item');

    const ownerImage = await fetch(`${baseUrl}${imagePath}`, {
      headers: { authorization: `Bearer ${ownerToken}` },
    });
    assert.equal(ownerImage.status, 200);
    assert.equal(ownerImage.headers.get('content-type'), 'image/png');
    assert.deepEqual(Buffer.from(await ownerImage.arrayBuffer()), png);

    const otherImage = await fetch(`${baseUrl}${imagePath}`, {
      headers: { authorization: `Bearer ${otherToken}` },
    });
    assert.equal(otherImage.status, 404);

    const removed = await request(baseUrl, '/email-auth/stock/items', {
      method: 'PUT',
      token: ownerToken,
      payload: { items: [{
        id: 'image-item', name: 'Image Item', category: 'General',
        price: 10, costPrice: 5, stockRemaining: 2, unitsSold: 0,
        sku: '', imageUrl: '', reorderLevel: 1,
      }] },
    });
    assert.equal(removed.status, 200);
    const deletedImage = await fetch(`${baseUrl}${imagePath}`, {
      headers: { authorization: `Bearer ${ownerToken}` },
    });
    assert.equal(deletedImage.status, 404);
  });
});

test('sessions remain valid until explicitly revoked', async () => {
  let currentTime = 1_000_000;
  const day = 24 * 60 * 60 * 1000;
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    now: () => currentTime,
    makeOtp: () => '246810',
    sendEmail: async () => {},
  }, async (baseUrl) => {
    await post(baseUrl, '/email-auth/request-otp', { email: 'musa@example.com' });
    const verification = await post(baseUrl, '/email-auth/verify-otp', {
      email: 'musa@example.com',
      otp: '246810',
    });
    const registered = await post(baseUrl, '/email-auth/register', {
      email: 'musa@example.com',
      verificationToken: verification.body.verificationToken,
      name: 'Musa Mangi',
      shopName: 'Umoja Shop',
      phone: '',
      password: 'correct horse battery',
      items: [],
    });
    const token = registered.body.sessionToken;

    currentTime += 5 * 365 * day;
    const restored = await request(baseUrl, '/email-auth/me', { token });
    assert.equal(restored.status, 200);
    assert.equal(restored.body.user.email, 'musa@example.com');
    assert.equal((await request(baseUrl, '/email-auth/stock/items', { token })).status, 200);

    const signedOut = await request(baseUrl, '/email-auth/logout', {
      method: 'POST',
      token,
      payload: {},
    });
    assert.equal(signedOut.status, 200);
    assert.equal((await request(baseUrl, '/email-auth/me', { token })).status, 401);
  });
});

test('stock alert device tokens are account scoped and alerts fire on low or empty transitions', async () => {
  const pushes = [];
  const stock = [{
    id: 'item-1', name: 'Maize Flour', category: 'Food', price: 200,
    costPrice: 170, stockRemaining: 12, unitsSold: 4, sku: 'MF-1',
    imageUrl: '', reorderLevel: 5,
  }];
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    makeOtp: () => '246810',
    sendEmail: async () => {},
    sendPush: async (token, notification) => {
      pushes.push({ token, ...notification });
      return true;
    },
  }, async (baseUrl) => {
    await post(baseUrl, '/email-auth/request-otp', { email: 'musa@example.com' });
    const verification = await post(baseUrl, '/email-auth/verify-otp', {
      email: 'musa@example.com',
      otp: '246810',
    });
    const registered = await post(baseUrl, '/email-auth/register', {
      email: 'musa@example.com',
      verificationToken: verification.body.verificationToken,
      name: 'Musa Mangi',
      shopName: 'Umoja Shop',
      phone: '',
      password: 'correct horse battery',
      items: stock,
    });
    const token = registered.body.sessionToken;
    const anonymous = await request(baseUrl, '/email-auth/notifications/device', {
      method: 'POST',
      payload: { deviceToken: 'device-token-1', platform: 'android' },
    });
    assert.equal(anonymous.status, 401);

    const subscribed = await request(baseUrl, '/email-auth/notifications/device', {
      method: 'POST',
      token,
      payload: { deviceToken: 'device-token-1', platform: 'android' },
    });
    assert.equal(subscribed.status, 200);

    await request(baseUrl, '/email-auth/stock/items', {
      method: 'PUT',
      token,
      payload: { items: [{ ...stock[0], stockRemaining: 8, unitsSold: 8 }] },
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(pushes.length, 1);
    assert.equal(pushes[0].token, 'device-token-1');
    assert.equal(pushes[0].title, 'Stock update');
    assert.equal(pushes[0].body, 'Maize Flour is at least 50% sold. 8 units remain.');

    await request(baseUrl, '/email-auth/stock/items', {
      method: 'PUT',
      token,
      payload: { items: [{ ...stock[0], stockRemaining: 5, unitsSold: 11 }] },
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(pushes.length, 2);
    assert.equal(pushes[1].title, 'Low stock alert');
    assert.equal(pushes[1].data.stockRemaining, '5');
    assert.equal(pushes[1].data.alertType, 'low_stock');
    assert.equal(pushes[1].data.route, 'stock');
    assert.equal(pushes[1].data.actionLabel, 'Restock product');

    await request(baseUrl, '/email-auth/stock/items', {
      method: 'PUT',
      token,
      payload: { items: [{ ...stock[0], stockRemaining: 0, unitsSold: 16 }] },
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(pushes.length, 3);
    assert.equal(pushes[2].title, 'Out of stock');
  });
});

test('resend is throttled and a later resend invalidates the old code', async () => {
  let currentTime = 100000;
  let sendCount = 0;
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    now: () => currentTime,
    makeOtp: () => (++sendCount === 1 ? '111111' : '222222'),
    sendEmail: async () => {},
  }, async (baseUrl) => {
    assert.equal((await post(baseUrl, '/email-auth/request-otp', {
      email: 'musa@example.com',
    })).status, 200);
    assert.equal((await post(baseUrl, '/email-auth/request-otp', {
      email: 'musa@example.com',
    })).status, 429);

    currentTime += 60000;
    assert.equal((await post(baseUrl, '/email-auth/request-otp', {
      email: 'musa@example.com',
    })).status, 200);
    assert.equal((await post(baseUrl, '/email-auth/verify-otp', {
      email: 'musa@example.com',
      otp: '111111',
    })).status, 400);
    assert.equal((await post(baseUrl, '/email-auth/verify-otp', {
      email: 'musa@example.com',
      otp: '222222',
    })).body.verified, true);
  });
});

test('rejects expired codes and hides email provider failures', async () => {
  let currentTime = 100000;
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    now: () => currentTime,
    makeOtp: () => '123456',
    sendEmail: async () => {},
  }, async (baseUrl) => {
    await post(baseUrl, '/email-auth/request-otp', { email: 'musa@example.com' });
    currentTime += 10 * 60 * 1000 + 1;
    assert.equal((await post(baseUrl, '/email-auth/verify-otp', {
      email: 'musa@example.com',
      otp: '123456',
    })).status, 400);
  });

  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    sendEmail: async () => { throw new Error('private provider detail'); },
  }, async (baseUrl) => {
    const response = await post(baseUrl, '/email-auth/request-otp', {
      email: 'musa@example.com',
    });
    assert.equal(response.status, 503);
    assert.equal(JSON.stringify(response.body).includes('private provider detail'), false);
  });
});

test('fails closed if the server has no email sender configured', async () => {
  await withService({
    apiKey: '',
    fromEmail: '',
    sendEmail: async () => assert.fail('email sender must not be called'),
  }, async (baseUrl) => {
    const response = await post(baseUrl, '/email-auth/request-otp', {
      email: 'musa@example.com',
    });
    assert.equal(response.status, 503);
    assert.equal(response.body.success, false);
  });
});

test('suspended accounts receive 201 ticketId from support/request even when upstream is slow', async () => {
  const receivedSupportPayloads = [];
  const supportServer = createServer(async (req, res) => {
    let body = '';
    for await (const chunk of req) body += chunk;
    receivedSupportPayloads.push(JSON.parse(body || '{}'));
    // Simulate >8s slow response? Keep fast in unit test while verifying JSON + 201 flow.
    await new Promise((resolve) => setTimeout(resolve, 60));
    res.writeHead(201, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      data: { id: 'TKT-1099', status: 'received' },
    }));
  });
  await new Promise((resolve) => supportServer.listen(0, '127.0.0.1', resolve));
  const supportAddr = supportServer.address();
  const saltBytes = randomBytes(16);
  const adminPassword = 'admin-secret-password';
  const adminPasswordSalt = saltBytes.toString('hex');
  const adminPasswordHash = scryptSync(adminPassword, saltBytes, 64).toString('hex');

  try {
    await withService({
      apiKey: 'test-key',
      fromEmail: 'verify@example.com',
      hashSecret: 'test-hash-secret',
      makeOtp: () => '246810',
      sendEmail: async () => {},
      adminEmail: 'admin@example.com',
      adminPasswordSalt,
      adminPasswordHash,
      mfSupportContactUrl: `http://127.0.0.1:${supportAddr.port}/api/contact`,
    }, async (baseUrl) => {
      await post(baseUrl, '/email-auth/request-otp', { email: 'musa@example.com' });
      const verification = await post(baseUrl, '/email-auth/verify-otp', {
        email: 'musa@example.com',
        otp: '246810',
      });
      const registered = await post(baseUrl, '/email-auth/register', {
        email: 'musa@example.com',
        verificationToken: verification.body.verificationToken,
        name: 'Musa Mangi',
        shopName: 'Umoja Shop',
        phone: '+254700111222',
        password: 'customer-password-123',
        items: [],
      });
      assert.equal(registered.status, 201);

      const adminLogin = await post(baseUrl, '/email-auth/admin/login', {
        email: 'admin@example.com',
        password: adminPassword,
      });
      assert.equal(adminLogin.status, 200);
      const suspended = await request(
        baseUrl,
        `/email-auth/admin/users/${registered.body.user.id}/status`,
        {
          method: 'PATCH',
          token: adminLogin.body.sessionToken,
          payload: { status: 'suspended' },
        },
      );
      assert.equal(suspended.status, 200);

      const resetBlocked = await post(baseUrl, '/email-auth/request-otp', {
        email: 'musa@example.com',
        purpose: 'password_reset',
      });
      assert.equal(resetBlocked.status, 403);
      assert.equal(resetBlocked.body.code, 'ACCOUNT_SUSPENDED');
      assert.match(resetBlocked.body.message, /Password reset is unavailable/);

      const review = await post(baseUrl, '/email-auth/support/request', {
        email: 'musa@example.com',
        password: 'customer-password-123',
        reason: 'Please review my shop suspension after updating details.',
      });
      assert.equal(review.status, 201);
      assert.equal(review.body.success, true);
      assert.equal(review.body.ticketId, 'TKT-1099');
      assert.equal(receivedSupportPayloads.length, 1);
      assert.equal(JSON.stringify(receivedSupportPayloads[0]).includes('customer-password-123'), false);
    });
  } finally {
    await new Promise((resolve) => supportServer.close(resolve));
  }
});

test('legacy app devices receive an update push after login while current apps do not', async () => {
  const pushes = [];
  await withService({
    apiKey: 'test-key',
    fromEmail: 'verify@example.com',
    hashSecret: 'test-hash-secret',
    makeOtp: () => '246810',
    sendEmail: async () => {},
    getLatestRelease: async () => ({ versionCode: 22, versionName: '1.1.11' }),
    sendPush: async (token, notification) => {
      pushes.push({ token, ...notification });
      return true;
    },
  }, async (baseUrl) => {
    await post(baseUrl, '/email-auth/request-otp', { email: 'legacy@example.com' });
    const verification = await post(baseUrl, '/email-auth/verify-otp', {
      email: 'legacy@example.com',
      otp: '246810',
    });
    const registered = await post(baseUrl, '/email-auth/register', {
      email: 'legacy@example.com',
      verificationToken: verification.body.verificationToken,
      name: 'Legacy Owner',
      shopName: 'Legacy Shop',
      phone: '',
      password: 'correct horse battery',
      items: [],
    });
    assert.equal(registered.status, 201);

    // Simulate an older app (<= 1.1.10) registering without appVersionCode.
    const oldDeviceReg = await request(baseUrl, '/email-auth/notifications/device', {
      method: 'POST',
      token: registered.body.sessionToken,
      payload: { deviceToken: 'old-app-token', platform: 'android' },
    });
    assert.equal(oldDeviceReg.status, 200);
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(pushes.length, 1);
    assert.equal(pushes[0].token, 'old-app-token');
    assert.equal(pushes[0].title, 'Update JengaBiz to v1.1.11');
    assert.equal(pushes[0].data.route, 'update');
    assert.equal(pushes[0].data.versionCode, '22');

    // Logging in again on that same old device does not duplicate push for v22.
    const login = await post(baseUrl, '/email-auth/login', {
      email: 'legacy@example.com',
      password: 'correct horse battery',
    });
    assert.equal(login.status, 200);
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(pushes.length, 1);

    // Simulate a device already running v1.1.11 (appVersionCode: 22).
    const newDeviceReg = await request(baseUrl, '/email-auth/notifications/device', {
      method: 'POST',
      token: login.body.sessionToken,
      payload: {
        deviceToken: 'new-app-token',
        platform: 'android',
        appVersionCode: 22,
      },
    });
    assert.equal(newDeviceReg.status, 200);
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(pushes.length, 1);
  });
});

test('profile photo uploads update active photo and preserve per-user collection in TeleDrive', async () => {
  const teledriveDir = mkdtempSync(join(tmpdir(), 'jengabiz-teledrive-'));
  const samplePng = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89,
  ]);
  const sampleJpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0xff, 0xd9]);
  const updatedJpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x01, 0xff, 0xd9]);

  try {
    await withService({
      apiKey: 'test-key',
      fromEmail: 'verify@example.com',
      hashSecret: 'test-hash-secret',
      makeOtp: () => '246810',
      sendEmail: async () => {},
      profileUploadsDir: teledriveDir,
    }, async (baseUrl) => {
      const unauthPut = await request(baseUrl, '/email-auth/profile/image', {
        method: 'PUT',
        payload: {
          imageType: 'personal',
          mimeType: 'image/png',
          imageBase64: samplePng.toString('base64'),
        },
      });
      assert.equal(unauthPut.status, 401);

      await post(baseUrl, '/email-auth/request-otp', { email: 'photo@example.com' });
      const verification = await post(baseUrl, '/email-auth/verify-otp', {
        email: 'photo@example.com',
        otp: '246810',
      });
      const registered = await post(baseUrl, '/email-auth/register', {
        email: 'photo@example.com',
        verificationToken: verification.body.verificationToken,
        name: 'Photo Owner',
        shopName: 'Photo Shop',
        phone: '',
        password: 'correct horse battery',
        items: [],
      });
      assert.equal(registered.status, 201);
      const token = registered.body.sessionToken;
      const accountId = registered.body.user.id;

      await post(baseUrl, '/email-auth/request-otp', { email: 'other@example.com' });
      const verificationB = await post(baseUrl, '/email-auth/verify-otp', {
        email: 'other@example.com',
        otp: '246810',
      });
      const registeredB = await post(baseUrl, '/email-auth/register', {
        email: 'other@example.com',
        verificationToken: verificationB.body.verificationToken,
        name: 'Second Owner',
        shopName: 'Second Shop',
        phone: '',
        password: 'correct horse battery',
        items: [],
      });
      assert.equal(registeredB.status, 201);
      const tokenB = registeredB.body.sessionToken;
      const accountIdB = registeredB.body.user.id;

      const badType = await request(baseUrl, '/email-auth/profile/image', {
        method: 'PUT',
        token,
        payload: {
          imageType: 'banner',
          mimeType: 'image/png',
          imageBase64: samplePng.toString('base64'),
        },
      });
      assert.equal(badType.status, 400);

      const badMagic = await request(baseUrl, '/email-auth/profile/image', {
        method: 'PUT',
        token,
        payload: {
          imageType: 'personal',
          mimeType: 'image/jpeg',
          imageBase64: samplePng.toString('base64'),
        },
      });
      assert.equal(badMagic.status, 400);

      const uploadPersonal = await request(baseUrl, '/email-auth/profile/image', {
        method: 'PUT',
        token,
        payload: {
          imageType: 'personal',
          mimeType: 'image/png',
          imageBase64: samplePng.toString('base64'),
        },
      });
      assert.equal(uploadPersonal.status, 200);
      assert.equal(uploadPersonal.body.imageType, 'personal');
      assert.equal(uploadPersonal.body.storage, 'teledrive');
      assert.equal(uploadPersonal.body.collectionCount, 1);

      const userDir = join(teledriveDir, accountId);
      const filesAfterFirst = readdirSync(userDir);
      assert.equal(filesAfterFirst.length, 1);
      const personalFilePath = join(userDir, filesAfterFirst[0]);
      assert.deepEqual(readFileSync(personalFilePath), samplePng);

      // Changing pic updates active profile photo AND keeps the previous upload in this user's collection.
      const uploadShop = await request(baseUrl, '/email-auth/profile/image', {
        method: 'PUT',
        token,
        payload: {
          imageType: 'shop',
          mimeType: 'image/jpeg',
          imageBase64: sampleJpeg.toString('base64'),
        },
      });
      assert.equal(uploadShop.status, 200);
      assert.equal(uploadShop.body.imageType, 'shop');
      assert.equal(uploadShop.body.storage, 'teledrive');
      assert.equal(uploadShop.body.collectionCount, 2);

      // Changing the same type again keeps all 3 in this user's collection.
      const uploadShopAgain = await request(baseUrl, '/email-auth/profile/image', {
        method: 'PUT',
        token,
        payload: {
          imageType: 'shop',
          mimeType: 'image/jpeg',
          imageBase64: updatedJpeg.toString('base64'),
        },
      });
      assert.equal(uploadShopAgain.status, 200);
      assert.equal(uploadShopAgain.body.collectionCount, 3);

      const filesAfterChanges = readdirSync(userDir);
      assert.equal(filesAfterChanges.length, 3);
      assert.equal(existsSync(personalFilePath), true);

      const fetchedActive = await fetch(`${baseUrl}/email-auth/profile/image`, {
        headers: { authorization: `Bearer ${token}` },
      });
      assert.equal(fetchedActive.status, 200);
      assert.equal(fetchedActive.headers.get('content-type'), 'image/jpeg');
      assert.equal(fetchedActive.headers.get('x-profile-image-type'), 'shop');
      assert.deepEqual(Buffer.from(await fetchedActive.arrayBuffer()), updatedJpeg);

      // Even if local disk active file is moved/deleted by TeleDrive, SQLite retains the blob
      // and re-creates the file on disk on demand!
      const listBefore = await fetch(`${baseUrl}/email-auth/profile/images`, {
        headers: { authorization: `Bearer ${token}` },
      });
      const listBeforeJson = await listBefore.json();
      const activeEntry = listBeforeJson.collection.find((e) => e.isActive);
      assert.ok(activeEntry && activeEntry.storagePath);
      const activeFilePath = join(teledriveDir, activeEntry.storagePath);
      assert.ok(existsSync(activeFilePath));
      unlinkSync(activeFilePath);
      assert.ok(!existsSync(activeFilePath));

      const fetchedFromDb = await fetch(`${baseUrl}/email-auth/profile/image`, {
        headers: { authorization: `Bearer ${token}` },
      });
      assert.equal(fetchedFromDb.status, 200);
      assert.equal(fetchedFromDb.headers.get('content-type'), 'image/jpeg');
      assert.deepEqual(Buffer.from(await fetchedFromDb.arrayBuffer()), updatedJpeg);
      // Verify active disk file was re-created
      assert.ok(existsSync(activeFilePath));

      const listCollection = await fetch(`${baseUrl}/email-auth/profile/images`, {
        headers: { authorization: `Bearer ${token}` },
      });
      assert.equal(listCollection.status, 200);
      const listJson = await listCollection.json();
      assert.equal(listJson.collection.length, 3);
      assert.equal(listJson.collection.filter((entry) => entry.isActive).length, 1);

      // Separate account saves into its own isolated TeleDrive collection folder.
      const uploadOther = await request(baseUrl, '/email-auth/profile/image', {
        method: 'PUT',
        token: tokenB,
        payload: {
          imageType: 'personal',
          mimeType: 'image/png',
          imageBase64: samplePng.toString('base64'),
        },
      });
      assert.equal(uploadOther.status, 200);
      assert.equal(uploadOther.body.collectionCount, 1);
      assert.equal(readdirSync(join(teledriveDir, accountIdB)).length, 1);

      // Removing current active photo clears GET /email-auth/profile/image while keeping prior collection entries intact.
      const deleted = await request(baseUrl, '/email-auth/profile/image', {
        method: 'DELETE',
        token,
        payload: {},
      });
      assert.equal(deleted.status, 200);
      assert.equal(deleted.body.removed, true);
      assert.equal(readdirSync(userDir).length, 2);

      const afterDelete = await fetch(`${baseUrl}/email-auth/profile/image`, {
        headers: { authorization: `Bearer ${token}` },
      });
      assert.equal(afterDelete.status, 404);
    });
  } finally {
    rmSync(teledriveDir, { recursive: true, force: true });
  }
});


test('security camera captures save to account folder in TeleDrive and list captures', async () => {
  const teledriveDir = mkdtempSync(join(tmpdir(), 'jengabiz-teledrive-sec-'));
  const validJpeg = (tag) => Buffer.concat([
    Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01]),
    Buffer.from(`-camera-capture-${tag}-`),
    Buffer.from([0xff, 0xd9]),
  ]);

  try {
    await withService({
      apiKey: 'test-key',
      fromEmail: 'verify@example.com',
      hashSecret: 'test-hash-secret',
      profileUploadsDir: teledriveDir,
      makeOtp: () => '998877',
      sendEmail: async () => {},
    }, async (baseUrl) => {
      await post(baseUrl, '/email-auth/request-otp', { email: 'security-cam@example.com' });
      const verification = await post(baseUrl, '/email-auth/verify-otp', {
        email: 'security-cam@example.com',
        otp: '998877',
      });
      const registered = await post(baseUrl, '/email-auth/register', {
        email: 'security-cam@example.com',
        verificationToken: verification.body.verificationToken,
        name: 'Cam Owner',
        shopName: 'Cam Shop',
        phone: '',
        password: 'correct horse battery',
        items: [],
      });
      assert.equal(registered.status, 201);
      const token = registered.body.sessionToken;
      const accountId = registered.body.user.id;

      const fakeJpegs = [validJpeg(1), validJpeg(2), validJpeg(3)];

      const uploadBatch = await request(baseUrl, '/email-auth/security/camera-capture', {
        method: 'POST',
        token,
        payload: {
          captures: fakeJpegs.map((data, index) => ({
            mimeType: 'image/jpeg',
            imageBase64: data.toString('base64'),
            seq: index + 1,
            capturedAt: Date.now() + index * 100,
          })),
        },
      });

      assert.equal(uploadBatch.status, 200);
      assert.equal(uploadBatch.body.success, true);
      assert.equal(uploadBatch.body.savedCount, 3);
      assert.equal(uploadBatch.body.captures.length, 3);
      assert.equal(uploadBatch.body.captures[0].storage, 'teledrive');

      const userDir = join(teledriveDir, accountId);
      const savedFiles = readdirSync(userDir).filter((name) => name.startsWith('security-'));
      assert.equal(savedFiles.length, 3);

      const listResponse = await fetch(`${baseUrl}/email-auth/security/captures`, {
        headers: { authorization: `Bearer ${token}` },
      });
      assert.equal(listResponse.status, 200);
      const listJson = await listResponse.json();
      assert.equal(listJson.success, true);
      assert.equal(listJson.captures.length, 3);
    });
  } finally {
    rmSync(teledriveDir, { recursive: true, force: true });
  }
});

test('stock images sync to TeleDrive stocks folder and clean up when items removed', async () => {
  const teledriveDir = mkdtempSync(join(tmpdir(), 'jengabiz-teledrive-stocks-'));
  const samplePng = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89,
  ]);

  try {
    await withService({
      apiKey: 'test-key',
      fromEmail: 'verify@example.com',
      hashSecret: 'test-hash-secret',
      profileUploadsDir: teledriveDir,
      makeOtp: () => '112233',
      sendEmail: async () => {},
    }, async (baseUrl) => {
      await post(baseUrl, '/email-auth/request-otp', { email: 'stocksync@example.com' });
      const verification = await post(baseUrl, '/email-auth/verify-otp', {
        email: 'stocksync@example.com',
        otp: '112233',
      });
      const registered = await post(baseUrl, '/email-auth/register', {
        email: 'stocksync@example.com',
        verificationToken: verification.body.verificationToken,
        name: 'TeleDrive Sync Shop',
        shopName: 'TeleDrive Shop',
        phone: '',
        password: 'password123',
        items: [{
          id: 'item-laptop',
          name: 'HP EliteBook',
          category: 'Computers',
          price: 45000,
          costPrice: 38000,
          stockRemaining: 5,
          unitsSold: 2,
          sku: 'HP-EB-840',
          imageUrl: '',
          reorderLevel: 2,
        }],
      });
      assert.equal(registered.status, 201);
      const token = registered.body.sessionToken;
      const accountId = registered.body.user.id;

      // Upload stock image
      const upload = await request(baseUrl, '/email-auth/stock/images/item-laptop', {
        method: 'PUT',
        token,
        payload: {
          mimeType: 'image/png',
          imageBase64: samplePng.toString('base64'),
        },
      });
      assert.equal(upload.status, 200);
      assert.equal(upload.body.imageUrl, 'stock-image:item-laptop');

      // Check TeleDrive stocks folder on disk
      const userStocksDir = join(teledriveDir, accountId, 'stocks');
      assert.ok(existsSync(userStocksDir), 'stocks directory should exist');
      const files = readdirSync(userStocksDir);
      assert.equal(files.length, 1);
      assert.ok(files[0].startsWith('hp-elitebook-item-laptop'));
      assert.ok(files[0].endsWith('.png'));

      const diskFilePath = join(userStocksDir, files[0]);
      assert.deepEqual(readFileSync(diskFilePath), samplePng);

      // Verify deletion from disk and re-creation from DB blob on fetch
      unlinkSync(diskFilePath);
      assert.ok(!existsSync(diskFilePath));

      const fetchedImage = await fetch(`${baseUrl}/email-auth/stock/images/item-laptop`, {
        headers: { authorization: `Bearer ${token}` },
      });
      assert.equal(fetchedImage.status, 200);
      assert.deepEqual(Buffer.from(await fetchedImage.arrayBuffer()), samplePng);
      assert.ok(existsSync(diskFilePath), 'disk file should be recreated on demand');

      // Update stock items removing the image reference cleans up disk file
      const updateItems = await request(baseUrl, '/email-auth/stock/items', {
        method: 'PUT',
        token,
        payload: {
          items: [{
            id: 'item-laptop',
            name: 'HP EliteBook',
            category: 'Computers',
            price: 45000,
            costPrice: 38000,
            stockRemaining: 5,
            unitsSold: 2,
            sku: 'HP-EB-840',
            imageUrl: '',
            reorderLevel: 2,
          }],
        },
      });
      assert.equal(updateItems.status, 200);
      assert.ok(!existsSync(diskFilePath), 'disk file should be unlinked when image reference is removed');
    });
  } finally {
    rmSync(teledriveDir, { recursive: true, force: true });
  }
});

