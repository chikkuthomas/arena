// The walkthrough must be offered exactly once per app run, and never again
// after it's been seen — otherwise a rebuild of the rooms list could stack two
// copies of it on screen.
import 'package:arena/services/onboarding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Clear the in-memory session guard between tests.
    await OnboardingService.reset();
  });

  test('offered on a fresh install, but only once per run', () async {
    expect(await OnboardingService.shouldOffer(), isTrue);
    expect(await OnboardingService.shouldOffer(), isFalse);
  });

  test('never offered again once it has been seen', () async {
    await OnboardingService.markSeen();
    expect(await OnboardingService.hasSeen(), isTrue);
    expect(await OnboardingService.shouldOffer(), isFalse);
  });

  test('reset makes it offerable again for Replay walkthrough', () async {
    await OnboardingService.markSeen();
    await OnboardingService.reset();
    expect(await OnboardingService.hasSeen(), isFalse);
    expect(await OnboardingService.shouldOffer(), isTrue);
  });
}
