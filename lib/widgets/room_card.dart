import 'package:flutter/material.dart';

import '../models/room.dart';
import '../services/room_service.dart';
import '../theme.dart';

/// A single tappable room in the rooms list, showing the topic, category and a
/// lock if it's private.
class RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// The message count this user had already seen. When set (the Visited list),
  /// the card shows a badge with how many messages arrived since. Null = no badge.
  final int? unreadBaseline;

  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
    this.onLongPress,
    this.unreadBaseline,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.card,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(categoryEmoji(room.category),
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      room.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  if (unreadBaseline != null)
                    _UnreadBadge(roomId: room.id, seenCount: unreadBaseline!),
                  if (room.isDaily)
                    const _Tag(text: 'TOPIC OF THE DAY', color: AppColors.accent),
                  if (room.isPrivate)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.lock,
                          size: 16, color: AppColors.textGrey),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                room.topic,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textGrey,
                  height: 1.3,
                ),
              ),
              if (room.isPrivate) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock, size: 16, color: AppColors.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is a private group. You\'ll need the group '
                          'password to join — please contact the group '
                          'administrator for access.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _Tag(text: room.category, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  // Visited entries are saved snapshots without a message
                  // count, so read the room's live count there.
                  unreadBaseline != null
                      ? StreamBuilder<int>(
                          stream: RoomService().watchMessageCount(room.id),
                          builder: (context, snapshot) => _MessageCount(
                              count: snapshot.data ?? room.messageCount),
                        )
                      : _MessageCount(count: room.messageCount),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      'by ${room.createdByName}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small "💬 N" chip showing how many messages a room has, to spark curiosity
/// about busy debates. Reads a little friendlier than a bare number.
class _MessageCount extends StatelessWidget {
  final int count;
  const _MessageCount({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.forum_outlined, size: 14, color: AppColors.textGrey),
        const SizedBox(width: 4),
        Text(
          count == 0
              ? 'No messages yet'
              : '$count ${count == 1 ? 'message' : 'messages'}',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A red pill showing how many new messages arrived since the user last opened
/// the room. Streams the room's live message count and subtracts what was seen.
/// Shows nothing when there's nothing new.
class _UnreadBadge extends StatelessWidget {
  final String roomId;
  final int seenCount;
  const _UnreadBadge({required this.roomId, required this.seenCount});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: RoomService().watchMessageCount(roomId),
      builder: (context, snapshot) {
        final total = snapshot.data ?? seenCount;
        final unread = total - seenCount;
        if (unread <= 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          constraints: const BoxConstraints(minWidth: 24),
          child: Text(
            unread > 99 ? '99+' : '$unread',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
