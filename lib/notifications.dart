import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'ledger.dart';
import 'models.dart';
import 'utils.dart';

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// নোটিফিকেশনে ট্যাপ করলে কোন কাস্টমার খুলবে।
  static final ValueNotifier<int?> openCustomer = ValueNotifier(null);

  static Future<void> init() async {
    if (kIsWeb) return; // ওয়েবে শিডিউলড নোটিফিকেশন নেই
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) =>
          openCustomer.value = int.tryParse(r.payload ?? ''),
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      openCustomer.value = int.tryParse(
        launch!.notificationResponse?.payload ?? '',
      );
    }
  }

  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  static Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: id);
  }

  static Future<void> schedule(Customer c) async {
    if (kIsWeb) return;
    await cancel(c.id);
    final at = c.reminderAt;
    if (at == null || !c.hasDue || at.isBefore(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id: c.id,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      title: c.ledger == Ledger.pabo
          ? 'বাকি আদায়: ${c.name}'
          : 'দেনা পরিশোধ: ${c.name}',
      body:
          '${taka(c.balance)} ${c.ledger == Ledger.pabo ? 'পাওনা' : 'দিতে হবে'}'
          '${c.dueDate != null ? ' • ${dueLabel(c.dueDate!, c.ledger)}' : ''}',
      payload: '${c.id}',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'due_reminder',
          'বাকির রিমাইন্ডার',
          channelDescription: 'বাকি আদায়ের তারিখে মনে করিয়ে দেয়',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static const _summaryBaseId = 900000;
  static const summaryHour = 9;

  /// আগামী ৭ দিনের প্রতিদিন সকাল ৯টায় সারাংশ: সেদিন কার কাছ থেকে কত আদায়
  /// করতে হবে আর কতজনের মেয়াদ পার হয়েছে। ডাটা বদলালেই নতুন করে হিসাব হয়।
  static Future<void> scheduleDailySummaries(List<Customer> customers) async {
    if (kIsWeb) return;
    final now = DateTime.now();
    for (var i = 0; i < 8; i++) {
      await cancel(_summaryBaseId + i);
      final day = DateTime(now.year, now.month, now.day + i);
      final at = DateTime(day.year, day.month, day.day, summaryHour);
      if (at.isBefore(now)) continue;

      // দিনের দিন বা মেয়াদ পার হওয়া — খাতা অনুযায়ী আলাদা
      List<Customer> dueBy(Ledger l) => customers
          .where(
            (c) =>
                c.ledger == l &&
                c.hasDue &&
                c.dueDate != null &&
                !DateUtils.dateOnly(c.dueDate!).isAfter(day),
          )
          .toList();
      final pabo = dueBy(Ledger.pabo);
      final debo = dueBy(Ledger.debo);
      if (pabo.isEmpty && debo.isEmpty) continue;

      double sum(List<Customer> l) => l.fold(0, (s, c) => s + c.balance);
      String names(List<Customer> l) => l.map((c) => c.name).take(3).join(', ');
      final lines = <String>[
        if (pabo.isNotEmpty)
          'আদায়: ${bn(pabo.length)} জনের কাছে ${taka(sum(pabo))} (${names(pabo)})',
        if (debo.isNotEmpty)
          'পরিশোধ: ${bn(debo.length)} জনকে ${taka(sum(debo))} (${names(debo)})',
      ];
      final body = lines.join('\n');
      final title = pabo.isNotEmpty
          ? 'আজ আদায় করুন: ${taka(sum(pabo))}'
          : 'আজ পরিশোধ করুন: ${taka(sum(debo))}';

      await _plugin.zonedSchedule(
        id: _summaryBaseId + i,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        title: title,
        body: body,
        payload: 'summary',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_summary',
            'দৈনিক সারাংশ',
            channelDescription:
                'প্রতিদিন সকালে কার কাছ থেকে কত পাবেন আর কাকে কত দেবেন',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
