import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks people to rate Arena on the Play Store — politely, and at a sensible
/// moment.
///
/// Two ways in:
///  * **Manual** — Settings → "Rate Arena" opens the Play Store listing, so a
///    tap always does something visible.
///  * **Automatic** — after the user has actually used the app a few times we
///    show Google's native in-app review sheet exactly once. Google itself
///    rate-limits that sheet, so we never nag.
///
/// Like the notification code, every method swallows its errors: a rating
/// prompt is a nice-to-have and must never crash or block the app.
class ReviewService {
  /// Set once we've shown (or tried to show) the automatic prompt.
  static const _promptedKey = 'rate_prompted_v1';

  /// How many meaningful actions the user has taken (rooms opened to debate).
  static const _engagementKey = 'rate_engagement_count_v1';

  /// Ask only after this many meaningful actions. Google's guidance is to
  /// prompt once someone has experienced enough of the app to have an opinion.
  static const _threshold = 5;

  static final InAppReview _review = InAppReview.instance;

  /// Records one meaningful interaction (currently: entering a debate room).
  /// Cheap, local, and safe to call often.
  static Future<void> recordEngagement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_promptedKey) ?? false) return; // already asked
      final count = (prefs.getInt(_engagementKey) ?? 0) + 1;
      await prefs.setInt(_engagementKey, count);
    } catch (_) {/* best-effort */}
  }

  /// Shows the native review sheet if the user has engaged enough and hasn't
  /// been asked before. Does nothing otherwise.
  static Future<void> maybePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_promptedKey) ?? false) return;
      final count = prefs.getInt(_engagementKey) ?? 0;
      if (count < _threshold) return;
      if (!await _review.isAvailable()) return;
      // Mark first: if the sheet fails or Google silently suppresses it, we
      // still don't retry on every launch.
      await prefs.setBool(_promptedKey, true);
      await _review.requestReview();
    } catch (_) {/* best-effort — never surface this to the user */}
  }

  /// Opens the Arena listing on the Play Store. Used by the Settings button,
  /// where the user explicitly asked for it. Returns false if it couldn't open
  /// so the caller can show a message.
  static Future<bool> openStoreListing() async {
    try {
      await _review.openStoreListing();
      return true;
    } catch (_) {
      return false;
    }
  }
}
