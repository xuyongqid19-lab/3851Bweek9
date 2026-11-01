import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:global_village_app/pages/family_page.dart';
import 'package:global_village_app/services/family_service.dart';
import 'package:global_village_app/models/family_group.dart';

Map<String, dynamic> group(String id, String name, {String role = 'owner'}) => {
      'id': id,
      'name': name,
      'description': 'A caring family',
      'me': {
        'userId': 'u1',
        'realName': 'Chen Ming',
        'kinship': 'Dad',
        'role': role
      },
      'members': [
        {
          'userId': 'u1',
          'realName': 'Chen Ming',
          'kinship': 'Dad',
          'role': role
        },
        {
          'userId': 'u2',
          'realName': 'Chen Bo',
          'kinship': 'Uncle',
          'role': 'member'
        }
      ],
      'records': [],
      'events': [],
      'checkins': [],
      'unread': 1,
      'latest': {
        'summary': 'A family update',
        'createdAt': '2026-09-09T10:30:00Z'
      },
      'invite': 'ABC123456789ABC123',
    };
FamilyService service(Future<http.Response> Function(http.Request) handler) =>
    FamilyService(
        baseUrl: 'http://test',
        headers: () async => {},
        client: MockClient(handler));
http.Response json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json'});
Future<void> show(WidgetTester tester, Widget child, {double scale = 1}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: widget!),
      home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('empty Family gives create and join entry points',
      (tester) async {
    final api = service((_) async => json({'primaryId': null, 'groups': []}));
    addTearDown(api.close);
    await show(tester, FamilyPage(service: api));
    expect(find.text('A space for your family'), findsOneWidget);
    expect(find.text('Create family'), findsOneWidget);
    expect(find.text('Join family'), findsOneWidget);
  });
  testWidgets('primary cards and other family row route to the correct group',
      (tester) async {
    final paths = <String>[];
    final a = group('a', 'Primary Chen'), b = group('b', 'Other Chen');
    final api = service((r) async {
      paths.add(r.url.path);
      return json(r.url.path == '/families'
          ? {
              'primaryId': 'a',
              'groups': [a, b]
            }
          : b);
    });
    addTearDown(api.close);
    await show(tester, FamilyPage(service: api));
    expect(find.text('PRIMARY FAMILY'), findsOneWidget);
    expect(find.text('Activities'), findsOneWidget);
    expect(find.text('Member status'), findsOneWidget);
    expect(find.text('Other Chen'), findsOneWidget);
    await tester.ensureVisible(find.text('Other Chen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Chen'));
    await tester.pumpAndSettle();
    expect(paths, contains('/families/b'));
    expect(find.text('Family updates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'create validates real name and relationship without sending a request',
      (tester) async {
    int calls = 0;
    final api = service((_) async {
      calls++;
      return json({});
    });
    addTearDown(api.close);
    await show(tester, FamilyEntryPage(api: api, joining: false));
    final submit = find.widgetWithText(FilledButton, 'Create family');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Your real name is required'), findsOneWidget);
    expect(find.text('Your family relationship is required'), findsOneWidget);
  });
  testWidgets('failed create keeps the entered identity and family name',
      (tester) async {
    final api = service((_) async => json({'error': 'Cannot save now'}, 503));
    addTearDown(api.close);
    await show(tester, FamilyEntryPage(api: api, joining: false));
    final inputs = find.byType(TextFormField);
    await tester.enterText(inputs.at(0), 'New Chen');
    await tester.enterText(inputs.at(2), '陈明');
    await tester.enterText(inputs.at(3), '舅舅');
    final submit = find.widgetWithText(FilledButton, 'Create family');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Cannot save now'), findsOneWidget);
    expect(find.text('陈明'), findsOneWidget);
    expect(find.text('舅舅'), findsOneWidget);
    expect(find.text('New Chen'), findsOneWidget);
  });
  testWidgets('join requires preview and resets it when the code changes',
      (tester) async {
    final paths = <String>[];
    final api = service((r) async {
      paths.add(r.url.path);
      return json(
          {'id': 'g', 'name': 'Preview family', 'description': 'Group info'});
    });
    addTearDown(api.close);
    await show(tester, FamilyEntryPage(api: api, joining: true));
    final inputs = find.byType(TextFormField);
    await tester.enterText(inputs.at(0), 'CODE1');
    await tester.enterText(inputs.at(1), 'Real Person');
    await tester.enterText(inputs.at(2), 'Uncle');
    final submit = find.widgetWithText(FilledButton, 'Join family');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(paths, isEmpty);
    await tester
        .ensureVisible(find.widgetWithText(OutlinedButton, 'Preview family'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Preview family'));
    await tester.pumpAndSettle();
    expect(paths, ['/families/preview']);
    await tester.enterText(find.byType(TextFormField).at(0), 'CODE2');
    await tester.pumpAndSettle();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(paths, ['/families/preview']);
  });
  testWidgets('ordinary members cannot see invite or admin settings',
      (tester) async {
    final g = group('g', 'Chen', role: 'member');
    final api = service((_) async => json(g));
    addTearDown(api.close);
    await show(
        tester, FamilyGroupPage(api: api, groupId: 'g', initialSection: 4));
    expect(find.text('Set as my primary family'), findsOneWidget);
    expect(find.text('Edit family information'), findsNothing);
    expect(find.text('Invite code'), findsNothing);
    expect(find.text('Manage permissions'), findsNothing);
  });
  testWidgets('large text layout remains usable on a narrow display',
      (tester) async {
    final g = group('g', 'A long family name with many members');
    final api = service((_) async => json({
          'primaryId': 'g',
          'groups': [g]
        }));
    addTearDown(api.close);
    await show(tester, FamilyPage(service: api), scale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Member status'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('offline errors show retry instead of fake empty families',
      (tester) async {
    final api = service((_) async => throw http.ClientException('offline'));
    addTearDown(api.close);
    await show(tester, FamilyPage(service: api));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('A space for your family'), findsNothing);
  });
  testWidgets('activity form requires a real date and participant',
      (tester) async {
    int calls = 0;
    final api = service((_) async {
      calls++;
      return json({});
    });
    addTearDown(api.close);
    await show(
        tester,
        FamilyFormPage(
            api: api,
            group: FamilyGroup(group('g', 'Chen')),
            kind: 'activities'));
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.ensureVisible(find.text('Select a date'));
    expect(find.text('Select a date'), findsOneWidget);
  });
}
