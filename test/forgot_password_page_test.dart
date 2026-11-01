import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/pages/forgot_password_page.dart';
import 'package:global_village_app/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> openPage(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
    return Scaffold(
        body: TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const ForgotPasswordPage(),
      )),
      child: const Text('Open recovery'),
    ));
  })));
  await tester.tap(find.text('Open recovery'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    AuthService.httpClientOverride?.close();
    AuthService.httpClientOverride = null;
  });

  testWidgets('invalid email does not call the server', (tester) async {
    var calls = 0;
    AuthService.httpClientOverride = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    await openPage(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.ensureVisible(find.text('Send Code'));
    await tester.tap(find.text('Send Code'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('send code starts cooldown and verified reset returns to login',
      (tester) async {
    final requests = <http.Request>[];
    SharedPreferences.setMockInitialValues(
        {'auth_token': 'old-session', 'auth_user': '{}'});
    AuthService.httpClientOverride = MockClient((request) async {
      requests.add(request);
      return http.Response(
          jsonEncode(request.url.path.endsWith('forgot-password')
              ? {'message': 'Check your email.', 'retryAfterSeconds': 60}
              : {'message': 'Password reset successfully.'}),
          200);
    });
    await openPage(tester);
    await tester.enterText(
        find.byType(TextFormField).at(0), 'Student@Example.com');
    await tester.ensureVisible(find.text('Send Code'));
    await tester.tap(find.text('Send Code'));
    await tester.pumpAndSettle();
    expect(find.text('Resend in 60s'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(jsonDecode(requests.first.body)['email'], 'student@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.enterText(find.byType(TextFormField).at(2), 'new-password');
    await tester.enterText(find.byType(TextFormField).at(3), 'new-password');
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await tester.pumpAndSettle();
    expect(find.text('Open recovery'), findsOneWidget);
    expect(requests.last.url.path, '/auth/reset-password');
    expect(jsonDecode(requests.last.body), {
      'email': 'student@example.com',
      'code': '123456',
      'newPassword': 'new-password',
    });
    expect(await AuthService.getAuthToken(), isNull);
  });

  testWidgets('mail failure shows error and never claims delivery',
      (tester) async {
    AuthService.httpClientOverride = MockClient((_) async =>
        http.Response(jsonEncode({'error': 'Mail service unavailable.'}), 503));
    await openPage(tester);
    await tester.enterText(
        find.byType(TextFormField).at(0), 'student@example.com');
    await tester.ensureVisible(find.text('Send Code'));
    await tester.tap(find.text('Send Code'));
    await tester.pumpAndSettle();
    expect(find.text('Mail service unavailable.'), findsOneWidget);
    expect(find.text('Send Code'), findsOneWidget);
    expect(find.text('Resend in 60s'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('incorrect code keeps recovery open and preserves the session',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'old-session'});
    AuthService.httpClientOverride = MockClient((request) async =>
        request.url.path.endsWith('forgot-password')
            ? http.Response(
                jsonEncode(
                    {'message': 'Check your email.', 'retryAfterSeconds': 60}),
                200)
            : http.Response(
                jsonEncode({'error': 'Invalid or expired code.'}), 400));
    await openPage(tester);
    await tester.enterText(
        find.byType(TextFormField).at(0), 'student@example.com');
    await tester.ensureVisible(find.text('Send Code'));
    await tester.tap(find.text('Send Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.enterText(find.byType(TextFormField).at(2), 'new-password');
    await tester.enterText(find.byType(TextFormField).at(3), 'new-password');
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordPage), findsOneWidget);
    expect(find.text('Invalid or expired code.'), findsOneWidget);
    expect(await AuthService.getAuthToken(), 'old-session');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
