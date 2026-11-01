import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/pages/change_password_page.dart';
import 'package:global_village_app/pages/profile_page.dart';
import 'package:global_village_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Change Password returns to the latest Profile without losing an unsaved edit', (tester) async {
    // No token: the profile keeps its existing offline fallback; no real server is contacted.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const ProfilePage(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Interest Match'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Unsaved team profile edit');
    final entry = find.widgetWithText(TextButton, 'Change Password');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordPage), findsOneWidget);
    expect(find.text('Current Password'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordPage), findsNothing);
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text,
      'Unsaved team profile edit',
    );
    expect(find.text('Save'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
