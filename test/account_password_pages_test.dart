import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/pages/change_password_page.dart';
import 'package:global_village_app/pages/forgot_password_page.dart';
import 'package:global_village_app/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> openPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
    return Scaffold(
        body: TextButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      ),
      child: const Text('Open account page'),
    ));
  })));
  await tester.tap(find.text('Open account page'));
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> fillAnswers(WidgetTester tester, String value) async {
  for (var index = 1; index <= 3; index++) {
    final field = find.byType(TextFormField).at(index);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    AuthService.httpClientOverride?.close();
    AuthService.httpClientOverride = null;
  });

  testWidgets(
      'security recovery verifies server proof and resets without any email endpoint',
      (tester) async {
    final requests = <http.Request>[];
    AuthService.httpClientOverride = MockClient((request) async {
      requests.add(request);
      final body = request.url.path.endsWith('identify')
          ? {
              'questions': [
                'What is your favourite food?',
                'What city were you born in?',
                'What is your childhood nickname?'
              ],
              'challenge': 'challenge'
            }
          : request.url.path.endsWith('verify')
              ? {'resetToken': 'verified-proof', 'expiresInSeconds': 300}
              : {'message': 'Password Reset Successfully'};
      return http.Response(jsonEncode(body), 200);
    });
    await openPage(tester, const ForgotPasswordPage());
    await tester.tap(find.text('Security Question'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'student');
    await press(tester, 'Continue');
    expect(find.text('What is your favourite food?'), findsOneWidget);
    await fillAnswers(tester, 'answer');
    await press(tester, 'Verify Answers');
    expect(find.text('Confirm New Password'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'new-password');
    await tester.enterText(find.byType(TextFormField).at(1), 'different');
    await press(tester, 'Reset Password');
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(requests.length, 2);
    await tester.enterText(find.byType(TextFormField).at(1), 'new-password');
    await press(tester, 'Reset Password');
    expect(find.text('Open account page'), findsOneWidget);
    expect(requests.map((r) => r.url.path).toList(), [
      '/auth/security-question/identify',
      '/auth/security-question/verify',
      '/auth/security-question/reset',
    ]);
    expect(jsonDecode(requests.last.body)['resetToken'], 'verified-proof');
  });

  testWidgets(
      'switching recovery methods clears answers, passwords and account inputs',
      (tester) async {
    AuthService.httpClientOverride = MockClient((_) async => http.Response(
          jsonEncode({
            'questions': [
              'What is your favourite food?',
              'What city were you born in?',
              'What is your childhood nickname?'
            ],
            'challenge': 'challenge'
          }),
          200,
        ));
    await openPage(tester, const ForgotPasswordPage());
    await tester.enterText(
        find.byType(TextFormField).at(0), 'student@example.com');
    await tester.enterText(
        find.byType(TextFormField).at(2), 'sensitive-password');
    await tester.ensureVisible(find.text('Security Question'));
    await tester.tap(find.text('Security Question'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty);
    await tester.enterText(find.byType(TextFormField).at(0), 'student');
    await press(tester, 'Continue');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'sensitive-answer');
    await tester.ensureVisible(find.text('Email Verification'));
    await tester.tap(find.text('Email Verification'));
    await tester.pumpAndSettle();
    for (final field
        in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
      expect(field.controller!.text, isEmpty);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wrong security answer stays on answer step and never resets',
      (tester) async {
    final requests = <http.Request>[];
    AuthService.httpClientOverride = MockClient((request) async {
      requests.add(request);
      return request.url.path.endsWith('identify')
          ? http.Response(
              jsonEncode({
                'questions': [
                  'What is your favourite food?',
                  'What city were you born in?',
                  'What is your childhood nickname?'
                ],
                'challenge': 'challenge'
              }),
              200)
          : http.Response(
              jsonEncode({'error': 'Unable to verify this account or answer.'}),
              400);
    });
    await openPage(tester, const ForgotPasswordPage());
    await tester.tap(find.text('Security Question'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'student');
    await press(tester, 'Continue');
    await fillAnswers(tester, 'wrong');
    await press(tester, 'Verify Answers');
    expect(
        find.text('Unable to verify this account or answer.'), findsOneWidget);
    expect(find.text('Confirm New Password'), findsNothing);
    expect(requests.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'password change validates confirmation, sends JWT and signs out only after server success',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'existing-jwt', 'auth_user': '{}'});
    final requests = <http.Request>[];
    AuthService.httpClientOverride = MockClient((request) async {
      requests.add(request);
      return http.Response(
          jsonEncode({
            'message': 'Password changed successfully. Please sign in again.'
          }),
          200);
    });
    await openPage(tester, const ChangePasswordPage());
    await tester.enterText(find.byType(TextFormField).at(0), 'old-password');
    await tester.enterText(find.byType(TextFormField).at(1), 'new-password');
    await tester.enterText(find.byType(TextFormField).at(2), 'different');
    await press(tester, 'Change Password');
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(requests, isEmpty);
    await tester.enterText(find.byType(TextFormField).at(2), 'new-password');
    await press(tester, 'Change Password');
    expect(requests.single.url.path, '/auth/change-password');
    expect(requests.single.headers['Authorization'], 'Bearer existing-jwt');
    expect(await AuthService.getAuthToken(), isNull);
    expect(find.byType(ChangePasswordPage), findsNothing);
    expect(find.text('Password changed successfully. Please sign in again.'),
        findsOneWidget);
  });

  testWidgets(
      'password change failure preserves login and does not show success',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'existing-jwt'});
    AuthService.httpClientOverride = MockClient((_) async => http.Response(
          jsonEncode({'error': 'Current password is incorrect.'}),
          400,
        ));
    await openPage(tester, const ChangePasswordPage());
    await tester.enterText(find.byType(TextFormField).at(0), 'wrong-password');
    await tester.enterText(find.byType(TextFormField).at(1), 'new-password');
    await tester.enterText(find.byType(TextFormField).at(2), 'new-password');
    await press(tester, 'Change Password');
    expect(find.text('Current password is incorrect.'), findsOneWidget);
    expect(await AuthService.getAuthToken(), 'existing-jwt');
    expect(find.byType(ChangePasswordPage), findsOneWidget);
    expect(find.text('Password changed successfully. Please sign in again.'),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'header and system back return to account, clear proofs and permit a different account',
      (tester) async {
    final requests = <http.Request>[];
    AuthService.httpClientOverride = MockClient((request) async {
      requests.add(request);
      return http.Response(
          jsonEncode(request.url.path.endsWith('identify')
              ? {
                  'questions': [
                    'First school?',
                    'Favourite food?',
                    'Birth city?'
                  ],
                  'challenge': 'challenge-${requests.length}'
                }
              : {'resetToken': 'old-proof'}),
          200);
    });
    await openPage(tester, const ForgotPasswordPage());
    await tester.tap(find.text('Security Question'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('security-account')), 'first-account');
    await press(tester, 'Continue');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordPage), findsOneWidget);
    expect(find.text('Question 1'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const ValueKey('security-account')),
                matching: find.byType(TextField)))
            .readOnly,
        false);
    await tester.enterText(
        find.byKey(const ValueKey('security-account')), 'second-account');
    await press(tester, 'Continue');
    expect(jsonDecode(requests.last.body)['account'], 'second-account');
    await fillAnswers(tester, 'answer');
    await press(tester, 'Verify Answers');
    await tester.enterText(
        find.byType(TextFormField).first, 'sensitive-password');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordPage), findsOneWidget);
    expect(find.text('Confirm New Password'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('security-account')), 'third-account');
    await press(tester, 'Continue');
    expect(requests.last.url.path, '/auth/security-question/identify');
    expect(jsonDecode(requests.last.body)['account'], 'third-account');
    for (final field in tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .skip(1)) {
      expect(field.controller!.text, isEmpty);
    }
    await tester.ensureVisible(find.text('Back to Login'));
    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(find.text('Open account page'), findsOneWidget);
    expect(
        requests.any((request) => request.url.path.endsWith('/reset')), false);
  });

  testWidgets(
      'Change Password back button receives taps and preserves the session',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'existing-jwt', 'auth_user': '{"id":"student"}'});
    await openPage(tester, const ChangePasswordPage());
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open account page'), findsOneWidget);
    expect(await AuthService.getAuthToken(), 'existing-jwt');
    expect((await AuthService.getCurrentUser())?['id'], 'student');
  });
}
