import 'package:flutter/material.dart';

import '../services/moderation_service.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

/// Lists everyone this person has blocked, with a way to undo it.
///
/// Blocking is a safety feature, so it has to be reversible — an accidental
/// block was previously permanent and invisible. Blocks live on the phone (see
/// [ModerationService]), so this list is per-device.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _moderation = ModerationService();
  List<BlockedUser>? _blocked; // null = still loading

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<BlockedUser> list;
    try {
      list = await _moderation.loadBlockedDetailed();
    } catch (_) {
      list = const [];
    }
    if (mounted) setState(() => _blocked = list);
  }

  Future<void> _unblock(BlockedUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _moderation.unblockUser(user.uid);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not unblock — please try again.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _blocked =
        _blocked?.where((b) => b.uid != user.uid).toList(growable: false));
    messenger.showSnackBar(
      SnackBar(content: Text('${user.name} unblocked.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blocked;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Blocked users')),
      body: blocked == null
          ? const Center(child: CircularProgressIndicator())
          : blocked.isEmpty
              ? const _EmptyState()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        "Blocked people's messages are hidden from you in "
                        'every room, on this device. Unblock to see them again.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: blocked.length,
                        itemBuilder: (_, i) {
                          final u = blocked[i];
                          return ListTile(
                            leading: UserAvatar(
                              emoji: u.avatar,
                              name: u.name,
                              size: 44,
                            ),
                            title: Text(
                              u.name,
                              style: const TextStyle(
                                fontSize: 17,
                                color: AppColors.textDark,
                              ),
                            ),
                            trailing: OutlinedButton(
                              onPressed: () => _unblock(u),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                    color: AppColors.textGrey, width: 1),
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 12),
                              ),
                              child: const Text('Unblock'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 72, color: AppColors.textGrey),
            const SizedBox(height: 20),
            const Text(
              "You haven't blocked anyone",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Long-press a message in any room and choose Block to hide that '
              "person. They'll show up here so you can unblock them.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
