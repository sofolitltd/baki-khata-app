import 'package:flutter/material.dart';

import '../ledger.dart';
import '../models.dart';
import '../notifications.dart';
import '../photo.dart';
import '../store.dart';
import '../sync.dart';
import '../utils.dart';
import 'customer_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'entry_sheet.dart';
import 'stats_screen.dart';

/// উপরে খাতা-সুইচ, নিচে নেভিগেশন বার, আর সব ট্যাবে নতুন এন্ট্রির বাটন।
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    Notifier.openCustomer.addListener(_openFromNotification);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openFromNotification(),
    );
  }

  @override
  void dispose() {
    Notifier.openCustomer.removeListener(_openFromNotification);
    super.dispose();
  }

  void _openFromNotification() {
    final id = Notifier.openCustomer.value;
    if (id == null || !mounted) return;
    Notifier.openCustomer.value = null;
    if (Store.instance.byId(id) != null) openCustomer(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final store = Store.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        body: Column(
          children: [
            const SafeArea(bottom: false, child: LedgerSwitch()),
            Expanded(
              // উপরের প্যাডিং খাতা-সুইচ নিয়ে নেয়। বাইরের Scaffold কিবোর্ডের
              // জায়গাও আগেই ছেড়ে দেয়; ভেতরের ট্যাবের Scaffold আবার ছাড়লে
              // নিচের অংশ ফাঁকা হয়ে যায়।
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .removePadding(removeTop: true)
                    .removeViewInsets(removeBottom: true),
                child: IndexedStack(
                  index: _tab,
                  children: [
                    DashboardScreen(onSeeAll: () => setState(() => _tab = 1)),
                    const CustomersScreen(),
                    const StatsScreen(),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: _tab == 2
            ? null
            : FloatingActionButton.extended(
                onPressed: () async {
                  if (_tab == 1) {
                    final id = await showCustomerForm(context);
                    if (id != null && context.mounted) {
                      openCustomer(context, id);
                    }
                  } else {
                    showEntrySheet(context);
                  }
                },
                icon: Icon(
                  _tab == 1
                      ? Icons.person_add_alt_1_rounded
                      : Icons.add_rounded,
                ),
                label: Text(
                  _tab == 1 ? 'নতুন ${store.text.party}' : store.text.newEntry,
                ),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'হোম',
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_alt_outlined),
              selectedIcon: const Icon(Icons.people_alt_rounded),
              label: store.text.partyPlural,
            ),
            const NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'রিপোর্ট',
            ),
          ],
        ),
      ),
    );
  }
}

/// উপরের "পাওনা | দেনা" সুইচ — দুই খাতার মোটসহ। একবারে একটাই খাতা দেখা যায়।
class LedgerSwitch extends StatelessWidget {
  const LedgerSwitch({super.key});

  /// লোগো আর সুইচ একই উচ্চতার।
  static const _barHeight = 56.0;

  /// লোগোর কোণের বাঁকের সাথে মিল (৫৮/২৫৬ × ৫৬)।
  static const _radius = 13.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Store.instance,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final store = Store.instance;
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;

    Widget seg(Ledger l, IconData icon) {
      final selected = store.ledger == l;
      final accent = ledgerAccent(l, Theme.of(context).brightness);
      final fg = selected ? Colors.white : cs.onSurfaceVariant;
      return Expanded(
        child: GestureDetector(
          onTap: () => store.setLedger(l),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LedgerText.of(l).name,
                        style: TextStyle(color: fg, fontSize: 12, height: 1.2),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          taka(store.totalOf(l)),
                          style: TextStyle(
                            color: selected ? Colors.white : accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Tooltip(
            message: 'প্রোফাইল',
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: Image.asset(
                'assets/logo/logo_256.png',
                width: _barHeight,
                height: _barHeight,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: _barHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: light ? Colors.white : cs.surfaceContainer,
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .6),
                ),
              ),
              child: Row(
                children: [
                  seg(Ledger.pabo, Icons.call_received_rounded),
                  seg(Ledger.debo, Icons.call_made_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          const SyncButton(size: _barHeight),
        ],
      ),
    );
  }
}

/// কাস্টমার/পাওনাদারের পাতা খোলা — তার খাতাটাই সক্রিয় করে।
void openCustomer(BuildContext context, int id) {
  final store = Store.instance;
  final c = store.byId(id);
  if (c != null) store.setLedger(c.ledger);
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CustomerScreen(id: id)),
  );
}

/// কাস্টমারের নামের প্রথম অক্ষর দিয়ে গোল অ্যাভাটার — নাম অনুযায়ী রঙ বদলায়।
class NameAvatar extends StatelessWidget {
  const NameAvatar(this.customer, {super.key, this.radius = 22});
  final Customer customer;
  final double radius;

  static const _palette = [
    Color(0xFF0F766E),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFF4D7C0F),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[customer.name.hashCode.abs() % _palette.length];
    if (customer.photo.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: color.withValues(alpha: .14),
        backgroundImage: ResizeImage(
          photoProvider(customer.photo),
          width: (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: .14),
      child: Text(
        customer.name.characters.first.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: radius * .8,
        ),
      ),
    );
  }
}
