import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/daily_topics.dart';
import '../models/message.dart';
import '../models/room.dart';
import '../services/auth_service.dart';
import '../services/daily_override_service.dart';
import '../services/daily_topic_service.dart';
import '../services/onboarding_service.dart';
import '../services/review_service.dart';
import '../services/room_service.dart';
import '../theme.dart';
import '../widgets/join_stance_dialog.dart';
import '../widgets/room_card.dart';
import '../widgets/user_avatar.dart';
import 'chat_room_screen.dart';
import 'create_room_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'profile_screen.dart';
import 'room_discovery_screen.dart';
import 'settings_screen.dart';

/// The home screen: today's featured topic, a search box, category filters, and
/// the live list of every debate room.
class RoomsListScreen extends StatefulWidget {
  const RoomsListScreen({super.key});

  @override
  State<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends State<RoomsListScreen>
    with WidgetsBindingObserver {
  final _rooms = RoomService();
  final _auth = AuthService();
  final _daily = DailyTopicService();
  final _searchController = TextEditingController();

  String _query = '';
  String? _category; // null = all categories
  bool _openingDaily = false;
  bool _showJoined = false; // false = rooms I created, true = rooms I joined
  bool _hideVerifyBanner = false;

  Set<String> _hidden = {}; // rooms the user removed from their own list
  StreamSubscription<Set<String>>? _hiddenSub;

  DailyTopic? _todayOverride; // admin override for today's topic, if any

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _hiddenSub = _rooms.watchHiddenRoomIds(uid).listen((ids) {
        if (mounted) setState(() => _hidden = ids);
      });
    }
    // Check whether they've verified their email since the app was opened.
    _refreshVerification();
    _loadTodayOverride();
    _maybeShowOnboarding();
  }

  /// First launch on this phone? Show the walkthrough once. Runs after the
  /// first frame so the rooms list is already built underneath it, and is
  /// wrapped so a storage hiccup can never block the app.
  Future<void> _maybeShowOnboarding() async {
    try {
      if (!await OnboardingService.shouldOffer()) return;
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      });
    } catch (_) {/* never block the rooms list */}
  }

  /// Called when the user comes back from a debate room. Coming out of a room
  /// is the natural moment to ask for a rating — they've just used the app for
  /// real. [ReviewService] only ever asks once, and only after a few visits.
  Future<void> _afterRoomVisit() async {
    await ReviewService.recordEngagement();
    await ReviewService.maybePrompt();
  }

  /// If an admin has set today's topic, show that on the featured card.
  Future<void> _loadTodayOverride() async {
    final o = await DailyOverrideService.get();
    if (o != null && o.appliesTo(DateTime.now()) && mounted) {
      setState(() => _todayOverride = DailyTopic(o.topic, o.category));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the email app? Re-check so the "verify email" banner
    // disappears once they've actually verified.
    if (state == AppLifecycleState.resumed) _refreshVerification();
  }

  /// Reloads the user from the server and rebuilds, so [emailVerified] (and thus
  /// the banner's visibility) reflects the latest state. Best-effort.
  Future<void> _refreshVerification() async {
    try {
      await _auth.reloadUser();
      if (mounted) setState(() {});
    } catch (_) {/* offline or not signed in — ignore */}
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out of Arena?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => const LoginScreen(startInSignUp: false)),
        (route) => false,
      );
    }
  }

  /// Dialog to change the account password (re-auth with the current one first).
  Future<void> _showChangePassword() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        String? error;
        bool busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Change password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentCtrl,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Current password'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'New password (6+ characters)'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!,
                        style: const TextStyle(
                            color: AppColors.primary, fontSize: 13)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (newCtrl.text.length < 6) {
                          setLocal(() => error =
                              'New password must be at least 6 characters.');
                          return;
                        }
                        setLocal(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await _auth.changePassword(
                            currentPassword: currentCtrl.text,
                            newPassword: newCtrl.text,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Password changed.')),
                            );
                          }
                        } catch (e) {
                          var msg = AuthService.friendlyError(e);
                          if (e is FirebaseAuthException &&
                              (e.code == 'wrong-password' ||
                                  e.code == 'invalid-credential')) {
                            msg = 'Current password is incorrect.';
                          }
                          setLocal(() {
                            busy = false;
                            error = msg;
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hiddenSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openDailyRoom() async {
    if (_openingDaily) return;
    setState(() => _openingDaily = true);
    try {
      final uid = _auth.currentUser!.uid;
      final room = await _daily.ensureTodayRoom(uid: uid);
      // Use the side picked last time; only ask the first time in this room.
      Stance? stance;
      try {
        stance = await _rooms.getStoredStance(uid, room.id);
      } catch (_) {/* treat as not-yet-chosen */}
      if (stance == null) {
        if (!mounted) return;
        stance = await pickJoinStance(context, topic: room.topic);
        if (stance == null) return; // cancelled
      }
      // Remember the daily room under "Visited" too, like any other room.
      try {
        await _rooms.recordJoin(uid, room, stance: stance);
      } catch (_) {/* non-fatal */}
      if (mounted) {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) =>
                    ChatRoomScreen(room: room, initialStance: stance!),
              ),
            )
            .then((_) => _afterRoomVisit());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open today\'s room.')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingDaily = false);
    }
  }

  bool _matchesFilters(Room room) {
    if (room.isDaily) return false; // shown in the featured card instead
    // In "My Rooms", hide rooms the user removed from their own list.
    if (!_showJoined && _hidden.contains(room.id)) return false;
    if (_category != null && room.category != _category) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return room.name.toLowerCase().contains(q) ||
        room.topic.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arena',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          IconButton(
            tooltip: 'Discover rooms',
            icon: const Icon(Icons.explore),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RoomDiscoveryScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: UserAvatar(
              emoji: _auth.myAvatar,
              name: _auth.displayName,
              size: 32,
            ),
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                        builder: (_) => const ProfileScreen()))
                    .then((_) => setState(() {})); // refresh the avatar icon
              } else if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              } else if (value == 'password') {
                _showChangePassword();
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                  value: 'profile', child: Text('Profile & avatar')),
              const PopupMenuItem(
                  value: 'settings', child: Text('Settings')),
              // Only email/password accounts have a password to change.
              if (_auth.hasPasswordProvider)
                const PopupMenuItem(
                    value: 'password', child: Text('Change password')),
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New room'),
      ),
      body: Column(
        children: [
          if (_auth.currentUser != null &&
              !(_auth.currentUser!.emailVerified) &&
              !_hideVerifyBanner)
            _VerifyEmailBanner(
              onResend: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await _auth.sendEmailVerification();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Verification email sent — check your '
                          'inbox and spam/junk folder.'),
                      duration: Duration(seconds: 6),
                    ),
                  );
                } catch (_) {}
              },
              onDismiss: () => setState(() => _hideVerifyBanner = true),
            ),
          _DailyTopicCard(
            topic: _todayOverride ?? _daily.todayTopic(),
            loading: _openingDaily,
            onTap: _openDailyRoom,
          ),
          _SearchBar(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
          ),
          _CategoryFilter(
            selected: _category,
            onSelected: (c) => setState(() => _category = c),
          ),
          _RoomsToggle(
            showJoined: _showJoined,
            onChanged: (v) => setState(() => _showJoined = v),
          ),
          Expanded(
            child: StreamBuilder<List<Room>>(
              stream: _showJoined
                  ? _rooms.watchJoinedRooms(_auth.currentUser!.uid)
                  : _rooms.watchMyRooms(_auth.currentUser!.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _Centered(
                    emoji: '⚠️',
                    title: 'Could not load rooms',
                    subtitle: 'Check your internet connection and try again.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list =
                    snapshot.data!.where(_matchesFilters).toList();
                if (list.isEmpty) {
                  final filtering = _query.isNotEmpty || _category != null;
                  return _Centered(
                    emoji: filtering
                        ? '🔍'
                        : (_showJoined ? '👥' : '🗣️'),
                    title: filtering
                        ? 'No rooms match'
                        : (_showJoined
                            ? 'No visited rooms yet'
                            : 'No rooms created yet'),
                    subtitle: filtering
                        ? 'Try a different search or category.'
                        : (_showJoined
                            ? 'Rooms you open will show up here, so you can '
                                'jump back in any time.'
                            : 'Create a new debate room or discover rooms from others!'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 90),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final room = list[i];
                    return RoomCard(
                      room: room,
                      onTap: () => _openRoom(room),
                      onLongPress: () => _roomCardMenu(room),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRoom(Room room) async {
    if (room.isPrivate) {
      final ok = await _askPassword(room);
      if (ok != true) return;
    }
    if (!mounted) return;
    final uid = _auth.currentUser!.uid;
    // Use the side they picked last time; only ask the first time.
    Stance? stance;
    try {
      stance = await _rooms.getStoredStance(uid, room.id);
    } catch (_) {/* treat as not-yet-chosen */}
    if (stance == null) {
      if (!mounted) return;
      stance = await pickJoinStance(context, topic: room.topic);
      if (stance == null || !mounted) return;
    }
    // Remember this room under "Visited" so they can come back easily.
    try {
      await _rooms.recordJoin(uid, room, stance: stance);
    } catch (_) {/* non-fatal */}
    if (!mounted) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(room: room, initialStance: stance!),
          ),
        )
        .then((_) => _afterRoomVisit());
  }

  /// Long-press menu on a room card. In "My Rooms" the creator can remove the
  /// room from their own list (the room keeps existing for everyone else); in
  /// "Visited" they can remove it from their history.
  Future<void> _roomCardMenu(Room room) async {
    final uid = _auth.currentUser!.uid;
    final isVisited = _showJoined;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(room.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_remove),
              title: Text(isVisited
                  ? 'Remove from Visited'
                  : 'Remove from my list'),
              subtitle: const Text(
                  "This won't delete the room — others can still chat in it."),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );
    if (choice != 'remove') return;
    try {
      if (isVisited) {
        await _rooms.removeVisited(uid, room.id);
      } else {
        await _rooms.hideRoom(uid, room.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isVisited
                ? 'Removed from Visited'
                : 'Removed from your list'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                if (isVisited) {
                  await _rooms.recordJoin(uid, room);
                } else {
                  await _rooms.unhideRoom(uid, room.id);
                }
              },
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update your list.')),
        );
      }
    }
  }

  Future<bool?> _askPassword(Room room) {
    final controller = TextEditingController();
    String? error;
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Private room'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('"${room.name}" needs a password to join.',
                      style: const TextStyle(color: AppColors.textGrey)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(88, 44),
                  ),
                  onPressed: () {
                    if (_rooms.checkPassword(room, controller.text)) {
                      Navigator.pop(context, true);
                    } else {
                      setLocal(() => error = 'Wrong password');
                    }
                  },
                  child: const Text('Join'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A toggle to switch the list between rooms I created and rooms I've joined.
class _RoomsToggle extends StatelessWidget {
  final bool showJoined;
  final ValueChanged<bool> onChanged;
  const _RoomsToggle({required this.showJoined, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          _seg('My Rooms', !showJoined, () => onChanged(false)),
          const SizedBox(width: 8),
          _seg('Visited', showJoined, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

/// A dismissible banner nudging the user to verify their email.
class _VerifyEmailBanner extends StatelessWidget {
  final VoidCallback onResend;
  final VoidCallback onDismiss;
  const _VerifyEmailBanner({required this.onResend, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.accent.withValues(alpha: 0.18),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_outlined,
              size: 18, color: AppColors.textDark),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Verify your email to secure your account. '
              'Check your spam/junk folder too.',
              style: TextStyle(fontSize: 13, color: AppColors.textDark),
            ),
          ),
          TextButton(onPressed: onResend, child: const Text('Resend')),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// The featured "Topic of the Day" banner at the top of the list.
class _DailyTopicCard extends StatelessWidget {
  final DailyTopic topic;
  final bool loading;
  final VoidCallback onTap;

  const _DailyTopicCard({
    required this.topic,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🔥', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(
                            'TOPIC OF THE DAY',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        topic.topic,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap to join the debate →',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search rooms…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;
  const _CategoryFilter({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final items = <String?>[null, ...kCategories];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = items[i];
          final isSel = c == selected;
          final label = c == null ? 'All' : '${categoryEmoji(c)} $c';
          return ChoiceChip(
            label: Text(label),
            selected: isSel,
            onSelected: (_) => onSelected(c),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: isSel ? Colors.white : AppColors.textDark,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.border),
            ),
          );
        },
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  const _Centered(
      {required this.emoji, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textGrey)),
          ],
        ),
      ),
    );
  }
}
