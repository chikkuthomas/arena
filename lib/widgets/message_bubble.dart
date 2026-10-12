import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme.dart';
import 'user_avatar.dart';

/// One chat bubble. My own messages sit on the right; others on the left.
/// A small coloured tag shows whether the message argues For or Against the
/// topic.
/// The emoji choices offered when reacting to a message.
const List<String> kReactionEmojis = ['👍', '❤️', '😂', '👏', '🔥'];

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final String? myUid;

  /// Called when the user picks an emoji to react with (or taps their existing
  /// reaction to remove it).
  final ValueChanged<String>? onReact;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.myUid,
    this.onReact,
  });

  void _openReactionPicker(BuildContext context) {
    if (onReact == null) return;
    final mine = message.myReaction(myUid);
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: kReactionEmojis.map((e) {
              final selected = e == mine;
              return InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onReact!(e);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 30)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // Colour the whole bubble by the side the sender is arguing:
    //   green = For (support), red = Against (oppose).
    // Neutral (e.g. old "just watching" messages) keeps the default styling.
    final Color bubbleColor;
    final Color textColor;
    switch (message.stance) {
      case Stance.forSide:
        bubbleColor = AppColors.forSide; // green
        textColor = Colors.white;
        break;
      case Stance.againstSide:
        bubbleColor = AppColors.againstSide; // red
        textColor = Colors.white;
        break;
      case Stance.neutral:
        bubbleColor = isMine ? AppColors.primary : AppColors.card;
        textColor = isMine ? Colors.white : AppColors.textDark;
        break;
    }
    final onColouredBubble = bubbleColor != AppColors.card;
    final counts = message.reactionCounts;
    final mine = message.myReaction(myUid);

    final content = Column(
      crossAxisAlignment: align,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: Text(
                message.senderName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGrey,
                ),
              ),
            ),
          Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (isMine && onReact != null) _reactButton(context),
              Flexible(
                child: GestureDetector(
                  onTap: onReact == null
                      ? null
                      : () => _openReactionPicker(context),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.70,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(14),
                      border: onColouredBubble
                          ? null
                          : const Border.fromBorderSide(
                              BorderSide(color: AppColors.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.isReply) ...[
                          _QuotedReply(message: message, onDark: onColouredBubble),
                          const SizedBox(height: 6),
                        ],
                        if (message.stance != Stance.neutral) ...[
                          _StanceTag(stance: message.stance, onDark: onColouredBubble),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          message.text,
                          style: TextStyle(fontSize: 15, color: textColor),
                        ),
                        if (message.edited)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'edited',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isMine && onReact != null) _reactButton(context),
            ],
          ),
          if (counts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                children: counts.entries.map((e) {
                  final selected = mine == e.key;
                  return GestureDetector(
                    onTap: onReact == null ? null : () => onReact!(e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              selected ? AppColors.primary : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '${e.key} ${e.value}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: isMine
          ? content
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  emoji: message.senderAvatar,
                  name: message.senderName,
                  size: 32,
                ),
                const SizedBox(width: 6),
                Expanded(child: content),
              ],
            ),
    );
  }

  Widget _reactButton(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: const Icon(Icons.add_reaction_outlined,
          size: 18, color: AppColors.textGrey),
      onPressed: () => _openReactionPicker(context),
    );
  }
}

/// The quoted message shown at the top of a reply bubble.
class _QuotedReply extends StatelessWidget {
  final Message message;
  final bool onDark; // sitting on my own (red) bubble
  const _QuotedReply({required this.message, required this.onDark});

  @override
  Widget build(BuildContext context) {
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.18)
        : AppColors.background;
    final accent = onDark ? Colors.white : AppColors.secondary;
    final bodyColor = onDark ? Colors.white70 : AppColors.textGrey;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.replyToSender ?? 'Someone',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            message.replyToText ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: bodyColor),
          ),
        ],
      ),
    );
  }
}

/// Small "FOR" / "AGAINST" pill shown at the top of a bubble.
class _StanceTag extends StatelessWidget {
  final Stance stance;
  final bool onDark; // true when sitting on my own (red) bubble
  const _StanceTag({required this.stance, required this.onDark});

  @override
  Widget build(BuildContext context) {
    final isFor = stance == Stance.forSide;
    final color = isFor ? AppColors.forSide : AppColors.againstSide;
    final label = isFor ? 'FOR' : 'AGAINST';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.22) : color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
