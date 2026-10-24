import 'ledger.dart';

class Customer {
  final int id;

  /// কোন খাতার মানুষ — পাওনা (কাস্টমার) না দেনা (পাওনাদার)।
  final Ledger ledger;
  final String name;
  final String phone;

  /// মূল নম্বরের বাইরে আরও নম্বর (সর্বোচ্চ [maxExtraPhones]টি)।
  final List<String> extraPhones;
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

  /// শেষ কবে বাকি দেওয়া হয়েছিল।
  final DateTime? lastBakiAt;

  const Customer({
    required this.id,
    this.ledger = Ledger.pabo,
    required this.name,
    this.phone = '',
    this.extraPhones = const [],
    this.address = '',
    this.photo = '',
    this.dueDate,
    this.reminderAt,
    required this.createdAt,
    this.balance = 0,
    this.lastEntryAt,
    this.lastBakiAt,
  });

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
    id: m['id'] as int,
    ledger: m['ledger'] == 'debo' ? Ledger.debo : Ledger.pabo,
    name: m['name'] as String,
    phone: (m['phone'] as String?) ?? '',
    extraPhones: splitPhones(m['extra_phones'] as String?),
    address: (m['address'] as String?) ?? '',
    photo: (m['photo'] as String?) ?? '',
    dueDate: _date(m['due_date']),
    reminderAt: _date(m['reminder_at']),
    createdAt: _date(m['created_at'])!,
    balance: ((m['balance'] as num?) ?? 0).toDouble(),
    lastEntryAt: _date(m['last_entry_at']),
    lastBakiAt: _date(m['last_baki_at']),
  );

  bool get hasDue => balance > 0.009;

  /// সব নম্বর, মূলটা আগে।
  List<String> get phones => [if (phone.isNotEmpty) phone, ...extraPhones];
}

const maxExtraPhones = 2;

/// ডাটাবেসে বাড়তি নম্বরগুলো এক লাইনে একটা করে রাখা থাকে।
List<String> splitPhones(String? v) => (v ?? '')
    .split('\n')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

String joinPhones(Iterable<String> phones) =>
    phones.map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');

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

/// কাস্টমারের সাথে যোগাযোগের ধরন।
enum ContactKind { call, sms, visit, note }

/// কবে কল/মেসেজ/সরাসরি তাগাদা দেওয়া হলো — সাথে কী বলল তার নোট।
class ContactLog {
  final int id;
  final int customerId;
  final ContactKind kind;
  final String note;
  final DateTime at;

  const ContactLog({
    required this.id,
    required this.customerId,
    required this.kind,
    this.note = '',
    required this.at,
  });

  factory ContactLog.fromMap(Map<String, Object?> m) => ContactLog(
    id: m['id'] as int,
    customerId: m['customer_id'] as int,
    kind: ContactKind.values.asNameMap()[m['kind']] ?? ContactKind.note,
    note: (m['note'] as String?) ?? '',
    at: _date(m['at'])!,
  );
}

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
