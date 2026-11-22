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
