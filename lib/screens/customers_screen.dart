import 'package:flutter/material.dart';

import '../ledger.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../voice.dart';
import 'audio_list_sheet.dart';
import 'customer_screen.dart';
import 'installment.dart';
import 'print_sheet.dart';
import 'shell.dart';

enum _Filter { due, overdue, today, upcoming, plan, planBehind, paid, all }

/// তালিকার ক্রম — সাম্প্রতিক লেনদেন, না টাকার অঙ্ক।
enum _Sort { recent, high, low }

String _filterLabel(_Filter f) {
  final t = Store.instance.text;
  return switch (f) {
    _Filter.due => t.hasDue,
    _Filter.overdue => 'মেয়াদ পার',
    _Filter.today =>
      Store.instance.ledger == Ledger.pabo ? 'আজ দেবে' : 'আজ দিতে হবে',
    _Filter.upcoming => 'সামনে',
    _Filter.plan => 'কিস্তি চলছে',
    _Filter.planBehind => 'কিস্তি পিছিয়ে',
    _Filter.paid => 'পরিশোধিত',
    _Filter.all => 'সবাই',
  };
}

/// সব কাস্টমারের তালিকা — খোঁজা ও ফিল্টার।
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _store = Store.instance;
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Customer c, _Filter f) => switch (f) {
    _Filter.due => c.hasDue,
    _Filter.overdue => c.hasDue && dueStatus(c.dueDate) == DueStatus.overdue,
    _Filter.today => c.hasDue && dueStatus(c.dueDate) == DueStatus.today,
    _Filter.upcoming =>
      c.hasDue &&
          (dueStatus(c.dueDate) == DueStatus.soon ||
              dueStatus(c.dueDate) == DueStatus.later),
    _Filter.plan => c.onPlan,
    _Filter.planBehind => c.onPlan && c.planStatus!.behindCount > 0,
    _Filter.paid => !c.hasDue,
    _Filter.all => true,
  };

  List<Customer> _visible() {
    final q = toEnDigits(_search.text.trim().toLowerCase());
    final list = _store.customers.where((c) {
      if (q.isNotEmpty) {
        return c.name.toLowerCase().contains(q) ||
            c.phones.any((p) => p.contains(q));
      }
      return _matches(c, _filter);
    }).toList();

    int recent(Customer a, Customer b) =>
        (b.lastEntryAt ?? b.createdAt).compareTo(a.lastEntryAt ?? a.createdAt);
    list.sort(
      (a, b) => switch (_sort) {
        _Sort.recent => recent(a, b),
        _Sort.high => b.balance.compareTo(a.balance),
        _Sort.low => a.balance.compareTo(b.balance),
      },
    );
    return list;
  }

  Future<void> _pickFilter() async {
    final f = await showModalBottomSheet<_Filter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetLabel(ctx, 'সাজানো'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  // ক্রম বদলালে শিট খোলা থাকে, যাতে ফিল্টারও বাছাই করা যায়
                  child: SegmentedButton<_Sort>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _Sort.recent,
                        label: Text('সাম্প্রতিক'),
                      ),
                      ButtonSegment(
                        value: _Sort.high,
                        icon: Icon(Icons.south_rounded, size: 16),
                        label: Text('টাকা বেশি'),
                      ),
                      ButtonSegment(
                        value: _Sort.low,
                        icon: Icon(Icons.north_rounded, size: 16),
                        label: Text('টাকা কম'),
                      ),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (v) {
                      setState(() => _sort = v.first);
                      setSheet(() {});
                    },
                  ),
                ),
                _sheetLabel(ctx, 'ফিল্টার'),
                for (final f in _Filter.values)
                  ListTile(
                    leading: Icon(
                      f == _filter
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: f == _filter
                          ? Theme.of(ctx).colorScheme.primary
                          : null,
                    ),
                    title: Text(_filterLabel(f)),
                    trailing: Text(
                      bn(_store.customers.where((c) => _matches(c, f)).length),
                    ),
                    onTap: () => Navigator.pop(ctx, f),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (f != null) setState(() => _filter = f);
  }

  Widget _sheetLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final list = _visible();
        final sum = list.fold<double>(
          0,
          (s, c) => c.hasDue ? s + c.balance : s,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(_store.text.partyPlural),
            actions: [
              IconButton(
                tooltip: 'তালিকা শুনুন',
                icon: const Icon(Icons.volume_up_rounded),
                onPressed: list.isEmpty
                    ? null
                    : () => showAudioListSheet(context, list),
              ),
              IconButton(
                tooltip: '${_store.text.addTitle}র তালিকা প্রিন্ট',
                icon: const Icon(Icons.print_outlined),
                onPressed: () => showPrintSheet(context),
              ),
              IconButton(
                tooltip: 'নতুন ${_store.text.party}',
                icon: const Icon(Icons.person_add_alt_1_rounded),
                onPressed: () async {
                  final id = await showCustomerForm(context);
                  if (id != null && context.mounted) openCustomer(context, id);
                },
              ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'নাম বা মোবাইল দিয়ে খুঁজুন',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _search.text.isEmpty
                                ? MicButton(
                                    onText: (t) => setState(() {
                                      _search.text = t;
                                      _search.selection =
                                          TextSelection.collapsed(
                                            offset: t.length,
                                          );
                                    }),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () =>
                                        setState(() => _search.clear()),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Badge(
                        isLabelVisible:
                            _filter != _Filter.all || _sort != _Sort.recent,
                        smallSize: 10,
                        child: IconButton.filledTonal(
                          tooltip: 'ফিল্টার',
                          style: IconButton.styleFrom(
                            fixedSize: const Size(52, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _pickFilter,
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (list.isNotEmpty && sum > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        Text(
                          [
                            if (_search.text.isEmpty && _filter != _Filter.all)
                              _filterLabel(_filter),
                            if (_sort == _Sort.high) 'বেশি টাকা আগে',
                            if (_sort == _Sort.low) 'কম টাকা আগে',
                            '${bn(list.length)} জন',
                          ].join(' • '),
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'মোট ${taka(sum)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: bakiColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_store.loaded && list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    isSearch: _search.text.isNotEmpty,
                    noCustomers: _store.customers.isEmpty,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => CustomerCard(customer: list[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// কাস্টমারের কার্ড — তালিকা ও হোমের খোঁজে একই রকম।
class CustomerCard extends StatelessWidget {
  const CustomerCard({super.key, required this.customer, this.onTap});
  final Customer customer;

  /// না দিলে কাস্টমারের খাতা খোলে।
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final cs = Theme.of(context).colorScheme;

    final String subtitle;
    if (!c.hasDue) {
      subtitle = c.balance < 0
          ? LedgerText.of(c.ledger).advance
          : '${LedgerText.of(c.ledger).addTitle} নেই';
    } else if (c.onPlan) {
      final s = c.planStatus!;
      subtitle = s.behindCount > 0
          ? '${bn(s.behindCount)} কিস্তি পিছিয়ে • ${planNextLine(c)}'
          : planNextLine(c);
    } else if (c.dueDate != null) {
      subtitle = dueLabel(c.dueDate!, c.ledger);
    } else {
      subtitle = 'তারিখ ঠিক হয়নি';
    }
    final reminderOn =
        c.hasDue &&
        c.reminderAt != null &&
        c.reminderAt!.isAfter(DateTime.now());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => openCustomer(context, c.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              NameAvatar(c),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (c.hasDue && c.lastBakiAt != null)
                      Text(
                        lastBakiLabel(c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    Row(
                      children: [
                        if (reminderOn) ...[
                          Icon(
                            Icons.notifications_active_rounded,
                            size: 14,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: !c.hasDue
                                  ? cs.onSurfaceVariant
                                  : c.onPlan && c.planStatus!.behindCount > 0
                                  ? cs.error
                                  : dueColor(context, c.dueDate),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                c.hasDue
                    ? taka(c.balance)
                    : (c.balance < 0 ? taka(c.balance) : '—'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.hasDue ? bakiColor : jomaColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isSearch, required this.noCustomers});
  final bool isSearch, noCustomers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, title, sub) = isSearch
        ? (
            Icons.search_off_rounded,
            'কাউকে পাওয়া যায়নি',
            'অন্য নাম দিয়ে খুঁজুন',
          )
        : noCustomers
        ? (
            Icons.menu_book_rounded,
            'খাতা এখনো খালি',
            Store.instance.text.emptyHint,
          )
        : (
            Icons.check_circle_outline_rounded,
            'এখানে কেউ নেই',
            'এই তালিকায় কেউ নেই',
          );
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: cs.primary.withValues(alpha: .5)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
