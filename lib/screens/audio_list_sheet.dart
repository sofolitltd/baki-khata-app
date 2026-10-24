import 'package:flutter/material.dart';

import '../ledger.dart';
import '../models.dart';
import '../theme.dart';
import '../utils.dart';
import '../voice.dart';
import 'shell.dart';

/// তালিকার একজন একজন করে নাম আর বাকির টাকা পড়ে শোনায় — প্লে, পজ,
/// আগের-পরের আর যেকোনো নামে চাপ দিয়ে সেখান থেকে শোনা।
Future<void> showAudioListSheet(
  BuildContext context,
  List<Customer> customers,
) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _AudioListSheet(customers: customers),
);

class _AudioListSheet extends StatefulWidget {
  const _AudioListSheet({required this.customers});
  final List<Customer> customers;

  @override
  State<_AudioListSheet> createState() => _AudioListSheetState();
}

class _AudioListSheetState extends State<_AudioListSheet> {
  static const _itemH = 64.0;

  final _scroll = ScrollController();
  int _i = 0;
  bool _playing = false;

  /// প্রতিবার চালানো/থামানোয় বাড়ে — পুরোনো লুপ বুঝে নিজে থেমে যায়।
  int _run = 0;

  /// শেষ পর্যন্ত শোনা হয়ে গেলে আবার চাপলে শুরু থেকে।
  bool _finished = false;

  List<Customer> get _list => widget.customers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _run++;
    Voice.instance.stop();
    _scroll.dispose();
    super.dispose();
  }

  String _speech(Customer c) {
    final t = LedgerText.of(c.ledger);
    final amount = c.hasDue
        ? '${takaWords(c.balance)} ${t.addTitle}'
        : 'কোনো ${t.addTitle} নেই';
    return '${banglaWords(_i + 1)}. ${c.name}, $amount।';
  }

  Future<void> _play() async {
    if (_list.isEmpty) return;
    if (_finished) _i = 0;
    _finished = false;
    final run = ++_run;
    setState(() => _playing = true);
    while (true) {
      _follow();
      final ok = await Voice.instance.speak(_speech(_list[_i]));
      if (!mounted || run != _run) return;
      if (!ok) {
        setState(() => _playing = false);
        toast(context, Voice.noVoiceMsg);
        return;
      }
      if (_i >= _list.length - 1) {
        setState(() {
          _playing = false;
          _finished = true;
        });
        return;
      }
      // দুজনের মাঝে একটু বিরতি
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted || run != _run) return;
      setState(() => _i++);
    }
  }

  void _pause() {
    _run++;
    Voice.instance.stop();
    setState(() => _playing = false);
  }

  void _jump(int i) {
    if (i < 0 || i >= _list.length) return;
    _run++;
    Voice.instance.stop();
    setState(() {
      _i = i;
      _finished = false;
    });
    _play();
  }

  /// এখন যার নাম পড়ছে সে যেন তালিকায় দেখা যায়।
  void _follow() {
    if (!_scroll.hasClients) return;
    final target = (_i * _itemH - _itemH * 2).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_list.isEmpty) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('তালিকায় কেউ নেই', textAlign: TextAlign.center),
        ),
      );
    }
    final c = _list[_i];
    final t = LedgerText.of(c.ledger);
    final total = _list.fold<double>(0, (s, c) => c.hasDue ? s + c.balance : s);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        children: [
          // এখন যাকে পড়ছে
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              children: [
                Text(
                  '${bn(_i + 1)} / ${bn(_list.length)} • মোট ${taka(total)}',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                NameAvatar(c, radius: 32),
                const SizedBox(height: 8),
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  c.hasDue ? taka(c.balance) : 'কোনো ${t.addTitle} নেই',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.hasDue ? bakiColor : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (_i + 1) / _list.length,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'আগের জন',
                      iconSize: 32,
                      onPressed: _i > 0 ? () => _jump(_i - 1) : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    const SizedBox(width: 16),
                    IconButton.filled(
                      tooltip: _playing ? 'থামান' : 'শুনুন',
                      iconSize: 40,
                      style: IconButton.styleFrom(
                        fixedSize: const Size(68, 68),
                      ),
                      onPressed: _playing ? _pause : _play,
                      icon: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      tooltip: 'পরের জন',
                      iconSize: 32,
                      onPressed: _i < _list.length - 1
                          ? () => _jump(_i + 1)
                          : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          // পুরো তালিকা — চাপলে সেখান থেকে শোনা
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.only(
                bottom: 12 + MediaQuery.paddingOf(context).bottom,
              ),
              itemExtent: _itemH,
              itemCount: _list.length,
              itemBuilder: (context, i) {
                final c = _list[i];
                final current = i == _i;
                return ListTile(
                  selected: current,
                  selectedTileColor: cs.primaryContainer.withValues(alpha: .5),
                  leading: SizedBox(
                    width: 28,
                    child: current && _playing
                        ? Icon(Icons.volume_up_rounded, color: cs.primary)
                        : Text(
                            bn(i + 1),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                  ),
                  title: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: current ? FontWeight.w700 : null,
                    ),
                  ),
                  trailing: Text(
                    c.hasDue ? taka(c.balance) : '—',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.hasDue ? bakiColor : cs.onSurfaceVariant,
                    ),
                  ),
                  onTap: () => _jump(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
