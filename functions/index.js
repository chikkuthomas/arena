// Arena Cloud Function.
//
// Whenever a new message is written to a room, push a notification to everyone
// who turned on notifications for that room (they are subscribed to the room's
// Firebase Cloud Messaging "topic"). This is what makes room notifications
// arrive even when the app is closed.
//
// Deploy with:  firebase deploy --only functions
// (Requires the Firebase project to be on the Blaze plan.)

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
        await getMessaging().send({
          topic: participantsTopicFor(roomId),
          notification: { title: roomName, body: '"' + roomName + '" ' + line },
          data: { roomId: roomId, type: "trending" },
          android: {
            priority: "high",
            notification: { channelId: "trending" },
          },
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
        .filter((e) => e.reporters.size >= 2)
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

// ---- Admin: delete user accounts + all their data (call from Admin app) --
// For each email: removes the Firebase Auth account AND everything they own —
// their profile (users/{uid} + subcollections), every message they posted, any
// rooms they created (recursively), their votes, and reports they filed.
// Irreversible. Guarded by the shared secret AND an explicit confirm token.
//
//   POST https://asia-south1-arena-a049d.cloudfunctions.net/deleteUserAccount
//   Header:  x-arena-key: <BROADCAST_SECRET>
//   Body:    { "emails": ["a@x.com", "b@y.com"], "confirm": "DELETE USERS" }
exports.deleteUserAccount = onRequest(
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
        let messagesDeleted = 0;
        let roomsDeleted = 0;

        // Reports they filed.
        const reps = await db
          .collection("reports")
          .where("reporterId", "==", uid)
          .get();
        for (const d of reps.docs) await d.ref.delete();

        // Walk every room: delete rooms they created outright, otherwise strip
        // their messages and their vote from that room.
        for (const roomDoc of roomsSnap.docs) {
          const roomRef = roomDoc.ref;
          if ((roomDoc.data() || {}).createdBy === uid) {
            await db.recursiveDelete(roomRef);
            roomsDeleted++;
            continue;
          }
          const msgs = await roomRef
            .collection("messages")
            .where("senderId", "==", uid)
            .get();
          for (const m of msgs.docs) {
            await m.ref.delete();
            messagesDeleted++;
          }
          await roomRef.collection("votes").doc(uid).delete();
        }

        // Their profile doc + subcollections (joinedRooms, hiddenRooms, pets…).
        await db.recursiveDelete(db.collection("users").doc(uid));
        // Finally the login account itself.
        await auth.deleteUser(uid);

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
