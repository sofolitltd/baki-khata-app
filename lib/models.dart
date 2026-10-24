import 'dart:convert';
import 'dart:math' as math;

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

  /// কিস্তিতে আদায়ের পরিকল্পনা (না থাকলে null)।
  final InstallmentPlan? plan;

  /// পরিকল্পনা শুরুর পর থেকে মোট জমা — ডাটাবেস থেকে হিসাব হয়।
  final double planPaid;

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
    this.plan,
    this.planPaid = 0,
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
    plan: InstallmentPlan.decode(m['plan'] as String?),
    planPaid: ((m['plan_paid'] as num?) ?? 0).toDouble(),
  );

  bool get hasDue => balance > 0.009;

  PlanStatus? get planStatus => plan?.status(planPaid);

  /// কিস্তি চলছে (শেষ হয়নি, বাকিও আছে)।
  bool get onPlan => hasDue && planStatus != null && !planStatus!.done;

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

/// কিস্তিতে আদায় — মোট কত, প্রতি কিস্তিতে কত, কত দিন পরপর।
/// আলাদা কোনো লেনদেন নেই: পরিকল্পনার দিন থেকে সাধারণ জমাগুলোই কিস্তি
/// হিসেবে গোনা হয়।
class InstallmentPlan {
  const InstallmentPlan({
    required this.total,
    required this.amount,
    required this.every,
    required this.start,
    required this.from,
  });

  final double total;
  final double amount;

  /// কত দিন পরপর; ০ = প্রতি মাসে একই তারিখে।
  final int every;

  /// প্রথম কিস্তির তারিখ।
  final DateTime start;

  /// এই দিন (ও পরের) জমাগুলো কিস্তিতে গোনা হয়।
  final DateTime from;

  int get count => (total / amount - 0.0001).ceil();

  /// k-তম কিস্তির তারিখ (০ থেকে)। মাসিক হলে মাসের দিন না থাকলে শেষ দিন।
  DateTime dateOf(int k) {
    if (every > 0) {
      return DateTime(start.year, start.month, start.day + every * k);
    }
    final month = DateTime(start.year, start.month + k);
    final days = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, math.min(start.day, days));
  }

  DateTime get end => dateOf(count - 1);

  PlanStatus status(double paid, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final p = math.min(paid, total);
    final done = p >= total - 0.009;
    // আজ পর্যন্ত যতগুলো কিস্তির তারিখ গেছে, ততটা দেওয়ার কথা
    var due = 0;
    while (due < count && !dateOf(due).isAfter(today)) {
      due++;
    }
    final expected = math.min(due * amount, total);
    final behind = math.max(0.0, expected - p);
    final current = math.min((p / amount + 0.0001).floor(), count - 1);
    return PlanStatus(
      paid: p,
      done: done,
      paidCount: math.min((p / amount + 0.0001).floor(), count),
      nextIndex: current,
      nextDate: dateOf(current),
      nextAmount: math.min((current + 1) * amount, total) - p,
      behind: behind,
      behindCount: (behind / amount - 0.0001).ceil(),
    );
  }

  String encode() => jsonEncode({
    'total': total,
    'amount': amount,
    'every': every,
    'start': start.millisecondsSinceEpoch,
    'from': from.millisecondsSinceEpoch,
  });

  static InstallmentPlan? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      final amount = (m['amount'] as num).toDouble();
      if (amount <= 0) return null;
      return InstallmentPlan(
        total: (m['total'] as num).toDouble(),
        amount: amount,
        every: m['every'] as int,
        start: DateTime.fromMillisecondsSinceEpoch(m['start'] as int),
        from: DateTime.fromMillisecondsSinceEpoch(m['from'] as int),
      );
    } catch (_) {
      return null;
    }
  }
}

class PlanStatus {
  const PlanStatus({
    required this.paid,
    required this.done,
    required this.paidCount,
    required this.nextIndex,
    required this.nextDate,
    required this.nextAmount,
    required this.behind,
    required this.behindCount,
  });

  /// পরিকল্পনায় এ পর্যন্ত দেওয়া (মোটের বেশি গোনা হয় না)।
  final double paid;
  final bool done;

  /// পুরোপুরি দেওয়া কিস্তি।
  final int paidCount;

  /// এখন যে কিস্তি চলছে (০ থেকে), তার তারিখ ও বাকি অংশ।
  final int nextIndex;
  final DateTime nextDate;
  final double nextAmount;

  /// আজ পর্যন্ত যা দেওয়ার কথা ছিল, তার চেয়ে কত কম।
  final double behind;
  final int behindCount;
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
