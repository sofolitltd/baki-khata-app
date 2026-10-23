import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ledger.dart';

const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// ইংরেজি সংখ্যাকে বাংলা সংখ্যায় রূপান্তর।
String bn(Object value) => value.toString().replaceAllMapped(
  RegExp(r'\d'),
  (m) => _bnDigits[int.parse(m[0]!)],
);

/// বাংলা সংখ্যাকে ইংরেজি সংখ্যায় রূপান্তর (ইনপুট পার্স করার জন্য)।
String toEnDigits(String value) {
  var out = value;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(_bnDigits[i], '$i');
  }
  return out;
}

double? parseAmount(String text) =>
    double.tryParse(toEnDigits(text).replaceAll(',', '').trim());

final _money = NumberFormat('#,##,##0.##', 'en_IN');

String taka(num value) => '৳ ${bn(_money.format(value.abs()))}';

String fmtDate(DateTime d) => bn(DateFormat('d MMMM yyyy', 'bn').format(d));
String fmtShortDate(DateTime d) => bn(DateFormat('d MMM', 'bn').format(d));
String fmtDateTime(DateTime d) =>
    '${bn(DateFormat('d MMM', 'bn').format(d))}, ${fmtTime(d.hour, d.minute)}';

/// "সকাল ১০:০০" ধরনের সময়।
String fmtTime(int hour, int minute) {
  final period = hour < 5
      ? 'রাত'
      : hour < 12
      ? 'সকাল'
      : hour < 15
      ? 'দুপুর'
      : hour < 18
      ? 'বিকাল'
      : hour < 20
      ? 'সন্ধ্যা'
      : 'রাত';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return bn('$period $h12:${minute.toString().padLeft(2, '0')}');
}

DateTime today() => DateUtils.dateOnly(DateTime.now());

int daysUntil(DateTime date) =>
    DateUtils.dateOnly(date).difference(today()).inDays;

enum DueStatus { none, overdue, today, soon, later }

DueStatus dueStatus(DateTime? due) {
  if (due == null) return DueStatus.none;
  final d = daysUntil(due);
  if (d < 0) return DueStatus.overdue;
  if (d == 0) return DueStatus.today;
  if (d <= 3) return DueStatus.soon;
  return DueStatus.later;
}

String dueLabel(DateTime due, [Ledger ledger = Ledger.pabo]) {
  final t = LedgerText.of(ledger);
  final d = daysUntil(due);
  if (d < 0) return '${bn(-d)} দিন পার হয়েছে';
  if (d == 0) return t.dueToday;
  if (d == 1) return t.dueTomorrow;
  return '${bn(d)} ${t.dueInDays}';
}

Color dueColor(BuildContext context, DateTime? due) {
  final cs = Theme.of(context).colorScheme;
  return switch (dueStatus(due)) {
    DueStatus.overdue => cs.error,
    DueStatus.today => const Color(0xFFD97706),
    DueStatus.soon => const Color(0xFFD97706),
    _ => cs.onSurfaceVariant,
  };
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// ফোনের কন্টাক্ট থেকে একটি নাম ও নম্বর বেছে নেওয়া। বাতিল/অনুমতি না দিলে null।
Future<({String name, String phone})?> pickContact() async {
  try {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      return null;
    }
    final c = await FlutterContacts.native.showPicker(
      properties: {ContactProperty.phone, ContactProperty.name},
    );
    if (c == null || c.phones.isEmpty) return null;
    final raw = c.phones.first.number;
    final phone = raw.replaceAll(RegExp(r'[^\d+]'), '');
    return (name: c.displayName ?? '', phone: phone);
  } catch (_) {
    return null;
  }
}

String _dialable(String phone) =>
    toEnDigits(phone).replaceAll(RegExp(r'[^\d+]'), '');

Future<void> _open(BuildContext context, Uri uri, String failMsg) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) toast(context, failMsg);
}

/// ডায়ালারে নাম্বার বসিয়ে খোলে।
Future<void> callPhone(BuildContext context, String phone) =>
    _open(context, Uri(scheme: 'tel', path: _dialable(phone)), 'কল করা যায়নি');

/// মেসেজ অ্যাপে নাম্বার ও লেখা বসিয়ে খোলে।
Future<void> sendSms(BuildContext context, String phone, String body) => _open(
  context,
  Uri.parse('sms:${_dialable(phone)}?body=${Uri.encodeComponent(body)}'),
  'এসএমএস পাঠানো যায়নি',
);
