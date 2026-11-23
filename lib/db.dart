import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// 一条账单
class Bill {
  int? id;
  double amount;
  int type; // 0 支出，1 收入
  String category;
  String remark;
  int timestamp;

  Bill({
    this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.remark,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'type': type,
        'category': category,
        'remark': remark,
        'timestamp': timestamp,
      };

  static Bill fromMap(Map<String, dynamic> map) => Bill(
        id: map['id'] as int?,
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        type: map['type'] as int? ?? 0,
        category: map['category'] as String? ?? '',
        remark: map['remark'] as String? ?? '',
        timestamp: map['timestamp'] as int? ?? 0,
      );
}

/// 自定义分类
class Category {
  int? id;
  String name;
  int type; // 0 支出，1 收入
  String icon; // 图标 key，映射见 category_icons.dart
  int sort;

  Category({
    this.id,
    required this.name,
    required this.type,
    required this.icon,
    this.sort = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'icon': icon,
        'sort': sort,
      };

  static Category fromMap(Map<String, dynamic> map) => Category(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        type: map['type'] as int? ?? 0,
        icon: map['icon'] as String? ?? 'other',
        sort: map['sort'] as int? ?? 0,
      );
}

/// 首次建库（或升级到 v3）时写入的默认分类
List<Category> _defaultCategories() => [
      Category(name: '餐饮', type: 0, icon: 'food', sort: 0),
      Category(name: '交通', type: 0, icon: 'car', sort: 1),
      Category(name: '购物', type: 0, icon: 'shop', sort: 2),
      Category(name: '娱乐', type: 0, icon: 'game', sort: 3),
      Category(name: '工资', type: 1, icon: 'salary', sort: 0),
      Category(name: '红包', type: 1, icon: 'gift', sort: 1),
      Category(name: '兼职', type: 1, icon: 'work', sort: 2),
    ];

class DBHelper {
  static Database? _db;

  /// 仅 Android：数据库放在应用私有 databases 目录。
  /// 用 sqflite 自带的 getDatabasesPath()，不再依赖 path_provider 插件。
  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'book.db');
    _db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _createBillTable(db);
        await _createBudgetTable(db);
        await _createCategoryTable(db);
        await _createIndexes(db);
        await _seedDefaultCategories(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createBudgetTable(db);
        }
        if (oldVersion < 3) {
          await _createCategoryTable(db);
          await _seedDefaultCategories(db);
        }
        if (oldVersion < 4) {
          await _createIndexes(db);
        }
      },
    );
    return _db!;
  }

  Future<void> _createBillTable(Database db) => db.execute('''
        CREATE TABLE bill (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL,
          type INTEGER,
          category TEXT,
          remark TEXT,
          timestamp INTEGER
        )
      ''');

  Future<void> _createBudgetTable(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS budget (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          month_key TEXT UNIQUE,
          budget_value REAL
        )
      ''');

  Future<void> _createCategoryTable(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS category (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type INTEGER NOT NULL,
          icon TEXT NOT NULL,
          sort INTEGER NOT NULL DEFAULT 0,
          UNIQUE(type, name)
        )
      ''');

  /// 按月范围查询账单时走索引，避免全表扫描
  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_bill_ts ON bill(timestamp)');
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final batch = db.batch();
    for (final c in _defaultCategories()) {
      batch.insert('category', c.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  // ---------------- 账单 ----------------

  Future<void> addBill(Bill b) async {
    final d = await db;
    await d.insert('bill', b.toMap());
  }

  Future<void> updateBill(Bill b) async {
    final d = await db;
    await d.update('bill', b.toMap(), where: 'id = ?', whereArgs: [b.id]);
  }

  Future<void> deleteBill(int id) async {
    final d = await db;
    await d.delete('bill', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Bill>> getMonthBill(int startTs, int endTs) async {
    final d = await db;
    final res = await d.query(
      'bill',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startTs, endTs],
      orderBy: 'timestamp DESC',
    );
    return res.map((row) => Bill.fromMap(row)).toList();
  }

  // ---------------- 预算 ----------------

  Future<void> saveBudget(String monthKey, double value) async {
    final d = await db;
    await d.insert(
      'budget',
      {'month_key': monthKey, 'budget_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double> getBudget(String monthKey) async {
    final d = await db;
    final rows = await d.query(
      'budget',
      where: 'month_key = ?',
      whereArgs: [monthKey],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['budget_value'] as num?)?.toDouble() ?? 0;
  }

  // ---------------- 分类 ----------------

  Future<List<Category>> getCategories() async {
    final d = await db;
    final rows =
        await d.query('category', orderBy: 'type ASC, sort ASC, id ASC');
    return rows.map((row) => Category.fromMap(row)).toList();
  }

  Future<int> addCategory(Category c) async {
    final d = await db;
    return d.insert('category', c.toMap());
  }

  /// 更新分类；若名称变化，同步更新历史账单里的分类名
  Future<void> updateCategory(Category c) async {
    final d = await db;
    final rows = await d.query('category', where: 'id = ?', whereArgs: [c.id]);
    await d.transaction((txn) async {
      await txn.update('category', c.toMap(),
          where: 'id = ?', whereArgs: [c.id]);
      if (rows.isNotEmpty) {
        final oldName = rows.first['name'] as String;
        if (oldName != c.name) {
          await txn.update(
            'bill',
            {'category': c.name},
            where: 'category = ? AND type = ?',
            whereArgs: [oldName, c.type],
          );
        }
      }
    });
  }

  Future<void> deleteCategory(int id) async {
    final d = await db;
    await d.delete('category', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countBillsOfCategory(String name, int type) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM bill WHERE category = ? AND type = ?',
      [name, type],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }
}
