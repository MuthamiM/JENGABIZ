import { createHash, randomBytes, randomUUID, scryptSync, timingSafeEqual } from 'node:crypto';

const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_ITEMS = 5000;
const DUMMY_SALT = Buffer.alloc(16, 0x5a);
const DUMMY_HASH = scryptSync('not-a-real-password', DUMMY_SALT, 64);

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
    PRAGMA user_version = 1;
  `);
  return db;
}

function profile(row) {
  return {
    id: row.id,
    name: row.name,
    shopName: row.shop_name,
    phone: row.phone,
    email: row.email,
    createdAt: row.created_at,
  };
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
    if (!name || name.length > 160 || category.length > 100 || sku.length > 128 || imageUrl.length > 2048) return null;
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

  function register({ email, name, shopName, phone, password, items = [] }) {
    return withTransaction(() => {
      if (db.prepare('SELECT 1 FROM accounts WHERE email = ?').get(email)) {
        return { conflict: true };
      }
      const id = `usr_${randomUUID()}`;
      const createdAt = new Date(now()).toISOString();
      const salt = randomBytes(16);
      db.prepare(`
        INSERT INTO accounts (id, email, name, shop_name, phone, password_salt, password_hash, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(id, email, name, shopName, phone, salt.toString('hex'), passwordDigest(password, salt), createdAt);
      insertItems(id, items);
      const token = createSession(id);
      return {
        conflict: false,
        sessionToken: token,
        user: { id, email, name, shopName, phone, createdAt },
      };
    });
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
    });
    return items.length;
  }

  function revokeSession(tokenHash) {
    db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(tokenHash);
  }

  return { register, login, authenticate, listStock, replaceStock, revokeSession };
}
