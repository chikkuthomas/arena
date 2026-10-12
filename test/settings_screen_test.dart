// The Settings screen is pure UI over a few services, so it can be pumped
// directly. We only check that every row renders — tapping them would reach
// platform channels that don't exist in a test.
import 'package:arena/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows every settings row', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Rate Arena'), findsOneWidget);
    expect(find.text('Share Arena'), findsOneWidget);

    // The list is taller than the test viewport, and ListView only builds the
    // rows that are on screen — so scroll down to reach the rest.
    for (final label in [
      'Blocked users',
      'Replay walkthrough',
      'Terms of Service',
      'Privacy Policy',
      'Delete account',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 120,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(label), findsOneWidget);
    }
  });

  // Deleting an account is irreversible, so the guard matters more than the
  // happy path (which needs Firebase and can't run here): the Delete button
  // must stay disabled until DELETE is typed exactly.
  testWidgets('delete-account dialog keeps Delete disabled until confirmed',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(find.text('Delete account'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('Delete account?'), findsOneWidget);

    TextButton deleteButton() => tester.widget<TextButton>(
          find.ancestor(
            of: find.text('Delete'),
            matching: find.byType(TextButton),
          ),
        );

    // Nothing typed yet.
    expect(deleteButton().onPressed, isNull);

    // A near-miss must not arm it.
    await tester.enterText(find.byType(TextField), 'delete me');
    await tester.pump();
    expect(deleteButton().onPressed, isNull);

    // The exact word arms it (case-insensitively, since the field forces caps).
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    expect(deleteButton().onPressed, isNotNull);

    // Cancel backs out without deleting anything.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete account?'), findsNothing);
  });
}
