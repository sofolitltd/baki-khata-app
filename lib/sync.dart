import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';

import 'package:intl/intl.dart';

import 'config.dart';
import 'photo.dart';
import 'pin_field.dart';
import 'store.dart';
import 'utils.dart';

class _ApiError implements Exception {
  _ApiError(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
}

/// লোকাল SQLite ↔ অনলাইন সার্ভার সিঙ্ক। অ্যাপ আগের মতো অফলাইনেই চলে;
/// ইন্টারনেট থাকলে `dirty` রেকর্ড পাঠায়, আর সার্ভারের নতুন পরিবর্তন নামায়।
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _kToken = 'sync_token';
  static const _kPhone = 'sync_phone';
  static const _kCursor = 'sync_cursor';
  static const _kLastAt = 'sync_last_at';
  static const _kLastPushed = 'sync_last_pushed';
  static const _kLastPulled = 'sync_last_pulled';
  static const _chunk = 200;

  late SharedPreferences _prefs;
  Timer? _debounce;
  bool _again = false;

  String? token;
  String? phone;
  bool syncing = false;
  String? error;
  DateTime? lastSyncAt;

  /// শেষ সফল সিঙ্কে কতগুলো রেকর্ড পাঠানো ও নামানো হয়েছে।
  int lastPushed = 0;
  int lastPulled = 0;
  int pending = 0;

  // সার্ভারের সংযোগের জন্য PIN ফোনের সুরক্ষিত স্টোরে (Keychain/Keystore) থাকে,
  // যাতে টোকেন না থাকলে বা মেয়াদ শেষ হলে ব্যবহারকারীকে আবার PIN দিতে না হয়।
  static const _secure = FlutterSecureStorage();
  static const _kPin = 'sync_pin';

  bool get loggedIn => token != null;
  int get _cursor => _prefs.getInt(_kCursor) ?? 0;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    token = _prefs.getString(_kToken);
    phone = _prefs.getString(_kPhone);
    final at = _prefs.getInt(_kLastAt);
    lastSyncAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    lastPushed = _prefs.getInt(_kLastPushed) ?? 0;
    lastPulled = _prefs.getInt(_kLastPulled) ?? 0;
    Store.instance.onLocalChange = schedule;
    pending = await Store.instance.pendingSyncCount();
    // ইন্টারনেট না থাকলে আবার চেষ্টার জন্য।
    Timer.periodic(const Duration(minutes: 2), (_) {
      if (!loggedIn) {
        retryConnect();
      } else if (pending > 0 || error != null) {
        syncNow();
      }
    });
    notifyListeners();
    if (loggedIn) {
      unawaited(syncNow());
    } else {
      unawaited(retryConnect());
    }
  }

  /// পরিবর্তনের একটু পরে একবারে সিঙ্ক (বারবার সেভে বারবার রিকুয়েস্ট এড়াতে)।
  void schedule() {
    pending++;
    notifyListeners();
    if (!loggedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  /// সফল হলে null, নইলে বাংলা ত্রুটির বার্তা।
  Future<String?> login(String phone, String pin) =>
      _auth('/auth/login', phone, pin);

  Future<String?> register(String phone, String pin) =>
      _auth('/auth/register', phone, pin);

  static const _existsMsg = 'এই নম্বরে আগেই অ্যাকাউন্ট আছে';

  /// অ্যাপে লগইন করা নম্বর; সার্ভারে সংযোগের ফর্মে আগে থেকে বসে।
  String? hintPhone;
  String? get savedPhone => _prefs.getString(_kPhone) ?? hintPhone;

  /// অ্যাপের লগইনের পরে একই নম্বর ও PIN দিয়ে সার্ভারে সংযোগ: অ্যাকাউন্ট না থাকলে
  /// খোলে, থাকলে লগইন করে। ব্যর্থ হলে ত্রুটি দেখায় (অফলাইনে চুপচাপ পরে আবার চেষ্টা)।
  Future<String?> connect(String phone, String pin) async {
    hintPhone = phone;
    var err = await register(phone, pin);
    if (err == _existsMsg) err = await login(phone, pin);
    if (err == null) {
      await _savePin(pin);
    } else if (err == _offlineMsg) {
      // অফলাইনে PIN রেখে দেওয়া হয়, ইন্টারনেট এলে নিজে সংযোগ হবে।
      await _savePin(pin);
    } else {
      // PIN ভুল/বদলে গেছে — পুরোনোটা রেখে লাভ নেই, নতুন করে চাওয়া হবে।
      await _clearPin();
    }
    if (err != null) {
      error = err;
      notifyListeners();
    }
    return err;
  }

  Future<void> _savePin(String pin) async {
    try {
      await _secure.write(key: _kPin, value: pin);
    } catch (_) {}
  }

  Future<void> _clearPin() async {
    try {
      await _secure.delete(key: _kPin);
    } catch (_) {}
  }

  bool _connecting = false;

  /// সংরক্ষিত PIN দিয়ে চুপচাপ সংযোগ (টোকেন না থাকলে বা মেয়াদ শেষ হলে)।
  /// PIN না থাকলে কিছু করে না — তখন শিটে PIN চাওয়া হয়।
  Future<void> retryConnect() async {
    if (loggedIn || _connecting || syncing) return;
    final ph = AuthService.instance.account?.phone ?? phone;
    if (ph == null) return;
    _connecting = true;
    try {
      final pin = await _secure.read(key: _kPin);
      if (pin != null) await connect(ph, pin);
    } catch (_) {
    } finally {
      _connecting = false;
    }
  }

  /// সংযুক্ত থাকলে সার্ভারে PIN বদলায়। সংযুক্ত না থাকলে কিছু করে না।
  Future<String?> changePin(String oldPin, String newPin) async {
    if (!loggedIn) {
      await _savePin(newPin);
      return null;
    }
    try {
      await _send(
        'POST',
        '/auth/change-pin',
        body: {'old_pin': oldPin, 'new_pin': newPin},
      );
      await _savePin(newPin);
      return null;
    } on _ApiError catch (e) {
      return e.message;
    } catch (_) {
      return 'PIN বদলাতে ইন্টারনেট লাগবে। ইন্টারনেট চালু করে আবার চেষ্টা করুন';
    }
  }

  Future<String?> _auth(String path, String phone, String pin) async {
    try {
      final res = await _send(
        'POST',
        path,
        body: {'phone': phone, 'pin': pin},
        authed: false,
      );
      final changedUser = _prefs.getString(_kPhone) != res['phone'];
      token = res['token'] as String;
      this.phone = res['phone'] as String;
      await _prefs.setString(_kToken, token!);
      await _prefs.setString(_kPhone, this.phone!);
      // নতুন অ্যাকাউন্ট হলে এই ফোনের সব ডাটা সেখানে যাবে, আর নতুন করে নামানো হবে।
      if (changedUser) {
        await _prefs.setInt(_kCursor, 0);
        await Store.instance.markAllDirty();
        pending = await Store.instance.pendingSyncCount();
      }
      error = null;
      notifyListeners();
      unawaited(syncNow());
      return null;
    } on _ApiError catch (e) {
      return e.message;
    } catch (_) {
      return _offlineMsg;
    }
  }

  /// লগআউট করলে এই ফোনের ডাটা মোছে না।
  Future<void> logout() async {
    _debounce?.cancel();
    token = null;
    error = null;
    lastSyncAt = null;
    lastPushed = lastPulled = 0;
    await _clearPin();
    await _dropToken();
  }

  /// টোকেন ফেলে দেয়, কিন্তু সংরক্ষিত PIN রাখে (মেয়াদ শেষ হলে নিজে আবার লগইন)।
  Future<void> _dropToken() async {
    token = null;
    await _prefs.remove(_kToken);
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (!loggedIn) return;
    if (syncing) {
      _again = true;
      return;
    }
    syncing = true;
    error = null;
    notifyListeners();
    final store = Store.instance;
    try {
      final d = await store.dirtyRows();
      final cs = [for (final r in d.customers) await _customerJson(r)];
      final es = d.entries.map(_entryJson).toList();
      for (var i = 0; i < cs.length; i += _chunk) {
        await _send(
          'POST',
          '/sync/push',
          body: {'customers': cs.skip(i).take(_chunk).toList(), 'entries': []},
        );
      }
      for (var i = 0; i < es.length; i += _chunk) {
        await _send(
          'POST',
          '/sync/push',
          body: {'customers': [], 'entries': es.skip(i).take(_chunk).toList()},
        );
      }
      await store.markPushed('customers', d.customers);
      await store.markPushed('entries', d.entries);

      final res = await _send('GET', '/sync/pull?since=$_cursor');
      await store.applyRemote(res['customers'] as List, res['entries'] as List);
      await _prefs.setInt(_kCursor, res['cursor'] as int);
      lastSyncAt = DateTime.now();
      lastPushed = d.customers.length + d.entries.length;
      lastPulled =
          (res['customers'] as List).length + (res['entries'] as List).length;
      await _prefs.setInt(_kLastAt, lastSyncAt!.millisecondsSinceEpoch);
      await _prefs.setInt(_kLastPushed, lastPushed);
      await _prefs.setInt(_kLastPulled, lastPulled);
    } on _ApiError catch (e) {
      error = e.message;
      if (e.unauthorized) {
        await _dropToken();
        unawaited(retryConnect());
      }
    } catch (_) {
      error = _offlineMsg;
    } finally {
      syncing = false;
      pending = await store.pendingSyncCount();
      notifyListeners();
    }
    if (_again) {
      _again = false;
      unawaited(syncNow());
    }
  }

  static const _offlineMsg = 'সার্ভারে কানেক্ট করা যায়নি। ইন্টারনেট দেখুন';

  static Future<Map<String, Object?>> _customerJson(
    Map<String, Object?> r,
  ) async => {
    'uid': r['uid'],
    'ledger': r['ledger'],
    'name': r['name'],
    'phone': r['phone'],
    'address': r['address'],
    'photo': await photoToData(r['photo'] as String? ?? ''),
    'due_date': r['due_date'],
    'reminder_at': r['reminder_at'],
    'created_at': r['created_at'],
    'updated_at': r['updated_at'],
    'deleted': r['deleted'] == 1,
  };

  static Map<String, Object?> _entryJson(Map<String, Object?> r) => {
    'uid': r['uid'],
    'customer_uid': r['customer_uid'],
    'type': r['type'],
    'amount': r['amount'],
    'date': r['date'],
    'note': r['note'],
    'updated_at': r['updated_at'],
    'deleted': r['deleted'] == 1,
  };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authed = true,
  }) async {
    final req = http.Request(method, Uri.parse('$apiBase$path'));
    req.headers['Content-Type'] = 'application/json';
    if (authed) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 25)),
    );
    final data = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw _ApiError(
      (data['error'] as String?) ?? 'সার্ভারে সমস্যা (${res.statusCode})',
      unauthorized: authed && res.statusCode == 401,
    );
  }
}

/// সিঙ্ক বাটন থেকে খোলা শিট: লগইন / সিঙ্কের অবস্থা।
void showSyncSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SyncSheet(),
  );
}

class _SyncSheet extends StatefulWidget {
  const _SyncSheet();

  @override
  State<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<_SyncSheet> {
  final _sync = SyncService.instance;
  // অ্যাপে লগইন করা নম্বরই সার্ভারের নম্বর — আলাদা করে চাওয়া হয় না।
  late final String _phone =
      AuthService.instance.account?.phone ?? _sync.savedPhone ?? '';
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    if (_sync.loggedIn) return;
    // সংরক্ষিত PIN থাকলে নিজেই সংযোগ হয়; না হলে (PIN বদলে গেছে) PIN-এর ঘর।
    unawaited(_autoRetry());
  }

  Future<void> _autoRetry() async {
    setState(() => _busy = true);
    await _sync.retryConnect();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!_sync.loggedIn) _pinFocus.requestFocus();
  }

  @override
  void dispose() {
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final msg = await _sync.connect(_phone, _pin.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = msg;
      if (msg != null) _pin.clear();
    });
    if (msg != null) _pinFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListenableBuilder(
        listenable: _sync,
        builder: (context, _) => SingleChildScrollView(
          child: _sync.loggedIn ? _status(context) : _form(context),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final ready = _phone.isNotEmpty && _pin.text.length == PinField.pinLength;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('অনলাইন ব্যাকআপ ও সিঙ্ক', style: t.titleLarge),
        const SizedBox(height: 6),
        Text(
          'আপনি অ্যাপে ${bn(_phone)} নম্বরে লগইন করা আছেন। ব্যাকআপ চালু করতে '
          'শুধু PIN দিন। ইন্টারনেট না থাকলেও অ্যাপ আগের মতোই চলবে।',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 16),
        PinField(
          controller: _pin,
          focusNode: _pinFocus,
          onChanged: () => setState(() {}),
          onCompleted: _submit,
        ),
        if ((_err ?? _sync.error) != null) ...[
          const SizedBox(height: 10),
          Text((_err ?? _sync.error)!, style: TextStyle(color: cs.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || !ready ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('সংযোগ করুন'),
        ),
      ],
    );
  }

  static String _amPm(DateTime d) => bn(DateFormat('h:mm a', 'en').format(d));

  String _lastSyncText(DateTime? last) {
    if (last == null) return 'এখনো সিঙ্ক হয়নি';
    final days = today().difference(DateUtils.dateOnly(last)).inDays;
    final day = days == 0
        ? 'আজ'
        : days == 1
        ? 'গতকাল'
        : fmtDate(last);
    final counts = _sync.lastPushed == 0 && _sync.lastPulled == 0
        ? 'নতুন কিছু ছিল না'
        : 'পাঠানো ${bn(_sync.lastPushed)}টি · নামানো ${bn(_sync.lastPulled)}টি';
    return 'শেষ সিঙ্ক: $day, ${_amPm(last)}\n$counts';
  }

  Widget _status(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final last = _sync.lastSyncAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('অনলাইন সিঙ্ক চালু', style: t.titleLarge),
        const SizedBox(height: 4),
        Text(_sync.phone ?? '', style: t.bodyMedium),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _sync.syncing
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _sync.error != null
                      ? Icons.error_outline_rounded
                      : Icons.cloud_done_rounded,
                  color: _sync.error != null ? cs.error : cs.primary,
                ),
          title: Text(
            _sync.syncing
                ? 'সিঙ্ক হচ্ছে...'
                : _sync.error ??
                      (_sync.pending > 0
                          ? 'পাঠানো বাকি: ${_sync.pending}টি'
                          : 'সব ডাটা সিঙ্ক করা আছে'),
          ),
          isThreeLine: true,
          subtitle: Text(_lastSyncText(last)),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _sync.syncing ? null : _sync.syncNow,
          icon: const Icon(Icons.sync_rounded),
          label: const Text('এখনই সিঙ্ক করুন'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _sync.syncing
              ? null
              : () async {
                  await _sync.logout();
                },
          child: const Text('লগআউট (এই ফোনের ডাটা থাকবে)'),
        ),
      ],
    );
  }
}

/// সিঙ্কের অবস্থা দেখানো ছোট ক্লাউড বাটন।
class SyncButton extends StatelessWidget {
  const SyncButton({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return ListenableBuilder(
      listenable: SyncService.instance,
      builder: (context, _) {
        final s = SyncService.instance;
        final (icon, color) = !s.loggedIn
            ? (Icons.cloud_off_rounded, cs.onSurfaceVariant)
            : s.error != null
            ? (Icons.cloud_off_rounded, cs.error)
            : s.syncing
            ? (Icons.cloud_sync_rounded, cs.primary)
            : s.pending > 0
            ? (Icons.cloud_upload_rounded, cs.primary)
            : (Icons.cloud_done_rounded, cs.primary);
        return Tooltip(
          message: 'অনলাইন সিঙ্ক',
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () {
              // ট্যাপ করলেই সিঙ্ক শুরু; শিটে অবস্থা দেখা যায়।
              unawaited(s.syncNow());
              showSyncSheet(context);
            },
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: light ? Colors.white : cs.surfaceContainer,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .6),
                ),
              ),
              child: Icon(icon, color: color),
            ),
          ),
        );
      },
    );
  }
}
