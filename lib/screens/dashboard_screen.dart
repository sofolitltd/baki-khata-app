import 'package:flutter/material.dart';

import '../ledger.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../voice.dart';
import 'customer_screen.dart';
import 'entry_sheet.dart';
import 'shell.dart';

/// প্রথম পাতা: মোট পাওনা, আজকের আদায়, কার কাছে যেতে হবে, সাম্প্রতিক লেনদেন।
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onSeeAll});
  final VoidCallback onSeeAll;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _store = Store.instance;
  double _collectedToday = 0;
  List<(Entry, String)> _recent = [];

  @override
  void initState() {
    super.initState();
    _store.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final t = await _store.totalsBetween(today(), null);
    final recent = await _store.recentEntries(8);
    if (!mounted) return;
    setState(() {
      _collectedToday = t.joma;
      _recent = recent;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final due = _store.customers.where((c) => c.hasDue).toList();
        final collectNow =
            due
                .where(
                  (c) =>
                      dueStatus(c.dueDate) == DueStatus.overdue ||
                      dueStatus(c.dueDate) == DueStatus.today,
                )
                .toList()
              ..sort((a, b) {
                final d = a.dueDate!.compareTo(b.dueDate!);
                return d != 0 ? d : b.balance.compareTo(a.balance);
              });
        final upcoming =
            due.where((c) => dueStatus(c.dueDate) == DueStatus.soon).toList()
              ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _store.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _CustomerSearch(store: _store),
                  const SizedBox(height: 12),
                  _HeroCard(
                    totalDue: _store.totalDue,
                    people: due.length,
                    collectedToday: _collectedToday,
                    overdue: due
                        .where((c) => dueStatus(c.dueDate) == DueStatus.overdue)
                        .fold<double>(0, (s, c) => s + c.balance),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _QuickButton(
                        icon: Icons.north_east_rounded,
                        label: _store.text.addShort,
                        color: bakiColor,
                        onTap: () => showEntrySheet(context),
                      ),
                      const SizedBox(width: 10),
                      _QuickButton(
                        icon: Icons.south_west_rounded,
                        label: _store.text.reduceShort,
                        color: jomaColor,
                        onTap: () =>
                            showEntrySheet(context, type: EntryType.joma),
                      ),
                      const SizedBox(width: 10),
                      _QuickButton(
                        icon: Icons.person_add_alt_1_rounded,
                        label: _store.text.party,
                        color: const Color(0xFF2563EB),
                        onTap: () async {
                          final id = await showCustomerForm(context);
                          if (id != null && context.mounted) {
                            openCustomer(context, id);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    title: _store.text.actToday,
                    trailing: collectNow.isEmpty
                        ? null
                        : taka(
                            collectNow.fold<double>(0, (s, c) => s + c.balance),
                          ),
                  ),
                  const SizedBox(height: 8),
                  if (collectNow.isEmpty)
                    _InfoCard(
                      icon: Icons.task_alt_rounded,
                      text: _store.customers.isEmpty
                          ? _store.text.emptyHint
                          : 'আজ কোনো তারিখ নেই',
                    )
                  else
                    _CustomerList(customers: collectNow.take(6).toList()),
                  if (collectNow.length > 6)
                    TextButton(
                      onPressed: widget.onSeeAll,
                      child: Text('আরও ${bn(collectNow.length - 6)} জন দেখুন'),
                    ),
                  if (upcoming.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle(title: 'সামনের ৩ দিনে'),
                    const SizedBox(height: 8),
                    _CustomerList(customers: upcoming.take(5).toList()),
                  ],
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle(title: 'সাম্প্রতিক লেনদেন'),
                    const SizedBox(height: 8),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < _recent.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                indent: 68,
                                color: cs.outlineVariant.withValues(alpha: .5),
                              ),
                            _RecentTile(
                              entry: _recent[i].$1,
                              name: _recent[i].$2,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.totalDue,
    required this.people,
    required this.collectedToday,
    required this.overdue,
  });
  final double totalDue, collectedToday, overdue;
  final int people;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: ledgerGradient(Store.instance.ledger),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: ledgerGradient(Store.instance.ledger).first
                .withValues(alpha: .28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                Store.instance.text.total,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Voice.instance.say(
                  context,
                  summarySpeech(
                    ledger: Store.instance.ledger,
                    total: totalDue,
                    people: people,
                    overdue: overdue,
                    collectedToday: collectedToday,
                  ),
                ),
                child: Tooltip(
                  message: 'শুনুন',
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  Store.instance.ledger == Ledger.pabo
                      ? '${bn(people)} জনের কাছে'
                      : '${bn(people)} জনকে দিতে হবে',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              taka(totalDue),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _HeroStat(
                  label: Store.instance.text.reducedToday,
                  value: taka(collectedToday),
                  icon: Icons.south_west_rounded,
                ),
                Container(width: 1, height: 34, color: Colors.white24),
                _HeroStat(
                  label: 'মেয়াদ পার',
                  value: taka(overdue),
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const Spacer(),
      if (trailing != null)
        Text(
          trailing!,
          style: const TextStyle(fontWeight: FontWeight.w700, color: bakiColor),
        ),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerList extends StatelessWidget {
  const _CustomerList({required this.customers});
  final List<Customer> customers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < customers.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 68,
                color: cs.outlineVariant.withValues(alpha: .5),
              ),
            _row(context, customers[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Customer c) => ListTile(
    onTap: () => openCustomer(context, c.id),
    contentPadding: const EdgeInsets.only(left: 14, right: 4),
    leading: NameAvatar(c, radius: 20),
    title: Text(
      c.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      dueLabel(c.dueDate!, c.ledger),
      style: TextStyle(color: dueColor(context, c.dueDate), fontSize: 13),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          taka(c.balance),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: bakiColor,
          ),
        ),
        IconButton(
          tooltip: 'কল',
          onPressed: c.phone.isEmpty ? null : () => callPhone(context, c.phone),
          icon: const Icon(Icons.call_rounded),
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    ),
  );
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.entry, required this.name});
  final Entry entry;
  final String name;

  @override
  Widget build(BuildContext context) {
    final isBaki = entry.type == EntryType.baki;
    final color = isBaki ? bakiColor : jomaColor;
    final when = DateUtils.isSameDay(entry.date, DateTime.now())
        ? 'আজ'
        : fmtShortDate(entry.date);
    return ListTile(
      onTap: () => openCustomer(context, entry.customerId),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isBaki ? Icons.north_east_rounded : Icons.south_west_rounded,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [when, if (entry.note.isNotEmpty) entry.note].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${isBaki ? '+' : '-'} ${taka(entry.amount)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// নাম বা মোবাইল লিখলে মিলে যাওয়া কাস্টমারের সাজেশন তালিকা; ট্যাপ করলে খাতা খোলে।
class _CustomerSearch extends StatelessWidget {
  const _CustomerSearch({required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => SearchAnchor.bar(
    barHintText: 'নাম বা মোবাইল দিয়ে খুঁজুন',
    barElevation: const WidgetStatePropertyAll(0),
    suggestionsBuilder: (context, controller) {
      final q = toEnDigits(controller.text.trim().toLowerCase());
      final list =
          store.customers
              .where(
                (c) =>
                    q.isEmpty ||
                    c.name.toLowerCase().contains(q) ||
                    c.phone.contains(q),
              )
              .toList()
            ..sort((a, b) {
              if (a.hasDue != b.hasDue) return a.hasDue ? -1 : 1;
              return a.name.compareTo(b.name);
            });
      return [
        for (final c in list)
          ListTile(
            leading: const Icon(Icons.person_rounded),
            title: Text(c.name),
            subtitle: Text(c.phone.isEmpty ? '—' : c.phone),
            trailing: c.hasDue
                ? Text(
                    taka(c.balance),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: bakiColor,
                    ),
                  )
                : null,
            onTap: () {
              controller.closeView('');
              openCustomer(context, c.id);
            },
          ),
      ];
    },
  );
}
