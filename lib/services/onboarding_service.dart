import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether this phone has already seen the welcome walkthrough.
///
/// Kept ON THE PHONE (like the block list in `ModerationService`) — it's a
/// one-time bit of polish, not account data, so there's no reason to spend a
/// Firestore read on it. Every call is wrapped in try/catch so a storage
/// failure can never stop the app from opening.
class OnboardingService {
  static const _seenKey = 'onboarding_seen_v1';

  /// True once we've already decided to show the walkthrough in this app run.
  /// The rooms list is rebuilt whenever Firebase re-emits an auth state (a
  /// token refresh is enough), which would otherwise push a second copy of the
  /// walkthrough on top of the first.
  static bool _offeredThisSession = false;

  /// Whether the walkthrough may be offered right now. Returns true at most
  /// once per app run, and only if it hasn't been seen before.
  static Future<bool> shouldOffer() async {
    if (_offeredThisSession) return false;
    if (await hasSeen()) return false;
    _offeredThisSession = true;
    return true;
  }

  /// Whether the walkthrough has already been completed or skipped.
  static Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) ?? false;
    } catch (_) {
      // If the flag can't be read, treat it as "seen" — better to skip the
      // walkthrough than to trap someone in it every single launch.
      return true;
    }
  }

  /// Called when the user finishes or skips the walkthrough.
  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {/* best-effort — nothing breaks if this fails */}
  }

  /// Clears the flag so Settings → "Replay walkthrough" can show it again.
  static Future<void> reset() async {
    _offeredThisSession = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_seenKey);
    } catch (_) {/* best-effort */}
  }
}
