import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store.dart';
import 'sync.dart';
import 'utils.dart';

/// অ্যাকাউন্টের তথ্য (ফোন নাম্বারই আইডি)।
class Account {
  const Account({
    required this.phone,
    required this.name,
    this.shopName = '',
    this.address = '',
    this.photo = '',
  });

  final String phone;
  final String name;
  final String shopName;
  final String address;

  /// ছবির পাথ বা data URI (ঐচ্ছিক)।
  final String photo;

  Account copyWith({
    String? name,
    String? shopName,
    String? address,
    String? photo,
  }) => Account(
    phone: phone,
    name: name ?? this.name,
    shopName: shopName ?? this.shopName,
    address: address ?? this.address,
    photo: photo ?? this.photo,
  );
}

/// ফোন নাম্বার + ৫ ডিজিটের PIN-এ লগইন (বিকাশের মতো)। অফলাইনে এই ফোনেই চলে;
/// ইন্টারনেট থাকলে একই নাম্বার ও PIN দিয়ে সার্ভারে সংযোগ হয়ে ডাটা সিঙ্ক হয়।
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  // আগের পাসওয়ার্ড-সংস্করণের ডাটা থেকে আলাদা রাখতে নতুন কী।
  static const _kUsers = 'auth_users_pin';
  static const _kCurrent = 'auth_current_pin';
  static const _kLastPhone = 'auth_last_phone';
  static const pinLength = 5;

  late SharedPreferences _prefs;
  Map<String, Map<String, dynamic>> _users = {};
  String? _current;

  bool get loggedIn => account != null;

  Account? get account {
    final u = _current == null ? null : _users[_current];
    if (u == null) return null;
    return Account(
      phone: _current!,
      name: u['name'] as String,
      shopName: (u['shop'] as String?) ?? '',
      address: (u['address'] as String?) ?? '',
      photo: (u['photo'] as String?) ?? '',
    );
  }

  /// সর্বশেষ লগইন করা নাম্বার — পরের বার নিজে থেকে বসে।
  String get lastPhone => _prefs.getString(_kLastPhone) ?? '';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_kUsers);
    if (raw != null) {
      _users = (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
      );
    }
    _current = _prefs.getString(_kCurrent);
    if (!_users.containsKey(_current)) _current = null;
  }

  /// বাংলা/ইংরেজি সংখ্যা, স্পেস, ড্যাশ, +৮৮ সরিয়ে ১১ ডিজিটের নাম্বার (01XXXXXXXXX)।
  /// ভুল হলে null।
  static String? normalizePhone(String input) {
    var d = toEnDigits(input).replaceAll(RegExp(r'[\s\-()]'), '');
    if (d.startsWith('+88')) {
      d = d.substring(3);
    } else if (d.startsWith('88') && d.length == 13) {
      d = d.substring(2);
    }
    return RegExp(r'^01[3-9]\d{8}$').hasMatch(d) ? d : null;
  }

  /// ঠিক ৫টি ডিজিট (বাংলা সংখ্যা হলেও ইংরেজিতে বদলে) — নইলে null।
  static String? cleanPin(String input) {
    final d = toEnDigits(input);
    return RegExp('^\\d{$pinLength}\$').hasMatch(d) ? d : null;
  }

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _newSalt() => Store.newUid();

  Future<void> _save() async {
    await _prefs.setString(_kUsers, jsonEncode(_users));
    if (_current == null) {
      await _prefs.remove(_kCurrent);
    } else {
      await _prefs.setString(_kCurrent, _current!);
      await _prefs.setString(_kLastPhone, _current!);
    }
    notifyListeners();
  }

  /// সফল হলে null, নইলে বাংলা ত্রুটির বার্তা।
  Future<String?> register({
    required String name,
    required String phone,
    required String pin,
  }) async {
    final n = name.trim();
    if (n.isEmpty) return 'আপনার নাম লিখুন';
    final ph = normalizePhone(phone);
    if (ph == null) return 'সঠিক ১১ ডিজিটের ফোন নাম্বার দিন (যেমন ০১৭XXXXXXXX)';
    final p = cleanPin(pin);
    if (p == null) return 'PIN ঠিক ${bn(pinLength)} ডিজিটের হতে হবে';
    if (_users.containsKey(ph)) {
      return 'এই নাম্বারে আগেই অ্যাকাউন্ট আছে। লগইন করুন';
    }
    final salt = _newSalt();
    _users[ph] = {'name': n, 'salt': salt, 'hash': _hash(salt, p)};
    _current = ph;
    await _save();
    unawaited(SyncService.instance.connect(ph, p));
    return null;
  }

  Future<String?> login({required String phone, required String pin}) async {
    final ph = normalizePhone(phone);
    if (ph == null) return 'সঠিক ১১ ডিজিটের ফোন নাম্বার দিন';
    final p = cleanPin(pin);
    if (p == null) return 'PIN ঠিক ${bn(pinLength)} ডিজিটের হতে হবে';
    final u = _users[ph];
    if (u != null && _hash(u['salt'] as String, p) == u['hash']) {
      _current = ph;
      await _save();
      unawaited(SyncService.instance.connect(ph, p));
      return null;
    }
    // এই ফোনে নাম্বার নেই, বা PIN অন্য ফোনে বদলানো হয়েছে — সার্ভার থেকে যাচাই।
    final err = await SyncService.instance.login(ph, p);
    if (err != null) {
      return u == null ? err : 'PIN ঠিক নয়';
    }
    final salt = _newSalt();
    _users[ph] = {
      ...?u,
      'name': (u?['name'] as String?) ?? 'আমার খাতা',
      'salt': salt,
      'hash': _hash(salt, p),
    };
    _current = ph;
    await _save();
    return null;
  }

  Future<void> logout() async {
    await SyncService.instance.logout();
    _current = null;
    await _save();
  }

  Future<String?> updateProfile({
    required String name,
    String shopName = '',
    String address = '',
    String? photo,
  }) async {
    final u = _users[_current];
    if (u == null) return 'লগইন করা নেই';
    final n = name.trim();
    if (n.isEmpty) return 'নাম খালি রাখা যাবে না';
    u['name'] = n;
    u['shop'] = shopName.trim();
    u['address'] = address.trim();
    if (photo != null) u['photo'] = photo;
    await _save();
    return null;
  }

  Future<String?> changePin(String oldPin, String newPin) async {
    final u = _users[_current];
    if (u == null) return 'লগইন করা নেই';
    final o = cleanPin(oldPin);
    if (o == null || _hash(u['salt'] as String, o) != u['hash']) {
      return 'বর্তমান PIN ঠিক নয়';
    }
    final n = cleanPin(newPin);
    if (n == null) return 'নতুন PIN ঠিক ${bn(pinLength)} ডিজিটের হতে হবে';
    // সার্ভারে সংযুক্ত থাকলে আগে সেখানে, নইলে দুই জায়গার PIN আলাদা হয়ে যাবে।
    final err = await SyncService.instance.changePin(o, n);
    if (err != null) return err;
    final salt = _newSalt();
    u['salt'] = salt;
    u['hash'] = _hash(salt, n);
    await _save();
    return null;
  }
}
