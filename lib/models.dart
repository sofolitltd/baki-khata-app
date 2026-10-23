import 'ledger.dart';

class Customer {
  final int id;

  /// কোন খাতার মানুষ — পাওনা (কাস্টমার) না দেনা (পাওনাদার)।
  final Ledger ledger;
  final String name;
  final String phone;
  final String address;

  /// কম্প্রেস করা ছবির লোকাল পাথ (ঐচ্ছিক)।
  final String photo;

  /// কবে টাকা দেবে বলেছে।
  final DateTime? dueDate;

  /// কখন রিমাইন্ডার দেখাবে।
  final DateTime? reminderAt;
  final DateTime createdAt;

  /// মোট বাকি (বাকি - জমা)। ডাটাবেস query থেকে হিসাব হয়।
  final double balance;
  final DateTime? lastEntryAt;

  const Customer({
    required this.id,
    this.ledger = Ledger.pabo,
    required this.name,
    this.phone = '',
    this.address = '',
    this.photo = '',
    this.dueDate,
    this.reminderAt,
    required this.createdAt,
    this.balance = 0,
    this.lastEntryAt,
  });

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
    id: m['id'] as int,
    ledger: m['ledger'] == 'debo' ? Ledger.debo : Ledger.pabo,
    name: m['name'] as String,
    phone: (m['phone'] as String?) ?? '',
    address: (m['address'] as String?) ?? '',
    photo: (m['photo'] as String?) ?? '',
    dueDate: _date(m['due_date']),
    reminderAt: _date(m['reminder_at']),
    createdAt: _date(m['created_at'])!,
    balance: ((m['balance'] as num?) ?? 0).toDouble(),
    lastEntryAt: _date(m['last_entry_at']),
  );

  bool get hasDue => balance > 0.009;
}

enum EntryType { baki, joma }

class Entry {
  final int id;
  final int customerId;
  final EntryType type;
  final double amount;
  final DateTime date;
  final String note;

  const Entry({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.date,
    this.note = '',
  });

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
    id: m['id'] as int,
    customerId: m['customer_id'] as int,
    type: m['type'] == 'joma' ? EntryType.joma : EntryType.baki,
    amount: (m['amount'] as num).toDouble(),
    date: _date(m['date'])!,
    note: (m['note'] as String?) ?? '',
  );
}

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
