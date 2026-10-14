import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/daily_topics.dart';
import '../models/room.dart';

/// Picks the "topic of the day" and manages the shared daily room.
///
/// The topic is chosen purely from the calendar date, so EVERY phone shows the
/// same topic on the same day with no server needed. The daily room uses a
/// date-based id (e.g. `daily_2026-6-28`) so everyone lands in the same room.
class DailyTopicService {
  final _db = FirebaseFirestore.instance;

  /// Today's date with the time stripped off.
  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The topic for a given day, chosen deterministically from the date.
  ///
  /// Uses DateTime.utc so the day number depends ONLY on the calendar date,
  /// never on the device's timezone. With local DateTime, midnight converts to
  /// a different UTC instant per zone — in IST (+5:30) local midnight on the
  /// 14th is 18:30 UTC on the 13th — so two devices in different zones derived
  /// DIFFERENT topics for the same calendar day, and (because roomIdFor keys
  /// off the local date) could each create their own room for the same debate:
  /// two "Topic of the Day" rooms with identical text, one of them dead.
  DailyTopic topicFor(DateTime date) {
    final dayNumber =
        DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
            Duration.millisecondsPerDay;
    final index = dayNumber % kDailyTopics.length;
    return kDailyTopics[index];
  }

  DailyTopic todayTopic() => topicFor(_today());

  String roomIdFor(DateTime date) =>
      'daily_${date.year}-${date.month}-${date.day}';

  String todayRoomId() => roomIdFor(_today());

  /// Returns today's shared daily room, creating it on first access. [uid] /
  /// [name] are the current user (so it satisfies the "create as yourself"
  /// rule); the room still shows "Arena" as the author.
  Future<Room> ensureTodayRoom({
    required String uid,
  }) async {
    final id = todayRoomId();
    final ref = _db.collection('rooms').doc(id);
    final existing = await ref.get();
    if (!existing.exists) {
      final t = todayTopic();
      await ref.set({
        'name': 'Topic of the Day',
        'topic': t.topic,
        'category': t.category,
        'isPrivate': false,
        'passwordHash': null,
        'createdBy': uid,
        'createdByName': 'Arena',
        'isDaily': true,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActivity': FieldValue.serverTimestamp(),
      });
    }
    final snap = await ref.get();
    return Room.fromDoc(snap);
  }
}
