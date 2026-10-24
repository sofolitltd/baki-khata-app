import 'package:flutter/material.dart';

import '../ledger.dart';
import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../voice.dart';

String contactLabel(ContactKind k) => switch (k) {
  ContactKind.call => 'কল',
  ContactKind.sms => 'মেসেজ',
  ContactKind.visit => 'সরাসরি তাগাদা',
  ContactKind.note => 'নোট',
};

IconData contactIcon(ContactKind k) => switch (k) {
  ContactKind.call => Icons.call_rounded,
  ContactKind.sms => Icons.sms_rounded,
  ContactKind.visit => Icons.storefront_rounded,
  ContactKind.note => Icons.sticky_note_2_rounded,
};

/// কী বলল — এক চাপে নোটে বসানোর জন্য।
const _quickTags = [
  'ফোন ধরেনি',
  'নম্বর বন্ধ',
  'পরে দেবে বলেছে',
  'আংশিক দেবে',
  'এই সপ্তাহে দেবে',
  'মাসের শুরুতে দেবে',
  'দেখা করতে বলেছে',
];

/// একাধিক নম্বর থাকলে কোনটায় — বেছে নিতে দেয়। বাতিল করলে null।
Future<String?> _pickPhone(BuildContext context, Customer c, IconData icon) {
  final phones = c.phones;
  if (phones.length <= 1) return Future.value(phones.firstOrNull);
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in phones)
            ListTile(
              leading: Icon(icon),
              title: Text(p),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ],
      ),
    ),
  );
}

/// কল করে ইতিহাসে লেখে; পরে "কী বলল" যোগ করার সুযোগ দেয়।
Future<void> callAndLog(BuildContext context, Customer c) async {
  final phone = await _pickPhone(context, c, Icons.call_rounded);
  if (phone == null || !context.mounted) return;
  await callPhone(context, phone);
  if (!context.mounted) return;
  await logContact(
    context,
    c,
    ContactKind.call,
    c.phones.length > 1 ? phone : '',
  );
}

/// বাকি থাকলে তাগাদার লেখা, না থাকলে ফাঁকা মেসেজ।
String dueSmsBody(Customer c) {
  if (c.ledger != Ledger.pabo || !c.hasDue) return '';
  final due = c.dueDate != null ? ' ${fmtDate(c.dueDate!)} তারিখের মধ্যে' : '';
  return 'আসসালামু আলাইকুম ${c.name}, দোকানে আপনার বাকি '
      '${taka(c.balance)}। অনুগ্রহ করে$due পরিশোধ করবেন। ধন্যবাদ।';
}

/// মেসেজ অ্যাপ খুলে ইতিহাসে লেখে।
Future<void> smsAndLog(BuildContext context, Customer c, [String? body]) async {
  final phone = await _pickPhone(context, c, Icons.sms_rounded);
  if (phone == null || !context.mounted) return;
  await sendSms(context, phone, body ?? dueSmsBody(c));
  if (!context.mounted) return;
  await logContact(
    context,
    c,
    ContactKind.sms,
    c.phones.length > 1 ? phone : '',
  );
}

/// ইতিহাসে লিখে নিচে "কী বলল লিখুন" দেখায়।
Future<void> logContact(
  BuildContext context,
  Customer c,
  ContactKind kind,
  String note,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final id = await Store.instance.addLog(c.id, kind, note: note);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        // কল থেকে ফিরে আসা পর্যন্ত যেন থাকে
        duration: const Duration(seconds: 12),
        content: Text('${contactLabel(kind)} ইতিহাসে লেখা হয়েছে'),
        action: SnackBarAction(
          label: 'কী বলল লিখুন',
          onPressed: () async {
            final logs = await Store.instance.logsOf(c.id);
            final log = logs.where((l) => l.id == id).firstOrNull;
            if (log != null && context.mounted) {
              showLogSheet(context, c, log: log);
            }
          },
        ),
      ),
    );
}

/// নতুন রেকর্ড বা আগেরটা এডিট/মুছুন।
Future<void> showLogSheet(
  BuildContext context,
  Customer c, {
  ContactLog? log,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _LogSheet(customer: c, log: log),
);

class _LogSheet extends StatefulWidget {
  const _LogSheet({required this.customer, this.log});
  final Customer customer;
  final ContactLog? log;

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  late ContactKind _kind = widget.log?.kind ?? ContactKind.visit;
  late final _note = TextEditingController(text: widget.log?.note);
  late DateTime _at = widget.log?.at ?? DateTime.now();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _toggleTag(String tag) {
    final parts = _note.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    parts.contains(tag) ? parts.remove(tag) : parts.add(tag);
    setState(() => _note.text = parts.join(', '));
  }

  Future<void> _pickAt() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    setState(() {
      final time = t ?? TimeOfDay.fromDateTime(_at);
      _at = DateTime(d.year, d.month, d.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final store = Store.instance;
    final log = widget.log;
    if (log == null) {
      await store.addLog(widget.customer.id, _kind, note: _note.text, at: _at);
    } else {
      await store.updateLog(log.id, kind: _kind, note: _note.text, at: _at);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await Store.instance.deleteLog(widget.log!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = TextStyle(
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
    );
    final picked = _note.text.split(',').map((s) => s.trim()).toSet();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.log == null ? 'যোগাযোগ লিখুন' : 'যোগাযোগ এডিট',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.customer.name,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('কীভাবে', style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in ContactKind.values)
                  ChoiceChip(
                    avatar: Icon(contactIcon(k), size: 18),
                    label: Text(contactLabel(k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('কী বলল', style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _quickTags)
                  FilterChip(
                    label: Text(tag),
                    selected: picked.contains(tag),
                    onSelected: (_) => _toggleTag(tag),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'নোট (ঐচ্ছিক)',
                prefixIcon: const Icon(Icons.notes_rounded),
                suffixIcon: MicButton(
                  onFinal: (t) => setState(
                    () => _note.text = [
                      _note.text.trim(),
                      t,
                    ].where((s) => s.isNotEmpty).join(', '),
                  ),
                  onText: (_) {},
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(fmtDateTime(_at)),
              trailing: const Text('বদলান'),
              onTap: _pickAt,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.log != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error),
                      ),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('মুছুন'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('সেভ করুন'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ইতিহাস বদলালে নিজে থেকে আবার পড়ে নেয়।
mixin _LogsLoader<T extends StatefulWidget> on State<T> {
  int get customerId;
  List<ContactLog>? logs;

  @override
  void initState() {
    super.initState();
    Store.instance.logsChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Store.instance.logsChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final l = await Store.instance.logsOf(customerId);
    if (mounted) setState(() => logs = l);
  }
}

/// কাস্টমার পাতায় এক লাইন — শেষ যোগাযোগ আর কতগুলো; চাপলে পুরো ইতিহাসের পাতা।
/// লেনদেনের তালিকা যেন নিচে চাপা না পড়ে, তাই এখানে পুরো তালিকা দেখানো হয় না।
class ContactHistoryTile extends StatefulWidget {
  const ContactHistoryTile({super.key, required this.customer});
  final Customer customer;

  @override
  State<ContactHistoryTile> createState() => _ContactHistoryTileState();
}

class _ContactHistoryTileState extends State<ContactHistoryTile>
    with _LogsLoader {
  @override
  int get customerId => widget.customer.id;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = logs?.firstOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ContactHistoryPage(customer: widget.customer),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: cs.primary.withValues(alpha: .1),
          child: Icon(Icons.history_rounded, color: cs.primary, size: 20),
        ),
        title: Text(
          logs == null || logs!.isEmpty
              ? 'যোগাযোগের ইতিহাস'
              : 'যোগাযোগের ইতিহাস (${bn(logs!.length)})',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          last == null
              ? 'এখনো কোনো কল বা তাগাদা নেই'
              : 'শেষ: ${contactLabel(last.kind)}'
                    '${last.note.isEmpty ? '' : ' — ${last.note}'}'
                    ' • ${agoLabel(last.at)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

/// একজন কাস্টমারের সব কল, মেসেজ, তাগাদা — নতুনটা উপরে।
class ContactHistoryPage extends StatefulWidget {
  const ContactHistoryPage({super.key, required this.customer});
  final Customer customer;

  @override
  State<ContactHistoryPage> createState() => _ContactHistoryPageState();
}

class _ContactHistoryPageState extends State<ContactHistoryPage>
    with _LogsLoader {
  @override
  int get customerId => widget.customer.id;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.customer;
    final list = logs;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('যোগাযোগের ইতিহাস'),
            Text(
              c.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: _compact,
                  onPressed: c.phones.isEmpty
                      ? null
                      : () => callAndLog(context, c),
                  child: const _OneLine(Icons.call_rounded, 'কল'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: _compact,
                  onPressed: c.phones.isEmpty
                      ? null
                      : () => smsAndLog(context, c),
                  child: const _OneLine(Icons.sms_rounded, 'মেসেজ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: _compact,
                  onPressed: () => showLogSheet(context, c),
                  child: const _OneLine(Icons.add_rounded, 'যোগ করুন'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: list == null
          ? const SizedBox.shrink()
          : list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 64,
                      color: cs.primary.withValues(alpha: .5),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'এখনো কোনো যোগাযোগ লেখা নেই',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'কল বা তাগাদা SMS দিলে নিজে থেকেই এখানে লেখা থাকবে। '
                      'সরাসরি তাগাদা দিলে "যোগ করুন" চেপে লিখে রাখুন।',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        _LogTile(
                          log: list[i],
                          onTap: () => showLogSheet(context, c, log: list[i]),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'এডিট বা মুছতে চাপুন',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}

/// পাশাপাশি তিনটা বাটনে কম প্যাডিং, যাতে লেখা জায়গা পায়।
final _compact = ButtonStyle(
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
);

/// আইকন আর লেখা এক লাইনে — জায়গা কম হলে ভাঙে না, একটু ছোট হয়ে যায়।
class _OneLine extends StatelessWidget {
  const _OneLine(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 6),
        Text(label, maxLines: 1, softWrap: false),
      ],
    ),
  );
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, required this.onTap});
  final ContactLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: cs.primary.withValues(alpha: .1),
        child: Icon(contactIcon(log.kind), color: cs.primary, size: 20),
      ),
      title: Text(
        log.note.isEmpty
            ? contactLabel(log.kind)
            : '${contactLabel(log.kind)} — ${log.note}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${fmtDateTime(log.at)} • ${agoLabel(log.at)}'),
    );
  }
}
