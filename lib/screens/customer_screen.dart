import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ledger.dart';
import '../models.dart';
import '../notifications.dart';
import '../photo.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import 'entry_sheet.dart';
import 'shell.dart';

/// নতুন কাস্টমার যোগ বা এডিট। নতুন হলে id ফেরত দেয়।
Future<int?> showCustomerForm(BuildContext context, {Customer? customer}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CustomerForm(customer: customer),
    );

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key, required this.id});
  final int id;

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final _store = Store.instance;
  List<Entry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = await _store.entriesOf(widget.id);
    if (mounted) setState(() => _entries = e);
  }

  Future<void> _addEntry(Customer c, EntryType type) async {
    final saved = await showEntrySheet(context, customer: c, type: type);
    if (saved == true) {
      await _load();
      if (!mounted) return;
      final updated = _store.byId(c.id);
      toast(
        context,
        type == EntryType.joma && updated != null && !updated.hasDue
            ? LedgerText.of(c.ledger).allSettled
            : 'সেভ হয়েছে',
      );
    }
  }

  Future<void> _deleteEntry(Entry e) async {
    final ok = await _confirm(
      'এন্ট্রি মুছবেন?',
      '${_entryWord(e)} ${taka(e.amount)} '
          '(${fmtDate(e.date)}) মুছে যাবে।',
    );
    if (ok) {
      await _store.deleteEntry(e);
      await _load();
    }
  }

  Future<void> _deleteCustomer(Customer c) async {
    final ok = await _confirm(
      '${c.name}-কে মুছবেন?',
      'এই ${LedgerText.of(c.ledger).party}-এর সব হিসাব স্থায়ীভাবে মুছে যাবে।',
    );
    if (ok) {
      await _store.deleteCustomer(c.id);
      if (mounted) Navigator.pop(context);
    }
  }

  String _entryWord(Entry e) {
    final t = LedgerText.of(_store.byId(e.customerId)?.ledger ?? Ledger.pabo);
    return e.type == EntryType.baki ? t.addTitle : t.reduceTitle;
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('না'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                minimumSize: const Size(88, 44),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('মুছুন'),
            ),
          ],
        ),
      ) ??
      false;

  void _call(Customer c) => callPhone(context, c.phone);

  void _sms(Customer c) {
    final due = c.dueDate != null
        ? ' ${fmtDate(c.dueDate!)} তারিখের মধ্যে'
        : '';
    final body =
        'আসসালামু আলাইকুম ${c.name}, দোকানে আপনার বাকি '
        '${taka(c.balance)}। অনুগ্রহ করে$due পরিশোধ করবেন। ধন্যবাদ।';
    sendSms(context, c.phone, body);
  }

  Future<void> _reminder(Customer c) async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (_) => _ReminderSheet(customer: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final c = _store.byId(widget.id);
        if (c == null) return const Scaffold();
        final cs = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${LedgerText.of(c.ledger).name} খাতা • ${LedgerText.of(c.ledger).party}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') showCustomerForm(context, customer: c);
                  if (v == 'delete') _deleteCustomer(c);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('তথ্য এডিট'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('মুছে ফেলুন'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _BalanceCard(customer: c, onReminder: () => _reminder(c)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _QuickAction(
                    icon: Icons.call_rounded,
                    label: 'কল',
                    onTap: c.phone.isEmpty ? null : () => _call(c),
                  ),
                  // তাগাদা SMS শুধু পাওনা খাতায় — নিজের দেনার জন্য না
                  if (c.ledger == Ledger.pabo) ...[
                    const SizedBox(width: 8),
                    _QuickAction(
                      icon: Icons.sms_outlined,
                      label: 'তাগাদা SMS',
                      onTap: c.phone.isEmpty || !c.hasDue
                          ? null
                          : () => _sms(c),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _QuickAction(
                    icon: Icons.alarm_rounded,
                    label: 'রিমাইন্ডার',
                    onTap: c.hasDue ? () => _reminder(c) : null,
                  ),
                ],
              ),
              if (c.phone.isEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => showCustomerForm(context, customer: c),
                  icon: const Icon(Icons.add_call),
                  label: const Text('মোবাইল নম্বর যোগ করুন'),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'লেনদেনের হিসাব',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (_entries == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_entries!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'এখনো কোনো লেনদেন নেই',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < _entries!.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 64),
                        _EntryTile(
                          entry: _entries![i],
                          text: LedgerText.of(c.ledger),
                          onLongPress: () => _deleteEntry(_entries![i]),
                        ),
                      ],
                    ],
                  ),
                ),
              if (_entries?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'মুছতে চাইলে এন্ট্রিতে চেপে ধরুন',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: bakiColor),
                      onPressed: () => _addEntry(c, EntryType.baki),
                      icon: const Icon(Icons.arrow_upward_rounded),
                      label: Text(LedgerText.of(c.ledger).add),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: jomaColor),
                      onPressed: () => _addEntry(c, EntryType.joma),
                      icon: const Icon(Icons.arrow_downward_rounded),
                      label: Text(LedgerText.of(c.ledger).reduce),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.customer, required this.onReminder});
  final Customer customer;
  final VoidCallback onReminder;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final cs = Theme.of(context).colorScheme;
    final reminderActive =
        c.reminderAt != null && c.reminderAt!.isAfter(DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NameAvatar(c, radius: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.hasDue
                            ? LedgerText.of(c.ledger).total
                            : (c.balance < 0
                                  ? LedgerText.of(c.ledger).advance
                                  : '${LedgerText.of(c.ledger).addTitle} নেই'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          taka(c.balance),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: c.hasDue ? bakiColor : jomaColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (c.phone.isNotEmpty || c.address.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                [c.phone, c.address].where((s) => s.isNotEmpty).join(' • '),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
            if (c.hasDue) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(
                    Icons.event_rounded,
                    size: 20,
                    color: dueColor(context, c.dueDate),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.dueDate == null
                          ? LedgerText.of(c.ledger).whenUnset
                          : '${fmtDate(c.dueDate!)} • ${dueLabel(c.dueDate!, c.ledger)}',
                      style: TextStyle(
                        color: dueColor(context, c.dueDate),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: onReminder,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Icon(
                      reminderActive
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_outlined,
                      size: 20,
                      color: reminderActive ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reminderActive
                            ? 'রিমাইন্ডার: ${fmtDateTime(c.reminderAt!)}'
                            : 'রিমাইন্ডার সেট করা নেই',
                        style: TextStyle(
                          color: reminderActive
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      reminderActive ? 'বদলান' : 'সেট করুন',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, color: enabled ? cs.primary : cs.outline),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: enabled ? cs.onSurface : cs.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.text,
    required this.onLongPress,
  });
  final Entry entry;
  final LedgerText text;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final isBaki = e.type == EntryType.baki;
    final color = isBaki ? bakiColor : jomaColor;
    return ListTile(
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .12),
        child: Icon(
          isBaki ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        e.note.isNotEmpty
            ? e.note
            : (isBaki ? text.addTitle : text.reduceTitle),
      ),
      subtitle: Text(fmtDate(e.date)),
      trailing: Text(
        '${isBaki ? '+' : '−'} ${taka(e.amount)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({required this.customer});
  final Customer customer;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late DateTime _due;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    final r = c.reminderAt;
    _due = c.dueDate ?? today().add(const Duration(days: 1));
    if (daysUntil(_due) < 0) _due = today().add(const Duration(days: 1));
    _time = r != null
        ? TimeOfDay.fromDateTime(r)
        : const TimeOfDay(hour: 10, minute: 0);
  }

  DateTime get _at =>
      DateTime(_due.year, _due.month, _due.day, _time.hour, _time.minute);

  Future<void> _save() async {
    if (_at.isBefore(DateTime.now())) {
      return toast(context, 'সময়টা পার হয়ে গেছে — পরের কোনো সময় দিন');
    }
    await Notifier.requestPermission();
    await Store.instance.setSchedule(widget.customer.id, _due, _at);
    if (mounted) {
      Navigator.pop(context);
      toast(context, 'রিমাইন্ডার সেট হয়েছে: ${fmtDateTime(_at)}');
    }
  }

  Future<void> _remove() async {
    await Store.instance.setSchedule(
      widget.customer.id,
      widget.customer.dueDate,
      null,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final quick = [('আগামীকাল', 1), ('৩ দিন পর', 3), ('৭ দিন পর', 7)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'রিমাইন্ডার / টাকা দেওয়ার তারিখ',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final (label, days) in quick)
                ChoiceChip(
                  label: Text(label),
                  selected: daysUntil(_due) == days,
                  onSelected: (_) =>
                      setState(() => _due = today().add(Duration(days: days))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: Text(fmtDate(_due)),
            subtitle: Text(
              LedgerText.of(widget.customer.ledger).whenAsk.replaceAll('?', ''),
            ),
            trailing: const Text('বদলান'),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _due,
                firstDate: today(),
                lastDate: today().add(const Duration(days: 730)),
              );
              if (d != null) setState(() => _due = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_rounded),
            title: Text(fmtTime(_time.hour, _time.minute)),
            subtitle: const Text('কখন মনে করাবে'),
            trailing: const Text('বদলান'),
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: _time,
              );
              if (t != null) setState(() => _time = t);
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.notifications_active_rounded),
            label: const Text('রিমাইন্ডার সেট করুন'),
          ),
          if (widget.customer.reminderAt != null)
            TextButton(
              onPressed: _remove,
              child: const Text('রিমাইন্ডার বন্ধ করুন'),
            ),
        ],
      ),
    );
  }
}

class _CustomerForm extends StatefulWidget {
  const _CustomerForm({this.customer});
  final Customer? customer;

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  late final _name = TextEditingController(text: widget.customer?.name);
  late final _phone = TextEditingController(text: widget.customer?.phone);
  late final _address = TextEditingController(text: widget.customer?.address);
  late String _photo = widget.customer?.photo ?? '';
  bool _saved = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    // সেভ না করে বের হলে নতুন তোলা ছবি মুছে ফেলা
    if (!_saved && _photo.isNotEmpty && _photo != widget.customer?.photo) {
      deletePhoto(_photo);
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ক্যামেরা দিয়ে ছবি তুলুন'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('গ্যালারি থেকে বাছাই'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (_photo.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('ছবি সরান'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final previous = _photo;
    if (source == 'remove') {
      setState(() => _photo = '');
    } else {
      final path = await pickCompressedPhoto(source as ImageSource);
      if (path == null) return;
      setState(() => _photo = path);
    }
    // আগের অসংরক্ষিত ছবি থাকলে মুছে ফেলা
    if (previous.isNotEmpty && previous != widget.customer?.photo) {
      deletePhoto(previous);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(context, 'নাম লিখুন');
    final store = Store.instance;
    final c = widget.customer;
    if (c == null) {
      final id = await store.addCustomer(
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
        photo: _photo,
      );
      _saved = true;
      await store.refresh();
      if (mounted) Navigator.pop(context, id);
    } else {
      await store.updateCustomer(
        c.id,
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
        photo: _photo,
      );
      _saved = true;
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.customer == null
                  ? 'নতুন ${Store.instance.text.party}'
                  : 'তথ্য এডিট',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      backgroundImage: _photo.isEmpty
                          ? null
                          : photoProvider(_photo),
                      child: _photo.isEmpty
                          ? const Icon(Icons.person_rounded, size: 44)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: const Icon(
                          Icons.photo_camera_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ছবি (ঐচ্ছিক)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.customer == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'নাম',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'মোবাইল নম্বর',
                prefixIcon: const Icon(Icons.phone_outlined),
                suffixIcon: IconButton(
                  tooltip: 'কন্টাক্ট থেকে নিন',
                  icon: const Icon(Icons.contacts_outlined),
                  onPressed: () async {
                    final p = await pickContact();
                    if (p != null) setState(() => _phone.text = p.phone);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                hintText: 'ঠিকানা (ঐচ্ছিক)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('সেভ করুন')),
          ],
        ),
      ),
    );
  }
}
