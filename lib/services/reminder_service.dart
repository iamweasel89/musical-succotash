import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';
import 'logger.dart';

// ── Reminder service (ВР4.2) ─────────────────────────────────────────────────
// Обёртка над flutter_local_notifications. Инициализация при старте,
// планирование/отмена напоминаний, запрос разрешений.

class ReminderService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _channelId = 'hex_canvas_reminders';
  static const String _channelName = 'Напоминания';
  static const String _channelDesc = 'Локальные напоминания hex-canvas';

  static Future<void> init() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      AppLogger.log('reminder', 'tz init failed: $e');
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: androidInit);

    await _plugin.initialize(init);

    // Создаём канал (Android 8+).
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );

    // Разрешения.
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    _initialized = true;
    AppLogger.log('reminder', 'service initialized');
  }

  static Future<void> schedule(Reminder r) async {
    if (!_initialized) await init();
    final when = tz.TZDateTime.from(r.scheduledAt, tz.local);
    try {
      await _plugin.zonedSchedule(
        r.nativeId,
        'Напоминание',
        r.text,
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: r.id,
      );
      AppLogger.log('reminder', 'scheduled id=${r.nativeId} at ${r.scheduledAt}');
    } catch (e) {
      AppLogger.log('reminder', 'schedule failed: $e');
      rethrow;
    }
  }

  static Future<void> cancel(Reminder r) async {
    if (!_initialized) await init();
    try {
      await _plugin.cancel(r.nativeId);
      AppLogger.log('reminder', 'cancelled id=${r.nativeId}');
    } catch (e) {
      AppLogger.log('reminder', 'cancel failed: $e');
    }
  }

  static Future<List<PendingNotificationRequest>> pending() async {
    if (!_initialized) await init();
    return _plugin.pendingNotificationRequests();
  }
}
