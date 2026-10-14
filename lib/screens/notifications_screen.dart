import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/message.dart';
import '../models/notification_item.dart';
import '../models/room.dart';
import '../services/notification_history_service.dart';
import '../theme.dart';
import 'chat_room_screen.dart';

/// Everything Arena has ever pushed to you, in one scrollable list: new room
/// messages, replies, trending nudges, and admin broadcasts.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _history = NotificationHistoryService();

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _history.markAllRead(uid);
  }

  Future<void> _open(NotificationItem item) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await _history.markRead(uid, item);
    final roomId = item.roomId;
    if (roomId == null || !mounted) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('rooms')
          .doc(roomId)
          .get();
      if (!doc.exists || !mounted) return;
      final room = Room.fromDoc(doc);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ChatRoomScreen(room: room, initialStance: Stance.neutral),
      ));
    } catch (_) {
      // Room may have been deleted — nothing to open.
    }
  }

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.reply:
        return Icons.reply;
      case NotificationType.trending:
        return Icons.whatshot;
      case NotificationType.broadcast:
        return Icons.campaign;
      case NotificationType.roomMessage:
        return Icons.chat_bubble_outline;
    }
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notifications')),
      body: uid == null
          ? const _EmptyState()
          : StreamBuilder<List<NotificationItem>>(
              stream: _history.watchAll(uid),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) return const _EmptyState();
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: item.read
                            ? AppColors.background
                            : AppColors.primaryLight.withValues(alpha: 0.2),
                        foregroundColor: AppColors.primary,
                        child: Icon(_iconFor(item.type)),
                      ),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight:
                              item.read ? FontWeight.normal : FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      subtitle: Text(
                        item.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _relativeTime(item.createdAt),
                        style: const TextStyle(
                            color: AppColors.textGrey, fontSize: 12),
                      ),
                      onTap: () => _open(item),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 72, color: AppColors.textGrey),
            SizedBox(height: 20),
            Text(
              'No notifications yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            SizedBox(height: 12),
            Text(
              "Replies, trending debates, and new topics will show up here.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.textGrey),
            ),
          ],
        ),
      ),
    );
  }
}
