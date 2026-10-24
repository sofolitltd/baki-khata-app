import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth.dart';
import '../ledger.dart';
import '../notifications.dart';
import '../photo.dart';
import '../pin_field.dart';
import '../store.dart';
import '../sync.dart';
import '../utils.dart';
import 'due_reminder.dart';

/// প্রোফাইল: নিজের তথ্য, দোকানের তথ্য, খাতার সারসংক্ষেপ, সিঙ্ক, PIN বদল ও লগআউট।
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('প্রোফাইল')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          auth,
          Store.instance,
          SyncService.instance,
        ]),
        builder: (context, _) {
          final acc = auth.account;
          if (acc == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _header(context, acc),
              const SizedBox(height: 16),
              _summary(context),
              const SizedBox(height: 16),
              _section(context, 'দোকানের তথ্য', [
                _info(Icons.storefront_rounded, 'দোকানের নাম', acc.shopName),
                _info(Icons.location_on_rounded, 'ঠিকানা', acc.address),
              ]),
              const SizedBox(height: 16),
              _section(context, 'অ্যাকাউন্ট', [
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('প্রোফাইল এডিট'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editProfile(context, acc),
                ),
                ListTile(
                  leading: const Icon(Icons.pin_rounded),
                  title: const Text('PIN বদলান'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _changePin(context),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_rounded),
                  title: const Text('অনলাইন ব্যাকআপ ও সিঙ্ক'),
                  subtitle: Text(
                    SyncService.instance.loggedIn ? 'চালু' : 'বন্ধ',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showSyncSheet(context),
                ),
              ]),
              const SizedBox(height: 16),
              _section(context, 'নোটিফিকেশন', [
                ValueListenableBuilder(
                  valueListenable: Notifier.summaryTime,
                  builder: (context, t, _) => ListTile(
                    leading: const Icon(Icons.wb_sunny_rounded),
                    title: const Text('সকালের সারাংশের সময়'),
                    subtitle: Text(fmtTime(t.hour, t.minute)),
                    trailing: const Text('বদলান'),
                    onTap: () async {
                      final picked = await pickReminderTime(context, t);
                      if (picked == null) return;
                      await Notifier.requestPermission();
                      await Notifier.setSummaryTime(picked);
                      await Store.instance.scheduleDaily();
                    },
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: Notifier.recapOn,
                  builder: (context, on, _) => SwitchListTile(
                    secondary: const Icon(Icons.nightlight_round),
                    title: const Text('দিনের শেষের হিসাব'),
                    subtitle: const Text(
                      'আজ কত বাকি দিলেন, কত আদায় হলো — না লিখলে মনে করিয়ে দেবে',
                    ),
                    value: on,
                    onChanged: (v) async {
                      if (v) await Notifier.requestPermission();
                      await Notifier.setRecap(on: v);
                      await Store.instance.scheduleDaily();
                    },
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: Notifier.recapOn,
                  builder: (context, on, _) => !on
                      ? const SizedBox.shrink()
                      : ValueListenableBuilder(
                          valueListenable: Notifier.recapTime,
                          builder: (context, t, _) => ListTile(
                            leading: const Icon(Icons.schedule_rounded),
                            title: const Text('দিনের শেষের হিসাবের সময়'),
                            subtitle: Text(fmtTime(t.hour, t.minute)),
                            trailing: const Text('বদলান'),
                            onTap: () async {
                              final picked = await pickReminderTime(context, t);
                              if (picked == null) return;
                              await Notifier.setRecap(time: picked);
                              await Store.instance.scheduleDaily();
                            },
                          ),
                        ),
                ),
              ]),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _logout(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('লগআউট'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, Account acc) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 8),
        _ProfileAvatar(acc, radius: 48),
        const SizedBox(height: 12),
        Text(
          acc.name,
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          bn(acc.phone),
          style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final store = Store.instance;
    Widget cell(Ledger l, String label, int count) {
      final color = ledgerAccent(l, Theme.of(context).brightness);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(
                  taka(store.totalOf(l)),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${bn(count)} জন',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    int count(Ledger l) => store.all.where((c) => c.ledger == l).length;
    return Card(
      child: Row(
        children: [
          cell(Ledger.pabo, 'মোট পাওনা', count(Ledger.pabo)),
          const SizedBox(height: 48, child: VerticalDivider(width: 1)),
          cell(Ledger.debo, 'মোট দেনা', count(Ledger.debo)),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _info(IconData icon, String label, String value) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    subtitle: Text(value.isEmpty ? 'দেওয়া হয়নি' : value),
  );

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('লগআউট করবেন?'),
        content: const Text('এই ফোনের খাতার ডাটা মুছবে না।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('না'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('লগআউট'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await AuthService.instance.logout();
  }

  void _editProfile(BuildContext context, Account acc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(acc),
    );
  }

  void _changePin(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ChangePinSheet(),
    );
  }
}

/// ছবি থাকলে ছবি, নইলে নামের প্রথম অক্ষর।
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar(this.acc, {required this.radius});
  final Account acc;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary.withValues(alpha: .14),
      backgroundImage: acc.photo.isEmpty ? null : photoProvider(acc.photo),
      child: acc.photo.isEmpty
          ? Text(
              acc.name.characters.first.toUpperCase(),
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                fontSize: radius * .8,
              ),
            )
          : null,
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet(this.acc);
  final Account acc;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.acc.name);
  late final _shop = TextEditingController(text: widget.acc.shopName);
  late final _address = TextEditingController(text: widget.acc.address);
  late String _photo = widget.acc.photo;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _shop.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('ক্যামেরা'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('গ্যালারি'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (_photo.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('ছবি মুছুন'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _photo = '');
                },
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final path = await pickCompressedPhoto(context, source);
    if (path != null && mounted) setState(() => _photo = path);
  }

  Future<void> _save() async {
    final old = widget.acc.photo;
    final msg = await AuthService.instance.updateProfile(
      name: _name.text,
      shopName: _shop.text,
      address: _address.text,
      photo: _photo,
    );
    if (!mounted) return;
    if (msg != null) {
      setState(() => _err = msg);
      return;
    }
    if (old.isNotEmpty && old != _photo) await deletePhoto(old);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.acc.copyWith(name: _name.text, photo: _photo);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'প্রোফাইল এডিট',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: _pick,
                child: Stack(
                  children: [
                    _ProfileAvatar(preview, radius: 44),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'আপনার নাম',
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _shop,
              decoration: const InputDecoration(
                labelText: 'দোকানের নাম (ঐচ্ছিক)',
                prefixIcon: Icon(Icons.storefront_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'ঠিকানা (ঐচ্ছিক)',
                prefixIcon: Icon(Icons.location_on_rounded),
              ),
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(
                _err!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('সেভ করুন')),
          ],
        ),
      ),
    );
  }
}

class _ChangePinSheet extends StatefulWidget {
  const _ChangePinSheet();

  @override
  State<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends State<_ChangePinSheet> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _oldFocus = FocusNode();
  final _newFocus = FocusNode();
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    // সংখ্যার কীপ্যাড নিজে খোলে।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _oldFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _oldFocus.dispose();
    _newFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final msg = await AuthService.instance.changePin(_old.text, _new.text);
    if (!mounted) return;
    if (msg != null) {
      setState(() {
        _busy = false;
        _err = msg;
        _new.clear();
      });
      _newFocus.requestFocus();
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN বদলানো হয়েছে')));
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('PIN বদলান', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            PinField(
              label: 'বর্তমান PIN',
              controller: _old,
              focusNode: _oldFocus,
              onChanged: () => setState(() {}),
              onCompleted: _newFocus.requestFocus,
            ),
            const SizedBox(height: 12),
            PinField(
              label: 'নতুন PIN (${bn(PinField.pinLength)} ডিজিট)',
              controller: _new,
              focusNode: _newFocus,
              onChanged: () => setState(() {}),
              onCompleted: _save,
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(
                _err!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  _busy ||
                      _old.text.length != PinField.pinLength ||
                      _new.text.length != PinField.pinLength
                  ? null
                  : _save,
              child: const Text('বদলান'),
            ),
          ],
        ),
      ),
    );
  }
}
