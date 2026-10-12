import 'package:flutter/material.dart';

import '../data/avatars.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/user_avatar.dart';

/// Lets the signed-in user see their profile and change their avatar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  late String _selected = _initialAvatar();
  bool _saving = false;

  String _initialAvatar() {
    final cur = _auth.myAvatar;
    // An old Google photo URL isn't one of our emojis — start on a default.
    if (cur != null && cur.isNotEmpty && !cur.startsWith('http')) return cur;
    return kAvatarEmojis.first;
  }

  Future<void> _pick(String emoji) async {
    if (_saving || emoji == _selected) {
      setState(() => _selected = emoji);
      return;
    }
    setState(() {
      _selected = emoji;
      _saving = true;
    });
    try {
      await _auth.updateAvatar(emoji);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar updated')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save — check your internet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Opens a dialog to change the display name shown next to your messages.
  Future<void> _editName() async {
    final controller = TextEditingController(text: _auth.displayName);
    String? error;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocal) {
            return AlertDialog(
              title: const Text('Display name'),
              content: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Name shown in debates',
                  errorText: error,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final v = controller.text.trim();
                    if (v.length < 2) {
                      setLocal(() => error = 'At least 2 characters.');
                      return;
                    }
                    Navigator.pop(dialogContext, v);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (newName == null || newName == _auth.displayName) return;
    try {
      await _auth.updateDisplayName(newName);
      if (mounted) {
        setState(() {}); // refresh the name shown on this screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display name updated')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save — check your internet.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            UserAvatar(emoji: _selected, name: _auth.displayName, size: 96),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _auth.displayName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Change display name',
                  icon: const Icon(Icons.edit, size: 20),
                  color: AppColors.secondary,
                  onPressed: _editName,
                ),
              ],
            ),
            if (_auth.email != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _auth.email!,
                  style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
                ),
              ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Choose your avatar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                if (_saving) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            AvatarPicker(selected: _selected, onSelected: _pick),
          ],
        ),
      ),
    );
  }
}
