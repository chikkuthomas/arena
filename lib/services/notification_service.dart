import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/daily_topics.dart';
import 'daily_override_service.dart';
import 'daily_topic_service.dart';

/// Local "topic of the day" notifications.
///
/// Each phone schedules its own daily alert (at 9 AM) showing that day's topic,
/// so the daily hook works with NO server. We pre-schedule the next two weeks
/// and refresh them every time the app opens.
///
/// IMPORTANT: every method swallows its own errors. Notifications are a nice
/// extra — a failure here must NEVER stop the app from working (this is exactly
/// what crashed PetBloom's release build).
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Called when the user taps a notification we showed while the app was in the
  /// foreground. The payload is the roomId to open. Wired up from main.dart.
  static void Function(String roomId)? onRoomTap;

  /// Sets up the plugin and asks for notification permission. Safe to call once
  /// at startup.
  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            onRoomTap?.call(payload);
          }
        },
      );
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      // Pre-create the channel used for pushed room messages, so notifications
      // that arrive while the app is closed use the right (high) importance.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'room_messages',
          'Room messages',
          description: 'New messages in rooms you follow',
          importance: Importance.high,
        ),
      );
      // Replies directed at you (someone replied to your message).
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'replies',
          'Replies to you',
          description: 'When someone replies to your message',
          importance: Importance.high,
        ),
      );
      // A debate you took part in is heating up (trending re-engagement).
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'trending',
          'Trending debates',
          description: 'When a debate you joined is heating up',
          importance: Importance.high,
        ),
      );
      // Admin broadcast — a fresh topic pushed to everyone at once.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'broadcast',
          'New debates',
          description: 'A brand-new debate topic for everyone',
          importance: Importance.high,
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      _ready = true;
    } catch (_) {
      // Notifications are optional — ignore any setup failure.
    }
  }

  /// Schedules a daily alert with each upcoming day's topic, for [days] ahead.
  /// Called on every app launch so the schedule stays fresh and accurate.
  static Future<void> scheduleDailyTopics({int days = 14, int hour = 9}) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final daily = DailyTopicService();
      final nowUtc = tz.TZDateTime.now(tz.UTC);
      // An admin can override a specific day's topic (and its push time). Fetch
      // it once; days without an override fall back to the hardcoded pool.
      final override = await DailyOverrideService.get();

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_topic',
          'Daily Topic',
          channelDescription: 'The Arena debate topic of the day',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

      for (var i = 0; i < days; i++) {
        final date = DateTime.now().add(Duration(days: i));
        var useHour = hour;
        var useMinute = 0;
        DailyTopic topic;
        if (override != null && override.appliesTo(date)) {
          topic = DailyTopic(override.topic, override.category);
          useHour = override.hour;
          useMinute = override.minute;
        } else {
          topic = daily.topicFor(date);
        }
        // Build the local push instant, then express it as a UTC instant so it
        // fires at the right wall-clock time without needing the zone name.
        final localWhen =
            DateTime(date.year, date.month, date.day, useHour, useMinute);
        final whenUtc = tz.TZDateTime.from(localWhen.toUtc(), tz.UTC);
        if (!whenUtc.isAfter(nowUtc)) continue; // skip if already past

        await _plugin.zonedSchedule(
          id: i, // a stable id per day-offset
          title: "Today's debate is live 🔥",
          body: topic.topic,
          scheduledDate: whenUtc,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // Never let a scheduling failure bubble up.
    }
  }

  /// Shows a notification for a pushed room message while the app is in the
  /// foreground. (When the app is in the background or closed, the system shows
  /// the push automatically.) [roomId] is the room to open if the user taps it.
  /// Best-effort — never throws.
  /// Removes a notification Android showed for a push (FCM posts it with the
  /// server-set tag and id 0). Used to drop your own messages' notifications.
  static Future<void> cancelPushed(String tag) async {
    try {
      await _plugin.cancel(id: 0, tag: tag);
    } catch (_) {/* best-effort */}
  }

  static Future<void> showRoomMessage(String title, String body,
          {String? roomId}) =>
      _showForeground('room_messages', 'Room messages',
          'New messages in rooms you follow', title, body, payload: roomId);

  /// Foreground notification for a reply directed at you.
  static Future<void> showReply(String title, String body, {String? roomId}) =>
      _showForeground('replies', 'Replies to you',
          'When someone replies to your message', title, body, payload: roomId);

  /// Foreground notification for a debate you joined that is now trending.
  static Future<void> showTrending(String title, String body,
          {String? roomId}) =>
      _showForeground('trending', 'Trending debates',
          'When a debate you joined is heating up', title, body,
          payload: roomId);

  /// Foreground notification for an admin broadcast of a brand-new topic.
  static Future<void> showBroadcast(String title, String body,
          {String? roomId}) =>
      _showForeground('broadcast', 'New debates',
          'A brand-new debate topic for everyone', title, body,
          payload: roomId);

  /// Shared foreground-notification helper. [payload] (a roomId) makes the
  /// notification open that room when tapped. Best-effort — never throws.
  static Future<void> _showForeground(String channelId, String channelName,
      String channelDesc, String title, String body,
      {String? payload}) async {
    if (!_ready) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      );
      // A rolling id so several messages don't overwrite one another.
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000 & 0x7fffffff;
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {
      // Optional feature — ignore any failure.
    }
  }
}
