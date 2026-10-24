import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ledger.dart';
import '../models.dart';
import '../notifications.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../voice.dart';
import 'customer_picker.dart';
import 'due_reminder.dart';
import 'installment.dart';

/// বাকি / জমা লেখার শিট।
/// [customer] না দিলে নতুন (বা আগের) কাস্টমারের নাম লিখে সরাসরি বাকি লেখা যায় —
/// এক স্ক্রিনেই কাজ শেষ।
Future<bool?> showEntrySheet(
  BuildContext context, {
  Customer? customer,
  EntryType type = EntryType.baki,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _EntrySheet(customer: customer, type: type),
);

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({this.customer, required this.type});
  final Customer? customer;
  final EntryType type;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _store = Store.instance;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  Customer? _picked; // নাম লিখতে গিয়ে আগের কাস্টমার বাছাই করলে
  TextEditingController? _acController;
  DateTime _date = DateTime.now();
  DateTime? _due;
  TimeOfDay _remindTime = defaultReminderTime;
  bool _remind = true;
  bool _saving = false;

  Customer? get _customer => widget.customer ?? _picked;
  bool get _isBaki => widget.type == EntryType.baki;

  /// কিস্তি চললে তারিখ ও রিমাইন্ডার কিস্তি থেকেই আসে।
  bool get _onPlan => _customer?.onPlan ?? false;
  LedgerText get _t => LedgerText.of(_customer?.ledger ?? _store.ledger);

  @override
  void initState() {
    super.initState();
    final existingDue = widget.customer?.dueDate;
    _due = existingDue != null && daysUntil(existingDue) >= 0
        ? existingDue
        : today().add(const Duration(days: 7));
    final r = widget.customer?.reminderAt;
    if (r != null) _remindTime = TimeOfDay.fromDateTime(r);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _amount, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'লেনদেনের তারিখ',
    );
    if (d == null) return;
    setState(
      () => _date = DateUtils.isSameDay(d, DateTime.now()) ? DateTime.now() : d,
    );
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (_customer == null && _name.text.trim().isEmpty) {
      return toast(context, 'নাম লিখুন');
    }
    if (amount == null || amount <= 0) {
      return toast(context, 'সঠিক টাকার পরিমাণ লিখুন');
    }

    // কিছু সেভ হওয়ার আগেই, যাতে বাতিল করলে অর্ধেক কাজ না থাকে
    DateTime? remindAt;
    if (_isBaki && !_onPlan && _due != null && _remind) {
      remindAt = await confirmReminderAt(context, _due!, _remindTime);
      if (remindAt == null || !mounted) return;
      await Notifier.requestPermission();
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);

    // একই নামে আগে কাস্টমার থাকলে নতুন করে না বানিয়ে সেটাই ব্যবহার
    final typed = _name.text.trim().toLowerCase();
    var id =
        _customer?.id ??
        _store.customers
            .where((c) => c.name.trim().toLowerCase() == typed)
            .firstOrNull
            ?.id;
    if (id == null && !_isBaki) {
      setState(() => _saving = false);
      return toast(context, 'তালিকা থেকে নাম বাছাই করুন');
    }
    id ??= await _store.addCustomer(name: _name.text, phones: [_phone.text]);

    await _store.addEntry(
      customerId: id,
      type: widget.type,
      amount: amount,
      date: _date,
      note: _note.text,
      dueDate: _due,
      reminderAt: remindAt,
      updateSchedule: _isBaki && !_onPlan,
    );
    if (remindAt != null) showReminderSet(messenger, remindAt);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _isBaki ? bakiColor : jomaColor;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: accent.withValues(alpha: .12),
                  child: Icon(
                    _isBaki
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isBaki ? _t.add : _t.reduce,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_customer != null)
                        Text(
                          _customer!.name,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'বন্ধ করুন',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // নতুন বাকি: নাম লিখলে আগের কাস্টমারের সাজেশন আসবে
            if (widget.customer == null) ...[
              _picked == null ? _nameField() : _pickedChip(),
              if (_picked == null && _isBaki) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'মোবাইল নম্বর (ঐচ্ছিক)',
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
              ],
              const SizedBox(height: 12),
            ],

            if (_onPlan) ...[_planHint(cs), const SizedBox(height: 12)],

            TextField(
              controller: _amount,
              autofocus: widget.customer != null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9০-৯.]')),
              ],
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
              decoration: InputDecoration(
                hintText: 'টাকার পরিমাণ',
                hintStyle: const TextStyle(fontSize: 20),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Text(
                    '৳',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(),
                suffixIcon: MicButton(
                  color: accent,
                  onText: (t) {
                    final v = parseSpokenAmount(t);
                    if (v == null) return;
                    setState(
                      () =>
                          _amount.text = v.toStringAsFixed(v % 1 == 0 ? 0 : 2),
                    );
                  },
                ),
              ),
            ),

            if (!_isBaki && (_customer?.hasDue ?? false)) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text('সব শোধ — ${taka(_customer!.balance)}'),
                  onPressed: () => setState(
                    () => _amount.text = _customer!.balance.toStringAsFixed(
                      _customer!.balance % 1 == 0 ? 0 : 2,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _isBaki ? _t.whatHint : 'নোট (ঐচ্ছিক)',
                prefixIcon: const Icon(Icons.notes_rounded),
                suffixIcon: MicButton(
                  onFinal: (t) => setState(() {
                    final cur = _note.text.trim();
                    _note.text = cur.isEmpty ? t : '$cur $t';
                  }),
                  onText: (_) {},
                ),
              ),
            ),

            if (_isBaki && !_onPlan) ...[
              const SizedBox(height: 18),
              DueReminderFields(
                label: _t.whenAsk,
                due: _due,
                remind: _remind,
                time: _remindTime,
                onDue: (d) => setState(() => _due = d),
                onRemind: (v) => setState(() => _remind = v),
                onTime: (t) => setState(() => _remindTime = t),
              ),
            ],

            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                DateUtils.isSameDay(_date, DateTime.now())
                    ? 'আজ, ${fmtDate(_date)}'
                    : fmtDate(_date),
              ),
              trailing: const Text('বদলান'),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_isBaki ? _t.addSave : _t.reduceSave),
            ),
          ],
        ),
      ),
    );
  }

  /// বাকিতে: কিস্তির বাইরে থাকবে। জমায়: এক চাপে চলতি কিস্তির টাকা।
  Widget _planHint(ColorScheme cs) {
    final c = _customer!;
    final s = c.planStatus!;
    final ask = s.behind > 0 ? s.behind : s.nextAmount;
    if (!_isBaki) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.event_repeat_rounded, size: 18),
          label: Text(
            s.behind > 0
                ? 'বকেয়া কিস্তি ${taka(ask)}'
                : 'এই কিস্তি ${taka(ask)}',
          ),
          onPressed: () => setState(
            () => _amount.text = ask == ask.roundToDouble()
                ? ask.toStringAsFixed(0)
                : ask.toStringAsFixed(2),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'কিস্তি চলছে (${planNextLine(c)})। এই ${_t.addTitle} কিস্তির '
              'বাইরে আলাদা থাকবে।',
              style: TextStyle(color: cs.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _select(Customer c) => setState(() {
    _picked = c;
    _name.text = c.name;
    final d = c.dueDate;
    if (d != null && daysUntil(d) >= 0) _due = d;
    final r = c.reminderAt;
    if (r != null) _remindTime = TimeOfDay.fromDateTime(r);
  });

  Widget _nameField() => Autocomplete<Customer>(
    displayStringForOption: (c) => c.name,
    optionsBuilder: (v) {
      final q = v.text.trim().toLowerCase();
      if (q.isEmpty) return const Iterable<Customer>.empty();
      return _store.customers
          .where(
            (c) =>
                c.name.toLowerCase().contains(q) ||
                c.phones.any((p) => p.contains(q)),
          )
          .take(5);
    },
    onSelected: _select,
    fieldViewBuilder: (context, controller, focus, onSubmit) {
      if (!identical(_acController, controller)) {
        _acController = controller;
        controller.addListener(() => _name.text = controller.text);
      }
      return TextField(
        controller: controller,
        focusNode: focus,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          hintText: _isBaki ? _t.partyHint : _t.reduceWho,
          prefixIcon: const Icon(Icons.person_outline_rounded),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // লেখা থাকলে এক চাপে মুছে ফেলার ✕
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, v, _) => v.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'মুছুন',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: controller.clear,
                      ),
              ),
              IconButton(
                tooltip: 'তালিকা থেকে বাছাই',
                icon: const Icon(Icons.people_alt_outlined),
                onPressed: () async {
                  final c = await pickCustomer(context);
                  if (c != null) _select(c);
                },
              ),
              MicButton(onFinal: (t) => controller.text = t, onText: (_) {}),
            ],
          ),
        ),
      );
    },
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: 260,
            maxWidth: MediaQuery.sizeOf(context).width - 40,
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final c in options)
                ListTile(
                  leading: const Icon(Icons.person_rounded),
                  title: Text(c.name),
                  subtitle: Text(
                    c.hasDue
                        ? '${_t.addTitle} ${taka(c.balance)}'
                        : (c.phone.isEmpty ? '${_t.addTitle} নেই' : c.phone),
                  ),
                  onTap: () => onSelected(c),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _pickedChip() => Card(
    child: ListTile(
      leading: const Icon(Icons.person_rounded),
      title: Text(_picked!.name),
      subtitle: Text(
        _picked!.hasDue
            ? 'আগের ${_t.addTitle} ${taka(_picked!.balance)}'
            : 'আগের ${_t.addTitle} নেই',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(() {
          _picked = null;
          _name.clear();
        }),
      ),
    ),
  );
}
