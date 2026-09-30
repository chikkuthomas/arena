import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

/// One person this user has blocked, with enough detail to list them on the
/// Blocked users screen without a Firestore lookup per row.
class BlockedUser {
  final String uid;
  final String name;
  final String? avatar;
  const BlockedUser({required this.uid, required this.name, this.avatar});

  Map<String, dynamic> toMap() =>
      {'uid': uid, 'name': name, if (avatar != null) 'avatar': avatar};

  factory BlockedUser.fromMap(Map<String, dynamic> m) => BlockedUser(
        uid: m['uid'] as String,
        name: (m['name'] as String?) ?? 'Someone',
        avatar: m['avatar'] as String?,
      );
}

/// Keeps the app civil: reporting bad messages and blocking users.
///
/// Reports are written to a `reports` collection so you can review them later
/// (and a future Cloud Function can auto-hide repeatedly-reported messages).
/// Blocks are stored ON THE PHONE — a blocked person's messages simply stop
/// showing for this user. Simple, instant, and works without extra rules.
class ModerationService {
  static const _blockedKey = 'blocked_user_ids';

  /// Display details for blocked people, keyed by uid. Stored next to
  /// [_blockedKey] rather than replacing it, so blocks made by older builds
  /// (which only saved the uid) keep working — they just show as "Someone"
  /// until the user blocks again.
  static const _blockedDetailsKey = 'blocked_user_details';
  // Resolved lazily rather than in a field initialiser: blocking is pure
  // on-device storage and must not require Firebase to be up just to
  // construct this service (it also makes the block logic unit-testable).
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The set of user ids this person has blocked.
  Future<Set<String>> loadBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_blockedKey) ?? <String>[]).toSet();
  }

  /// The blocked people with their names, for the Blocked users screen.
  /// Anyone blocked by an older build has no saved name, so they appear with a
  /// neutral placeholder rather than being hidden from the list.
  Future<List<BlockedUser>> loadBlockedDetailed() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_blockedKey) ?? <String>[]).toSet();
    Map<String, dynamic> details = {};
    try {
      final raw = prefs.getString(_blockedDetailsKey);
      if (raw != null && raw.isNotEmpty) {
        details = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {/* corrupt cache - fall back to names-less entries */}
    final list = ids.map((uid) {
      final d = details[uid];
      if (d is Map<String, dynamic>) return BlockedUser.fromMap(d);
      return BlockedUser(uid: uid, name: 'Someone');
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<Set<String>> blockUser(String uid, {String? name, String? avatar}) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_blockedKey) ?? <String>[]).toSet()
      ..add(uid);
    await prefs.setStringList(_blockedKey, set.toList());
    if (name != null && name.isNotEmpty) {
      await _saveDetails(prefs, uid,
          BlockedUser(uid: uid, name: name, avatar: avatar));
    }
    return set;
  }

  Future<void> _saveDetails(
      SharedPreferences prefs, String uid, BlockedUser? user) async {
    try {
      final raw = prefs.getString(_blockedDetailsKey);
      final map = (raw == null || raw.isEmpty)
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      if (user == null) {
        map.remove(uid);
      } else {
        map[uid] = user.toMap();
      }
      await prefs.setString(_blockedDetailsKey, jsonEncode(map));
    } catch (_) {/* the uid list is the source of truth - names are a bonus */}
  }

  Future<Set<String>> unblockUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_blockedKey) ?? <String>[]).toSet()
      ..remove(uid);
    await prefs.setStringList(_blockedKey, set.toList());
    await _saveDetails(prefs, uid, null);
    return set;
  }

  /// Files a report about a message.
  Future<void> reportMessage({
    required String roomId,
    required Message message,
    required String reporterId,
    String reason = '',
  }) async {
    await _db.collection('reports').add({
      'roomId': roomId,
      'messageId': message.id,
      'messageText': message.text,
      'offenderId': message.senderId,
      'offenderName': message.senderName,
      'reporterId': reporterId,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
