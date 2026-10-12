import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';

import '../models/message.dart';
import '../models/room.dart';

/// A live "who won" tally for a room: how many voted For vs Against, and which
/// side (if any) the current user picked.
class VoteTally {
  final int forCount;
  final int againstCount;
  final String? myVote; // 'for', 'against', or null

  const VoteTally({
    required this.forCount,
    required this.againstCount,
    this.myVote,
  });

  int get total => forCount + againstCount;
}

/// Reads and writes debate rooms and their messages in Firestore.
class RoomService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _db.collection('rooms');

  /// Live list of all rooms, newest activity first. Updates automatically as
  /// rooms are created or get new messages.
  Stream<List<Room>> watchRooms() {
    return _rooms
        .orderBy('lastActivity', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Room.fromDoc).toList());
  }

  /// Live list of rooms created by a specific user.
  Stream<List<Room>> watchMyRooms(String userId) {
    return _rooms
        .where('createdBy', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs.map(Room.fromDoc).toList());
  }

  /// Creates a room and returns its new id. For a private room, pass the raw
  /// [password]; we store only its hash.
  Future<String> createRoom({
    required String name,
    required String topic,
    required String category,
    required bool isPrivate,
    String? password,
    required String createdBy,
    required String createdByName,
  }) async {
    final room = Room(
      id: '',
      name: name.trim(),
      topic: topic.trim(),
      category: category,
      isPrivate: isPrivate,
      // The password hash is NOT stored on the room doc (clients can read that).
      // For private rooms we write a salted hash to the unreadable secure subdoc
      // below, and verification happens in the verifyRoomPassword function.
      passwordHash: null,
      createdBy: createdBy,
      createdByName: createdByName,
    );
    final ref = await _rooms.add(room.toCreateMap());
    if (isPrivate && password != null && password.trim().isNotEmpty) {
      final salt = _randomSalt();
      final hash =
          sha256.convert(utf8.encode(salt + password.trim())).toString();
      await ref.collection('secure').doc('auth').set({'hash': hash, 'salt': salt});
    }
    return ref.id;
  }

  /// A random salt (hex) for a private room's password hash.
  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Asks the server whether [password] is correct for a private [roomId].
  /// The check runs in the verifyRoomPassword Cloud Function so a tampered app
  /// can't bypass it and the hash never reaches the client.
  Future<bool> verifyRoomPassword(String roomId, String password) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('verifyRoomPassword');
    final res = await callable.call<dynamic>(
      {'roomId': roomId, 'password': password},
    );
    final data = res.data;
    return data is Map && data['ok'] == true;
  }

  /// Checks a typed [password] against a room's stored hash. (Legacy local
  /// check — kept for older rooms; new code uses [verifyRoomPassword].)
  bool checkPassword(Room room, String password) {
    if (!room.isPrivate) return true;
    return room.passwordHash == hashPassword(password);
  }

  /// Live list of the most recent [limit] messages in a room, returned oldest-
  /// first so the newest sits at the bottom like a normal chat.
  ///
  /// Only watching the latest window (instead of the whole history) keeps
  /// Firestore reads — and therefore cost — low even in rooms with thousands of
  /// messages. Raise [limit] (see the chat screen's "Load earlier messages") to
  /// pull in older messages.
  Stream<List<Message>> watchMessages(String roomId, {int limit = 30}) {
    return _rooms
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true) // newest first for the limit…
        .limit(limit)
        .snapshots()
        // …then flip back to oldest-first for display.
        .map((snap) =>
            snap.docs.map(Message.fromDoc).toList().reversed.toList());
  }

  /// Sends a message and bumps the room's lastActivity so it floats to the top.
  /// Pass [replyTo] to quote another message.
  Future<void> sendMessage({
    required String roomId,
    required String text,
    required String senderId,
    required String senderName,
    String? senderAvatar,
    required Stance stance,
    Message? replyTo,
  }) async {
    final message = Message(
      id: '',
      text: text.trim(),
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      stance: stance,
      replyToId: replyTo?.id,
      replyToText: replyTo?.text,
      replyToSender: replyTo?.senderName,
      replyToSenderId: replyTo?.senderId,
    );
    final batch = _db.batch();
    final msgRef = _rooms.doc(roomId).collection('messages').doc();
    batch.set(msgRef, message.toCreateMap());
    batch.update(_rooms.doc(roomId), {
      'lastActivity': FieldValue.serverTimestamp(),
      // Keep a running total so the rooms list can show "💬 N messages" — a
      // little hook that makes people curious to jump into a busy debate.
      'messageCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  // ---- "Who won?" voting -------------------------------------------------
  CollectionReference<Map<String, dynamic>> _votesCol(String roomId) =>
      _rooms.doc(roomId).collection('votes');

  /// Casts or changes the current user's "who won" vote ([side] is 'for' or
  /// 'against'). Voting the same side again removes the vote (toggle off).
  Future<void> castVote({
    required String roomId,
    required String userId,
    required String side,
  }) async {
    final ref = _votesCol(roomId).doc(userId);
    final snap = await ref.get();
    if (snap.exists && snap.data()?['side'] == side) {
      await ref.delete();
    } else {
      await ref.set({'side': side, 'at': FieldValue.serverTimestamp()});
    }
  }

  /// Live "who won" tally for a room, plus the current user's own vote.
  Stream<VoteTally> watchVotes(String roomId, String? myUid) {
    return _votesCol(roomId).snapshots().map((snap) {
      var forCount = 0;
      var againstCount = 0;
      String? mine;
      for (final d in snap.docs) {
        final side = d.data()['side'];
        if (side == 'for') forCount++;
        if (side == 'against') againstCount++;
        if (d.id == myUid) mine = side as String?;
      }
      return VoteTally(forCount: forCount, againstCount: againstCount, myVote: mine);
    });
  }

  /// Deletes a message (used when you remove your own message via moderation).
  Future<void> deleteMessage(String roomId, String messageId) async {
    await _rooms.doc(roomId).collection('messages').doc(messageId).delete();
  }

  /// Edits the text of a message you sent. Marks it `edited` so the UI can show
  /// an "(edited)" note. Firestore rules only let the original author do this.
  Future<void> editMessage(
      String roomId, String messageId, String newText) async {
    await _rooms.doc(roomId).collection('messages').doc(messageId).update({
      'text': newText.trim(),
      'edited': true,
    });
  }

  /// Deletes a whole room you created (and all its messages/votes) via the
  /// deleteMyRoom Cloud Function, which checks you're the creator server-side.
  Future<void> deleteMyRoom(String roomId) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('deleteMyRoom');
    await callable.call<dynamic>({'roomId': roomId});
  }

  /// Adds or changes the current user's reaction on a message. Passing the same
  /// emoji the user already has removes it (toggle off).
  Future<void> toggleReaction({
    required String roomId,
    required String messageId,
    required String userId,
    required String emoji,
    String? currentEmoji,
  }) async {
    final ref = _rooms.doc(roomId).collection('messages').doc(messageId);
    if (currentEmoji == emoji) {
      // Tapped the same one again → remove it.
      await ref.update({'reactions.$userId': FieldValue.delete()});
    } else {
      await ref.update({'reactions.$userId': emoji});
    }
  }

  // ---- Participated / joined rooms --------------------------------------
  CollectionReference<Map<String, dynamic>> _joinedCol(String userId) =>
      _db.collection('users').doc(userId).collection('joinedRooms');

  /// Records that [userId] has joined [room] (so it shows under "Visited").
  /// Stores a denormalized snapshot so the list renders without extra reads.
  /// If [stance] is given it is remembered for next time; merge means an
  /// existing stance is never wiped by a re-join that omits it.
  Future<void> recordJoin(String userId, Room room, {Stance? stance}) async {
    await _joinedCol(userId).doc(room.id).set({
      'roomId': room.id,
      'name': room.name,
      'topic': room.topic,
      'category': room.category,
      'isPrivate': room.isPrivate,
      'createdBy': room.createdBy,
      'createdByName': room.createdByName,
      'joinedAt': FieldValue.serverTimestamp(),
      if (stance != null) 'stance': stance.name,
    }, SetOptions(merge: true));
  }

  /// The stance [userId] previously chose for [roomId], or null if they have
  /// never picked a side in this room yet.
  Future<Stance?> getStoredStance(String userId, String roomId) async {
    final doc = await _joinedCol(userId).doc(roomId).get();
    final name = doc.data()?['stance'];
    if (name == null) return null;
    return Stance.values.firstWhere((s) => s.name == name,
        orElse: () => Stance.neutral);
  }

  /// Updates the remembered stance for a room the user is already in.
  Future<void> setStance(String userId, String roomId, Stance stance) async {
    await _joinedCol(userId).doc(roomId).set(
      {'stance': stance.name},
      SetOptions(merge: true),
    );
  }

  /// Removes a room from this user's "Visited" list (does not delete the room).
  Future<void> removeVisited(String userId, String roomId) async {
    await _joinedCol(userId).doc(roomId).delete();
  }

  // ---- Hidden rooms (creator removes a room from their own list) ---------
  CollectionReference<Map<String, dynamic>> _hiddenCol(String userId) =>
      _db.collection('users').doc(userId).collection('hiddenRooms');

  /// Hides [roomId] from this user's "My Rooms" list WITHOUT deleting the room,
  /// so anyone still chatting there is unaffected.
  Future<void> hideRoom(String userId, String roomId) async {
    await _hiddenCol(userId).doc(roomId).set(
      {'hiddenAt': FieldValue.serverTimestamp()},
    );
  }

  /// Brings a previously hidden room back into the user's list.
  Future<void> unhideRoom(String userId, String roomId) async {
    await _hiddenCol(userId).doc(roomId).delete();
  }

  /// Live set of room ids this user has hidden from their own list.
  Stream<Set<String>> watchHiddenRoomIds(String userId) {
    return _hiddenCol(userId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  /// Live list of rooms the user has joined, most recently joined first.
  Stream<List<Room>> watchJoinedRooms(String userId) {
    return _joinedCol(userId)
        .orderBy('joinedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = d.data();
              return Room(
                id: m['roomId'] ?? d.id,
                name: m['name'] ?? '',
                topic: m['topic'] ?? '',
                category: m['category'] ?? 'Other',
                isPrivate: m['isPrivate'] ?? false,
                createdBy: m['createdBy'] ?? '',
                createdByName: m['createdByName'] ?? 'Someone',
                lastSeenCount: (m['lastSeenCount'] as num?)?.toInt() ?? 0,
              );
            }).toList());
  }

  /// Live message count for a room (used to badge unread messages in the list).
  Stream<int> watchMessageCount(String roomId) {
    return _rooms.doc(roomId).snapshots().map(
        (d) => (d.data()?['messageCount'] as num?)?.toInt() ?? 0);
  }

  /// Marks a room as read for [userId] up to its current message count, so the
  /// unread badge clears. Called when the user opens/leaves the chat.
  Future<void> markRoomRead(String userId, String roomId) async {
    try {
      final joinedRef = _joinedCol(userId).doc(roomId);
      // Only track for rooms already in the user's list — don't create a stray
      // (nameless) Visited entry for rooms opened straight from a notification.
      final joined = await joinedRef.get();
      if (!joined.exists) return;
      final roomDoc = await _rooms.doc(roomId).get();
      final count = (roomDoc.data()?['messageCount'] as num?)?.toInt() ?? 0;
      await joinedRef.set({'lastSeenCount': count}, SetOptions(merge: true));
    } catch (_) {
      // Best-effort — the badge is a nicety, never break the chat over it.
    }
  }

  /// Scrambles a password with SHA-256 so the real password is never stored.
  String hashPassword(String password) {
    return sha256.convert(utf8.encode(password.trim())).toString();
  }
}
