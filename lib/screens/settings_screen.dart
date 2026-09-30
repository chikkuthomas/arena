import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';
import '../services/review_service.dart';
import '../services/share_service.dart';
import '../theme.dart';
import 'blocked_users_screen.dart';
import 'legal_screen.dart';
import 'onboarding_screen.dart';

/// Settings: rate the app, share it, replay the walkthrough, and read the
/// legal documents.
///
/// Reached from the account menu on the rooms list. Everything here is
/// self-contained — nothing on this screen touches rooms, chat, or auth — so it
/// can't affect any existing behaviour.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
        ],
      ),
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
