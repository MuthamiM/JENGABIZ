import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
  scryptSync,
  timingSafeEqual,
} from 'node:crypto';

// Sessions stay valid until explicitly revoked. Keep the existing schema field
// at the largest safe integer for compatibility with older server builds.
const PERSISTENT_SESSION_EXPIRY = Number.MAX_SAFE_INTEGER;
const ADMIN_SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
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

export function initializeAccountStore(db, { encryptPhone, hashPhone }) {
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
      phone_ciphertext TEXT,
      phone_hash TEXT,
      country TEXT NOT NULL DEFAULT '',
      county TEXT NOT NULL DEFAULT '',
      county_detected INTEGER NOT NULL DEFAULT 0,
      referral_code TEXT,
      status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
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
    CREATE TABLE IF NOT EXISTS admin_users (
      id TEXT PRIMARY KEY,
      email TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('super_admin', 'admin')),
      status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
      password_salt TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      created_at TEXT NOT NULL,
      last_login_at TEXT
    );
    CREATE TABLE IF NOT EXISTS admin_sessions (
      token_hash TEXT PRIMARY KEY,
      admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
      expires_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS admin_sessions_admin_idx ON admin_sessions(admin_id);
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
    CREATE TABLE IF NOT EXISTS account_profile_images (
      account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
      image_type TEXT NOT NULL CHECK (image_type IN ('personal', 'shop')),
      mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
      image_data BLOB NOT NULL,
      updated_at INTEGER NOT NULL
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
    PRAGMA user_version = 4;
  `);

  db.prepare('UPDATE sessions SET expires_at = ? WHERE expires_at <> ?')
    .run(PERSISTENT_SESSION_EXPIRY, PERSISTENT_SESSION_EXPIRY);

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
  if (!accountColumns.has('phone_ciphertext')) {
    db.exec('ALTER TABLE accounts ADD COLUMN phone_ciphertext TEXT');
  }
  if (!accountColumns.has('phone_hash')) {
    db.exec('ALTER TABLE accounts ADD COLUMN phone_hash TEXT');
  }
  if (!accountColumns.has('status')) {
    db.exec("ALTER TABLE accounts ADD COLUMN status TEXT NOT NULL DEFAULT 'active'");
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

  const legacyPhones = db.prepare(`
    SELECT id, phone FROM accounts
    WHERE phone IS NOT NULL AND phone <> '' AND phone_ciphertext IS NULL
  `).all();
  if (legacyPhones.length) {
    db.exec('BEGIN IMMEDIATE');
    try {
      const migratePhone = db.prepare(`
        UPDATE accounts SET phone = '', phone_ciphertext = ?, phone_hash = ? WHERE id = ?
      `);
      for (const row of legacyPhones) {
        migratePhone.run(encryptPhone(row.phone), hashPhone(row.phone), row.id);
      }
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
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

function profile(row, decryptPhone) {
  return {
    id: row.id,
    name: row.name,
    shopName: row.shop_name,
    phone: row.phone_ciphertext ? decryptPhone(row.phone_ciphertext) : (row.phone ?? ''),
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

export function createAccountStore(db, {
  now = Date.now,
  phoneEncryptionKey = process.env.JENGABIZ_PHONE_ENCRYPTION_KEY,
  phoneHashKey = process.env.JENGABIZ_PHONE_HASH_KEY,
  adminEmail = process.env.JENGABIZ_ADMIN_EMAIL,
  adminName = process.env.JENGABIZ_ADMIN_NAME || 'MF Technologies Admin',
  adminPasswordSalt = process.env.JENGABIZ_ADMIN_PASSWORD_SALT,
  adminPasswordHash = process.env.JENGABIZ_ADMIN_PASSWORD_HASH,
} = {}) {
  function readKey(value) {
    if (typeof value === 'string' && /^[a-f0-9]{64}$/i.test(value)) {
      return Buffer.from(value, 'hex');
    }
    if (Buffer.isBuffer(value) && value.length === 32) return value;
    return randomBytes(32);
  }

  const encryptionKey = readKey(phoneEncryptionKey);
  const phonePepper = readKey(phoneHashKey);
  const normalizedPhone = (value) => String(value ?? '').replace(/\D/g, '');
  function encryptPhone(value) {
    const plaintext = String(value ?? '');
    if (!plaintext) return null;
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', encryptionKey, iv);
    const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), encrypted]).toString('base64url');
  }
  function decryptPhone(value) {
    try {
      const packed = Buffer.from(value, 'base64url');
      if (packed.length < 29) return '';
      const decipher = createDecipheriv('aes-256-gcm', encryptionKey, packed.subarray(0, 12));
      decipher.setAuthTag(packed.subarray(12, 28));
      return Buffer.concat([decipher.update(packed.subarray(28)), decipher.final()]).toString('utf8');
    } catch {
      return '';
    }
  }
  function hashPhone(value) {
    const normalized = normalizedPhone(value);
    return normalized ? createHmac('sha256', phonePepper).update(normalized).digest('hex') : null;
  }

  initializeAccountStore(db, { encryptPhone, hashPhone });

  const normalizedAdminEmail = String(adminEmail ?? '').trim().toLowerCase();
  if (normalizedAdminEmail && adminPasswordSalt && adminPasswordHash &&
      /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedAdminEmail) &&
      /^[a-f0-9]{32}$/i.test(adminPasswordSalt) && /^[a-f0-9]{128}$/i.test(adminPasswordHash)) {
    const existingAdmin = db.prepare('SELECT id, password_salt, password_hash FROM admin_users WHERE email = ?')
      .get(normalizedAdminEmail);
    if (!existingAdmin) {
      db.prepare(`
        INSERT INTO admin_users (id, email, name, role, status, password_salt, password_hash, created_at)
        VALUES (?, ?, ?, 'super_admin', 'active', ?, ?, ?)
      `).run(`adm_${randomUUID()}`, normalizedAdminEmail, adminName, adminPasswordSalt,
        adminPasswordHash, new Date(now()).toISOString());
    } else if (existingAdmin.password_salt !== adminPasswordSalt ||
               existingAdmin.password_hash !== adminPasswordHash) {
      db.exec('BEGIN IMMEDIATE');
      try {
        db.prepare(`
          UPDATE admin_users SET name = ?, role = 'super_admin', status = 'active',
            password_salt = ?, password_hash = ? WHERE email = ?
        `).run(adminName, adminPasswordSalt, adminPasswordHash, normalizedAdminEmail);
        db.prepare('DELETE FROM admin_sessions WHERE admin_id = ?').run(existingAdmin.id);
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
    }
  }

  const passwordDigest = (password, salt) =>
    scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });

  function safeEqual(left, right) {
    return left.length === right.length && timingSafeEqual(left, right);
  }

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
      .run(hashToken(token), accountId, PERSISTENT_SESSION_EXPIRY, timestamp);
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
        const normalizedPhoneHash = hashPhone(phone);
        if (referrer.email === email ||
            (normalizedPhoneHash && referrer.phone_hash && normalizedPhoneHash === referrer.phone_hash)) {
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
          (id, email, name, shop_name, phone, phone_ciphertext, phone_hash,
           country, county, county_detected, referral_code, password_salt, password_hash, created_at)
        VALUES (?, ?, ?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        id,
        email,
        name,
        shopName,
        encryptPhone(phone),
        hashPhone(phone),
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
      return profile(db.prepare('SELECT * FROM accounts WHERE id = ?').get(accountId), decryptPhone);
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
    if (row.status !== 'active') return { suspended: true };
    const sessionToken = createSession(row.id);
    return { sessionToken, user: profile(row, decryptPhone) };
  }

  function isAccountSuspended(email) {
    return db.prepare('SELECT 1 FROM accounts WHERE email = ? AND status = ?')
      .get(email, 'suspended') !== undefined;
  }

  function getSuspendedAccountForSupport(email, password) {
    const row = db.prepare('SELECT * FROM accounts WHERE email = ?').get(email);
    const salt = row ? Buffer.from(row.password_salt, 'hex') : DUMMY_SALT;
    const expected = row ? Buffer.from(row.password_hash, 'hex') : DUMMY_HASH;
    const candidate = Buffer.from(passwordDigest(password, salt), 'hex');
    const matches = candidate.length === expected.length && timingSafeEqual(candidate, expected);
    if (!row || row.status !== 'suspended' || !matches) return null;
    return {
      id: row.id,
      name: row.name,
      shopName: row.shop_name,
      phone: row.phone_ciphertext ? decryptPhone(row.phone_ciphertext) : (row.phone ?? ''),
      email: row.email,
    };
  }

  function resetPassword(email, password) {
    const account = db.prepare('SELECT id FROM accounts WHERE email = ?').get(email);
    if (!account) return false;

    const salt = randomBytes(16);
    const digest = passwordDigest(password, salt);
    return withTransaction(() => {
      const updated = db.prepare(`
        UPDATE accounts SET password_salt = ?, password_hash = ? WHERE id = ?
      `).run(salt.toString('hex'), digest, account.id);
      db.prepare('DELETE FROM sessions WHERE account_id = ?').run(account.id);
      return updated.changes === 1;
    });
  }

  function authenticate(token) {
    if (typeof token !== 'string' || token.length < 40 || token.length > 128) return null;
    const tokenHash = hashToken(token);
    const row = db.prepare(`
      SELECT sessions.account_id, sessions.expires_at, accounts.*
      FROM sessions JOIN accounts ON accounts.id = sessions.account_id
      WHERE sessions.token_hash = ?
    `).get(tokenHash);
    if (!row || row.status !== 'active') return null;
    db.prepare('UPDATE sessions SET expires_at = ? WHERE token_hash = ?')
      .run(PERSISTENT_SESSION_EXPIRY, tokenHash);
    return { id: row.account_id, user: profile(row, decryptPhone), tokenHash };
  }

  function publicAdmin(row) {
    return {
      id: row.id,
      email: row.email,
      name: row.name,
      role: row.role,
      createdAt: row.created_at,
      lastLoginAt: row.last_login_at ?? null,
    };
  }

  function adminLogin(email, password) {
    const normalizedEmail = String(email ?? '').trim().toLowerCase();
    const row = db.prepare('SELECT * FROM admin_users WHERE email = ?').get(normalizedEmail);
    const salt = row ? Buffer.from(row.password_salt, 'hex') : DUMMY_SALT;
    const expected = row ? Buffer.from(row.password_hash, 'hex') : DUMMY_HASH;
    const candidate = passwordDigest(String(password ?? ''), salt);
    const matches = safeEqual(candidate, expected);
    if (!row || !matches || row.status !== 'active') return null;

    const token = randomBytes(32).toString('base64url');
    const timestamp = now();
    db.prepare(`
      INSERT INTO admin_sessions (token_hash, admin_id, expires_at, created_at)
      VALUES (?, ?, ?, ?)
    `).run(hashToken(token), row.id, timestamp + ADMIN_SESSION_TTL_MS, timestamp);
    db.prepare('UPDATE admin_users SET last_login_at = ? WHERE id = ?')
      .run(new Date(timestamp).toISOString(), row.id);
    return { sessionToken: token, admin: publicAdmin({ ...row, last_login_at: new Date(timestamp).toISOString() }) };
  }

  function authenticateAdmin(token) {
    if (typeof token !== 'string' || token.length < 40 || token.length > 128) return null;
    const tokenHash = hashToken(token);
    const timestamp = now();
    const row = db.prepare(`
      SELECT admin_sessions.admin_id, admin_sessions.expires_at, admin_users.*
      FROM admin_sessions JOIN admin_users ON admin_users.id = admin_sessions.admin_id
      WHERE admin_sessions.token_hash = ?
    `).get(tokenHash);
    if (!row || row.status !== 'active' || row.expires_at <= timestamp) {
      if (row) db.prepare('DELETE FROM admin_sessions WHERE token_hash = ?').run(tokenHash);
      return null;
    }
    db.prepare('UPDATE admin_sessions SET expires_at = ? WHERE token_hash = ?')
      .run(timestamp + ADMIN_SESSION_TTL_MS, tokenHash);
    return { id: row.admin_id, user: publicAdmin(row), tokenHash };
  }

  function revokeAdminSession(tokenHash) {
    db.prepare('DELETE FROM admin_sessions WHERE token_hash = ?').run(tokenHash);
  }

  function listAdminAccounts() {
    return db.prepare(`
      SELECT id, email, name, role, status, created_at AS createdAt,
        last_login_at AS lastLoginAt
      FROM admin_users ORDER BY created_at ASC
    `).all();
  }

  function adminUsers(search = '', { status = 'all', limit = 60, offset = 0 } = {}) {
    const safeLimit = Math.max(1, Math.min(200, Math.floor(Number(limit) || 60)));
    const safeOffset = Math.max(0, Math.min(1_000_000_000, Math.floor(Number(offset) || 0)));
    const term = String(search).trim().slice(0, 120).toLowerCase();
    const filter = term ? `%${term.replace(/[\\%_]/g, '\\$&')}%` : null;
    const phoneHash = hashPhone(search);
    const statusFilter = ['active', 'suspended'].includes(status) ? status : null;
    const where = `
      WHERE (? IS NULL OR lower(a.name) LIKE ? ESCAPE '\\'
        OR lower(a.shop_name) LIKE ? ESCAPE '\\'
        OR lower(a.email) LIKE ? ESCAPE '\\'
        OR lower(a.county) LIKE ? ESCAPE '\\'
        OR (? IS NOT NULL AND a.phone_hash = ?))
        AND (? IS NULL OR a.status = ?)
    `;
    const params = [filter, filter, filter, filter, filter, phoneHash, phoneHash, statusFilter, statusFilter];
    const total = Number(db.prepare(`SELECT COUNT(*) AS total FROM accounts a ${where}`)
      .get(...params).total);
    const rows = db.prepare(`
      SELECT a.id, a.name, a.shop_name AS shopName, a.email,
        a.phone_ciphertext, a.phone, a.country, a.county,
        a.created_at AS createdAt, a.status,
        (SELECT COUNT(*) FROM stock_items s WHERE s.account_id = a.id) AS productCount,
        (SELECT COALESCE(SUM(stock_remaining), 0) FROM stock_items s WHERE s.account_id = a.id) AS unitsOnHand,
        (SELECT COALESCE(SUM(units_sold), 0) FROM stock_items s WHERE s.account_id = a.id) AS unitsSold,
        (SELECT COUNT(*) FROM referral_rewards r WHERE r.referrer_account_id = a.id) AS referralCount,
        (SELECT COALESCE(SUM(points), 0) FROM referral_rewards r WHERE r.referrer_account_id = a.id) AS referralPoints,
        (SELECT COUNT(*) FROM sessions ss WHERE ss.account_id = a.id) AS sessionCount,
        (SELECT COUNT(*) FROM notification_devices nd WHERE nd.account_id = a.id) AS deviceCount
      FROM accounts a ${where}
      ORDER BY a.created_at DESC LIMIT ? OFFSET ?
    `).all(...params, safeLimit, safeOffset).map((row) => {
      const phone = row.phone_ciphertext ? decryptPhone(row.phone_ciphertext) : row.phone;
      const digits = normalizedPhone(phone);
      return {
        id: row.id,
        name: row.name,
        shopName: row.shopName,
        email: row.email,
        phoneMasked: digits ? `•••• ${digits.slice(-4)}` : '',
        country: row.country,
        county: row.county,
        createdAt: row.createdAt,
        status: row.status,
        productCount: Number(row.productCount),
        unitsOnHand: Number(row.unitsOnHand),
        unitsSold: Number(row.unitsSold),
        referralCount: Number(row.referralCount),
        referralPoints: Number(row.referralPoints),
        sessionCount: Number(row.sessionCount),
        deviceCount: Number(row.deviceCount),
      };
    });
    return { items: rows, total, limit: safeLimit, offset: safeOffset };
  }

  function adminUserDetails(accountId) {
    const row = db.prepare(`
      SELECT id, name, shop_name AS shopName, email, phone_ciphertext, phone,
        phone_hash AS phoneHash, country, county, county_detected AS countyDetected,
        referral_code AS referralCode, created_at AS createdAt, status
      FROM accounts WHERE id = ?
    `).get(accountId);
    if (!row) return null;
    const user = {
      ...row,
      phone: row.phone_ciphertext ? decryptPhone(row.phone_ciphertext) : row.phone,
      countyDetected: row.countyDetected === 1,
    };
    delete user.phone_ciphertext;
    const stock = db.prepare(`
      SELECT id, name, category, price, cost_price AS costPrice,
        stock_remaining AS stockRemaining, units_sold AS unitsSold, sku,
        image_url AS imageUrl, reorder_level AS reorderLevel,
        EXISTS(SELECT 1 FROM stock_images i
          WHERE i.account_id = stock_items.account_id AND i.item_id = stock_items.id) AS hasImage
      FROM stock_items WHERE account_id = ? ORDER BY name COLLATE NOCASE
    `).all(accountId);
    const referrals = db.prepare(`
      SELECT r.id, r.points, r.created_at AS createdAt,
        CASE WHEN r.referrer_account_id = ? THEN 'invited' ELSE 'referred' END AS direction,
        other.name AS otherName, other.shop_name AS otherShop, other.email AS otherEmail
      FROM referral_rewards r
      JOIN accounts other ON other.id = CASE
        WHEN r.referrer_account_id = ? THEN r.referred_account_id
        ELSE r.referrer_account_id END
      WHERE r.referrer_account_id = ? OR r.referred_account_id = ?
      ORDER BY r.created_at DESC
    `).all(accountId, accountId, accountId, accountId);
    const extra = db.prepare(`
      SELECT
        (SELECT COUNT(*) FROM sessions WHERE account_id = ?) AS sessionCount,
        (SELECT COUNT(*) FROM notification_devices WHERE account_id = ?) AS deviceCount,
        (SELECT COUNT(*) FROM stock_images WHERE account_id = ?) AS imageCount
    `).get(accountId, accountId, accountId);
    return {
      user,
      stock,
      referrals,
      activity: {
        sessionCount: Number(extra.sessionCount),
        deviceCount: Number(extra.deviceCount),
        imageCount: Number(extra.imageCount),
      },
    };
  }

  function setCustomerStatus(accountId, status) {
    if (!['active', 'suspended'].includes(status)) return false;
    db.exec('BEGIN IMMEDIATE');
    try {
      const result = db.prepare('UPDATE accounts SET status = ? WHERE id = ?').run(status, accountId);
      if (result.changes === 1 && status === 'suspended') {
        db.prepare('DELETE FROM sessions WHERE account_id = ?').run(accountId);
        db.prepare('DELETE FROM notification_devices WHERE account_id = ?').run(accountId);
      }
      db.exec('COMMIT');
      return result.changes === 1;
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  }

  function adminExportData(dataset = 'all') {
    const allowed = new Set(['users', 'inventory', 'referrals', 'all']);
    if (!allowed.has(dataset)) return null;
    const users = () => db.prepare(`
      SELECT id, name, shop_name AS shopName, email,
        phone_ciphertext, phone, phone_hash AS phoneHash, country, county,
        created_at AS createdAt, status,
        (SELECT COUNT(*) FROM stock_items s WHERE s.account_id = accounts.id) AS productCount,
        (SELECT COALESCE(SUM(stock_remaining), 0) FROM stock_items s WHERE s.account_id = accounts.id) AS unitsOnHand,
        (SELECT COALESCE(SUM(units_sold), 0) FROM stock_items s WHERE s.account_id = accounts.id) AS unitsSold
      FROM accounts ORDER BY created_at ASC
    `).all().map((row) => {
      const phone = row.phone_ciphertext ? decryptPhone(row.phone_ciphertext) : row.phone;
      delete row.phone_ciphertext;
      row.phone = phone;
      row.productCount = Number(row.productCount);
      row.unitsOnHand = Number(row.unitsOnHand);
      row.unitsSold = Number(row.unitsSold);
      return row;
    });
    const inventory = () => db.prepare(`
      SELECT a.id AS accountId, a.shop_name AS shopName, a.email AS accountEmail,
        s.id AS productId, s.name, s.category, s.price, s.cost_price AS costPrice,
        s.stock_remaining AS stockRemaining, s.units_sold AS unitsSold,
        s.sku, s.image_url AS imageUrl, s.reorder_level AS reorderLevel,
        EXISTS(SELECT 1 FROM stock_images i
          WHERE i.account_id = s.account_id AND i.item_id = s.id) AS hasStoredImage
      FROM stock_items s JOIN accounts a ON a.id = s.account_id
      ORDER BY a.shop_name COLLATE NOCASE, s.name COLLATE NOCASE
    `).all().map((row) => ({
      ...row,
      hasStoredImage: Boolean(row.hasStoredImage),
    }));
    const referrals = () => db.prepare(`
      SELECT r.id, r.points, r.created_at AS createdAt,
        referrer.id AS referrerId, referrer.name AS referrerName,
        referrer.shop_name AS referrerShop, referrer.email AS referrerEmail,
        referred.id AS referredId, referred.name AS referredName,
        referred.shop_name AS referredShop, referred.email AS referredEmail
      FROM referral_rewards r
      JOIN accounts referrer ON referrer.id = r.referrer_account_id
      JOIN accounts referred ON referred.id = r.referred_account_id
      ORDER BY r.created_at ASC
    `).all();
    if (dataset === 'users') return users();
    if (dataset === 'inventory') return inventory();
    if (dataset === 'referrals') return referrals();
    return { generatedAt: new Date(now()).toISOString(), users: users(), inventory: inventory(), referrals: referrals() };
  }

  function listStock(accountId) {
    return db.prepare(`
      SELECT id, name, category, price, cost_price AS costPrice,
        stock_remaining AS stockRemaining, units_sold AS unitsSold,
        sku, image_url AS imageUrl, reorder_level AS reorderLevel
      FROM stock_items WHERE account_id = ? ORDER BY rowid
    `).all(accountId);
  }

  function adminOverview({ nowMs = now(), months = 6 } = {}) {
    const currentMonth = new Date(nowMs);
    const monthStarts = Array.from({ length: months }, (_, index) => {
      const month = new Date(Date.UTC(
        currentMonth.getUTCFullYear(),
        currentMonth.getUTCMonth() - (months - index - 1),
        1,
      ));
      return {
        key: month.toISOString().slice(0, 7),
        label: month.toLocaleString('en', { month: 'short', timeZone: 'UTC' }),
      };
    });
    const totals = db.prepare(`
      SELECT
        (SELECT COUNT(*) FROM accounts) AS shops,
        (SELECT COUNT(*) FROM accounts WHERE status = 'active') AS activeUsers,
        (SELECT COUNT(*) FROM accounts WHERE status = 'suspended') AS suspendedUsers,
        (SELECT COUNT(*) FROM stock_items) AS products,
        (SELECT COALESCE(SUM(stock_remaining), 0) FROM stock_items) AS unitsOnHand,
        (SELECT COALESCE(SUM(units_sold), 0) FROM stock_items) AS unitsSold,
        (SELECT COUNT(*) FROM stock_items WHERE stock_remaining = 0) AS outOfStock,
        (SELECT COUNT(*) FROM stock_items
          WHERE stock_remaining > 0 AND stock_remaining <= reorder_level) AS lowStock,
        (SELECT COUNT(*) FROM referral_rewards) AS referrals,
        (SELECT COALESCE(SUM(points), 0) FROM referral_rewards) AS referralPoints
    `).get();
    const firstMonth = `${monthStarts[0].key}-01T00:00:00.000Z`;
    const signups = db.prepare(`
      SELECT substr(created_at, 1, 7) AS month, COUNT(*) AS count
      FROM accounts WHERE created_at >= ?
      GROUP BY substr(created_at, 1, 7)
    `).all(firstMonth);
    const signupsByMonth = new Map(signups.map((row) => [row.month, Number(row.count)]));
    const recentShops = db.prepare(`
      SELECT a.id, a.name, a.shop_name AS shopName, a.email, a.county,
        a.status, a.created_at AS createdAt,
        (SELECT COUNT(*) FROM stock_items s WHERE s.account_id = a.id) AS productCount
      FROM accounts a ORDER BY a.created_at DESC LIMIT 6
    `).all();
    const lowStockItems = db.prepare(`
      SELECT s.name, s.category, s.stock_remaining AS stockRemaining,
        s.reorder_level AS reorderLevel, a.shop_name AS shopName
      FROM stock_items s JOIN accounts a ON a.id = s.account_id
      WHERE s.stock_remaining <= s.reorder_level
      ORDER BY CASE WHEN s.stock_remaining = 0 THEN 0 ELSE 1 END,
        s.stock_remaining ASC, s.name COLLATE NOCASE LIMIT 8
    `).all();
    const recentReferrals = db.prepare(`
      SELECT r.points, r.created_at AS createdAt,
        referrer.shop_name AS referrerShop,
        referred.shop_name AS referredShop
      FROM referral_rewards r
      JOIN accounts referrer ON referrer.id = r.referrer_account_id
      JOIN accounts referred ON referred.id = r.referred_account_id
      ORDER BY r.created_at DESC LIMIT 6
    `).all();
    return {
      totals: Object.fromEntries(Object.entries(totals).map(([key, value]) => [key, Number(value)])),
      signups: monthStarts.map((month) => ({ ...month, count: signupsByMonth.get(month.key) ?? 0 })),
      recentShops,
      lowStockItems,
      recentReferrals,
    };
  }

  function adminShops(search = '', limit = 100) {
    const safeLimit = Math.max(1, Math.min(200, Number(limit) || 100));
    const term = String(search).trim().slice(0, 120).toLowerCase();
    const filter = term ? `%${term.replace(/[\\%_]/g, '\\$&')}%` : null;
    return db.prepare(`
      SELECT a.id, a.name, a.shop_name AS shopName, a.email, a.county,
        a.created_at AS createdAt,
        (SELECT COUNT(*) FROM stock_items s WHERE s.account_id = a.id) AS productCount
      FROM accounts a
      WHERE ? IS NULL OR lower(a.name) LIKE ? ESCAPE '\\'
        OR lower(a.shop_name) LIKE ? ESCAPE '\\'
        OR lower(a.email) LIKE ? ESCAPE '\\'
        OR lower(a.county) LIKE ? ESCAPE '\\'
      ORDER BY a.created_at DESC LIMIT ?
    `).all(filter, filter, filter, filter, filter, safeLimit);
  }

  function adminInventory(search = '', { limit = 25, offset = 0 } = {}) {
    const safeLimit = Math.max(1, Math.min(200, Math.floor(Number(limit) || 25)));
    const safeOffset = Math.max(0, Math.min(1_000_000_000, Math.floor(Number(offset) || 0)));
    const term = String(search).trim().slice(0, 120).toLowerCase();
    const filter = term ? `%${term.replace(/[\\%_]/g, '\\$&')}%` : null;
    const where = `
      WHERE ? IS NULL OR lower(s.name) LIKE ? ESCAPE '\\'
        OR lower(s.category) LIKE ? ESCAPE '\\'
        OR lower(s.sku) LIKE ? ESCAPE '\\'
        OR lower(a.shop_name) LIKE ? ESCAPE '\\'
        OR lower(a.email) LIKE ? ESCAPE '\\'
    `;
    const params = [filter, filter, filter, filter, filter, filter];
    const total = Number(db.prepare(`
      SELECT COUNT(*) AS total
      FROM stock_items s JOIN accounts a ON a.id = s.account_id
      ${where}
    `).get(...params).total);
    const items = db.prepare(`
      SELECT s.id, s.name, s.category, s.sku, s.price,
        s.cost_price AS costPrice,
        s.stock_remaining AS stockRemaining, s.units_sold AS unitsSold,
        s.reorder_level AS reorderLevel, a.shop_name AS shopName,
        a.email AS accountEmail,
        EXISTS(SELECT 1 FROM stock_images i
          WHERE i.account_id = s.account_id AND i.item_id = s.id) AS hasImage,
        CASE WHEN s.stock_remaining = 0 THEN 'Out of stock'
          WHEN s.stock_remaining <= s.reorder_level THEN 'Low stock'
          ELSE 'In stock' END AS status
      FROM stock_items s JOIN accounts a ON a.id = s.account_id
      ${where}
      ORDER BY CASE WHEN s.stock_remaining = 0 THEN 0
        WHEN s.stock_remaining <= s.reorder_level THEN 1 ELSE 2 END,
        s.stock_remaining ASC, s.name COLLATE NOCASE LIMIT ? OFFSET ?
    `).all(...params, safeLimit, safeOffset);
    return { items, total, limit: safeLimit, offset: safeOffset };
  }

  function adminReferrals(search = '', { limit = 25, offset = 0 } = {}) {
    const safeLimit = Math.max(1, Math.min(200, Math.floor(Number(limit) || 25)));
    const safeOffset = Math.max(0, Math.min(1_000_000_000, Math.floor(Number(offset) || 0)));
    const term = String(search).trim().slice(0, 120).toLowerCase();
    const filter = term ? `%${term.replace(/[\\%_]/g, '\\$&')}%` : null;
    const where = `
      WHERE ? IS NULL OR lower(referrer.shop_name) LIKE ? ESCAPE '\\'
        OR lower(referrer.email) LIKE ? ESCAPE '\\'
        OR lower(referred.shop_name) LIKE ? ESCAPE '\\'
        OR lower(referred.email) LIKE ? ESCAPE '\\'
    `;
    const params = [filter, filter, filter, filter, filter];
    const joins = `
      FROM referral_rewards r
      JOIN accounts referrer ON referrer.id = r.referrer_account_id
      JOIN accounts referred ON referred.id = r.referred_account_id
    `;
    const total = Number(db.prepare(`SELECT COUNT(*) AS total ${joins} ${where}`)
      .get(...params).total);
    const referrals = db.prepare(`
      SELECT r.id, r.points, r.created_at AS createdAt,
        referrer.shop_name AS referrerShop,
        referrer.email AS referrerEmail,
        referred.shop_name AS referredShop,
        referred.email AS referredEmail
      ${joins}
      ${where}
      ORDER BY r.created_at DESC LIMIT ? OFFSET ?
    `).all(...params, safeLimit, safeOffset);
    return { referrals, total, limit: safeLimit, offset: safeOffset };
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

  function getProfileImage(accountId) {
    return db.prepare(`
      SELECT image_type AS imageType, mime_type AS mimeType, image_data AS imageData
      FROM account_profile_images WHERE account_id = ?
    `).get(accountId) ?? null;
  }

  function removeProfileImage(accountId) {
    return db.prepare(
      'DELETE FROM account_profile_images WHERE account_id = ?',
    ).run(accountId).changes;
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
    isAccountSuspended,
    getSuspendedAccountForSupport,
    resetPassword,
    authenticate,
    listStock,
    adminOverview,
    adminShops,
    adminUsers,
    adminUserDetails,
    setCustomerStatus,
    adminInventory,
    adminReferrals,
    adminExportData,
    adminLogin,
    authenticateAdmin,
    revokeAdminSession,
    listAdminAccounts,
    replaceStock,
    saveStockImage,
    getStockImage,
    getProfileImage,
    removeProfileImage,
    saveNotificationDevice,
    removeNotificationDevice,
    listNotificationDevices,
    revokeSession,
  };
}
