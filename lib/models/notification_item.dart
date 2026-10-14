import 'package:cloud_firestore/cloud_firestore.dart';

/// One entry in the in-app notification history screen. Personal items come
/// from `users/{uid}/notifications` (written by the Cloud Function alongside
/// each push); broadcast items come from the shared `broadcasts` collection.
enum NotificationType { roomMessage, reply, trending, broadcast }

NotificationType _typeFromString(String? s) {
  switch (s) {
    case 'reply':
      return NotificationType.reply;
    case 'trending':
      return NotificationType.trending;
    case 'broadcast':
      return NotificationType.broadcast;
    default:
      return NotificationType.roomMessage;
  }
}

class NotificationItem {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String? roomId;
  final DateTime? createdAt;

  /// Broadcasts have no per-user read state — deliberately simple, since every
  /// account already gets the same broadcast with no per-user fan-out.
  final bool read;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.roomId,
    this.createdAt,
    this.read = true,
  });

  factory NotificationItem.fromPersonalDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return NotificationItem(
      id: doc.id,
      type: _typeFromString(d['type']),
      title: d['title'] ?? '',
      body: d['body'] ?? '',
      roomId: d['roomId'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      read: d['read'] == true,
    );
  }

  factory NotificationItem.fromBroadcastDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return NotificationItem(
      id: doc.id,
      type: NotificationType.broadcast,
      title: d['title'] ?? '',
      body: d['body'] ?? '',
      roomId: d['roomId'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      read: true, // no per-user state; never contributes to the unread badge
    );
  }
}
