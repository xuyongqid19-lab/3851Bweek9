import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/data/security_questions.dart';
import 'package:global_village_app/pages/profile_page.dart';
import 'package:global_village_app/pages/register_page.dart';
import 'package:global_village_app/pages/security_questions_page.dart';
import 'package:global_village_app/services/auth_service.dart';
import 'package:global_village_app/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> choose(WidgetTester tester, int index, String question) async {
  final choice = find.byKey(ValueKey('question-choice-$index'));
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text(question).last);
  await tester.pumpAndSettle();
}

Future<void> fillQuestions(WidgetTester tester, {bool custom = false}) async {
  for (var index = 0; index < 3; index++) {
    await choose(tester, index,
        custom ? customSecurityQuestion : securityQuestionPresets[index]);
    if (custom) {
      final field = find.byKey(ValueKey('custom-question-$index'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'My custom question number ${index + 1}?');
    }
    final answer = find.descendant(
        of: find.byKey(ValueKey('question-answer-$index')),
        matching: find.byType(TextFormField));
    await tester.ensureVisible(answer);
    await tester.enterText(answer, 'answer ${index + 1}');
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> registerFields(WidgetTester tester) async {
  await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const RegisterPage()));
  await tester.enterText(find.byType(TextFormField).at(0), 'Student');
  await tester.tap(find.byType(TextFormField).at(1));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  for (final entry in {
    3: 'student',
    4: 'student@example.com',
    5: '123456789',
    6: 'password123',
    7: 'password123'
  }.entries) {
    final field = find.byType(TextFormField).at(entry.key);
    await tester.ensureVisible(field);
    await tester.enterText(field, entry.value);
  }
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(
      {'auth_token': 'session', 'auth_user': '{}'}));
  tearDown(() {
    AuthService.httpClientOverride?.close();
    AuthService.httpClientOverride = null;
  });

  testWidgets(
      'registration without questions stays optional; opting in requires a complete set',
      (tester) async {
    final requests = <http.Request>[];
    AuthService.httpClientOverride = MockClient((request) async {
      requests.add(request);
      return http.Response(
          jsonEncode({'error': 'Test keeps registration open.'}), 400);
    });
    await registerFields(tester);
    await tapText(tester, 'Register');
    expect(requests.length, 1);
    expect(jsonDecode(requests.single.body)['securityQuestions'], isEmpty);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await choose(tester, 0, securityQuestionPresets.first);
    await tapText(tester, 'Register');
    expect(requests.length, 1);
    expect(find.text('Select a security question.'), findsNWidgets(2));
    await fillQuestions(tester, custom: true);
    await tapText(tester, 'Register');
    expect(requests.length, 2);
    final values = jsonDecode(requests.last.body)['securityQuestions'] as List;
    expect(values.length, 3);
    expect(values.last['question'], 'My custom question number 3?');
    expect(values.last['answer'], 'answer 3');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'management loads status, saves three custom questions with JWT and clears answers',
      (tester) async {
    final requests = <http.Request>[];
    AuthService.httpClientOverride = MockClient((request) async {
      requests.add(request);
      return http.Response(
          jsonEncode(request.method == 'GET'
              ? {'configured': false, 'hasLocalPassword': true, 'questions': []}
              : {'message': 'Security questions saved successfully.'}),
          200);
    });
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light, home: const SecurityQuestionsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Three security questions are not yet configured.'),
        findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField).first, 'current-password');
    await fillQuestions(tester, custom: true);
    await tapText(tester, 'Save Security Questions');
    expect(requests.last.headers['Authorization'], 'Bearer session');
    expect(
        jsonDecode(requests.last.body)['currentPassword'], 'current-password');
    expect((jsonDecode(requests.last.body)['securityQuestions'] as List).length,
        3);
    expect(
        find.text('Three security questions are configured.'), findsOneWidget);
    expect(find.text('Security questions saved successfully.'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    for (final field in fields.where((field) => field.obscureText)) {
      expect(field.controller!.text, isEmpty);
    }
    expect(await AuthService.getAuthToken(), 'session');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'duplicate custom questions are rejected before sending; wrong password stays on page',
      (tester) async {
    var posts = 0;
    AuthService.httpClientOverride = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'configured': true,
              'hasLocalPassword': true,
              'questions': securityQuestionPresets.take(3).toList(),
            }),
            200);
      }
      posts++;
      return http.Response(
          jsonEncode({'error': 'Current password is incorrect.'}), 400);
    });
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light, home: const SecurityQuestionsPage()));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty);
    await tester.enterText(find.byType(TextFormField).first, 'wrong-password');
    await fillQuestions(tester, custom: true);
    final duplicate = find.byKey(const ValueKey('custom-question-1'));
    await tester.ensureVisible(duplicate);
    await tester.enterText(duplicate, '  MY CUSTOM QUESTION NUMBER 1?  ');
    await tapText(tester, 'Save Security Questions');
    expect(posts, 0);
    expect(find.text('Choose three different questions.'), findsWidgets);
    await tester.ensureVisible(duplicate);
    await tester.enterText(duplicate, 'My custom question number 2?');
    await tapText(tester, 'Save Security Questions');
    expect(posts, 1);
    expect(find.text('Current password is incorrect.'), findsOneWidget);
    expect(find.byType(SecurityQuestionsPage), findsOneWidget);
    expect(await AuthService.getAuthToken(), 'session');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Google-only status explains the limitation and offers no password bypass',
      (tester) async {
    AuthService.httpClientOverride = MockClient((_) async => http.Response(
        jsonEncode({
          'configured': false,
          'hasLocalPassword': false,
          'questions': [],
        }),
        200));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light, home: const SecurityQuestionsPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('This account uses Google sign-in'),
        findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Save Security Questions'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'My Profile Security Questions entry opens and returns with the session intact',
      (tester) async {
    AuthService.httpClientOverride = MockClient((request) async =>
        http.Response(
            jsonEncode(request.url.path == '/auth/me'
                ? {
                    'user': {
                      'id': 'student',
                      'fullName': 'Student',
                      'email': 'student@example.com'
                    }
                  }
                : {
                    'configured': false,
                    'hasLocalPassword': true,
                    'questions': []
                  }),
            200));
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const ProfilePage()));
    await tester.pumpAndSettle();
    await tapText(tester, 'Security Questions');
    expect(find.byType(SecurityQuestionsPage), findsOneWidget);
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.text('My Profile'), findsOneWidget);
    expect(await AuthService.getAuthToken(), 'session');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
