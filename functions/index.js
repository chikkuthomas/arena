// Arena Cloud Function.
//
// Whenever a new message is written to a room, push a notification to everyone
// who turned on notifications for that room (they are subscribed to the room's
// Firebase Cloud Messaging "topic"). This is what makes room notifications
// arrive even when the app is closed.
//
// Deploy with:  firebase deploy --only functions
// (Requires the Firebase project to be on the Blaze plan.)

const { setGlobalOptions } = require("firebase-functions/v2");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const crypto = require("crypto");

initializeApp();

// Hard ceiling on how many copies of any function can run at once.
//
// Cloud Functions bills per invocation and scales to 1000 instances by default.
// A trigger loop or a burst of abuse would otherwise run up a bill with nothing
// to stop it, and Blaze has no spending cap — only after-the-fact alerts. With
// a cap, the worst case is that Arena gets SLOW under load, not expensive.
// Raise this if real traffic ever justifies it.
setGlobalOptions({ maxInstances: 10 });

// Must match RoomNotifyService.topicFor() in the Flutter app.
function topicFor(roomId) {
  return "room_" + roomId.replace(/[^a-zA-Z0-9-_.~%]/g, "_");
}

// Must match RoomNotifyService.userTopicFor() in the Flutter app.
function userTopicFor(uid) {
  return "user_" + uid.replace(/[^a-zA-Z0-9-_.~%]/g, "_");
}

// Must match RoomNotifyService.participantsTopicFor() in the Flutter app.
function participantsTopicFor(roomId) {
  return "room_participants_" + roomId.replace(/[^a-zA-Z0-9-_.~%]/g, "_");
}

// Everyone who runs the app subscribes to this one topic (see
// RoomNotifyService.allUsersTopic). An admin broadcast is pushed here so it
// reaches every user at once. MUST match the Flutter app.
const ALL_USERS_TOPIC = "all_users";

// Shared secret that guards the broadcast endpoint so only you can trigger it.
// Stored in Google Secret Manager (NOT in this public repo). Set it once with:
//   firebase functions:secrets:set BROADCAST_SECRET
// and send the same value as the "x-arena-key" header from Postman.
const broadcastSecret = defineSecret("BROADCAST_SECRET");

// "Trending" tuning: a burst of THRESHOLD messages within WINDOW_MS marks a room
// as on fire; at most one trending push per room every COOLDOWN_MS.
const TREND_WINDOW_MS = 30 * 60 * 1000; // 30 minutes
const TREND_THRESHOLD = 20; // messages within the window
const TREND_COOLDOWN_MS = 3 * 60 * 60 * 1000; // 3 hours

const TREND_LINES = [
  "🔥 is on fire — new arguments are flying. Jump back in!",
  "⚔️ is heating up! People are waiting for your comeback.",
  "🔥 Your debate is trending — don't let them win. Reply now!",
  "💬 is buzzing right now. Share your side before it cools off!",
];

// Writes a notification-history doc for one user. Best-effort — a history
// write must never block or fail the push it's recording.
async function recordNotification(uid, { type, title, body, roomId }) {
  try {
    await getFirestore().collection("users").doc(uid).collection("notifications").add({
      type, title, body, roomId: roomId || null,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
    });
  } catch (e) {
    console.error("Failed to record notification for", uid, e);
  }
}

// Fans a notification-history write out to every uid in a room subcollection
// (notifySubscribers or participants), skipping `skipUid` (e.g. the sender).
// Best-effort per-doc — one failed write must not stop the rest.
async function recordToSubcollection(roomId, subcollection, skipUid, payload) {
  try {
    const snap = await getFirestore()
      .collection("rooms").doc(roomId).collection(subcollection).get();
    await Promise.all(snap.docs
      .map((d) => d.id)
      .filter((uid) => uid !== skipUid)
      .map((uid) => recordNotification(uid, payload)));
  } catch (e) {
    console.error(`Failed to fan out ${subcollection} notifications for room`, roomId, e);
  }
}

exports.notifyRoomOnNewMessage = onDocumentCreated(
  "rooms/{roomId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const msg = snap.data() || {};
    const roomId = event.params.roomId;

    // Look up the room's name to use as the notification title.
    let roomName = "A debate";
    try {
      const roomDoc = await getFirestore().collection("rooms").doc(roomId).get();
      if (roomDoc.exists && roomDoc.data().name) {
        roomName = roomDoc.data().name;
      }
    } catch (e) {
      // Non-fatal — fall back to the default title.
    }

    const sender = msg.senderName || "Someone";
    const text = msg.text || "";
    // Keep the body short so it fits a notification.
    const body = (sender + ": " + text).slice(0, 180);

    try {
      await getMessaging().send({
        topic: topicFor(roomId),
        notification: { title: roomName, body: body },
        // senderId lets the sender's own device drop this push (you subscribe to
        // your room's topic, so FCM would otherwise notify you of your own message).
        // messageId + a per-message tag let the sender's phone find and remove
        // this exact notification if it arrives while their app is in the
        // background (Android shows it before any app code can filter it).
        data: {
          roomId: roomId,
          type: "room_message",
          senderId: msg.senderId || "",
          messageId: event.params.messageId,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "room_messages",
            tag: "msg_" + event.params.messageId,
          },
        },
      });
    } catch (e) {
      console.error("Failed to send room notification:", e);
    }
    await recordToSubcollection(roomId, "notifySubscribers", msg.senderId, {
      type: "room_message", title: roomName, body, roomId,
    });

    // If this message is a reply, also notify the author of the quoted message
    // directly (via their personal user topic) — even if they don't follow the
    // room. Skip when someone replies to their own message.
    const replyToSenderId = msg.replyToSenderId;
    if (replyToSenderId && replyToSenderId !== msg.senderId) {
      try {
        await getMessaging().send({
          topic: userTopicFor(replyToSenderId),
          notification: {
            title: sender + " replied to you",
            body: text.slice(0, 180),
          },
          data: { roomId: roomId, type: "reply" },
          android: {
            priority: "high",
            notification: { channelId: "replies" },
          },
        });
      } catch (e) {
        console.error("Failed to send reply notification:", e);
      }
      await recordNotification(replyToSenderId, {
        type: "reply", title: sender + " replied to you",
        body: text.slice(0, 180), roomId,
      });
    }

    // ---- Trending re-engagement -----------------------------------------
    // Track the room's message pace. If it bursts past the threshold within the
    // window (and we haven't pushed recently), nudge everyone who took part.
    try {
      const db = getFirestore();
      const roomRef = db.collection("rooms").doc(roomId);
      const now = Date.now();
      const fire = await db.runTransaction(async (tx) => {
        const doc = await tx.get(roomRef);
        const d = doc.exists ? doc.data() : {};
        let windowStart = d.trendWindowStart || 0;
        let count = d.trendCount || 0;
        const lastPush = d.lastTrendingPushAt || 0;

        if (now - windowStart > TREND_WINDOW_MS) {
          windowStart = now; // window expired — start a new one
          count = 1;
        } else {
          count += 1;
        }

        let shouldFire = false;
        const update = { trendWindowStart: windowStart, trendCount: count };
        if (count >= TREND_THRESHOLD && now - lastPush > TREND_COOLDOWN_MS) {
          shouldFire = true;
          update.lastTrendingPushAt = now;
          update.trendCount = 0; // reset so it doesn't re-fire immediately
        }
        tx.set(roomRef, update, { merge: true });
        return shouldFire;
      });

      if (fire) {
        const line = TREND_LINES[Math.floor(Math.random() * TREND_LINES.length)];
        const trendBody = '"' + roomName + '" ' + line;
        await getMessaging().send({
          topic: participantsTopicFor(roomId),
          notification: { title: roomName, body: trendBody },
          data: { roomId: roomId, type: "trending" },
          android: {
            priority: "high",
            notification: { channelId: "trending" },
          },
        });
        await recordToSubcollection(roomId, "participants", msg.senderId, {
          type: "trending", title: roomName, body: trendBody, roomId,
        });
      }
    } catch (e) {
      console.error("Failed trending check:", e);
    }
  }
);

// ---- Admin broadcast (call from Postman) --------------------------------
// POST a sentence (the debate topic). This creates a fresh public room for it
// and pushes ONE notification to every user (the "all_users" topic). Tapping
// the notification opens that new room in the app.
//
// Usage from Postman:
//   POST https://<region>-<project>.cloudfunctions.net/broadcastTopic
//   Header:  x-arena-key: <BROADCAST_SECRET above>
//   Body (either works):
//     • raw JSON:  { "topic": "Should AI replace teachers?" }
//     • raw text:  Should AI replace teachers?
//   Optional JSON field: "category": "Technology"
exports.broadcastTopic = onRequest(
  { region: "asia-south1", secrets: [broadcastSecret] },
  async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Use POST" });
  }

  // Only you, holding the shared secret, may fire a broadcast. If the secret was
  // never set, reject everything (never fall open).
  const expected = broadcastSecret.value();
  const key = req.get("x-arena-key") || req.query.key;
  if (!expected || key !== expected) {
    return res.status(401).json({ error: "Unauthorized — wrong or missing key" });
  }

  // Accept the topic as raw text, or as JSON { topic: "..." }.
  let topic = "";
  let category = "Other";
  if (typeof req.body === "string") {
    topic = req.body;
  } else if (req.body && typeof req.body === "object") {
    topic = req.body.topic || "";
    if (req.body.category) category = String(req.body.category);
  }
  topic = String(topic || "").trim();
  if (!topic) {
    return res.status(400).json({ error: "Provide a topic sentence" });
  }

  try {
    const db = getFirestore();

    // Create the room this broadcast points at. Shape matches Room.toCreateMap()
    // in the Flutter app so it renders like any other room.
    const roomRef = await db.collection("rooms").add({
      name: topic.slice(0, 80),
      topic: topic,
      category: category,
      isPrivate: false,
      passwordHash: null,
      createdBy: "admin",
      createdByName: "Arena",
      isDaily: false,
      isBroadcast: true,
      createdAt: FieldValue.serverTimestamp(),
      lastActivity: FieldValue.serverTimestamp(),
    });
    const roomId = roomRef.id;

    // One push to everyone. data.roomId + type let the app open the room on tap.
    await getMessaging().send({
      topic: ALL_USERS_TOPIC,
      notification: { title: "🔥 New debate is live!", body: topic.slice(0, 180) },
      data: { roomId: roomId, type: "broadcast" },
      android: {
        priority: "high",
        notification: { channelId: "broadcast" },
      },
    });

    // One shared doc every signed-in client reads directly — no per-user
    // fan-out needed since every account is already subscribed to this topic.
    await db.collection("broadcasts").doc(roomId).set({
      title: "🔥 New debate is live!",
      body: topic.slice(0, 180),
      roomId,
      createdAt: FieldValue.serverTimestamp(),
    });

    return res.status(200).json({ ok: true, roomId, topic });
  } catch (e) {
    console.error("broadcastTopic failed:", e);
    return res.status(500).json({ error: e.message || String(e) });
  }
});

// ---- Verify a private room's password (server-side) ---------------------
// The room password is checked here instead of on the phone, so a tampered
// client can't bypass it and the hash is never exposed to clients. New private
// rooms store a salted hash in the unreadable rooms/{id}/secure/auth subdoc;
// older rooms fall back to the legacy (unsalted) passwordHash on the room doc.
exports.verifyRoomPassword = onCall({ region: "asia-south1" }, async (req) => {
  if (!req.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const roomId = String((req.data && req.data.roomId) || "").trim();
  const password = String((req.data && req.data.password) || "");
  if (!roomId) {
    throw new HttpsError("invalid-argument", "Missing roomId.");
  }

  const db = getFirestore();
  const roomRef = db.collection("rooms").doc(roomId);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) {
    throw new HttpsError("not-found", "Room not found.");
  }
  const room = roomSnap.data() || {};
  if (!room.isPrivate) return { ok: true }; // public room — no password needed

  let storedHash = null;
  let salt = "";
  const secure = await roomRef.collection("secure").doc("auth").get();
  if (secure.exists) {
    storedHash = secure.data().hash;
    salt = secure.data().salt || "";
  } else if (room.passwordHash) {
    storedHash = room.passwordHash; // legacy room — unsalted
  }
  if (!storedHash) return { ok: false };

  const attempt = crypto
    .createHash("sha256")
    .update(salt + password.trim())
    .digest("hex");
  return { ok: attempt === storedHash };
});

// ---- Let a room's creator delete their own room --------------------------
// Callable from the app. Verifies (server-side) that the caller created the
// room, then recursively deletes it and everything under it (messages, votes,
// the secure password subdoc).
exports.deleteMyRoom = onCall({ region: "asia-south1" }, async (req) => {
  if (!req.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const roomId = String((req.data && req.data.roomId) || "").trim();
  if (!roomId) {
    throw new HttpsError("invalid-argument", "Missing roomId.");
  }
  const db = getFirestore();
  const ref = db.collection("rooms").doc(roomId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Room not found.");
  }
  if ((snap.data() || {}).createdBy !== req.auth.uid) {
    throw new HttpsError(
        "permission-denied", "Only the room's creator can delete it.");
  }
  await db.recursiveDelete(ref);
  return { ok: true };
});

// ---- Clean up stale, empty rooms ----------------------------------------
// Runs daily. Deletes rooms whose last activity is older than the cutoff AND
// that have no messages — so abandoned daily/broadcast rooms don't pile up.
// Conservative: any room with even one message is kept.
const STALE_ROOM_DAYS = 7;

exports.cleanupStaleRooms = onSchedule(
  { schedule: "every 24 hours", region: "asia-south1" },
  async () => {
    const db = getFirestore();
    const cutoff = new Date(Date.now() - STALE_ROOM_DAYS * 24 * 60 * 60 * 1000);
    const stale = await db
      .collection("rooms")
      .where("lastActivity", "<", cutoff)
      .get();

    let deleted = 0;
    for (const doc of stale.docs) {
      const msgs = await doc.ref.collection("messages").limit(1).get();
      if (!msgs.empty) continue; // keep any room that has messages
      // Remove the protected password subdoc too, if present.
      const secure = await doc.ref.collection("secure").doc("auth").get();
      if (secure.exists) await secure.ref.delete();
      await doc.ref.delete();
      deleted++;
    }
    console.log(`cleanupStaleRooms: deleted ${deleted} empty stale room(s)`);
  }
);

// ---- SAFETY: clear every room (call from Postman) -----------------------
// Recursively deletes ALL rooms and their messages/votes/subdocs — the same
// wipe as a manual cleanup, but on demand. User accounts and config are NOT
// touched. Guarded by BOTH the shared secret AND an explicit confirmation
// string, so it can never fire by accident.
//
// Usage from Postman:
//   POST https://asia-south1-arena-a049d.cloudfunctions.net/clearAllRooms
//   Header:  x-arena-key: <BROADCAST_SECRET>
//   Body (raw JSON):  { "confirm": "DELETE ALL ROOMS" }
exports.clearAllRooms = onRequest(
  { region: "asia-south1", secrets: [broadcastSecret] },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Use POST" });
    }
    const expected = broadcastSecret.value();
    const key = req.get("x-arena-key") || req.query.key;
    if (!expected || key !== expected) {
      return res.status(401).json({ error: "Unauthorized — wrong or missing key" });
    }
    const confirm =
      (req.body && typeof req.body === "object" && req.body.confirm) ||
      req.query.confirm;
    if (confirm !== "DELETE ALL ROOMS") {
      return res.status(400).json({
        error: 'Send {"confirm":"DELETE ALL ROOMS"} to proceed.',
      });
    }
    try {
      const db = getFirestore();
      await db.recursiveDelete(db.collection("rooms"));
      return res.status(200).json({ ok: true, cleared: "rooms" });
    } catch (e) {
      console.error("clearAllRooms failed:", e);
      return res.status(500).json({ error: e.message || String(e) });
    }
  }
);

// ---- Admin: set the "topic of the day" override (call from Admin app) ----
// Writes config/dailyOverride so every phone uses this topic for that day's
// push instead of the hardcoded pool. Same shape the app's DailyOverrideService
// reads. Guarded by the shared secret.
//
//   POST https://asia-south1-arena-a049d.cloudfunctions.net/setDailyTopic
//   Header:  x-arena-key: <BROADCAST_SECRET>
//   Body: { "topic": "...", "date": "yyyy-mm-dd", "hour": 9, "minute": 0,
//           "category": "Trending" }
exports.setDailyTopic = onRequest(
  { region: "asia-south1", secrets: [broadcastSecret] },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Use POST" });
    }
    const expected = broadcastSecret.value();
    const key = req.get("x-arena-key") || req.query.key;
    if (!expected || key !== expected) {
      return res.status(401).json({ error: "Unauthorized — wrong or missing key" });
    }
    const b = (req.body && typeof req.body === "object") ? req.body : {};
    const topic = String(b.topic || "").trim();
    const date = String(b.date || "").trim();
    const category = String(b.category || "Trending").trim() || "Trending";
    const hour = Number.isInteger(b.hour) ? b.hour : 9;
    const minute = Number.isInteger(b.minute) ? b.minute : 0;
    if (!topic) return res.status(400).json({ error: "Provide a topic" });
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return res.status(400).json({ error: "Provide date as yyyy-mm-dd" });
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return res.status(400).json({ error: "Invalid hour/minute" });
    }
    try {
      await getFirestore().collection("config").doc("dailyOverride").set({
        topic: topic,
        category: category,
        date: date,
        hour: hour,
        minute: minute,
        setAt: FieldValue.serverTimestamp(),
      });
      return res.status(200).json({ ok: true, topic, date, hour, minute });
    } catch (e) {
      console.error("setDailyTopic failed:", e);
      return res.status(500).json({ error: e.message || String(e) });
    }
  }
);

// ---- Admin: delete one room by id (call from Admin app) ------------------
// Recursively deletes a single room and all its messages/votes/subdocs.
// Guarded by the shared secret.
//
//   POST https://asia-south1-arena-a049d.cloudfunctions.net/deleteRoom
//   Header:  x-arena-key: <BROADCAST_SECRET>
//   Body: { "roomId": "<room id>" }
exports.deleteRoom = onRequest(
  { region: "asia-south1", secrets: [broadcastSecret] },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Use POST" });
    }
    const expected = broadcastSecret.value();
    const key = req.get("x-arena-key") || req.query.key;
    if (!expected || key !== expected) {
      return res.status(401).json({ error: "Unauthorized — wrong or missing key" });
    }
    const b = (req.body && typeof req.body === "object") ? req.body : {};
    const roomId = String(b.roomId || "").trim();
    if (!roomId) return res.status(400).json({ error: "Provide a roomId" });
    try {
      const db = getFirestore();
      const ref = db.collection("rooms").doc(roomId);
      const snap = await ref.get();
      if (!snap.exists) {
        return res.status(404).json({ error: "Room not found" });
      }
      const name = (snap.data() || {}).name || "";
      await db.recursiveDelete(ref);
      return res.status(200).json({ ok: true, deleted: roomId, name });
    } catch (e) {
      console.error("deleteRoom failed:", e);
      return res.status(500).json({ error: e.message || String(e) });
    }
  }
);

// ---- Admin: messages reported by 2+ people (for the Admin app) -----------
// Aggregates the `reports` collection by messageId, counts DISTINCT reporters,
// and returns messages reported by 2 or more different users, with details.
// Guarded by the shared secret (sent as x-arena-key). GET or POST.
//
//   GET https://asia-south1-arena-a049d.cloudfunctions.net/reportedMessages
//   Header:  x-arena-key: <BROADCAST_SECRET>
exports.reportedMessages = onRequest(
  { region: "asia-south1", secrets: [broadcastSecret] },
  async (req, res) => {
    const expected = broadcastSecret.value();
    const key = req.get("x-arena-key") || req.query.key;
    if (!expected || key !== expected) {
      return res.status(401).json({ error: "Unauthorized — wrong or missing key" });
    }
    try {
      const db = getFirestore();
      // ?min=1 lists every reported message (the Admin app's "All" view).
      const minReporters = Math.max(1, parseInt(req.query.min, 10) || 2);
      const snap = await db.collection("reports").get();
      const byMsg = {};
      snap.forEach((doc) => {
        const d = doc.data() || {};
        const mid = d.messageId || doc.id;
        if (!byMsg[mid]) {
          byMsg[mid] = {
            messageId: mid,
            roomId: d.roomId || "",
            messageText: d.messageText || "",
            offenderId: d.offenderId || "",
            offenderName: d.offenderName || "",
            reporters: new Set(),
            reasons: [],
          };
        }
        const e = byMsg[mid];
        if (d.reporterId) e.reporters.add(d.reporterId);
        if (d.reason) e.reasons.push(String(d.reason));
      });
      const reports = Object.values(byMsg)
        .filter((e) => e.reporters.size >= minReporters)
        .map((e) => ({
          messageId: e.messageId,
          roomId: e.roomId,
          messageText: e.messageText,
          offenderId: e.offenderId,
          offenderName: e.offenderName,
          reportCount: e.reporters.size,
          reasons: e.reasons,
        }))
        .sort((a, b) => b.reportCount - a.reportCount);
      return res.status(200).json({ ok: true, count: reports.length, reports });
    } catch (e) {
      console.error("reportedMessages failed:", e);
      return res.status(500).json({ error: e.message || String(e) });
    }
  }
);

// ---- Shared: erase one user and everything they own ----------------------
// Used by BOTH the admin endpoint (looks users up by email) and the
// self-service deleteMyAccount callable (uses the caller's own auth token).
// Pass a one-off snapshot of /rooms so bulk admin deletes read it once.
// Irreversible. Idempotent enough that a stale rooms entry is harmless.
// Stand-in identity left on content whose author has gone. DELETED_UID must
// never be a real uid, so no live user inherits edit/delete rights over the
// content (the Firestore rules key off senderId / createdBy).
const DELETED_UID = "deleted";
const DELETED_NAME = "Deleted user";

async function purgeUser(uid, roomsSnap, { anonymise = false } = {}) {
  const db = getFirestore();
  const auth = getAuth();
  let messagesDeleted = 0;
  let roomsDeleted = 0;
  let messagesAnonymised = 0;
  let roomsAnonymised = 0;

  // Reports they filed. Always hard-deleted — these are private to the user
  // and have no value to anyone else once the account is gone.
  const reps = await db
    .collection("reports")
    .where("reporterId", "==", uid)
    .get();
  for (const d of reps.docs) await d.ref.delete();

  // Walk every room.
  //
  // anonymise=false (admin/moderation): delete rooms they created outright and
  // strip their messages — used when removing an abusive account's content.
  //
  // anonymise=true (self-service deletion): KEEP the rooms and the messages and
  // just blank the author identity. Deleting a room would take every other
  // participant's messages with it — and the "Topic of the Day" room is owned
  // by whichever user happened to open the app first that day
  // (DailyTopicService.ensureTodayRoom), so a single person leaving would
  // otherwise wipe a shared debate that looks like it belongs to Arena.
  for (const roomDoc of roomsSnap.docs) {
    const roomRef = roomDoc.ref;
    const theirRoom = (roomDoc.data() || {}).createdBy === uid;

    if (theirRoom && !anonymise) {
      await db.recursiveDelete(roomRef);
      roomsDeleted++;
      continue;
    }
    if (theirRoom) {
      await roomRef.update({
        createdBy: DELETED_UID,
        createdByName: DELETED_NAME,
      });
      roomsAnonymised++;
    }

    const msgs = await roomRef
      .collection("messages")
      .where("senderId", "==", uid)
      .get();
    for (const m of msgs.docs) {
      if (anonymise) {
        await m.ref.update({
          senderId: DELETED_UID,
          senderName: DELETED_NAME,
          senderAvatar: FieldValue.delete(),
        });
        messagesAnonymised++;
      } else {
        await m.ref.delete();
        messagesDeleted++;
      }
    }

    // Messages by OTHER people that quote one of theirs carry a denormalized
    // copy of their name and uid (see Message.replyToSender/replyToSenderId).
    // Blank those too, or the name survives in every reply quote.
    if (anonymise) {
      const quotes = await roomRef
        .collection("messages")
        .where("replyToSenderId", "==", uid)
        .get();
      for (const q of quotes.docs) {
        await q.ref.update({
          replyToSenderId: DELETED_UID,
          replyToSender: DELETED_NAME,
        });
      }
    }

    await roomRef.collection("votes").doc(uid).delete();
    // Drop them from this room's notification fan-out lists too — otherwise a
    // future message keeps fanning a write out to a uid that no longer exists.
    await roomRef.collection("notifySubscribers").doc(uid).delete();
    await roomRef.collection("participants").doc(uid).delete();
  }

  // Their profile doc + subcollections (joinedRooms, hiddenRooms…).
  await db.recursiveDelete(db.collection("users").doc(uid));
  // Finally the login account itself.
  await auth.deleteUser(uid);

  return { messagesDeleted, roomsDeleted, messagesAnonymised, roomsAnonymised };
}

// ---- Let a signed-in user delete their OWN account ----------------------
// Google Play requires an in-app account deletion path for any app that lets
// people create accounts. This is deliberately a callable (not an onRequest
// guarded by BROADCAST_SECRET): identity comes from the caller's auth token,
// so the app never needs to hold a shared secret. A user can only ever delete
// themselves — the uid is taken from the token, never from the request body.
// timeoutSeconds: purgeUser walks EVERY room (one query per room), so the work
// grows with the size of the database, not with how much the user posted. At
// the 60s default a big enough /rooms collection would time out midway — and
// because the login is deleted last, that leaves data half-erased with the
// account still usable. 300s buys a lot of headroom; if this ever gets close,
// the fix is a targeted index, not a bigger number.
exports.deleteMyAccount = onCall(
    { region: "asia-south1", timeoutSeconds: 300 }, async (req) => {
  if (!req.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  // Belt-and-braces against an accidental client call; the real confirmation
  // is the two-step dialog in the app.
  if (!req.data || req.data.confirm !== "DELETE") {
    throw new HttpsError("invalid-argument", 'Send { confirm: "DELETE" }.');
  }
  const uid = req.auth.uid;
  const db = getFirestore();
  const roomsSnap = await db.collection("rooms").get();
  try {
    // anonymise: the user's own data goes, but rooms and debate threads they
    // took part in survive with the author blanked. See purgeUser.
    const stats = await purgeUser(uid, roomsSnap, { anonymise: true });
    return { ok: true, ...stats };
  } catch (e) {
    console.error("deleteMyAccount failed for", uid, e);
    throw new HttpsError("internal", "Could not delete the account.");
  }
});

// ---- Admin: delete user accounts + all their data (call from Admin app) --
// For each email: removes the Firebase Auth account AND everything they own —
// their profile (users/{uid} + subcollections), every message they posted, any
// rooms they created (recursively), their votes, and reports they filed.
// Irreversible. Guarded by the shared secret AND an explicit confirm token.
//
//   POST https://asia-south1-arena-a049d.cloudfunctions.net/deleteUserAccount
//   Header:  x-arena-key: <BROADCAST_SECRET>
//   Body:    { "emails": ["a@x.com", "b@y.com"], "confirm": "DELETE USERS" }
// timeoutSeconds: same full-/rooms walk as deleteMyAccount, once per email in
// the batch, so this one needs the headroom even more.
exports.deleteUserAccount = onRequest(
  { region: "asia-south1", secrets: [broadcastSecret], timeoutSeconds: 300 },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Use POST" });
    }
    const expected = broadcastSecret.value();
    const key = req.get("x-arena-key") || req.query.key;
    if (!expected || key !== expected) {
      return res.status(401).json({ error: "Unauthorized — wrong or missing key" });
    }
    const b = (req.body && typeof req.body === "object") ? req.body : {};
    if (b.confirm !== "DELETE USERS") {
      return res.status(400).json({
        error: 'Send {"confirm":"DELETE USERS"} to proceed.',
      });
    }
    const emails = Array.isArray(b.emails)
      ? b.emails
      : (b.email ? [b.email] : []);
    const cleaned = emails.map((e) => String(e || "").trim()).filter(Boolean);
    if (cleaned.length === 0) {
      return res.status(400).json({ error: "Provide emails: [ ... ]" });
    }
    try {
      const db = getFirestore();
      const auth = getAuth();
      // Snapshot all rooms once; deletes below are idempotent so a stale entry
      // (a room removed while processing an earlier user) is harmless.
      const roomsSnap = await db.collection("rooms").get();
      const results = [];

      for (const email of cleaned) {
        let uid = null;
        try {
          uid = (await auth.getUserByEmail(email)).uid;
        } catch (_) {
          results.push({ email, status: "not_found" });
          continue;
        }
        const { messagesDeleted, roomsDeleted } = await purgeUser(uid, roomsSnap);

        results.push({
          email,
          uid,
          status: "deleted",
          messagesDeleted,
          roomsDeleted,
        });
      }
      return res.status(200).json({ ok: true, results });
    } catch (e) {
      console.error("deleteUserAccount failed:", e);
      return res.status(500).json({ error: e.message || String(e) });
    }
  }
);

// ---- Admin: create a pre-verified account (e.g. for Play Store review) ---
// Because email/password sign-ups must verify their email before entering,
// Google's reviewers (who can't open our inbox) need an account that is ALREADY
// verified. This creates one with emailVerified=true so they can log straight in.
// Guarded by the shared secret.
//
//   POST https://asia-south1-arena-a049d.cloudfunctions.net/createVerifiedUser
//   Header:  x-arena-key: <BROADCAST_SECRET>
//   Body:    { "email": "...", "password": "...", "name": "Reviewer" }
exports.createVerifiedUser = onRequest(
  { region: "asia-south1", secrets: [broadcastSecret] },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Use POST" });
    }
    const expected = broadcastSecret.value();
    const key = req.get("x-arena-key") || req.query.key;
    if (!expected || key !== expected) {
      return res.status(401).json({ error: "Unauthorized — wrong or missing key" });
    }
    const b = (req.body && typeof req.body === "object") ? req.body : {};
    const email = String(b.email || "").trim();
    const password = String(b.password || "");
    const name = String(b.name || "Reviewer").trim() || "Reviewer";
    if (!email.includes("@") || password.length < 6) {
      return res.status(400).json({ error: "Provide a valid email and a 6+ char password" });
    }
    try {
      const auth = getAuth();
      let user;
      try {
        user = await auth.createUser({
          email, password, displayName: name, emailVerified: true,
        });
      } catch (e) {
        // Already exists → make sure it's verified and reset its password/name.
        if (e && e.code === "auth/email-already-exists") {
          const existing = await auth.getUserByEmail(email);
          user = await auth.updateUser(existing.uid, {
            password, displayName: name, emailVerified: true,
          });
        } else {
          throw e;
        }
      }
      // Give them a profile doc too, like a normal signup.
      await getFirestore().collection("users").doc(user.uid).set({
        displayName: name, email, createdAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      return res.status(200).json({
        ok: true, uid: user.uid, email, emailVerified: true,
      });
    } catch (e) {
      console.error("createVerifiedUser failed:", e);
      return res.status(500).json({ error: e.message || String(e) });
    }
  }
);

// ---- Admin: manage users (call from Admin app) ---------------------------
// One endpoint, several actions, all guarded by the shared secret:
//
//   POST https://asia-south1-arena-a049d.cloudfunctions.net/adminUsers
//   Header:  x-arena-key: <BROADCAST_SECRET>
//   Body:    { "action": "...", ... }
//
//   list                                  → every user (name, email, status)
//   messages      { uid }                 → that user's recent messages
//   notify        { uid | uids | all:true, title, body } → push to one user,
//                                           selected users, or everyone
//   ban           { uid, reason? }        → block from logging in and posting
//   unban         { uid }
//   deleteMessage { roomId, messageId }   → remove a message (+ its reports)
//   dismissReport { messageId }           → clear reports, keep the message
//   rooms                                 → every room, latest activity first
//   roomMessages  { roomId }              → a room's latest 300 messages
//
// A ban disables the login account, signs them out everywhere, and writes
// banned/{uid}, which firestore.rules checks so they can't post even with a
// still-valid session token.
exports.adminUsers = onRequest(
  { region: "asia-south1", secrets: [broadcastSecret] },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Use POST" });
    }
    const expected = broadcastSecret.value();
    const key = req.get("x-arena-key") || req.query.key;
    if (!expected || key !== expected) {
      return res.status(401).json({ error: "Unauthorized — wrong or missing key" });
    }
    const b = (req.body && typeof req.body === "object") ? req.body : {};
    const action = String(b.action || "");
    const uid = String(b.uid || "").trim();
    const db = getFirestore();
    const auth = getAuth();
    const needUid = () => {
      if (!uid) throw Object.assign(new Error("Provide a uid"), { status: 400 });
    };

    try {
      switch (action) {
        case "list": {
          const banned = new Set(
            (await db.collection("banned").get()).docs.map((d) => d.id));
          const profiles = {};
          (await db.collection("users").get()).docs.forEach((d) => {
            profiles[d.id] = d.data() || {};
          });
          const users = [];
          let pageToken;
          do {
            const page = await auth.listUsers(1000, pageToken);
            for (const u of page.users) {
              const p = profiles[u.uid] || {};
              users.push({
                uid: u.uid,
                email: u.email || "",
                name: p.displayName || u.displayName || "",
                avatar: p.avatar || "",
                provider: (u.providerData[0] || {}).providerId || "",
                emailVerified: !!u.emailVerified,
                disabled: !!u.disabled,
                banned: banned.has(u.uid),
                createdAt: Date.parse(u.metadata.creationTime) || 0,
                lastLogin: Date.parse(u.metadata.lastSignInTime) || 0,
              });
            }
            pageToken = page.pageToken;
          } while (pageToken);
          users.sort((a, c) => c.lastLogin - a.lastLogin);
          return res.status(200).json({ ok: true, count: users.length, users });
        }

        case "messages": {
          needUid();
          const rooms = await db.collection("rooms").get();
          const out = [];
          for (const r of rooms.docs) {
            const msgs = await r.ref.collection("messages")
              .where("senderId", "==", uid).get();
            msgs.forEach((m) => {
              const d = m.data() || {};
              out.push({
                roomId: r.id,
                roomName: (r.data() || {}).name || "",
                messageId: m.id,
                text: d.text || "",
                stance: d.stance || "",
                createdAt: d.createdAt ? d.createdAt.toMillis() : 0,
              });
            });
          }
          out.sort((a, c) => c.createdAt - a.createdAt);
          return res.status(200).json({ ok: true, count: out.length, messages: out.slice(0, 100) });
        }

        case "notify": {
          // One user (uid), several (uids: [...]), or everyone (all: true).
          const title = String(b.title || "Arena").slice(0, 80);
          const body = String(b.body || "").trim().slice(0, 300);
          if (!body) return res.status(400).json({ error: "Provide a message" });
          const payload = {
            notification: { title, body },
            data: { type: "broadcast" },
            android: { priority: "high", notification: { channelId: "broadcast" } },
          };
          if (b.all === true) {
            await getMessaging().send({ topic: ALL_USERS_TOPIC, ...payload });
            return res.status(200).json({ ok: true, notified: "all" });
          }
          const uids = (Array.isArray(b.uids) ? b.uids : [uid])
            .map((x) => String(x || "").trim()).filter(Boolean);
          if (uids.length === 0) return res.status(400).json({ error: "Provide uids" });
          let sent = 0;
          const failed = [];
          for (const u of uids) {
            try {
              await getMessaging().send({ topic: userTopicFor(u), ...payload });
              sent++;
            } catch (e) {
              failed.push(u);
            }
          }
          return res.status(200).json({ ok: true, sent, failed });
        }

        case "ban": {
          needUid();
          const reason = String(b.reason || "").slice(0, 300);
          await db.collection("banned").doc(uid).set({
            reason, bannedAt: FieldValue.serverTimestamp(),
          });
          await auth.updateUser(uid, { disabled: true });
          await auth.revokeRefreshTokens(uid);
          return res.status(200).json({ ok: true, banned: uid });
        }

        case "unban": {
          needUid();
          await db.collection("banned").doc(uid).delete();
          await auth.updateUser(uid, { disabled: false });
          return res.status(200).json({ ok: true, unbanned: uid });
        }

        case "deleteMessage": {
          const roomId = String(b.roomId || "").trim();
          const messageId = String(b.messageId || "").trim();
          if (!roomId || !messageId) {
            return res.status(400).json({ error: "Provide roomId and messageId" });
          }
          await db.collection("rooms").doc(roomId)
            .collection("messages").doc(messageId).delete();
          const reps = await db.collection("reports")
            .where("messageId", "==", messageId).get();
          for (const d of reps.docs) await d.ref.delete();
          return res.status(200).json({ ok: true, deleted: messageId });
        }

        case "dismissReport": {
          const messageId = String(b.messageId || "").trim();
          if (!messageId) return res.status(400).json({ error: "Provide a messageId" });
          const reps = await db.collection("reports")
            .where("messageId", "==", messageId).get();
          for (const d of reps.docs) await d.ref.delete();
          return res.status(200).json({ ok: true, dismissed: reps.size });
        }

        case "rooms": {
          const rooms = await db.collection("rooms").get();
          const out = await Promise.all(rooms.docs.map(async (r) => {
            const d = r.data() || {};
            let messageCount = 0;
            try {
              messageCount = (await r.ref.collection("messages").count().get())
                .data().count;
            } catch (_) {/* leave 0 */}
            const ms = (t) => (t && t.toMillis ? t.toMillis() : 0);
            return {
              roomId: r.id,
              name: d.name || "",
              topic: d.topic || "",
              category: d.category || "",
              isPrivate: !!d.isPrivate,
              isDaily: !!d.isDaily,
              isBroadcast: !!d.isBroadcast,
              createdBy: d.createdBy || "",
              createdByName: d.createdByName || "",
              createdAt: ms(d.createdAt),
              lastActivity: ms(d.lastActivity) || ms(d.createdAt),
              messageCount,
            };
          }));
          out.sort((a, c) => c.lastActivity - a.lastActivity);
          return res.status(200).json({ ok: true, count: out.length, rooms: out });
        }

        case "roomMessages": {
          const roomId = String(b.roomId || "").trim();
          if (!roomId) return res.status(400).json({ error: "Provide a roomId" });
          const snap = await db.collection("rooms").doc(roomId)
            .collection("messages").orderBy("createdAt", "desc").limit(300).get();
          const messages = snap.docs.map((m) => {
            const d = m.data() || {};
            return {
              messageId: m.id,
              text: d.text || "",
              senderId: d.senderId || "",
              senderName: d.senderName || "",
              stance: d.stance || "",
              createdAt: d.createdAt ? d.createdAt.toMillis() : 0,
            };
          });
          return res.status(200).json({ ok: true, count: messages.length, messages });
        }

        default:
          return res.status(400).json({ error: "Unknown action: " + action });
      }
    } catch (e) {
      console.error("adminUsers failed:", action, e);
      return res.status(e.status || 500).json({ error: e.message || String(e) });
    }
  }
);
