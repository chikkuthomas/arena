// Tests for the new-user walkthrough. These screens don't touch Firebase, so
// unlike the rest of the app they can be pumped in a normal widget test.
import 'package:arena/screens/onboarding_screen.dart';
import 'package:arena/services/onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opens on the first slide and shows a Skip button',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    expect(find.text('Welcome to Arena'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    // The last slide's button shouldn't be on screen yet.
    expect(find.text('Start debating'), findsNothing);
  });

  testWidgets('Next walks through every slide and ends on Start debating',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    for (final title in ['Pick your side', 'Debate live', 'Vote who won']) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Start debating'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('Skip marks the walkthrough as seen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    expect(await OnboardingService.hasSeen(), isFalse);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(await OnboardingService.hasSeen(), isTrue);
  });

  testWidgets('finishing the last slide marks it as seen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Start debating'));
    await tester.pumpAndSettle();
    expect(await OnboardingService.hasSeen(), isTrue);
  });
}
