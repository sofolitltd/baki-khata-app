import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import 'shell.dart';

/// নাম টাইপ না করে পুরো তালিকা থেকে কাস্টমার বাছাই। বাতিল করলে null।
Future<Customer?> pickCustomer(BuildContext context) =>
    showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CustomerPicker(),
    );

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker();

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final _store = Store.instance;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Customer> _visible() {
    final q = toEnDigits(_search.text.trim().toLowerCase());
    final list = _store.customers
        .where(
          (c) =>
              q.isEmpty ||
              c.name.toLowerCase().contains(q) ||
              c.phones.any((p) => p.contains(q)),
        )
        .toList();
    // সম্প্রতি লেনদেন হয়েছে এমনরা আগে
    list.sort(
      (a, b) => (b.lastEntryAt ?? b.createdAt).compareTo(
        a.lastEntryAt ?? a.createdAt,
      ),
    );
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _store.text;
    final list = _visible();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      minChildSize: .5,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '${t.partyPlural} খুঁজুন',
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        'কাউকে পাওয়া যায়নি',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final c = list[i];
                        return ListTile(
                          leading: NameAvatar(c, radius: 20),
                          title: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: c.phone.isEmpty ? null : Text(c.phone),
                          trailing: Text(
                            c.hasDue ? taka(c.balance) : '—',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: c.hasDue ? bakiColor : cs.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
