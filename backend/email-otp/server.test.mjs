import assert from 'node:assert/strict';
import { createServer } from 'node:http';
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

test('active sessions roll forward for 90 days and can restore the profile', async () => {
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

    currentTime += 89 * day;
    const restored = await request(baseUrl, '/email-auth/me', { token });
    assert.equal(restored.status, 200);
    assert.equal(restored.body.user.email, 'musa@example.com');

    currentTime += 89 * day;
    assert.equal((await request(baseUrl, '/email-auth/stock/items', { token })).status, 200);

    currentTime += 91 * day;
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
