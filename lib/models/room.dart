import 'package:cloud_firestore/cloud_firestore.dart';

/// A debate room. Stored in Firestore at `rooms/{id}`.
///
/// For a PRIVATE room we store only a [passwordHash] (a scrambled version of
/// the password), never the real password. v1 checks the password on the phone
/// by hashing what the user typed and comparing — good enough to start, but
/// real security would move this check to the server (see SETUP notes).
class Room {
  final String id;
  final String name;
  final String topic; // the debate question, e.g. "Was the moon landing real?"
  final String category; // one of kCategories
  final bool isPrivate;
  final String? passwordHash;
  final String createdBy; // user id of the creator
  final String createdByName; // display name of the creator
  final bool isDaily; // true for the auto-generated "topic of the day" room
  final DateTime? createdAt;
  final DateTime? lastActivity; // updated on every message, used to sort rooms
  final int messageCount; // running total of messages, shown on the room card

  /// The room's messageCount the last time this user viewed it (from their
  /// joinedRooms record). Not stored on the room doc — used only to compute the
  /// unread badge in the Visited list. Defaults to messageCount so unseen rooms
  /// don't wrongly look "unread".
  final int lastSeenCount;

  Room({
    required this.id,
    required this.name,
    required this.topic,
    required this.category,
    required this.isPrivate,
    this.passwordHash,
    required this.createdBy,
    required this.createdByName,
    this.isDaily = false,
    this.createdAt,
    this.lastActivity,
    this.messageCount = 0,
    this.lastSeenCount = 0,
  });

  /// Builds a Room from a Firestore document snapshot.
  factory Room.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Room(
      id: doc.id,
      name: d['name'] ?? '',
      topic: d['topic'] ?? '',
      category: d['category'] ?? 'Other',
      isPrivate: d['isPrivate'] ?? false,
      passwordHash: d['passwordHash'],
      createdBy: d['createdBy'] ?? '',
      createdByName: d['createdByName'] ?? 'Someone',
      isDaily: d['isDaily'] ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      lastActivity: (d['lastActivity'] as Timestamp?)?.toDate(),
      messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// The data we write when creating a room. Server fills in the timestamps.
  Map<String, dynamic> toCreateMap() => {
        'name': name,
        'topic': topic,
        'category': category,
        'isPrivate': isPrivate,
        'passwordHash': passwordHash,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'isDaily': isDaily,
        'messageCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActivity': FieldValue.serverTimestamp(),
      };
}
