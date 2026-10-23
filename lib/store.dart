import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'ledger.dart';
import 'models.dart';
import 'notifications.dart';
import 'photo.dart';

/// অ্যাপের সব ডাটা (লোকাল SQLite) — একটাই জায়গা থেকে পড়া/লেখা হয়।
///
/// অফলাইন-ফার্স্ট: সব কাজ আগে লোকাল ডাটাবেসে হয়। পরে অনলাইন সিঙ্ক যোগ করার
/// জন্য প্রতিটা রেকর্ডে আছে —
///   uid        : সব ডিভাইসে একই থাকা স্থায়ী আইডি (লোকাল `id` শুধু এই ফোনের)
///   updated_at : শেষ পরিবর্তনের সময় (সিঙ্কে কোনটা নতুন তা বোঝার জন্য)
///   deleted    : মুছলে সাথে সাথে না মুছে চিহ্ন দেওয়া, যাতে সার্ভারেও মোছা যায়
///   dirty      : ১ = সার্ভারে এখনো পাঠানো হয়নি
class Store extends ChangeNotifier {
  Store._();
  static final Store instance = Store._();

  late Database _db;

  /// দুই খাতার সবাই।
  List<Customer> all = [];
  bool loaded = false;

  /// এখন কোন খাতা খোলা। পুরো অ্যাপের রঙ/লেখা এর উপর নির্ভর করে।
  Ledger ledger = Ledger.pabo;
  LedgerText get text => LedgerText.of(ledger);

  /// থিম বদলানোর জন্য আলাদা নোটিফায়ার (ডাটা বদলালে থিম রিবিল্ড হয় না)।
  final ledgerNotifier = ValueNotifier(Ledger.pabo);

  void setLedger(Ledger l) {
    if (l == ledger) return;
    ledger = l;
    ledgerNotifier.value = l;
    notifyListeners();
  }

  /// শুধু খোলা খাতার মানুষ।
  List<Customer> get customers => all.where((c) => c.ledger == ledger).toList();

  double totalOf(Ledger l) =>
      all.fold(0, (s, c) => c.ledger == l && c.hasDue ? s + c.balance : s);

  static final _rand = Random.secure();
  static String newUid() => List.generate(
    16,
    (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// পরিবর্তিত রেকর্ডে সিঙ্ক-ফিল্ড বসানো।
  static Map<String, Object?> _touch(Map<String, Object?> values) => {
    ...values,
    'updated_at': _now(),
    'dirty': 1,
  };

  /// লোকাল ডাটা বদলালে সিঙ্ক সার্ভিসকে জানানোর হুক।
  VoidCallback? onLocalChange;

  Future<void> init() async {
    if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
    _db = await openDatabase(
      kIsWeb
          ? 'baki_khata.db'
          : p.join(await getDatabasesPath(), 'baki_khata.db'),
      version: 4,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE customers ADD COLUMN photo TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 3) await _addSyncColumns(db);
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE customers ADD COLUMN ledger TEXT NOT NULL DEFAULT 'pabo'",
          );
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uid TEXT NOT NULL UNIQUE,
            ledger TEXT NOT NULL DEFAULT 'pabo',
            name TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '',
            address TEXT NOT NULL DEFAULT '',
            photo TEXT NOT NULL DEFAULT '',
            due_date INTEGER,
            reminder_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            dirty INTEGER NOT NULL DEFAULT 1
          )''');
        await db.execute('''
          CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uid TEXT NOT NULL UNIQUE,
            customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
            customer_uid TEXT NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            date INTEGER NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            dirty INTEGER NOT NULL DEFAULT 1
          )''');
        await db.execute(
          'CREATE INDEX idx_entries_customer ON entries(customer_id)',
        );
      },
    );
    await refresh();
  }

  /// পুরনো (v2) ডাটাবেসে সিঙ্ক-কলাম যোগ ও আগের ডাটায় uid বসানো।
  static Future<void> _addSyncColumns(Database db) async {
    for (final t in ['customers', 'entries']) {
      await db.execute(
        "ALTER TABLE $t ADD COLUMN uid TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE $t ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE $t ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE $t ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute("UPDATE $t SET uid = lower(hex(randomblob(16)))");
      await db.execute('CREATE UNIQUE INDEX idx_${t}_uid ON $t(uid)');
    }
    await db.execute(
      "ALTER TABLE entries ADD COLUMN customer_uid TEXT NOT NULL DEFAULT ''",
    );
    await db.execute('UPDATE customers SET updated_at = created_at');
    await db.execute('''
      UPDATE entries SET updated_at = date,
        customer_uid = (SELECT uid FROM customers c WHERE c.id = entries.customer_id)
    ''');
  }

  Future<void> refresh() async {
    final rows = await _db.rawQuery('''
      SELECT c.*,
        COALESCE(SUM(CASE WHEN e.type = 'baki' THEN e.amount ELSE -e.amount END), 0) AS balance,
        MAX(e.date) AS last_entry_at
      FROM customers c
      LEFT JOIN entries e ON e.customer_id = c.id AND e.deleted = 0
      WHERE c.deleted = 0
      GROUP BY c.id
    ''');
    all = rows.map(Customer.fromMap).toList();
    loaded = true;
    notifyListeners();
    Notifier.scheduleDailySummaries(all);
  }

  Customer? byId(int id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  double get totalDue => totalOf(ledger);

  /// সার্ভারে পাঠানো বাকি আছে এমন রেকর্ডের সংখ্যা (সিঙ্ক চালু হলে কাজে লাগবে)।
  Future<int> pendingSyncCount() async {
    final r = await _db.rawQuery(
      'SELECT (SELECT COUNT(*) FROM customers WHERE dirty = 1) + '
      '(SELECT COUNT(*) FROM entries WHERE dirty = 1) AS n',
    );
    return r.first['n'] as int;
  }

  Future<List<Entry>> entriesOf(int customerId) async {
    final rows = await _db.query(
      'entries',
      where: 'customer_id = ? AND deleted = 0',
      whereArgs: [customerId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Entry.fromMap).toList();
  }

  Future<int> addCustomer({
    required String name,
    String phone = '',
    String address = '',
    String photo = '',
  }) async {
    final id = await _db.insert(
      'customers',
      _touch({
        'uid': newUid(),
        'ledger': ledger.name,
        'name': name.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'photo': photo,
        'created_at': _now(),
      }),
    );
    onLocalChange?.call();
    return id;
  }

  Future<void> updateCustomer(
    int id, {
    required String name,
    String phone = '',
    String address = '',
    String photo = '',
  }) async {
    final old = byId(id)?.photo ?? '';
    if (old.isNotEmpty && old != photo) await deletePhoto(old);
    await _db.update(
      'customers',
      _touch({
        'name': name.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'photo': photo,
      }),
      where: 'id = ?',
      whereArgs: [id],
    );
    await _afterChange(id);
  }

  Future<void> deleteCustomer(int id) async {
    final photo = byId(id)?.photo ?? '';
    if (photo.isNotEmpty) await deletePhoto(photo);
    await _db.transaction((txn) async {
      await txn.update(
        'customers',
        _touch({'deleted': 1, 'photo': ''}),
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'entries',
        _touch({'deleted': 1}),
        where: 'customer_id = ? AND deleted = 0',
        whereArgs: [id],
      );
    });
    await Notifier.cancel(id);
    await refresh();
    onLocalChange?.call();
  }

  /// বাকি বা জমা যোগ করা। বাকির সাথে "কবে দেবে" ও রিমাইন্ডার সেট হয়।
  Future<void> addEntry({
    required int customerId,
    required EntryType type,
    required double amount,
    DateTime? date,
    String note = '',
    DateTime? dueDate,
    DateTime? reminderAt,
    bool updateSchedule = false,
  }) async {
    final customerUid = (await _db.query(
      'customers',
      columns: ['uid'],
      where: 'id = ?',
      whereArgs: [customerId],
    )).first['uid'];
    await _db.insert(
      'entries',
      _touch({
        'uid': newUid(),
        'customer_id': customerId,
        'customer_uid': customerUid,
        'type': type.name,
        'amount': amount,
        'date': (date ?? DateTime.now()).millisecondsSinceEpoch,
        'note': note.trim(),
      }),
    );
    if (updateSchedule) {
      await _setSchedule(customerId, dueDate, reminderAt);
    }
    await _afterChange(customerId);
  }

  Future<void> deleteEntry(Entry e) async {
    await _db.update(
      'entries',
      _touch({'deleted': 1}),
      where: 'id = ?',
      whereArgs: [e.id],
    );
    await _afterChange(e.customerId);
  }

  Future<void> setSchedule(
    int customerId,
    DateTime? dueDate,
    DateTime? reminderAt,
  ) async {
    await _setSchedule(customerId, dueDate, reminderAt);
    await _afterChange(customerId);
  }

  Future<void> _setSchedule(int id, DateTime? due, DateTime? reminder) =>
      _db.update(
        'customers',
        _touch({
          'due_date': due?.millisecondsSinceEpoch,
          'reminder_at': reminder?.millisecondsSinceEpoch,
        }),
        where: 'id = ?',
        whereArgs: [id],
      );

  /// যেকোনো পরিবর্তনের পর: হিসাব রিফ্রেশ, বাকি শোধ হলে তারিখ/রিমাইন্ডার মুছে ফেলা,
  /// আর রিমাইন্ডার নোটিফিকেশন নতুন করে সেট করা।
  Future<void> _afterChange(int id) async {
    onLocalChange?.call();
    await refresh();
    final c = byId(id);
    if (c == null) return;
    if (!c.hasDue && (c.dueDate != null || c.reminderAt != null)) {
      await _setSchedule(id, null, null);
      await refresh();
    }
    await Notifier.schedule(byId(id)!);
  }

  /// সব কাস্টমারের সাম্প্রতিক লেনদেন (নামসহ)।
  Future<List<(Entry, String)>> recentEntries(int limit) async {
    final rows = await _db.rawQuery(
      '''
      SELECT e.*, c.name AS customer_name FROM entries e
      JOIN customers c ON c.id = e.customer_id
      WHERE e.deleted = 0 AND c.deleted = 0 AND c.ledger = ?
      ORDER BY e.date DESC, e.id DESC LIMIT ?
    ''',
      [ledger.name, limit],
    );
    return [
      for (final r in rows) (Entry.fromMap(r), r['customer_name'] as String),
    ];
  }

  // ---------- অনলাইন সিঙ্ক ----------

  /// সার্ভারে পাঠানো বাকি রেকর্ডগুলো।
  Future<
    ({List<Map<String, Object?>> customers, List<Map<String, Object?>> entries})
  >
  dirtyRows() async => (
    customers: await _db.query('customers', where: 'dirty = 1'),
    entries: await _db.query('entries', where: 'dirty = 1'),
  );

  /// পাঠানো রেকর্ড "পরিষ্কার" চিহ্নিত করা। পাঠানোর মাঝে বদলে গেলে (updated_at ভিন্ন)
  /// dirty-ই থেকে যায়, পরের সিঙ্কে আবার যায়।
  Future<void> markPushed(String table, List<Map<String, Object?>> rows) async {
    final b = _db.batch();
    for (final r in rows) {
      b.update(
        table,
        {'dirty': 0},
        where: 'uid = ? AND updated_at = ?',
        whereArgs: [r['uid'], r['updated_at']],
      );
    }
    await b.commit(noResult: true);
  }

  /// নতুন অ্যাকাউন্টে ঢুকলে এই ফোনের সব ডাটা আবার পাঠানোর জন্য।
  Future<void> markAllDirty() async {
    await _db.update('customers', {'dirty': 1});
    await _db.update('entries', {'dirty': 1});
  }

  /// সার্ভার থেকে আসা পরিবর্তন মেশানো। লোকালে নতুন কিছু থাকলে সেটাই থাকে।
  /// ছবি সিঙ্ক হয় না (লোকাল ফাইল), তাই ছবির ঘর ছোঁয়া হয় না।
  Future<void> applyRemote(List customers, List entries) async {
    if (customers.isEmpty && entries.isEmpty) return;
    final changed = <int>{};
    final removed = <int>{};
    await _db.transaction((txn) async {
      for (final m in customers.cast<Map<String, dynamic>>()) {
        final local = (await txn.query(
          'customers',
          columns: ['id', 'updated_at'],
          where: 'uid = ?',
          whereArgs: [m['uid']],
        )).firstOrNull;
        final values = {
          'ledger': m['ledger'],
          'name': m['name'],
          'phone': m['phone'],
          'address': m['address'],
          'due_date': m['due_date'],
          'reminder_at': m['reminder_at'],
          'created_at': m['created_at'],
          'updated_at': m['updated_at'],
          'deleted': m['deleted'] == true ? 1 : 0,
          'dirty': 0,
        };
        int id;
        if (local == null) {
          id = await txn.insert('customers', {
            ...values,
            'uid': m['uid'],
            'photo': '',
          });
        } else if ((m['updated_at'] as int) >= (local['updated_at'] as int)) {
          id = local['id'] as int;
          await txn.update(
            'customers',
            values,
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          continue;
        }
        (m['deleted'] == true ? removed : changed).add(id);
      }
      for (final m in entries.cast<Map<String, dynamic>>()) {
        final customer = (await txn.query(
          'customers',
          columns: ['id'],
          where: 'uid = ?',
          whereArgs: [m['customer_uid']],
        )).firstOrNull;
        if (customer == null) continue;
        final local = (await txn.query(
          'entries',
          columns: ['id', 'updated_at'],
          where: 'uid = ?',
          whereArgs: [m['uid']],
        )).firstOrNull;
        final values = {
          'customer_id': customer['id'],
          'customer_uid': m['customer_uid'],
          'type': m['type'],
          'amount': m['amount'],
          'date': m['date'],
          'note': m['note'],
          'updated_at': m['updated_at'],
          'deleted': m['deleted'] == true ? 1 : 0,
          'dirty': 0,
        };
        if (local == null) {
          await txn.insert('entries', {...values, 'uid': m['uid']});
        } else if ((m['updated_at'] as int) >= (local['updated_at'] as int)) {
          await txn.update(
            'entries',
            values,
            where: 'id = ?',
            whereArgs: [local['id']],
          );
        } else {
          continue;
        }
        changed.add(customer['id'] as int);
      }
    });
    await refresh();
    for (final id in removed) {
      await Notifier.cancel(id);
    }
    for (final id in changed.difference(removed)) {
      final c = byId(id);
      if (c != null) await Notifier.schedule(c);
    }
  }

  // ---------- পরিসংখ্যান ----------

  /// নির্দিষ্ট সময়ের মধ্যে মোট বাকি দেওয়া ও জমা পাওয়া।
  Future<({double baki, double joma, int count})> totalsBetween(
    DateTime? from,
    DateTime? to,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT e.type, SUM(e.amount) AS total, COUNT(*) AS n FROM entries e
      JOIN customers c ON c.id = e.customer_id
      WHERE e.deleted = 0 AND c.ledger = ? AND e.date >= ? AND e.date < ?
      GROUP BY e.type
    ''',
      [
        ledger.name,
        from?.millisecondsSinceEpoch ?? 0,
        to?.millisecondsSinceEpoch ?? 8640000000000000,
      ],
    );
    var baki = 0.0, joma = 0.0, n = 0;
    for (final r in rows) {
      final t = (r['total'] as num).toDouble();
      if (r['type'] == 'baki') {
        baki = t;
      } else {
        joma = t;
      }
      n += r['n'] as int;
    }
    return (baki: baki, joma: joma, count: n);
  }

  /// গত [months] মাসের মাসভিত্তিক বাকি ও আদায়।
  Future<List<({DateTime month, double baki, double joma})>> monthly(
    int months,
  ) async {
    final now = DateTime.now();
    final out = <({DateTime month, double baki, double joma})>[];
    for (var i = months - 1; i >= 0; i--) {
      final start = DateTime(now.year, now.month - i);
      final end = DateTime(now.year, now.month - i + 1);
      final t = await totalsBetween(start, end);
      out.add((month: start, baki: t.baki, joma: t.joma));
    }
    return out;
  }
}
