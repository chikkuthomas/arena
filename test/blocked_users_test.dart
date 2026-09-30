// Blocking is a safety feature, so the list and the undo path both matter.
// These cover the storage rules, including blocks saved by older builds that
// never recorded a name.
import 'package:arena/screens/blocked_users_screen.dart';
import 'package:arena/services/moderation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a blocked person is listed with their name', () async {
    final m = ModerationService();
    await m.blockUser('uid1', name: 'Rambo', avatar: '🔥');
    final list = await m.loadBlockedDetailed();
    expect(list, hasLength(1));
    expect(list.single.uid, 'uid1');
    expect(list.single.name, 'Rambo');
    expect(list.single.avatar, '🔥');
  });

  test('unblocking removes them from the list', () async {
    final m = ModerationService();
    await m.blockUser('uid1', name: 'Rambo');
    await m.unblockUser('uid1');
    expect(await m.loadBlockedDetailed(), isEmpty);
    expect(await m.loadBlocked(), isEmpty);
  });

  test('blocks saved by an older build still appear, without a name', () async {
    // Older builds wrote only the uid list, with no details entry.
    SharedPreferences.setMockInitialValues({
      'blocked_user_ids': ['legacy-uid'],
    });
    final list = await ModerationService().loadBlockedDetailed();
    expect(list, hasLength(1));
    expect(list.single.uid, 'legacy-uid');
    expect(list.single.name, 'Someone');
  });

  test('the list is sorted by name', () async {
    final m = ModerationService();
    await m.blockUser('u1', name: 'Zara');
    await m.blockUser('u2', name: 'Anil');
    final names = (await m.loadBlockedDetailed()).map((b) => b.name).toList();
    expect(names, ['Anil', 'Zara']);
  });

  testWidgets('empty state explains how blocking works', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BlockedUsersScreen()));
    await tester.pumpAndSettle();
    expect(find.text("You haven't blocked anyone"), findsOneWidget);
  });

  testWidgets('a blocked person shows with an Unblock button that works',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'blocked_user_ids': ['uid1'],
      'blocked_user_details': '{"uid1":{"uid":"uid1","name":"Rambo"}}',
    });
    await tester.pumpWidget(const MaterialApp(home: BlockedUsersScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Rambo'), findsOneWidget);
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();

    expect(find.text('Rambo'), findsNothing);
    expect(find.text("You haven't blocked anyone"), findsOneWidget);
    expect(await ModerationService().loadBlocked(), isEmpty);
  });
}
