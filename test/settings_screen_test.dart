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
    expect(find.text('Replay walkthrough'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}
