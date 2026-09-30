# 📝 Changelog - Arena

All notable changes to Arena will be documented in this file.

## [1.13.0] - September 30, 2026

Everything in this release comes from the Testers Community feedback report.
That report found **no crashes and no bugs** — all four items were "opportunities
for enhancement", so nothing existing was changed except the one unfinished
share button noted below.

### ✨ Added
- **Settings screen** (account menu → **Settings**). A new home for the things
  that aren't profile or account: rate, share, replay the walkthrough, and the
  Terms / Privacy documents (previously only reachable from the login screen).
- **"Rate Arena"** (`services/review_service.dart`, `in_app_review`). Two ways
  in: the Settings button always opens the Play Store listing, and after the
  user has come out of **5** debate rooms the app shows Google's native in-app
  review sheet **once**, ever. The counter lives in `SharedPreferences`; Google
  rate-limits the sheet itself, so there is no way for this to nag.
- **"Share Arena"** (`services/share_service.dart`, `share_plus`). Opens the
  phone's normal share sheet with an invite and the Play Store link, so users
  can pull friends in over WhatsApp, SMS, email or anything else installed.
- **New-user walkthrough** (`screens/onboarding_screen.dart`). Four slides —
  what Arena is, picking a side, debating live, voting on who won — shown once
  per phone on first launch, with **Skip** always visible. Replayable any time
  from Settings. It is pushed from the rooms list after the first frame, so it
  cannot interfere with the login / verify-email routing in `main.dart`.
- **Real tests.** `test/` now covers the walkthrough slides, the Skip and
  finish paths, the once-per-run guard, and the Settings rows (9 tests).

### 🐛 Fixed
- **Room sharing actually shares now.** The WhatsApp / Email / More buttons in
  a room's share dialog had a `TODO` and only copied text to the clipboard.
  They now open the real share sheet, and fall back to copying (with a clearer
  message) if the sheet can't be opened. The Copy buttons are untouched.

### 📄 Changed (store, not app)
- **`playstore/STORE_LISTING.md` rewritten for ASO.** The full description grew
  from ~1,900 to ~3,000 of the 4,000 allowed characters and now works the real
  search terms (debate app, discussion, argue, live chat rooms, current events)
  into natural sentences, plus a short-description rewrite and a maintenance
  checklist. No keyword stuffing — that breaks Play policy.

### ⚠️ Open question (not changed — needs your decision)
- **Minimum age disagrees between places.** The in-app Terms of Service
  (`screens/legal_screen.dart`) still says **13+**, while the sign-up checkbox
  and the store listing say **18+**. The Terms, the listing and the Play
  content-rating questionnaire should all say the same thing.
- **Version bumped to `1.0.1+3`** (versionName 1.0.1, versionCode 3) so this
  can be uploaded to Play. Bump `+N` again on every subsequent upload.

## [1.12.0] - July 15, 2026

### 🎨 Added (branding / Play Store prep)
- **New app icon + branding.** Adopted the Arena logo — a split blue/orange
  colosseum with a bold "A" and two figures facing off inside. Updated the
  in-app launcher icon at every density (mdpi→xxxhdpi) and produced the Play
  Store assets (512 icon, 1024×500 feature graphic, store listing text) under
  `playstore/`.
- **18+ confirmation on sign-up.** The Terms checkbox now also confirms the user
  is 18 or older (Arena is an adults-only open-debate app); the privacy policy's
  age section was updated to match.

## [1.11.0] - July 14, 2026

### 📦 Changed (package rename — Play Store prep)
- **App package renamed `com.arena.arena` → `com.cryptork.arena`.** `com.arena.arena`
  was already taken on Google Play, so the store identity moves to
  `com.cryptork.arena` (namespace, applicationId and MainActivity all updated). A
  new Android app was registered in Firebase (`arena-a049d`) for the new package
  with this machine's debug SHA-1 + SHA-256, and a fresh `google-services.json`
  was swapped in so Google Sign-In and messaging keep working.

### 🔒 Added (account security)
- **Email verification is now required.** Email/password sign-ups must click the
  link in their inbox before they can enter Arena (new `VerifyEmailScreen` gate,
  wired in `main.dart` and the login screen). This blocks fake/throwaway
  addresses and makes ban-evasion harder. Google Sign-In accounts are already
  verified and pass straight through. The gate re-checks on resume and continues
  automatically once the link is tapped.

### ✨ Added
- **"Reset password" popup dialog.** "Forgot password?" now opens a small dialog
  (on the login screen) with its own email field, instead of showing a red error
  on the login email box. Any email already typed is pre-filled; otherwise the
  user types it right there — so the reset flow is never blocked by an empty
  field. Sends the reset link and confirms with a snackbar.
- **Message counts on rooms.** Every room now tracks a running `messageCount`
  (incremented in the send batch) and shows "💬 N messages" on the room cards in
  both the rooms list and Discover — a curiosity hook toward busy debates.

### 🔧 Changed
- **Sign-up screen no longer shows the avatar picker.** New accounts get a random
  avatar automatically; users change it inside the app (Profile & avatar). Keeps
  the sign-up form short and focused.
- **Room creators pick their side on creation.** Creating a room now asks the
  creator For/Against/Watching so they enter ready to argue instead of stuck on
  "just watching"; the choice is remembered like any other room.

## [1.10.5] - July 13, 2026

### 🐛 Fixed
- **Room no longer flips to "choose your side" (watcher mode).** Tapping a
  notification for a room you're already in stacked a fresh watcher-mode chat
  screen on top. Now `_openRoom` skips re-opening the room you're viewing and
  restores your saved stance for that room.
- **Keyboard no longer pops back up** after opening a message's long-press menu
  and pressing back — opening the menu now drops the input focus.

### ✨ Added (admin/moderation)
- **`reportedMessages` Cloud Function** — aggregates the existing `reports`
  collection by message and returns messages flagged by **2+ distinct users**,
  for review in the Admin app. (Users could already report messages; this adds
  the admin view. Reports are private to the admin — no external/legal action.)

## [1.10.4] - July 13, 2026

### 🔧 Changed
- **Login-first welcome screen** — the auth screen now opens on the **Log in**
  form by default (with a "New here? Create an account" link) instead of opening
  on sign-up. Sign-up is one tap away via the toggle. (`startInSignUp` now
  defaults to false.)

### ✅ Verified
- Confirmed message avatars: a sender who picked an emoji avatar shows that emoji
  next to their messages (denormalized `senderAvatar` → `UserAvatar`); users with
  no avatar fall back to their name's initial. (Own messages show no avatar by
  design; pre-feature messages show the initial.)

## [1.10.3] - July 13, 2026

### 🔧 Changed
- **Moved the admin "push trending topic" box out of the app.** The admin-only
  card on the home screen (set the topic-of-the-day override) is **removed** —
  regular users never saw it anyway, and it now lives in the separate **Admin
  app**. Added a secret-guarded `setDailyTopic` Cloud Function that writes
  `config/dailyOverride`; the Admin app calls it. The app still *reads* the
  override for its daily push (unchanged for users).

## [1.10.2] - July 13, 2026

### 🧹 Added (admin)
- **"Clear all rooms" API** — new `clearAllRooms` HTTP Cloud Function (Postman)
  recursively deletes every room and all their messages/votes on demand (user
  accounts and config are untouched). Guarded by the `x-arena-key` secret AND an
  explicit `{"confirm":"DELETE ALL ROOMS"}` body so it can't fire by accident.
  Server-only — no app change. See `NOTIFICATIONS_SETUP.md`.

## [1.10.1] - July 13, 2026

### 🔒 Security
- **Private rooms are now actually password-gated.** Joining a private room by
  code prompts for the password and verifies it via the `verifyRoomPassword`
  Cloud Function (salted hash in the unreadable `rooms/{id}/secure/auth` subdoc).
  New private rooms no longer store any hash on the readable room doc. Added the
  `cloud_functions` package. (Members/creators who open a room they've already
  joined aren't re-prompted; outsiders joining by code are.)

## [1.10.0] - July 13, 2026

### ✨ Added
- **"Who won?" voting** — every debate room now has a live *Who's winning?*
  panel. Anyone watching can vote For or Against; a split bar shows the running
  tally in real time. One vote per user (tap your side again to undo). Stored in
  a `rooms/{id}/votes/{uid}` subcollection.
- **Profanity warning before sending** — if a message contains vulgar/abusive
  language, a confirmation dialog warns the sender it could get them banned or
  into real/legal trouble, and asks them to confirm before it sends. Client-side
  check (a warning, not censorship) in `data/profanity.dart`.

### 🔒 Security & infrastructure
- **Private-room passwords verified server-side** — new `verifyRoomPassword`
  callable Cloud Function checks a salted hash held in an unreadable
  `rooms/{id}/secure/auth` subdoc (rules block all client reads). The function
  is deployed and ready; the app's join-flow wiring lands in a follow-up.
- **Stale-room cleanup** — new daily `cleanupStaleRooms` scheduled function
  deletes empty rooms with no activity for 7+ days (rooms with any message are
  always kept), so abandoned daily/broadcast rooms don't pile up.
- **Cloud Functions upgraded to Node.js 22** (Node 20 is decommissioned
  2026-10-30).
- Firestore rules: added the protected `secure/*` subdoc and the `votes/*`
  subcollection (read the tally, write only your own vote). Existing anti-spoof
  rules (post only as yourself, messages can only edit reactions) were already in
  place.

## [1.9.0] - July 12, 2026

### ✨ Added
- **Emoji avatars (profile pictures)** — users now pick an avatar from a set of
  24 emoji (drawn on coloured circles, no image files / storage cost). Choose one
  at **sign-up**, and change it anytime from **Profile & avatar** in the account
  menu. Avatars appear next to the sender's name on every message.
  - Stored on the profile (Firebase Auth `photoURL` + `users/{uid}.avatar`) and
    **denormalized** onto each message (`senderAvatar`) so the chat renders with
    no extra reads — same pattern as `senderName`.
  - If a user hasn't picked one, their avatar falls back to the first letter of
    their name on a colour derived from it.
  - New reusable pieces: `data/avatars.dart`, `widgets/user_avatar.dart`,
    `widgets/avatar_picker.dart`, `screens/profile_screen.dart`.

## [1.8.0] - July 12, 2026

### ✨ Added
- **Admin broadcast topic (Postman API)** — a new HTTP Cloud Function,
  `broadcastTopic`, lets the admin push a brand-new debate to **every user at
  once** by POSTing a single sentence from Postman (or any HTTP client). It
  creates a fresh public room for that sentence and sends one notification to
  the app-wide `all_users` topic. Guarded by a shared secret (`x-arena-key`
  header) so only the admin can fire it. New **"New debates"** notification
  channel (`broadcast`).
- **Tap-to-open a room from a notification** — tapping any push now opens the
  room it points at, in all app states: launched from cold start
  (`getInitialMessage`), from the background (`onMessageOpenedApp`), and from a
  foreground notification (payload-carried roomId). Previously taps did nothing.
  This also improves the existing reply/trending/room-message pushes.
- Every device now subscribes to the `all_users` topic at startup
  (`RoomNotifyService.subscribeAll`) so broadcasts reach everyone.

### ⚠️ Requires (one-time)
- **Set the broadcast secret** (`firebase functions:secrets:set BROADCAST_SECRET`
  — kept in Secret Manager, never in this public repo), **redeploy the Cloud
  Function** (`firebase deploy --only functions`) to publish the new
  `broadcastTopic` endpoint, and rebuild the app so phones subscribe to
  `all_users` and handle notification taps. See `NOTIFICATIONS_SETUP.md` →
  "Admin broadcast topic (Postman)".

## [1.7.0] - July 5, 2026

### ✨ Added
- **Trending-debate notifications** — when a debate you took part in suddenly
  heats up (a burst of ~20+ messages within 30 min), everyone who joined that
  room gets a catchy "🔥 your debate is on fire — jump back in!" push to pull
  them back, even without the 🔔 bell. Powered by the Cloud Function with a
  3-hour per-room cooldown; new **"Trending debates"** notification channel;
  suppressed while you're already in that room. Each device follows a
  `room_participants_<roomId>` topic when it opens a room.
- **Admin "push trending topic"** — signed in as the admin
  (`cryptork97@gmail.com`), the rooms list shows a box to type a topic + a "use
  default push time (9 AM)" toggle (or pick a custom time) + Push. It queues that
  topic to **override the next daily topic** for everyone (stored at
  `config/dailyOverride`); each phone reads it and swaps that day's push. No
  admin topic set → the usual hardcoded topic is used.

### ⚠️ Requires (one-time on Windows)
- **Redeploy the Cloud Function** (`firebase deploy --only functions`) for the
  trending push, and **publish the updated `firestore.rules`** (adds the
  `config/*` rule) in the Firebase console. See `NOTIFICATIONS_SETUP.md`.

## [1.6.0] - July 4, 2026

### ✨ Added
- **Reply notifications** — when someone **replies to your message** in a room,
  you get a notification ("<name> replied to you"), even when the app is closed
  and **even if you don't follow that room**. Delivered by the same Cloud
  Function, targeted to you personally.
  - How it works: each signed-in device subscribes to a personal push topic
    (`user_<uid>`); reply messages now store the quoted author's uid
    (`replyToSenderId`); the Cloud Function pushes to that user's topic on a
    reply. A new **"Replies to you"** notification channel keeps them separate
    from room-follow alerts. You never get notified for replying to yourself.
  - ⚠️ **Requires a redeploy** of the Cloud Function (`firebase deploy --only
    functions`) and a rebuilt app — see `NOTIFICATIONS_SETUP.md` → "Updating".

## [1.5.0] - July 3, 2026

### ✨ Added
- **Forgot password** — a "Forgot password?" link on the login screen emails a
  reset link.
- **Change password** in-app — the account menu (top-right) has "Change
  password" for email/password accounts (re-authenticates, then updates).
- **Chat colour-coding by side** — For (support) messages are **green**, Against
  (oppose) are **red**, for everyone, so sides are visible at a glance.
- **Message pagination** — chat loads only the latest ~30 messages plus a "Load
  earlier messages" button, keeping Firestore reads (and cost) low in busy rooms.
- **(Dev only) Admin quick-login** — a one-tap login button that appears ONLY in
  builds made with `--dart-define ADMIN_EMAIL/ADMIN_PASSWORD`. Public builds omit
  the defines, so it's never shipped and no credentials are compiled in.

### ✨ Improved
- **Login layout** — "Continue with Google" now sits above the Create-account
  button (not after it); the Terms checkbox is above both and shows only on
  signup.
- **Password show/hide** eye on the password field.
- **Auth error messages show in full** (no longer cut off after one line).
- **Verify-email banner clears automatically** once the email is verified (the
  home screen re-checks on resume).
- **"Check your spam/junk folder"** added to the verification + reset messages.
- **After logout you land on the Login view** (not Create account).
- **The two auth buttons load independently** — tapping Create/Log-in no longer
  also spins the Google button, and vice-versa.

### 🐞 Fixed
- **"Just watching" bar** was rendering as vertical text — rebuilt as a robust
  full-width bar.
- **Email/password login hang** — sign-in would spin forever. Cause: builds used
  a stale `google-services.json` after a signing fingerprint was added. Fixed by
  re-pulling the live config (`firebase apps:sdkconfig`) and rebuilding. Google
  sign-in works once the app's SHA-1/SHA-256 are registered in Firebase.

### 🚀 Ops
- Per-room notifications are **deployed and live** (Cloud Function
  `notifyRoomOnNewMessage`, region asia-south1) on the **Blaze** plan (free at
  current scale; a cleanup policy keeps container storage from accruing cost).

## [1.4.0] - July 1, 2026

### ✨ Added
- **Per-room notifications (🔔).** Each debate room now has a bell in its top
  bar (default OFF). Turn it on to get a notification for every new message in
  that room — even when the app is closed. Delivery is powered by a new Firebase
  Cloud Function (`functions/`) that pushes to everyone subscribed to the room's
  FCM topic. Requires a one-time deploy on the Blaze plan — see
  `NOTIFICATIONS_SETUP.md`.

### ✨ Improved
- **Terms & Conditions are only required when creating an account**, not when
  logging in (email or Google).
- **"Just watching" users can no longer type.** The message box is replaced by a
  "Pick a side to join in" prompt until they choose For or Against.
- **Swipe a message left or right to reply** to it (long-press still opens the
  full reply / react / report / block menu).

## [1.3.0] - June 29, 2026

### ✨ Added
- **Remove a room from your own list without deleting it.** Long-press a room
  in **My Rooms** → "Remove from my list" — it disappears from your list but
  the room keeps existing so anyone still chatting there is unaffected. Long-
  press in **Visited** to remove it from your history. Both have an Undo.

### 🔐 Fixed
- **Terms & Conditions are now enforced for Google sign-in too** — the
  "Continue with Google" button stays disabled until the agreement box is
  ticked (matches Create account).

## [1.2.0] - June 29, 2026

### ✨ Improved
- **Your side is remembered per room.** You're asked which side you're on only
  the **first** time you enter a room. After that it defaults to the side you
  chose. You can switch sides anytime with the **⇄ (For/Against/Watching)**
  button in the room's top bar — your new choice is remembered too.
- **Logout now asks for confirmation** ("Log out? Cancel / Log out") so you
  don't get signed out by an accidental tap.
- **Auto-capitalised first letter** on name fields (display name, room name)
  and the debate topic, so entries start with a capital by default. Email and
  password are left untouched.

## [1.1.0] - June 29, 2026

### 🐞 Fixed
- **Your side is now locked once you enter a room.** Before, the For/Against
  chips in the message bar could still be tapped to switch sides mid-debate.
  Now the side you pick when joining is shown as a read-only badge (🔒 Arguing:
  For / Against / Just watching) and can't be changed.
- **Rooms joined by code/link now appear under "Visited."** Entering a room via
  Join by Code now also asks your side and records the room in your history,
  just like every other way of opening a room.

## [1.0.9] - June 29, 2026

### ✨ Improved
- **Topics rewritten in plain, simple words** so anyone can understand and join
  in, whatever their reading level (e.g. "Should there be term limits for
  judges?" → "Should judges be made to leave their job after some years,
  instead of staying for life?"). Still 365, one per day for a full year.
- **"Visited" rooms history:** the home toggle's "Joined" tab is now **Visited**
  and records *every* room you open — including the daily Topic of the Day —
  most recent first, kept separate from the rooms you created ("My Rooms"). So
  you have a real history of rooms you've been in.

## [1.0.8] - June 29, 2026

### ✨ Added
- **365 daily debate topics** (up from ~44): a full year of provocative,
  reply-tempting questions — dilemmas, paradoxes and classic debates across
  Science, Religion/Philosophy, Movies, Politics, Sports, Technology, History
  and "Other" (ethics dilemmas + harmless conspiracy prompts). Topics now go a
  whole year before any repeat. Still chosen deterministically from the date,
  so every phone shows the same topic each day with no server.

## [1.0.7] - June 29, 2026

### ✨ Added
- **Terms & Conditions agreement:** account creation now requires ticking an
  "I agree to the Terms of Service and Privacy Policy" checkbox. **Create
  account** and **Continue with Google** stay disabled until it's checked.
- New in-app **Terms of Service** and **Privacy Policy** pages (tappable links
  on the checkbox). Verified on device: links open the legal pages, ticking the
  box enables the buttons.

## [1.0.6] - June 29, 2026

### ✨ Added
- **Continue with Google** sign-in (real Google account → Firebase), alongside
  email/password.

## [1.0.5] - June 29, 2026

### ✨ Added
- **Reply to a message:** long-press any message → Reply. A quoted preview of
  the original (sender + text) sits above your input while composing and is
  shown at the top of the sent message, so rebuttals are easy to follow.

## [1.0.4] - June 29, 2026

### ✨ Added / improved
- **Login error validation:** wrong/invalid email now highlights the **email**
  field ("Incorrect email address."), wrong password highlights the
  **password** field ("Incorrect password.") — instead of always blaming the
  password.
- **Pick your side before joining:** tapping a room now prompts Support / Oppose
  (or "just watching") and drops you in with that stance preselected.
- **Private group clarity:** private rooms show a clear notice on the card
  ("you'll need the group password — contact the admin") before you tap in.
- **Joined rooms:** new **My Rooms / Joined** toggle on the home screen; rooms
  you join are remembered so you can jump back in.
- **Message reactions:** react to messages with 👍 ❤️ 😂 👏 🔥, with live
  per-emoji counts; add/change/remove updates in real time.
- **Email verification:** sign-up now sends a verification link, with a
  "verify your email" banner + Resend on the home screen.

### 🔐 Firestore rules
- Messages may now be updated **only** to change the `reactions` map (text is
  still immutable). **Re-publish `firestore.rules`** for reactions to work.

## [1.0.3] - June 29, 2026

### 🐞 Fixed
- **Share Room dialog** showed empty Room ID and Share Link fields (and the
  Copy buttons were missing). Rebuilt the value rows as a full-width Column
  with `SelectableText` + a Copy button below each, so the room ID and link
  always render. Verified on device.
- `firestore.rules`: added owner-only access to `users/{uid}/**` so PetBloom
  (same Firebase project) can store per-user data without affecting Arena.

## [1.0.2] - June 28, 2026

### ✨ Fixed
- **Room Filtering Logic**
  - Home screen: Now shows ONLY rooms created by current user
  - Discovery: Shows rooms created by OTHERS only
  - Users no longer see duplicate rooms in both screens
- **Empty State Messages**
  - Updated to reflect new filtering logic
  - Clearer instructions for users

### 📦 Updated
- room_service.dart: Added `watchMyRooms()` method
- rooms_list_screen.dart: Uses user-specific room stream
- room_discovery_screen.dart: Filters out user's own rooms

---

## [1.0.1] - June 28, 2026

### ✨ Added
- **Room Discovery Screen**
  - Browse all public rooms from other users
  - Real-time room list with search
  - Category filtering
  - Trending rooms (active in last 24 hours)

- **Room Sharing System**
  - Unique Room ID generation (format: `debate-abc123`)
  - Shareable deep links: `https://arena.app/room/{roomId}`
  - Copy-to-clipboard for both ID and link
  - Share buttons for WhatsApp, Email, More

- **Join by Code**
  - Paste room ID to join
  - Paste full link to extract and join
  - Auto-detects link format
  - Error handling for invalid codes

- **Deep Linking Support**
  - `arena.app/room/{roomId}` opens app directly
  - Falls back to Play Store if app not installed
  - Automatic room joining on successful open

### 🎨 UI/UX
- New Discover button (search icon) in AppBar
- Room discovery screen with category filter
- Join by code screen with paste functionality
- Share dialog with multiple share options
- Color-coded room categories

### 📦 Created
- room_discovery_screen.dart: Room browsing & search
- room_share_dialog.dart: Room sharing with ID & link
- join_by_code_screen.dart: Code-based room joining

---

## [1.0.0] - June 28, 2026

### ✨ Initial Release

**Core Features**
- User authentication (name sign-in)
- Live debate rooms (public & private)
- Real-time chat with Firestore
- For/Against stance selection
- Topic of the Day feature
- Category organization
- User blocking (local via shared_preferences)
- Message moderation & deletion
- Report functionality
- Daily 9 AM notifications
- Search & category filters

**Technical**
- Flutter 3.44.4
- Firebase (Firestore, Auth, Cloud Messaging)
- flutter_local_notifications for system alerts
- timezone support for scheduling
- Dart 3.12.2

## 🔜 Upcoming Features

### [1.1.0] - Planned
- Google & phone number authentication
- Server-side push notifications via Firebase Cloud Messaging
- Admin panel for managing reported content
- Enhanced user profiles
- User reputation/rating system
- Advanced room analytics

### [2.0.0] - Future
- Audio debate rooms
- Video debate streaming
- Live debate scheduling
- AI-powered moderation
- Community leaderboards
- Debate analytics & insights
- Debate tournament system

---

## 📊 Version History Summary

| Version | Date | Highlights |
|---------|------|-----------|
| 1.0.2 | Jun 28, 2026 | Fixed room filtering (home vs discovery) |
| 1.0.1 | Jun 28, 2026 | Added room discovery, sharing, deep linking |
| 1.0.0 | Jun 28, 2026 | Initial release with core debate features |

---

**Note**: This changelog tracks major changes. See git commit history for detailed technical changes.
