import 'package:flutter/material.dart';

import '../utils.dart';

/// রিমাইন্ডারের সময় বাছাইয়ের ঘড়ি। বাতিল করলে null।
Future<TimeOfDay?> pickReminderTime(BuildContext context, TimeOfDay initial) =>
    showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'রিমাইন্ডারের সময়',
    );

/// তারিখ + সময় মিলিয়ে রিমাইন্ডার। সময় পার হয়ে গেলে এক ঘণ্টা পরে।
DateTime reminderAt(DateTime due, TimeOfDay time) {
  final at = DateTime(due.year, due.month, due.day, time.hour, time.minute);
  return at.isBefore(DateTime.now())
      ? DateTime.now().add(const Duration(hours: 1))
      : at;
}

/// কবে দেবে / ফেরত দেব — তারিখ, রিমাইন্ডার চালু-বন্ধ আর তার সময়।
class DueReminderFields extends StatelessWidget {
  const DueReminderFields({
    super.key,
    required this.label,
    required this.due,
    required this.remind,
    required this.time,
    required this.onDue,
    required this.onRemind,
    required this.onTime,
  });

  final String label;
  final DateTime? due;
  final bool remind;
  final TimeOfDay time;
  final ValueChanged<DateTime?> onDue;
  final ValueChanged<bool> onRemind;
  final ValueChanged<TimeOfDay> onTime;

  static const _options = [
    ('আজ', 0),
    ('৩ দিন', 3),
    ('৭ দিন', 7),
    ('১৫ দিন', 15),
    ('১ মাস', 30),
  ];

  bool get _custom =>
      due != null && !_options.any((o) => daysUntil(due!) == o.$2);

  Future<void> _pickDate(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: due ?? today(),
      firstDate: today(),
      lastDate: today().add(const Duration(days: 730)),
      helpText: label,
    );
    if (d == null || !context.mounted) return;
    onDue(d);
    // তারিখ বাছাইয়ের পরই রিমাইন্ডারের সময় — বাতিল করলে আগের সময় থাকে
    await _pickTime(context);
  }

  Future<void> _pickTime(BuildContext context) async {
    final t = await pickReminderTime(context, time);
    if (t != null) onTime(t);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (text, days) in _options)
              ChoiceChip(
                label: Text(text),
                selected: due != null && daysUntil(due!) == days,
                onSelected: (_) => onDue(today().add(Duration(days: days))),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(_custom ? fmtShortDate(due!) : 'তারিখ'),
              selected: _custom,
              onSelected: (_) => _pickDate(context),
            ),
            ChoiceChip(
              label: const Text('ঠিক নেই'),
              selected: due == null,
              onSelected: (_) => onDue(null),
            ),
          ],
        ),
        if (due != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: remind,
            onChanged: onRemind,
            secondary: Icon(
              Icons.notifications_active_outlined,
              color: cs.primary,
            ),
            title: const Text('রিমাইন্ডার দিন'),
            subtitle: Text(fmtDate(due!)),
          ),
        if (due != null && remind)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.schedule_rounded, color: cs.primary),
            title: Text(fmtTime(time.hour, time.minute)),
            subtitle: const Text('রিমাইন্ডারের সময়'),
            trailing: const Text('বদলান'),
            onTap: () => _pickTime(context),
          ),
      ],
    );
  }
}
