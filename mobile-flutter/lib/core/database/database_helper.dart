import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('duka_ledger.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Shared Contract Offline Schema with UUIDs & updated_at
    await db.execute('''
      CREATE TABLE shops (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        profile_type TEXT NOT NULL,
        payment_number TEXT,
        location_id TEXT,
        language TEXT DEFAULT 'sw',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        buy_price REAL NOT NULL,
        sell_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        low_stock_level INTEGER NOT NULL DEFAULT 5,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        credit_limit REAL DEFAULT 1000.0,
        current_balance REAL DEFAULT 0.0,
        trust_score TEXT DEFAULT 'Normal',
        notes TEXT,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        customer_id TEXT,
        type TEXT NOT NULL,
        total REAL NOT NULL,
        items_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        mpesa_code TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }
}
