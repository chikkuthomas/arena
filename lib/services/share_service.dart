import 'package:share_plus/share_plus.dart';

/// Opens the phone's normal share sheet (WhatsApp, Telegram, email, SMS…).
///
/// Used in two places:
///  * Settings → "Share Arena" — invite friends to the app itself.
///  * A room's share dialog — invite friends to one specific debate.
///
/// Every method is wrapped so a share failure can never crash the app; callers
/// get `false` back and can fall back to the existing "copy to clipboard".
class ShareService {
  /// Arena's Play Store listing. Must match `applicationId` in
  /// `android/app/build.gradle.kts`.
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.cryptork.arena';

  /// Shares an invite to the app.
  static Future<bool> shareApp() async {
    const text = 'I\'ve been debating on Arena — pick a side and argue it out '
        'with people on any topic. Today\'s debate is already going 🔥\n\n'
        '$playStoreUrl';
    return _share(text, subject: 'Come debate with me on Arena');
  }

  /// Shares an invite to one debate room.
  static Future<bool> shareRoom({
    required String roomName,
    required String roomId,
    required String link,
  }) async {
    final text = 'Join the debate on Arena: "$roomName"\n\n$link\n\n'
        'Or open Arena and use Room ID: $roomId\n\n'
        'Get Arena: $playStoreUrl';
    return _share(text, subject: 'Join my debate on Arena');
  }

  /// Shows the share sheet. Returns false if it couldn't be opened at all —
  /// the user simply cancelling still counts as success (nothing went wrong).
  static Future<bool> _share(String text, {String? subject}) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, subject: subject),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (_) {
      return false;
    }
  }
}
