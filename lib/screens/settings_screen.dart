import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../services/review_service.dart';
import '../services/share_service.dart';
import '../theme.dart';
import 'blocked_users_screen.dart';
import 'legal_screen.dart';
import 'onboarding_screen.dart';

/// Settings: rate the app, share it, replay the walkthrough, read the legal
/// documents, and delete the account.
///
/// Reached from the account menu on the rooms list. Everything here is
/// read-only or self-contained apart from "Delete account", which is the one
/// destructive action — Google Play requires an in-app deletion path for any
/// app that lets people sign up.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _deleteAccount(BuildContext context) async {
    // The root messenger (MaterialApp's) outlives this screen, so the
    // confirmation still shows after we pop back to the login screen.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (deleted != true) return;

    // AuthService.deleteMyAccount already signed out, so the auth gate in
    // main.dart is showing the login screen underneath — drop the pushed
    // routes (Settings, rooms list) so the user lands on it.
    navigator.popUntil((r) => r.isFirst);
    messenger.showSnackBar(
      const SnackBar(
          content: Text('Your account has been deleted. Your posts now show '
              'as "Deleted user".')),
    );
  }

  Future<void> _rate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ReviewService.openStoreListing();
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the Play Store on this device.'),
        ),
      );
    }
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ShareService.shareApp();
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet.')),
      );
    }
  }

  Future<void> _replayWalkthrough(BuildContext context) async {
    // Clear the flag so it would show again on a fresh launch too, then show it
    // right now.
    await OnboardingService.reset();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  void _openLegal(BuildContext context, LegalDoc doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalScreen(doc: doc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader('Support Arena'),
          _SettingsTile(
            icon: Icons.star_rate_rounded,
            iconColour: AppColors.accent,
            title: 'Rate Arena',
            subtitle: 'Leave a rating on the Play Store',
            onTap: () => _rate(context),
          ),
          _SettingsTile(
            icon: Icons.ios_share_rounded,
            iconColour: AppColors.primary,
            title: 'Share Arena',
            subtitle: 'Invite friends to join the debate',
            onTap: () => _share(context),
          ),
          const Divider(height: 24, color: AppColors.border),
          const _SectionHeader('Safety'),
          _SettingsTile(
            icon: Icons.block,
            iconColour: AppColors.againstSide,
            title: 'Blocked users',
            subtitle: 'See and undo who you have blocked',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
            ),
          ),
          const Divider(height: 24, color: AppColors.border),
          const _SectionHeader('Help'),
          _SettingsTile(
            icon: Icons.school_outlined,
            iconColour: AppColors.secondary,
            title: 'Replay walkthrough',
            subtitle: 'See how Arena works again',
            onTap: () => _replayWalkthrough(context),
          ),
          const Divider(height: 24, color: AppColors.border),
          const _SectionHeader('Legal'),
          _SettingsTile(
            icon: Icons.description_outlined,
            iconColour: AppColors.textGrey,
            title: 'Terms of Service',
            onTap: () => _openLegal(context, LegalDoc.terms),
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            iconColour: AppColors.textGrey,
            title: 'Privacy Policy',
            onTap: () => _openLegal(context, LegalDoc.privacy),
          ),
          const Divider(height: 24, color: AppColors.border),
          const _SectionHeader('Account'),
          _SettingsTile(
            icon: Icons.delete_forever_outlined,
            iconColour: AppColors.againstSide,
            title: 'Delete account',
            subtitle: 'Permanently erase your login, profile and votes',
            onTap: () => _deleteAccount(context),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Two-step confirmation for an irreversible delete: it spells out exactly what
/// goes, and the button stays disabled until the word DELETE is typed, so this
/// can't happen on a stray tap.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _confirmWord = 'DELETE';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canDelete =>
      !_busy && _controller.text.trim().toUpperCase() == _confirmWord;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService().deleteMyAccount();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // A suspended account is refused deletion server-side so its messages
      // stay available as moderation evidence. Show that reason instead of
      // blaming the connection, or the user retries forever.
      var message = 'Could not delete your account. Check your connection and '
          'try again.';
      if (e is FirebaseFunctionsException && e.code == 'permission-denied') {
        message = e.message ??
            'This account is suspended and cannot be deleted.';
      }
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      // Scrollable because the on-screen keyboard opens as soon as the confirm
      // field is focused, roughly halving the available height. Without this
      // the content overflows and the action buttons render on top of it.
      scrollable: true,
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This cannot be undone. We will permanently delete:',
            style: TextStyle(color: AppColors.textDark, height: 1.35),
          ),
          const SizedBox(height: 10),
          const Text(
            '•  your login and profile\n'
            '•  your votes and the reports you filed',
            style: TextStyle(color: AppColors.textGrey, height: 1.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your messages and any rooms you created stay up, so others keep '
            'their side of the debate — but they show as "Deleted user" and '
            'are no longer linked to you.',
            style: TextStyle(color: AppColors.textGrey, height: 1.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Type DELETE to confirm:',
            style: TextStyle(color: AppColors.textDark, height: 1.35),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: _confirmWord,
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.againstSide,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _canDelete ? _confirm : null,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.againstSide,
          ),
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textGrey,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColour;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColour,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        height: 38,
        width: 38,
        decoration: BoxDecoration(
          color: iconColour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColour, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textGrey),
            ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textGrey),
      onTap: onTap,
    );
  }
}
