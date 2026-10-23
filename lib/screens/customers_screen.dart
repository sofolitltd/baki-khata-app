import 'package:flutter/material.dart';

import '../ledger.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import 'customer_screen.dart';
import 'shell.dart';

enum _Filter { due, overdue, today, upcoming, paid, all }

String _filterLabel(_Filter f) {
  final t = Store.instance.text;
  return switch (f) {
    _Filter.due => t.hasDue,
    _Filter.overdue => 'মেয়াদ পার',
    _Filter.today =>
      Store.instance.ledger == Ledger.pabo ? 'আজ দেবে' : 'আজ দিতে হবে',
    _Filter.upcoming => 'সামনে',
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
  _Filter _filter = _Filter.due;

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
    _Filter.paid => !c.hasDue,
    _Filter.all => true,
  };

  List<Customer> _visible() {
    final q = toEnDigits(_search.text.trim().toLowerCase());
    final list = _store.customers.where((c) {
      if (q.isNotEmpty) {
        return c.name.toLowerCase().contains(q) || c.phone.contains(q);
      }
      return _matches(c, _filter);
    }).toList();

    // বাকি আছে এমনরা আগে; তাদের মধ্যে যার তারিখ আগে, তারপর বেশি বাকি
    int rank(Customer c) => c.dueDate == null
        ? 1 << 30
        : DateUtils.dateOnly(c.dueDate!).millisecondsSinceEpoch ~/ 86400000;
    list.sort((a, b) {
      if (a.hasDue != b.hasDue) return a.hasDue ? -1 : 1;
      if (!a.hasDue) {
        return (b.lastEntryAt ?? b.createdAt).compareTo(
          a.lastEntryAt ?? a.createdAt,
        );
      }
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : b.balance.compareTo(a.balance);
    });
    return list;
  }

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
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'নাম বা মোবাইল দিয়ে খুঁজুন',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _search.clear()),
                            ),
                    ),
                  ),
                ),
              ),
              if (_search.text.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final f in _Filter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                '${_filterLabel(f)} ${bn(_store.customers.where((c) => _matches(c, f)).length)}',
                              ),
                              selected: _filter == f,
                              onSelected: (_) => setState(() => _filter = f),
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
                          '${bn(list.length)} জন',
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
                    itemBuilder: (_, i) => _CustomerTile(customer: list[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final cs = Theme.of(context).colorScheme;

    final String subtitle;
    if (!c.hasDue) {
      subtitle = c.balance < 0
          ? LedgerText.of(c.ledger).advance
          : '${LedgerText.of(c.ledger).addTitle} নেই';
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
        onTap: () => openCustomer(context, c.id),
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
                              color: c.hasDue
                                  ? dueColor(context, c.dueDate)
                                  : cs.onSurfaceVariant,
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
