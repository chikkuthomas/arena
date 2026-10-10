import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-room "notify me about new messages" opt-in. Default is OFF.
///
/// When a user turns it ON for a room, the phone subscribes to that room's
/// Firebase Cloud Messaging topic. A Cloud Function then pushes a notification
/// to that topic on every new message — so the alert arrives even when the app
/// is closed. Turning it OFF unsubscribes.
///
/// The on/off choice is also remembered on the phone (shared_preferences) so the
/// bell shows the right state when the room is reopened.
class RoomNotifyService {
  /// The room the user is currently looking at, if any. The foreground message
  /// handler uses this to avoid popping a notification for the room already on
  /// screen. Set when a chat room opens; cleared when it closes.
  static String? activeRoomId;

  static String _prefKey(String roomId) => 'notify_$roomId';

  static const _uidKey = 'signed_in_uid';

  /// Remembers who is signed in on this phone (null = signed out), so the
  /// background push handler can recognise your own messages without waiting
  /// for Firebase Auth to restore itself.
  static Future<void> saveUid(String? uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid == null) {
        await prefs.remove(_uidKey);
      } else {
        await prefs.setString(_uidKey, uid);
      }
    } catch (_) {/* best-effort */}
  }

  /// The uid saved by [saveUid], or null.
  static Future<String?> savedUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getString(_uidKey);
    } catch (_) {
      return null;
    }
  }

  /// One topic every device subscribes to, so an admin can push a single
  /// broadcast that reaches every user at once (see the broadcastTopic Cloud
  /// Function). MUST match ALL_USERS_TOPIC in the Cloud Function.
  static const String allUsersTopic = 'all_users';

  /// Subscribes this device to the app-wide broadcast topic. Called at startup.
  /// Best-effort — never throws.
  static Future<void> subscribeAll() async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(allUsersTopic);
    } catch (_) {
      // Offline / messaging unavailable — the app must still work.
    }
  }

  /// FCM topic names only allow [a-zA-Z0-9-_.~%]. Room ids are normally safe,
  /// but sanitise defensively. MUST match the sanitising in the Cloud Function.
  static String topicFor(String roomId) =>
      'room_${roomId.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_')}';

  /// Each signed-in device subscribes to its own user topic so the Cloud
  /// Function can push a "someone replied to you" alert to that specific person,
  /// regardless of whether they follow the room. MUST match the Cloud Function.
  static String userTopicFor(String uid) =>
      'user_${uid.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_')}';

  /// Subscribes this device to the signed-in user's personal reply topic.
  /// Best-effort — never throws (called at startup / on login).
  static Future<void> subscribeUser(String uid) async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(userTopicFor(uid));
    } catch (_) {
      // Offline or messaging unavailable — the app must still work.
    }
  }

  /// Unsubscribes this device from a user's reply topic (called on logout, so a
  /// shared phone's next user doesn't receive the previous user's alerts).
  static Future<void> unsubscribeUser(String uid) async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(userTopicFor(uid));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Drops EVERY push subscription on this device by deleting its FCM token —
  /// room bells (room_*), trending/participant topics, and the all_users
  /// broadcast. Called on logout so the signed-out user stops getting any room
  /// notifications. A fresh token is created lazily on the next subscribe.
  static Future<void> clearAllSubscriptions() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Best-effort — offline / messaging unavailable.
    }
  }

  /// Re-subscribes this device to every room whose 🔔 bell the user had turned
  /// on (remembered in prefs). Called on login, since logout deletes the token
  /// and with it all room subscriptions.
  static Future<void> resubscribeSavedRooms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const prefix = 'notify_';
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefix) && (prefs.getBool(key) ?? false)) {
          final roomId = key.substring(prefix.length);
          await FirebaseMessaging.instance.subscribeToTopic(topicFor(roomId));
        }
      }
    } catch (_) {
      // Best-effort.
    }
  }

  /// Topic for everyone who has taken part in a room. The Cloud Function pushes
  /// a "your debate is trending, jump back in" alert here when the room heats up,
  /// to pull participants back — even if they never turned on the 🔔 bell.
  /// MUST match the Cloud Function's participantsTopicFor().
  static String participantsTopicFor(String roomId) =>
      'room_participants_${roomId.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_')}';

  /// Subscribes this device to a room's "trending" re-engagement topic. Called
  /// when the user opens/takes part in a room. Best-effort — never throws.
  static Future<void> subscribeParticipant(String roomId) async {
    try {
      await FirebaseMessaging.instance
          .subscribeToTopic(participantsTopicFor(roomId));
    } catch (_) {
      // Offline / messaging unavailable — must not break the chat.
    }
  }

  /// Unsubscribes this device from a room's "trending" re-engagement topic.
  /// Called when the user leaves a room. Best-effort — never throws.
  static Future<void> unsubscribeParticipant(String roomId) async {
    try {
      await FirebaseMessaging.instance
          .unsubscribeFromTopic(participantsTopicFor(roomId));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Whether notifications are currently on for [roomId].
  static Future<bool> isOn(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(roomId)) ?? false;
  }

  /// Turns the 🔔 bell ON for a room the user takes part in (creates it or
  /// posts in it) — but only if they've never set it themselves, so an explicit
  /// "off" is respected. Best-effort — never throws, must not break the chat.
  /// Returns true if it switched the bell on.
  static Future<bool> autoEnable(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefKey(roomId))) return false;
      await setOn(roomId, true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Turns the bell ON for every room this user is part of — rooms they
  /// opened ("Visited") and rooms they created ("My Rooms") — skipping any
  /// where they explicitly chose a setting. Runs on login/startup so existing
  /// users (and fresh installs) get notified without re-posting in each room.
  /// Best-effort — never throws.
  static Future<void> autoEnableMyRooms(String uid) async {
    try {
      final db = FirebaseFirestore.instance;
      final joined =
          await db.collection('users').doc(uid).collection('joinedRooms').get();
      final created = await db
          .collection('rooms')
          .where('createdBy', isEqualTo: uid)
          .get();
      final ids = {
        ...joined.docs.map((d) => (d.data()['roomId'] as String?) ?? d.id),
        ...created.docs.map((d) => d.id),
      };
      for (final id in ids) {
        await autoEnable(id);
      }
    } catch (_) {
      // Offline / permission issue — the app must still work.
    }
  }

  /// Turns notifications on/off for [roomId]. Subscribes/unsubscribes the phone
  /// to the room's push topic and remembers the choice. Throws if it can't reach
  /// Firebase, so the caller can revert the toggle and warn the user.
  static Future<void> setOn(String roomId, bool on) async {
    final topic = topicFor(roomId);
    if (on) {
      // Make sure we're allowed to show notifications (Android 13+/iOS).
      await FirebaseMessaging.instance.requestPermission();
      await FirebaseMessaging.instance.subscribeToTopic(topic);
    } else {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(roomId), on);
  }
}
