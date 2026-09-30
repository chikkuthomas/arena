import 'package:flutter/material.dart';

import '../data/profanity.dart';
import '../models/message.dart';
import '../models/room.dart';
import '../services/auth_service.dart';
import '../services/moderation_service.dart';
import '../services/room_notify_service.dart';
import '../services/room_service.dart';
import '../theme.dart';
import '../widgets/join_stance_dialog.dart';
import '../widgets/message_bubble.dart';
import '../widgets/vote_panel.dart';

/// The live debate. Shows the topic at the top, the running conversation, and
/// an input bar where you pick a stance (For / Against / Neutral) and send.
class ChatRoomScreen extends StatefulWidget {
  final Room room;

  /// The stance the user picked when joining (Support / Oppose). Pre-selects
  /// the input bar so their first message is already tagged.
  final Stance initialStance;

  const ChatRoomScreen({
    super.key,
    required this.room,
    this.initialStance = Stance.neutral,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _rooms = RoomService();
  final _auth = AuthService();
  final _moderation = ModerationService();

  late Stance _stance = widget.initialStance;
  bool _sending = false;
  Set<String> _blocked = {};
  Message? _replyingTo; // the message currently being replied to, if any
  bool _notifyOn = false; // notify me about new messages in this room
  int _messageLimit = 30; // how many recent messages to load (pagination)
  String? _lastBottomMsgId; // auto-scroll only when a NEW message arrives

  @override
  void initState() {
    super.initState();
    // Tell the push handler this room is on screen, so it won't pop a
    // notification for a message we can already see.
    RoomNotifyService.activeRoomId = widget.room.id;
    // Follow this room's "trending" re-engagement topic so we can pull the user
    // back if the debate heats up later (separate from the 🔔 bell).
    RoomNotifyService.subscribeParticipant(widget.room.id);
    _loadBlocked();
    _loadNotify();
  }

  Future<void> _loadNotify() async {
    final on = await RoomNotifyService.isOn(widget.room.id);
    if (mounted) setState(() => _notifyOn = on);
  }

  /// Flips the per-room notification toggle (subscribes/unsubscribes the phone).
  Future<void> _toggleNotify() async {
    final next = !_notifyOn;
    setState(() => _notifyOn = next);
    try {
      await RoomNotifyService.setOn(widget.room.id, next);
      _toast(next
          ? 'Notifications on for this room 🔔'
          : 'Notifications off for this room');
    } catch (_) {
      if (mounted) setState(() => _notifyOn = !next); // revert on failure
      _toast('Could not update notifications — check your internet.');
    }
  }

  Future<void> _toggleReaction(Message m, String emoji) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _rooms.toggleReaction(
        roomId: widget.room.id,
        messageId: m.id,
        userId: uid,
        emoji: emoji,
        currentEmoji: m.myReaction(uid),
      );
    } catch (_) {
      _toast('Could not update reaction.');
    }
  }

  Future<void> _loadBlocked() async {
    final blocked = await _moderation.loadBlocked();
    if (mounted) setState(() => _blocked = blocked);
  }

  /// Lets the user deliberately switch the side they're arguing. The new
  /// choice is remembered for this room (so next time it's the default).
  Future<void> _changeStance() async {
    final picked = await pickJoinStance(context, topic: widget.room.topic);
    if (picked == null || picked == _stance || !mounted) return;
    setState(() => _stance = picked);
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _rooms.setStance(uid, widget.room.id, picked);
      } catch (_) {/* non-fatal */}
    }
  }

  @override
  void dispose() {
    if (RoomNotifyService.activeRoomId == widget.room.id) {
      RoomNotifyService.activeRoomId = null;
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Shown when a message contains flagged language. Returns true to send anyway.
  Future<bool?> _confirmProfanity() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
        title: const Text('Think before you send'),
        content: const Text(
          'Your message contains offensive language. Abusive, threatening or '
          'hateful messages can get you banned and may lead to real trouble or '
          'legal issues.\n\nAre you sure you want to send it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Edit message'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    // Warn (but don't block) before sending vulgar/abusive language.
    if (hasProfanity(text)) {
      final proceed = await _confirmProfanity();
      if (proceed != true || !mounted) return;
    }
    setState(() => _sending = true);
    final user = _auth.currentUser!;
    try {
      await _rooms.sendMessage(
        roomId: widget.room.id,
        text: text,
        senderId: user.uid,
        senderName: _auth.displayName,
        senderAvatar: _auth.myAvatar,
        stance: _stance,
        replyTo: _replyingTo,
      );
      _input.clear();
      if (mounted) setState(() => _replyingTo = null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message failed — check your internet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Loads an older batch of messages (raises the live window's limit).
  void _loadEarlier() {
    setState(() => _messageLimit += 30);
  }

  /// The reply icon revealed behind a message as it's swiped sideways.
  Widget _swipeReplyHint(Alignment alignment) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Icon(Icons.reply, color: AppColors.secondary),
    );
  }

  /// Begins replying to a message. Only debaters (For/Against) can reply —
  /// someone who is "just watching" is nudged to pick a side first.
  void _startReply(Message m) {
    if (_stance == Stance.neutral) {
      _toast("You're just watching — switch to For or Against to reply.");
      return;
    }
    setState(() => _replyingTo = m);
  }

  /// Long-press menu on a message: delete your own, or report/block others.
  void _showMessageActions(Message m) {
    final isMine = m.senderId == _auth.currentUser?.uid;
    // Drop focus from the input so dismissing this menu doesn't pop the keyboard
    // back up when it was minimized before the long-press.
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply, color: AppColors.secondary),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startReply(m);
                },
              ),
              if (isMine)
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: AppColors.primary),
                  title: const Text('Delete my message'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _deleteMessage(m);
                  },
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Report message'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _reportMessage(m);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: AppColors.primary),
                  title: Text('Block ${m.senderName}'),
                  subtitle:
                      const Text('Hide all their messages on this phone'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _blockUser(m);
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessage(Message m) async {
    try {
      await _rooms.deleteMessage(widget.room.id, m.id);
    } catch (_) {
      _toast('Could not delete the message.');
    }
  }

  Future<void> _reportMessage(Message m) async {
    try {
      await _moderation.reportMessage(
        roomId: widget.room.id,
        message: m,
        reporterId: _auth.currentUser!.uid,
      );
      _toast('Thanks — message reported.');
    } catch (_) {
      _toast('Could not send the report.');
    }
  }

  Future<void> _blockUser(Message m) async {
    final updated = await _moderation.blockUser(
      m.senderId,
      name: m.senderName,
      avatar: m.senderAvatar,
    );
    if (mounted) {
      setState(() => _blocked = updated);
      _toast('${m.senderName} blocked.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.room.name,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text(
              '${categoryEmoji(widget.room.category)} ${widget.room.category}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _notifyOn
                ? 'Notifications on — tap to turn off'
                : 'Get notified of new messages',
            onPressed: _toggleNotify,
            icon: Icon(
              _notifyOn
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              color: Colors.white,
            ),
          ),
          TextButton.icon(
            onPressed: _changeStance,
            icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 18),
            label: Text(
              _stance == Stance.forSide
                  ? 'For'
                  : _stance == Stance.againstSide
                      ? 'Against'
                      : 'Watching',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _TopicBanner(topic: widget.room.topic),
          VotePanel(
            roomId: widget.room.id,
            myUid: _auth.currentUser?.uid,
          ),
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream:
                  _rooms.watchMessages(widget.room.id, limit: _messageLimit),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Could not load messages.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Hide messages from anyone this user has blocked.
                final messages = snapshot.data!
                    .where((m) => !_blocked.contains(m.senderId))
                    .toList();
                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No arguments yet.\nFire the first shot! 🔥',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textGrey),
                      ),
                    ),
                  );
                }
                // Auto-jump to the newest message only when a NEW one arrives
                // at the bottom (or on first load) — NOT when the user loads
                // older messages, so their scroll position is preserved.
                final bottomId = messages.last.id;
                if (bottomId != _lastBottomMsgId) {
                  _lastBottomMsgId = bottomId;
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _jumpToBottom());
                }
                // If we filled the whole window there may be older messages.
                final hasMore = snapshot.data!.length >= _messageLimit;
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (hasMore && index == 0) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: TextButton(
                            onPressed: _loadEarlier,
                            child: const Text('Load earlier messages'),
                          ),
                        ),
                      );
                    }
                    final i = hasMore ? index - 1 : index;
                    final m = messages[i];
                    // Swipe a message sideways to reply to it; long-press still
                    // opens the full menu (reply / react / report / block).
                    return Dismissible(
                      key: ValueKey(m.id),
                      direction: DismissDirection.horizontal,
                      background: _swipeReplyHint(Alignment.centerLeft),
                      secondaryBackground:
                          _swipeReplyHint(Alignment.centerRight),
                      confirmDismiss: (_) async {
                        _startReply(m);
                        return false; // never actually remove the message
                      },
                      child: GestureDetector(
                        onLongPress: () => _showMessageActions(m),
                        child: MessageBubble(
                          message: m,
                          isMine: m.senderId == myUid,
                          myUid: myUid,
                          onReact: (emoji) => _toggleReaction(m, emoji),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Only debaters (For / Against) can type. A "just watching" user
          // sees a gentle prompt to pick a side instead of the input box.
          if (_stance == Stance.neutral)
            _WatchingBar(onPickSide: _changeStance)
          else ...[
            if (_replyingTo != null)
              _ReplyPreviewBar(
                message: _replyingTo!,
                onCancel: () => setState(() => _replyingTo = null),
              ),
            _InputBar(
              controller: _input,
              stance: _stance,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ],
      ),
    );
  }
}

/// Sits above the input while composing a reply, showing what's being quoted.
class _ReplyPreviewBar extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;
  const _ReplyPreviewBar({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Container(width: 3, height: 36, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${message.senderName}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _TopicBanner extends StatelessWidget {
  final String topic;
  const _TopicBanner({required this.topic});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.secondary,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚔️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              topic,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the input box when the user is "just watching". Tapping it
/// opens the pick-a-side chooser so they can join the debate and start typing.
class _WatchingBar extends StatelessWidget {
  final VoidCallback onPickSide;
  const _WatchingBar({required this.onPickSide});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "You're just watching this debate.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textGrey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPickSide,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Pick a side to join in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final Stance stance;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.stance,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _StanceBadge(stance: stance),
                const Spacer(),
                const Text(
                  'Tap ⇄ above to switch side',
                  style: TextStyle(fontSize: 11, color: AppColors.textGrey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Make your argument…',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: sending ? null : onSend,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: sending
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A badge showing the side the user is currently arguing. It defaults to the
/// side chosen on entry (remembered per room) and updates when they switch
/// sides via the control in the app bar.
class _StanceBadge extends StatelessWidget {
  final Stance stance;

  const _StanceBadge({required this.stance});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (stance) {
      Stance.forSide => ('Arguing: For', AppColors.forSide),
      Stance.againstSide => ('Arguing: Against', AppColors.againstSide),
      Stance.neutral => ('Just watching', AppColors.textGrey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
