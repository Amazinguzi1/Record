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
  String payMethod; // 支付方式：储蓄卡/信用卡/微信/支付宝等

  Bill({
    this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.remark,
    required this.timestamp,
    this.payMethod = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'type': type,
        'category': category,
        'remark': remark,
        'timestamp': timestamp,
        'pay_method': payMethod,
      };

  static Bill fromMap(Map<String, dynamic> map) => Bill(
        id: map['id'] as int?,
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        type: map['type'] as int? ?? 0,
        category: map['category'] as String? ?? '',
        remark: map['remark'] as String? ?? '',
        timestamp: map['timestamp'] as int? ?? 0,
        payMethod: map['pay_method'] as String? ?? '',
      );
}

/// 资产账户（现金 / 储蓄卡 / 信用卡 / 移动支付 / 自定义）
class Account {
  int? id;
  String type; // cash, debit, credit, mobile, custom
  String name;
  String bankName;
  String cardLast4;
  String remark;
  double amount; // 资产账户为余额；信用卡为欠款

  Account({
    this.id,
    required this.type,
    required this.name,
    this.bankName = '',
    this.cardLast4 = '',
    this.remark = '',
    this.amount = 0,
  });

  bool get isLiability => type == 'credit' || type == 'custom_debt';

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'bank_name': bankName,
        'card_last4': cardLast4,
        'remark': remark,
        'amount': amount,
      };

  static Account fromMap(Map<String, dynamic> map) => Account(
        id: map['id'] as int?,
        type: map['type'] as String? ?? 'custom',
        name: map['name'] as String? ?? '',
        bankName: map['bank_name'] as String? ?? '',
        cardLast4: map['card_last4'] as String? ?? '',
        remark: map['remark'] as String? ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// 常用记账模板
class Regular {
  int? id;
  int type; // 0 支出，1 收入
  String category;
  double amount;
  String remark;
  String payMethod;

  Regular({
    this.id,
    required this.type,
    required this.category,
    required this.amount,
    this.remark = '',
    this.payMethod = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'category': category,
        'amount': amount,
        'remark': remark,
        'pay_method': payMethod,
      };

  static Regular fromMap(Map<String, dynamic> map) => Regular(
        id: map['id'] as int?,
        type: map['type'] as int? ?? 0,
        category: map['category'] as String? ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        remark: map['remark'] as String? ?? '',
        payMethod: map['pay_method'] as String? ?? '',
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
      version: 7,
      onCreate: (db, version) async {
        await _createBillTable(db);
        await _createBudgetTable(db);
        await _createCategoryTable(db);
        await _createAssetTable(db);
        await _createAccountTable(db);
        await _createRegularTable(db);
        await _createIndexes(db);
        await _seedDefaultCategories(db);
        await _seedAsset(db);
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
        if (oldVersion < 5) {
          await _createAssetTable(db);
          await _seedAsset(db);
        }
        if (oldVersion < 6) {
          await _createAccountTable(db);
          await db.execute('ALTER TABLE bill ADD COLUMN pay_method TEXT');
        }
        if (oldVersion < 7) {
          await _createRegularTable(db);
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
          timestamp INTEGER,
          pay_method TEXT
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

  Future<void> _createAssetTable(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS asset (
          id INTEGER PRIMARY KEY,
          assets REAL,
          liabilities REAL
        )
      ''');

  Future<void> _seedAsset(Database db) async {
    await db.insert(
      'asset',
      {'id': 1, 'assets': 0.0, 'liabilities': 0.0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _createAccountTable(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS account (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          name TEXT NOT NULL,
          bank_name TEXT,
          card_last4 TEXT,
          remark TEXT,
          amount REAL
        )
      ''');

  Future<void> _createRegularTable(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS regular (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type INTEGER NOT NULL,
          category TEXT NOT NULL,
          amount REAL,
          remark TEXT,
          pay_method TEXT
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
    await d.transaction((txn) async {
      await txn.insert('bill', b.toMap());
      await _applyPayment(txn, b, 1);
    });
  }

  Future<void> updateBill(Bill b) async {
    final d = await db;
    await d.transaction((txn) async {
      final rows =
          await txn.query('bill', where: 'id = ?', whereArgs: [b.id]);
      if (rows.isNotEmpty) {
        await _applyPayment(txn, Bill.fromMap(rows.first), -1);
      }
      await txn.update('bill', b.toMap(), where: 'id = ?', whereArgs: [b.id]);
      await _applyPayment(txn, b, 1);
    });
  }

  Future<void> deleteBill(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      final rows = await txn.query('bill', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        await _applyPayment(txn, Bill.fromMap(rows.first), -1);
      }
      await txn.delete('bill', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// 账单支付方式 -> 资产账户类型
  String? _accountTypeOfPayment(String payMethod) {
    switch (payMethod) {
      case '储蓄卡':
        return 'debit';
      case '信用卡':
        return 'credit';
      case '微信':
      case '支付宝':
        return 'mobile';
      default:
        return null;
    }
  }

  /// 按支付方式联动增减账户（sign=1 记账生效，-1 撤销）
  /// 资产账户：支出减余额、收入增余额；负债账户：支出增欠款、收入减欠款
  Future<void> _applyPayment(
      DatabaseExecutor txn, Bill bill, int sign) async {
    final accType = _accountTypeOfPayment(bill.payMethod);
    if (accType == null || bill.amount == 0) return;
    final rows = await txn.query('account',
        where: 'type = ?',
        whereArgs: [accType],
        orderBy: 'id ASC',
        limit: 1);
    if (rows.isEmpty) return;
    final acc = Account.fromMap(rows.first);
    double delta;
    if (acc.isLiability) {
      delta = bill.type == 1 ? -bill.amount : bill.amount;
    } else {
      delta = bill.type == 1 ? bill.amount : -bill.amount;
    }
    await txn.update(
      'account',
      {'amount': acc.amount + delta * sign},
      where: 'id = ?',
      whereArgs: [acc.id],
    );
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

  // ---------------- 资产 ----------------

  /// 返回 (资产总额, 负债总额)
  Future<(double, double)> getAsset() async {
    final d = await db;
    final rows = await d.query('asset', where: 'id = 1');
    if (rows.isEmpty) return (0.0, 0.0);
    final r = rows.first;
    return ((r['assets'] as num?)?.toDouble() ?? 0,
        (r['liabilities'] as num?)?.toDouble() ?? 0);
  }

  Future<void> saveAsset(double assets, double liabilities) async {
    final d = await db;
    await d.insert(
      'asset',
      {'id': 1, 'assets': assets, 'liabilities': liabilities},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------- 资产账户 ----------------

  Future<List<Account>> getAccounts() async {
    final d = await db;
    final rows = await d.query('account', orderBy: 'id ASC');
    return rows.map((r) => Account.fromMap(r)).toList();
  }

  Future<int> addAccount(Account a) async {
    final d = await db;
    return d.insert('account', a.toMap());
  }

  Future<void> updateAccount(Account a) async {
    final d = await db;
    await d.update('account', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
  }

  Future<void> deleteAccount(int id) async {
    final d = await db;
    await d.delete('account', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- 常用记账 ----------------

  Future<List<Regular>> getRegulars() async {
    final d = await db;
    final rows = await d.query('regular', orderBy: 'id ASC');
    return rows.map((r) => Regular.fromMap(r)).toList();
  }

  Future<int> addRegular(Regular r) async {
    final d = await db;
    return d.insert('regular', r.toMap());
  }

  Future<void> updateRegular(Regular r) async {
    final d = await db;
    await d.update('regular', r.toMap(),
        where: 'id = ?', whereArgs: [r.id]);
  }

  Future<void> deleteRegular(int id) async {
    final d = await db;
    await d.delete('regular', where: 'id = ?', whereArgs: [id]);
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

/// 金额千位分隔，保留两位小数（如 12345.6 -> 12,345.60）
String fmtMoney(double v) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}${buf.toString()}.${parts[1]}';
}
