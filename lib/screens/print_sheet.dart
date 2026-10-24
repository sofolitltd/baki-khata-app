import 'package:flutter/material.dart';

import '../ledger.dart';
import '../print_slips.dart';
import '../store.dart';
import '../utils.dart';

/// বাকির তালিকা প্রিন্টের অপশন — কীভাবে সাজাবে, কোন ক্রমে।
Future<void> showPrintSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const _PrintSheet(),
);

class _PrintSheet extends StatefulWidget {
  const _PrintSheet();

  @override
  State<_PrintSheet> createState() => _PrintSheetState();
}

class _PrintSheetState extends State<_PrintSheet> {
  final Ledger _ledger = Store.instance.ledger;
  PrintGroup _group = PrintGroup.lastBaki;
  bool _oldestFirst = true;
  bool _busy = false;

  LedgerText get _t => LedgerText.of(_ledger);

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      await printDueSlips(
        ledger: _ledger,
        group: _group,
        oldestFirst: _oldestFirst,
      );
    } catch (_) {
      if (mounted) toast(context, 'প্রিন্ট করা যায়নি');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = printSections(_ledger, _group, _oldestFirst);
    final count = sections.fold(0, (n, s) => n + s.customers.length);
    final sum = sections.fold<double>(0, (n, s) => n + s.sum);
    final label = TextStyle(
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_t.addTitle}র তালিকা প্রিন্ট',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'প্রত্যেকের আলাদা স্লিপ — প্রিন্ট করে দাগ বরাবর কেটে নিন',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('কীভাবে সাজাবেন', style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (g, text) in [
                  (PrintGroup.lastBaki, 'শেষ ${_t.addTitle}র মাস'),
                  (PrintGroup.due, 'দেওয়ার তারিখের মাস'),
                  (PrintGroup.name, 'নাম অনুযায়ী'),
                ])
                  ChoiceChip(
                    label: Text(text),
                    selected: _group == g,
                    onSelected: (_) => setState(() => _group = g),
                  ),
              ],
            ),
            if (_group != PrintGroup.name) ...[
              const SizedBox(height: 16),
              Text('ক্রম', style: label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('পুরোনো আগে'),
                    selected: _oldestFirst,
                    onSelected: (_) => setState(() => _oldestFirst = true),
                  ),
                  ChoiceChip(
                    label: const Text('নতুন আগে'),
                    selected: !_oldestFirst,
                    onSelected: (_) => setState(() => _oldestFirst = false),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (sections.length > 1 || sections.firstOrNull?.title != null)
              for (final s in sections)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.title!)),
                      Text(
                        '${bn(s.customers.length)} জন • ${taka(s.sum)}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'মোট ${bn(count)} জন',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  taka(sum),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || count == 0 ? null : _print,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_rounded),
              label: Text(
                count == 0 ? 'কারও ${_t.addTitle} নেই' : 'প্রিন্ট / PDF',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
