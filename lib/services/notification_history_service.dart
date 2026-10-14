import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_item.dart';

/// Reads the in-app notification history: personal pushes (room message,
/// reply, trending) plus admin broadcasts, merged into one timeline.
class NotificationHistoryService {
  final _db = FirebaseFirestore.instance;

  static const _personalLimit = 100;
  static const _broadcastLimit = 50;

  /// Merges the two source streams into one list, newest first. Rebuilds the
  /// merge whenever either side emits — simplest correct approach at this
  /// volume (a couple hundred docs, not a firehose).
  Stream<List<NotificationItem>> watchAll(String uid) {
    final personal = _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(_personalLimit)
        .snapshots();
    final broadcasts = _db
        .collection('broadcasts')
        .orderBy('createdAt', descending: true)
        .limit(_broadcastLimit)
        .snapshots();

    final controller = StreamController<List<NotificationItem>>.broadcast();
    List<NotificationItem>? lastPersonal;
    List<NotificationItem>? lastBroadcasts;

    void emit() {
      if (lastPersonal == null || lastBroadcasts == null) return;
      final merged = [...lastPersonal!, ...lastBroadcasts!]
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
      controller.add(merged);
    }

    final subs = <StreamSubscription>[
      personal.listen((snap) {
        lastPersonal =
            snap.docs.map(NotificationItem.fromPersonalDoc).toList();
        emit();
      }, onError: controller.addError),
      broadcasts.listen((snap) {
        lastBroadcasts =
            snap.docs.map(NotificationItem.fromBroadcastDoc).toList();
        emit();
      }, onError: controller.addError),
    ];

    controller.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };
    return controller.stream;
  }

  /// Unread count for the bell badge — personal items only (broadcasts have
  /// no per-user read state, see [NotificationItem]).
  Stream<int> watchUnreadCount(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Future<void> markRead(String uid, NotificationItem item) async {
    if (item.type == NotificationType.broadcast) return;
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .doc(item.id)
          .update({'read': true});
    } catch (_) {/* best-effort */}
  }

  /// Marks every currently-unread personal notification as read — called when
  /// the history screen opens, so the badge clears once they've seen the list.
  Future<void> markAllRead(String uid) async {
    try {
      final unread = await _db
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();
      final batch = _db.batch();
      for (final d in unread.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {/* best-effort */}
  }
}
