import { createHash, randomBytes, randomUUID, scryptSync, timingSafeEqual } from 'node:crypto';

// Keep shop sessions for up to 90 days, extending the expiry on active use.
const SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;
const MAX_ITEMS = 5000;
const DUMMY_SALT = Buffer.alloc(16, 0x5a);
const DUMMY_HASH = scryptSync('not-a-real-password', DUMMY_SALT, 64);
const MAX_STOCK_IMAGE_STORAGE_BYTES = 32 * 1024 * 1024;
const KENYAN_COUNTIES = [
  'Mombasa', 'Kwale', 'Kilifi', 'Tana River', 'Lamu', 'Taita-Taveta',
  'Garissa', 'Wajir', 'Mandera', 'Marsabit', 'Isiolo', 'Meru',
  'Tharaka-Nithi', 'Embu', 'Kitui', 'Machakos', 'Makueni', 'Nyandarua',
  'Nyeri', 'Kirinyaga', "Murang'a", 'Kiambu', 'Turkana', 'West Pokot',
  'Samburu', 'Trans Nzoia', 'Uasin Gishu', 'Elgeyo-Marakwet', 'Nandi',
  'Baringo', 'Laikipia', 'Nakuru', 'Narok', 'Kajiado', 'Kericho', 'Bomet',
  'Kakamega', 'Vihiga', 'Bungoma', 'Busia', 'Siaya', 'Kisumu', 'Homa Bay',
  'Migori', 'Kisii', 'Nyamira', 'Nairobi',
];
const COUNTY_BY_KEY = new Map(KENYAN_COUNTIES.map((county) => [
  county.toLowerCase().replace(/[^a-z0-9]/g, ''), county,
]));
COUNTY_BY_KEY.set('nairobcity', 'Nairobi');

export function initializeAccountStore(db) {
  db.exec(`
    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = FULL;
    CREATE TABLE IF NOT EXISTS accounts (
      id TEXT PRIMARY KEY,
      email TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      shop_name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      country TEXT NOT NULL DEFAULT '',
      county TEXT NOT NULL DEFAULT '',
      county_detected INTEGER NOT NULL DEFAULT 0,
      referral_code TEXT,
      password_salt TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      expires_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS sessions_account_idx ON sessions(account_id);
    CREATE TABLE IF NOT EXISTS stock_items (
      account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      id TEXT NOT NULL,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      price REAL NOT NULL,
      cost_price REAL NOT NULL,
      stock_remaining INTEGER NOT NULL,
      units_sold INTEGER NOT NULL,
      sku TEXT NOT NULL,
      image_url TEXT NOT NULL,
      reorder_level INTEGER NOT NULL,
      PRIMARY KEY (account_id, id)
    );
    CREATE INDEX IF NOT EXISTS stock_account_idx ON stock_items(account_id);
    CREATE TABLE IF NOT EXISTS stock_images (
      account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL,
      mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
      image_data BLOB NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (account_id, item_id)
    );
    CREATE TABLE IF NOT EXISTS notification_devices (
      token TEXT PRIMARY KEY,
      account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
      updated_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS notification_devices_account_idx ON notification_devices(account_id);
    CREATE TABLE IF NOT EXISTS referral_rewards (
      id TEXT PRIMARY KEY,
      referrer_account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      referred_account_id TEXT NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
      points INTEGER NOT NULL CHECK (points IN (50, 75)),
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS referral_rewards_referrer_idx ON referral_rewards(referrer_account_id);
    PRAGMA user_version = 2;
  `);

  const accountColumns = new Set(
    db.prepare('PRAGMA table_info(accounts)').all().map((column) => column.name),
  );
  if (!accountColumns.has('country')) {
    db.exec("ALTER TABLE accounts ADD COLUMN country TEXT NOT NULL DEFAULT ''");
  }
  if (!accountColumns.has('county')) {
    db.exec("ALTER TABLE accounts ADD COLUMN county TEXT NOT NULL DEFAULT ''");
  }
  if (!accountColumns.has('county_detected')) {
    db.exec('ALTER TABLE accounts ADD COLUMN county_detected INTEGER NOT NULL DEFAULT 0');
  }
  if (!accountColumns.has('referral_code')) {
    db.exec('ALTER TABLE accounts ADD COLUMN referral_code TEXT');
  }
  db.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS accounts_referral_code_unique
      ON accounts(referral_code) WHERE referral_code IS NOT NULL;
  `);

  const missingCodes = db.prepare(
    "SELECT id FROM accounts WHERE referral_code IS NULL OR referral_code = ''",
  ).all();
  const updateCode = db.prepare('UPDATE accounts SET referral_code = ? WHERE id = ?');
  for (const account of missingCodes) {
    updateCode.run(generateReferralCode(db), account.id);
  }
  return db;
}

function generateReferralCode(db) {
  let code;
  do {
    code = randomBytes(6).toString('hex').toUpperCase();
  } while (db.prepare('SELECT 1 FROM accounts WHERE referral_code = ?').get(code));
  return code;
}

function profile(row) {
  return {
    id: row.id,
    name: row.name,
    shopName: row.shop_name,
    phone: row.phone,
    email: row.email,
    country: row.country ?? '',
    county: row.county ?? '',
    countyDetected: row.county_detected === 1,
    referralCode: row.referral_code ?? '',
    createdAt: row.created_at,
  };
}

function normalizedLocationPart(value) {
  return String(value ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
}

function normalizeKenyanCounty(value) {
  const key = String(value ?? '')
    .trim()
    .replace(/\s+county$/i, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
  return COUNTY_BY_KEY.get(key) ?? null;
}

function hasReferralLocation(country, county) {
  const normalizedCountry = normalizedLocationPart(country);
  return (normalizedCountry === 'ke' || normalizedCountry === 'kenya') &&
    normalizeKenyanCounty(county) !== null;
}

function referralPoints(referrer, referred) {
  const sameCounty = normalizeKenyanCounty(referrer.county) ===
    normalizeKenyanCounty(referred.county);
  return sameCounty ? 50 : 75;
}

function passwordDigest(password, salt) {
  return scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 }).toString('hex');
}

export function validateStockItems(value) {
  if (!Array.isArray(value) || value.length > MAX_ITEMS) return null;
  const ids = new Set();
  const items = [];
  for (const raw of value) {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const id = typeof raw.id === 'string' && raw.id.trim()
      ? raw.id.trim().slice(0, 128)
      : randomUUID();
    const name = typeof raw.name === 'string' ? raw.name.trim() : '';
    const category = typeof raw.category === 'string' ? raw.category.trim() : 'General';
    const sku = typeof raw.sku === 'string' ? raw.sku.trim() : '';
    const imageUrl = typeof raw.imageUrl === 'string' ? raw.imageUrl.trim() : '';
    const price = Number(raw.price ?? 0);
    const costPrice = Number(raw.costPrice ?? 0);
    const stockRemaining = Number(raw.stockRemaining ?? 0);
    const unitsSold = Number(raw.unitsSold ?? 0);
    const reorderLevel = Number(raw.reorderLevel ?? 10);
    const safeImageReference = imageUrl === '' ||
      imageUrl === `stock-image:${id}` ||
      (() => {
        try {
          const url = new URL(imageUrl);
          return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password;
        } catch {
          return false;
        }
      })();
    if (!name || name.length > 160 || category.length > 100 || sku.length > 128 || imageUrl.length > 2048 || !safeImageReference) return null;
    if (ids.has(id)) return null;
    if (![price, costPrice].every((n) => Number.isFinite(n) && n >= 0 && n <= 1_000_000_000)) return null;
    if (![stockRemaining, unitsSold, reorderLevel].every((n) => Number.isSafeInteger(n) && n >= 0 && n <= 9_999_999)) return null;
    ids.add(id);
    items.push({ id, name, category: category || 'General', price, costPrice, stockRemaining, unitsSold, sku, imageUrl, reorderLevel });
  }
  return items;
}

export function createAccountStore(db, { now = Date.now } = {}) {
  initializeAccountStore(db);

  function insertItems(accountId, items) {
    const insert = db.prepare(`
      INSERT INTO stock_items
        (account_id, id, name, category, price, cost_price, stock_remaining,
         units_sold, sku, image_url, reorder_level)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    for (const item of items) {
      insert.run(accountId, item.id, item.name, item.category, item.price,
        item.costPrice, item.stockRemaining, item.unitsSold, item.sku,
        item.imageUrl, item.reorderLevel);
    }
  }

  function createSession(accountId) {
    const token = randomBytes(32).toString('base64url');
    const timestamp = now();
    db.prepare('INSERT INTO sessions (token_hash, account_id, expires_at, created_at) VALUES (?, ?, ?, ?)')
      .run(hashToken(token), accountId, timestamp + SESSION_TTL_MS, timestamp);
    return token;
  }

  function hashToken(value) {
    return createHash('sha256').update(value).digest('hex');
  }

  function withTransaction(action) {
    db.exec('BEGIN IMMEDIATE');
    try {
      const result = action();
      db.exec('COMMIT');
      return result;
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  }

  function register({
    email,
    name,
    shopName,
    phone,
    county = '',
    referralCode = '',
    password,
    items = [],
  }) {
    return withTransaction(() => {
      if (db.prepare('SELECT 1 FROM accounts WHERE email = ?').get(email)) {
        return { conflict: true };
      }
      const normalizedCode = String(referralCode).trim().toUpperCase();
      const normalizedCounty = normalizeKenyanCounty(county);
      const referrer = normalizedCode
        ? db.prepare('SELECT * FROM accounts WHERE referral_code = ?').get(normalizedCode)
        : null;
      if (normalizedCode && !referrer) return { invalidReferral: true };
      if (referrer) {
        const normalizedPhone = String(phone ?? '').replace(/\D/g, '');
        const referrerPhone = String(referrer.phone ?? '').replace(/\D/g, '');
        if (referrer.email === email ||
            (normalizedPhone && referrerPhone && normalizedPhone === referrerPhone)) {
          return { invalidReferral: true };
        }
        if (!normalizedCounty ||
            !hasReferralLocation(referrer.country, referrer.county)) {
          return { referralLocationRequired: true };
        }
      }
      const id = `usr_${randomUUID()}`;
      const createdAt = new Date(now()).toISOString();
      const salt = randomBytes(16);
      db.prepare(`
        INSERT INTO accounts
          (id, email, name, shop_name, phone, country, county, county_detected, referral_code,
           password_salt, password_hash, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        id,
        email,
        name,
        shopName,
        phone,
        'KE',
        normalizedCounty ?? '',
        normalizedCounty && normalizedCode ? 1 : 0,
        generateReferralCode(db),
        salt.toString('hex'),
        passwordDigest(password, salt),
        createdAt,
      );
      insertItems(id, items);
      if (referrer) {
        db.prepare(`
          INSERT INTO referral_rewards
            (id, referrer_account_id, referred_account_id, points, created_at)
          VALUES (?, ?, ?, ?, ?)
        `).run(
          randomUUID(),
          referrer.id,
          id,
          referralPoints(referrer, { county: normalizedCounty }),
          now(),
        );
      }
      const token = createSession(id);
      return {
        conflict: false,
        sessionToken: token,
        user: {
          id,
          email,
          name,
          shopName,
          phone,
          country: 'KE',
          county: normalizedCounty ?? '',
          referralCode: db.prepare('SELECT referral_code FROM accounts WHERE id = ?').get(id).referral_code,
          createdAt,
        },
      };
    });
  }

  function updateReferralLocation(accountId, county) {
    const normalizedCounty = normalizeKenyanCounty(county);
    if (!normalizedCounty) return null;
    return withTransaction(() => {
      const account = db.prepare('SELECT * FROM accounts WHERE id = ?').get(accountId);
      if (!account) return null;
      const hasRewards = db.prepare(`
        SELECT 1 FROM referral_rewards
        WHERE referrer_account_id = ? OR referred_account_id = ?
        LIMIT 1
      `).get(accountId, accountId);
      if (hasRewards &&
          normalizeKenyanCounty(account.county) !== normalizedCounty) {
        return false;
      }
      db.prepare('UPDATE accounts SET country = ?, county = ?, county_detected = 1 WHERE id = ?')
        .run('KE', normalizedCounty, accountId);
      return profile(db.prepare('SELECT * FROM accounts WHERE id = ?').get(accountId));
    });
  }

  function getReferralSummary(accountId) {
    const account = db.prepare(
      'SELECT referral_code, country, county, county_detected FROM accounts WHERE id = ?',
    ).get(accountId);
    if (!account) return null;
    const totals = db.prepare(`
      SELECT COUNT(*) AS referralCount,
        COALESCE(SUM(points), 0) AS totalPoints,
        SUM(CASE WHEN points = 50 THEN 1 ELSE 0 END) AS sameCountyCount,
        SUM(CASE WHEN points = 75 THEN 1 ELSE 0 END) AS differentCountyCount
      FROM referral_rewards WHERE referrer_account_id = ?
    `).get(accountId);
    const totalPoints = Number(totals.totalPoints ?? 0);
    const threshold = 200;
    return {
      referralCode: account.referral_code,
      country: account.country ?? '',
      county: account.county ?? '',
      hasLocation: account.county_detected === 1 &&
        hasReferralLocation(account.country, account.county),
      referralCount: Number(totals.referralCount ?? 0),
      sameCountyCount: Number(totals.sameCountyCount ?? 0),
      differentCountyCount: Number(totals.differentCountyCount ?? 0),
      totalPoints,
      pointsToRedemption: Math.max(0, threshold - totalPoints),
      redemptionThreshold: threshold,
      redemptionAvailable: totalPoints >= threshold,
      redemptionImplemented: false,
    };
  }

  function login(email, password) {
    const row = db.prepare('SELECT * FROM accounts WHERE email = ?').get(email);
    const salt = row ? Buffer.from(row.password_salt, 'hex') : DUMMY_SALT;
    const expected = row ? Buffer.from(row.password_hash, 'hex') : DUMMY_HASH;
    const candidate = Buffer.from(passwordDigest(password, salt), 'hex');
    const matches = candidate.length === expected.length && timingSafeEqual(candidate, expected);
    if (!row || !matches) return null;
    const sessionToken = createSession(row.id);
    return { sessionToken, user: profile(row) };
  }

  function authenticate(token) {
    if (typeof token !== 'string' || token.length < 40 || token.length > 128) return null;
    const tokenHash = hashToken(token);
    const row = db.prepare(`
      SELECT sessions.account_id, sessions.expires_at, accounts.*
      FROM sessions JOIN accounts ON accounts.id = sessions.account_id
      WHERE sessions.token_hash = ?
    `).get(tokenHash);
    if (!row || row.expires_at <= now()) {
      db.prepare('DELETE FROM sessions WHERE expires_at <= ?').run(now());
      return null;
    }
    db.prepare('UPDATE sessions SET expires_at = ? WHERE token_hash = ?')
      .run(now() + SESSION_TTL_MS, tokenHash);
    return { id: row.account_id, user: profile(row), tokenHash };
  }

  function listStock(accountId) {
    return db.prepare(`
      SELECT id, name, category, price, cost_price AS costPrice,
        stock_remaining AS stockRemaining, units_sold AS unitsSold,
        sku, image_url AS imageUrl, reorder_level AS reorderLevel
      FROM stock_items WHERE account_id = ? ORDER BY rowid
    `).all(accountId);
  }

  function replaceStock(accountId, items) {
    withTransaction(() => {
      db.prepare('DELETE FROM stock_items WHERE account_id = ?').run(accountId);
      insertItems(accountId, items);
      const itemsWithStoredImages = new Set(items
        .filter((item) => item.imageUrl === `stock-image:${item.id}`)
        .map((item) => item.id));
      const storedImages = db.prepare(
        'SELECT item_id FROM stock_images WHERE account_id = ?',
      ).all(accountId);
      const removeImage = db.prepare(
        'DELETE FROM stock_images WHERE account_id = ? AND item_id = ?',
      );
      for (const image of storedImages) {
        if (!itemsWithStoredImages.has(image.item_id)) {
          removeImage.run(accountId, image.item_id);
        }
      }
    });
    return items.length;
  }

  function saveStockImage(accountId, itemId, mimeType, imageData, updatedAt = now()) {
    const item = db.prepare(
      'SELECT 1 AS found FROM stock_items WHERE account_id = ? AND id = ?',
    ).get(accountId, itemId);
    if (!item) return false;
    const used = db.prepare(`
      SELECT COALESCE(SUM(length(image_data)), 0) AS bytes
      FROM stock_images WHERE account_id = ? AND item_id <> ?
    `).get(accountId, itemId).bytes;
    if (used + imageData.length > MAX_STOCK_IMAGE_STORAGE_BYTES) return 'quota';
    db.prepare(`
      INSERT INTO stock_images (account_id, item_id, mime_type, image_data, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(account_id, item_id) DO UPDATE SET
        mime_type = excluded.mime_type,
        image_data = excluded.image_data,
        updated_at = excluded.updated_at
    `).run(accountId, itemId, mimeType, imageData, updatedAt);
    return true;
  }

  function getStockImage(accountId, itemId) {
    return db.prepare(`
      SELECT mime_type AS mimeType, image_data AS imageData
      FROM stock_images WHERE account_id = ? AND item_id = ?
    `).get(accountId, itemId) ?? null;
  }

  function saveNotificationDevice(accountId, token, platform, updatedAt = now()) {
    db.prepare(`
      INSERT INTO notification_devices (token, account_id, platform, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(token) DO UPDATE SET
        account_id = excluded.account_id,
        platform = excluded.platform,
        updated_at = excluded.updated_at
    `).run(token, accountId, platform, updatedAt);
  }

  function removeNotificationDevice(accountId, token) {
    return db.prepare('DELETE FROM notification_devices WHERE account_id = ? AND token = ?')
      .run(accountId, token).changes;
  }

  function listNotificationDevices(accountId) {
    return db.prepare('SELECT token, platform FROM notification_devices WHERE account_id = ?')
      .all(accountId);
  }

  function revokeSession(tokenHash) {
    db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(tokenHash);
  }

  return {
    register,
    updateReferralLocation,
    getReferralSummary,
    login,
    authenticate,
    listStock,
    replaceStock,
    saveStockImage,
    getStockImage,
    saveNotificationDevice,
    removeNotificationDevice,
    listNotificationDevices,
    revokeSession,
  };
}
