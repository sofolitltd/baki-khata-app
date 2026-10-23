import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ledger.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import 'customer_screen.dart';

enum _Period { today, week, month, all }

const _periodLabels = {
  _Period.today: 'আজ',
  _Period.week: '৭ দিন',
  _Period.month: 'এই মাস',
  _Period.all: 'সব সময়',
};

typedef _Totals = ({double baki, double joma, int count});
typedef _Month = ({DateTime month, double baki, double joma});

/// আদায়ের হিসাব ও পরিসংখ্যান।
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _store = Store.instance;
  _Period _period = _Period.month;
  _Totals? _totals;
  _Totals? _allTime;
  List<_Month>? _months;

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

  (DateTime?, DateTime?) _range() {
    final now = DateTime.now();
    final t = today();
    return switch (_period) {
      _Period.today => (t, null),
      _Period.week => (t.subtract(const Duration(days: 6)), null),
      _Period.month => (DateTime(now.year, now.month), null),
      _Period.all => (null, null),
    };
  }

  Future<void> _load() async {
    final (from, to) = _range();
    final results = await Future.wait([
      _store.totalsBetween(from, to),
      _store.totalsBetween(null, null),
    ]);
    final months = await _store.monthly(6);
    if (!mounted) return;
    setState(() {
      _totals = results[0];
      _allTime = results[1];
      _months = months;
    });
  }

  void _open(int id) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CustomerScreen(id: id)),
  );

  @override
  Widget build(BuildContext context) {
    final due = _store.customers.where((c) => c.hasDue).toList();

    // আগে ধরতে হবে: মেয়াদ পার ও আজকের — বেশি দিন পার হওয়া আগে
    final collectNow =
        due
            .where(
              (c) =>
                  c.dueDate != null &&
                  (dueStatus(c.dueDate) == DueStatus.overdue ||
                      dueStatus(c.dueDate) == DueStatus.today),
            )
            .toList()
          ..sort((a, b) {
            final d = a.dueDate!.compareTo(b.dueDate!);
            return d != 0 ? d : b.balance.compareTo(a.balance);
          });
    final top = [...due]..sort((a, b) => b.balance.compareTo(a.balance));

    return Scaffold(
      appBar: AppBar(title: Text('${_store.text.name}র হিসাব')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in _Period.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_periodLabels[p]!),
                        selected: _period == p,
                        onSelected: (_) {
                          setState(() => _period = p);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MetricCard(
                  label: _store.text.reduced,
                  value: _totals == null ? '—' : taka(_totals!.joma),
                  icon: Icons.south_west_rounded,
                  color: jomaColor,
                ),
                const SizedBox(width: 10),
                _MetricCard(
                  label: _store.text.added,
                  value: _totals == null ? '—' : taka(_totals!.baki),
                  icon: Icons.north_east_rounded,
                  color: bakiColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _RecoveryCard(totalDue: _store.totalDue, allTime: _allTime),
            const SizedBox(height: 12),
            _AgingCard(due: due),
            const SizedBox(height: 12),
            if (collectNow.isNotEmpty) ...[
              _Section(
                title: _store.ledger == Ledger.pabo
                    ? 'আগে এদের কাছ থেকে আদায় করুন'
                    : 'আগে এদের পরিশোধ করুন',
                subtitle:
                    '${bn(collectNow.length)} জন • ${taka(collectNow.fold<double>(0, (s, c) => s + c.balance))}',
                icon: Icons.priority_high_rounded,
                iconColor: bakiColor,
                children: [
                  for (final c in collectNow.take(10))
                    _CustomerRow(customer: c, onTap: () => _open(c.id)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (_months != null) _MonthlyChart(months: _months!),
            const SizedBox(height: 12),
            if (top.isNotEmpty)
              _Section(
                title: _store.text.biggest,
                icon: Icons.leaderboard_rounded,
                children: [
                  for (final c in top.take(5))
                    _CustomerRow(customer: c, onTap: () => _open(c.id)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: .12),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.totalDue, required this.allTime});
  final double totalDue;
  final _Totals? allTime;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final given = allTime?.baki ?? 0;
    final rate = given <= 0 ? 0.0 : (allTime!.joma / given).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'এখন ${Store.instance.text.total}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        taka(totalDue),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: bakiColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Store.instance.text.rate,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    Text(
                      '${bn((rate * 100).round())}%',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 10,
                backgroundColor: bakiColor.withValues(alpha: .15),
                color: jomaColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'এ পর্যন্ত ${Store.instance.text.added} ${taka(given)}, ${Store.instance.text.reduced} ${taka(allTime?.joma ?? 0)}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// পাওনা টাকা কোন অবস্থায় আছে — মেয়াদ পার, আজ, সামনে, তারিখ নেই।
class _AgingCard extends StatelessWidget {
  const _AgingCard({required this.due});
  final List<Customer> due;

  @override
  Widget build(BuildContext context) {
    final buckets = <(String, Color, bool Function(Customer))>[
      (
        'মেয়াদ পার',
        bakiColor,
        (c) => dueStatus(c.dueDate) == DueStatus.overdue,
      ),
      (
        Store.instance.ledger == Ledger.pabo ? 'আজ দেবে' : 'আজ দিতে হবে',
        const Color(0xFFD97706),
        (c) => dueStatus(c.dueDate) == DueStatus.today,
      ),
      (
        '৭ দিনের মধ্যে',
        const Color(0xFF2563EB),
        (c) =>
            c.dueDate != null &&
            daysUntil(c.dueDate!) >= 1 &&
            daysUntil(c.dueDate!) <= 7,
      ),
      (
        '৭ দিনের পরে',
        jomaColor,
        (c) => c.dueDate != null && daysUntil(c.dueDate!) > 7,
      ),
      ('তারিখ ঠিক হয়নি', Colors.grey, (c) => c.dueDate == null),
    ];
    final total = due.fold<double>(0, (s, c) => s + c.balance);
    final rows = [
      for (final (label, color, test) in buckets)
        (
          label,
          color,
          due.where(test).fold<double>(0, (s, c) => s + c.balance),
          due.where(test).length,
        ),
    ];

    return _Section(
      title: '${Store.instance.text.name}র অবস্থা',
      icon: Icons.donut_large_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: total <= 0
                  ? ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (_, color, amount, _) in rows)
                          if (amount > 0)
                            Expanded(
                              flex: math.max(
                                1,
                                (amount / total * 1000).round(),
                              ),
                              child: Container(color: color),
                            ),
                      ],
                    ),
            ),
          ),
        ),
        for (final (label, color, amount, count) in rows)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 6, backgroundColor: color),
            minLeadingWidth: 12,
            title: Text(label, style: const TextStyle(fontSize: 15)),
            subtitle: Text('${bn(count)} জন'),
            trailing: Text(
              taka(amount),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: amount > 0 ? color : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.months});
  final List<_Month> months;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = months.fold<double>(
      0,
      (m, e) => math.max(m, math.max(e.baki, e.joma)),
    );
    const barMax = 120.0;

    Widget bar(double v, Color color) => Container(
      width: 12,
      height: maxV <= 0 ? 2 : math.max(2, v / maxV * barMax),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );

    return _Section(
      title: 'গত ৬ মাস',
      icon: Icons.bar_chart_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              _legend(bakiColor, Store.instance.text.added),
              const SizedBox(width: 16),
              _legend(jomaColor, Store.instance.text.reduceTitle),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in months)
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bar(m.baki, bakiColor),
                          const SizedBox(width: 3),
                          bar(m.joma, jomaColor),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('MMM', 'bn').format(m.month),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legend(Color c, String label) => Row(
    children: [
      CircleAvatar(radius: 5, backgroundColor: c),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 13)),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.iconColor,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(icon, color: iconColor ?? cs.primary),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: subtitle == null ? null : Text(subtitle!),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onTap});
  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return ListTile(
      onTap: onTap,
      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        c.dueDate == null ? 'তারিখ ঠিক হয়নি' : dueLabel(c.dueDate!, c.ledger),
        style: TextStyle(color: dueColor(context, c.dueDate)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            taka(c.balance),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: bakiColor,
            ),
          ),
          if (c.phone.isNotEmpty)
            IconButton(
              tooltip: 'কল',
              icon: Icon(
                Icons.call_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => callPhone(context, c.phone),
            ),
        ],
      ),
    );
  }
}
