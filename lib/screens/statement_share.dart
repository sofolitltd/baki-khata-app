import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ledger.dart';
import '../models.dart';
import '../statement_image.dart';
import '../store.dart';
import '../utils.dart';

/// কাস্টমারের হিসাবের ছবি বানিয়ে আগে দেখায়, তারপর শেয়ার (WhatsApp ইত্যাদি)।
Future<void> shareStatement(BuildContext context, Customer c) async {
  final entries = await Store.instance.entriesOf(c.id);
  final png = await renderStatement(c, entries);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _StatementPreview(customer: c, png: png),
    ),
  );
}

class _StatementPreview extends StatefulWidget {
  const _StatementPreview({required this.customer, required this.png});
  final Customer customer;
  final Uint8List png;

  @override
  State<_StatementPreview> createState() => _StatementPreviewState();
}

class _StatementPreviewState extends State<_StatementPreview> {
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final c = widget.customer;
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'hisab_${c.id}.png'));
      await file.writeAsBytes(widget.png);
      final t = LedgerText.of(c.ledger);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: c.hasDue
              ? '${c.name}, আপনার ${t.addTitle} ${taka(c.balance)}। বিস্তারিত ছবিতে।'
              : '${c.name}, আপনার হিসাবের বিবরণ।',
        ),
      );
    } catch (_) {
      if (mounted) toast(context, 'শেয়ার করা যায়নি');
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('হিসাবের ছবি')),
      body: InteractiveViewer(
        maxScale: 4,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(widget.png),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _sharing ? null : _share,
            icon: const Icon(Icons.share_rounded),
            label: const Text('শেয়ার করুন'),
          ),
        ),
      ),
    );
  }
}
