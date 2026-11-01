import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:global_village_app/models/family_tree.dart';
import 'package:global_village_app/pages/family_page.dart';
import 'package:global_village_app/pages/family_tree_page.dart';
import 'package:global_village_app/services/family_service.dart';

Map<String, dynamic> group(String id, {String role = 'owner'}) => {
      'id': id,
      'name': 'Family $id',
      'description': '',
      'me': {
        'userId': 'u',
        'realName': 'User',
        'kinship': 'Cousin',
        'role': role
      },
      'members': [],
      'records': [],
      'events': [],
      'checkins': [],
      'treeSummary': {'familyCount': 1, 'pendingCount': 0},
    };
Map<String, dynamic> snapshot(
        {String id = 'a',
        String role = 'owner',
        List<Map<String, dynamic>> requests = const []}) =>
    {
      'groupId': id,
      'role': role,
      'version': 'version-1',
      'nodes': [
        {'id': id, 'name': 'Family $id', 'canOpen': true}
      ],
      'connections': [],
      if (role != 'member') ...{'code': 'TREE123', 'requests': requests},
    };
Map<String, dynamic> pending({bool approved = false}) => {
      'id': 'r1',
      'sourceId': 'b',
      'targetId': 'a',
      'sourceName': 'Family b',
      'targetName': 'Family a',
      'label': 'Extended family',
      'message': 'Join our branches',
      'status': 'pending',
      'reason': '',
      'expiresAt': '2026-10-22T10:00:00.000Z',
      'requiredCount': 3,
      'approvedCount': 1,
      'myApproval': approved,
      'canCancel': false,
    };
http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});
FamilyService api(Future<http.Response> Function(http.Request) handler) =>
    FamilyService(
      client: MockClient(handler),
      baseUrl: 'http://test',
      headers: () async => {'Authorization': 'Bearer test'},
    );
Future<void> show(WidgetTester tester, Widget page,
    {double width = 390, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      home: page is FamilyPage ? Scaffold(body: page) : page,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!)));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  for (int i = 0; i < 15 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder.last);
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await reveal(tester, finder);
  await tester.tap(finder.last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('outline expresses paths without inferring personal ancestry', () {
    final data = snapshot();
    data['nodes'] = [
      {'id': 'a', 'name': 'Home', 'canOpen': true},
      {'id': 'b', 'name': 'Branch', 'canOpen': false},
      {'id': 'c', 'name': 'Remote', 'canOpen': false}
    ];
    data['connections'] = [
      {'a': 'a', 'b': 'b', 'label': 'Related'},
      {'a': 'b', 'b': 'c', 'label': 'Extended'}
    ];
    final outline = FamilyTreeSnapshot(data).outline;
    expect(outline.map((n) => n['depth']), [0, 1, 2]);
    expect(outline.last['parent'], 'b');
    expect(outline.last['label'], 'Extended');
  });
  testWidgets(
      'Family entry opens the primary tree without changing primary preference',
      (tester) async {
    final paths = <String>[];
    final service = api((r) async {
      paths.add('${r.method} ${r.url.path}');
      return response(r.url.path == '/families'
          ? {
              'primaryId': 'a',
              'groups': [group('a')]
            }
          : snapshot());
    });
    addTearDown(service.close);
    await show(tester, FamilyPage(service: service));
    await tapText(tester, 'Family tree');
    expect(find.text('No connected families yet'), findsOneWidget);
    expect(paths, contains('GET /families/a/tree'));
    expect(paths.any((p) => p.contains('/primary')), false);
  });
  testWidgets(
      'member can inspect topology but has no codes or request controls',
      (tester) async {
    final service = api((r) async => response(r.url.path == '/families'
        ? {
            'primaryId': 'a',
            'groups': [group('a', role: 'member')]
          }
        : snapshot(role: 'member')));
    addTearDown(service.close);
    await show(tester, FamilyTreePage(api: service, groupId: 'a'));
    await tapText(tester, 'Manage');
    expect(find.text('Your tree connection code'), findsNothing);
    expect(find.textContaining('Ask a family administrator'), findsOneWidget);
    await tapText(tester, 'Requests');
    expect(find.text('Approve'), findsNothing);
    expect(find.textContaining('Only family administrators'), findsOneWidget);
  });
  testWidgets(
      'send needs preview and consent and preserves inputs on uncertain failure',
      (tester) async {
    final sent = <Map<String, dynamic>>[];
    final service = api((r) async {
      if (r.url.path == '/families') {
        return response({
          'primaryId': 'a',
          'groups': [group('a')]
        });
      }
      if (r.url.path.endsWith('/preview')) {
        return response({
          'id': 'b',
          'name': 'Family b',
          'requiredApprovals': 2,
          'snapshot': 'preview-version'
        });
      }
      if (r.url.path.endsWith('/requests')) {
        sent.add(jsonDecode(r.body));
        return response({'error': 'Unable to confirm save'}, 503);
      }
      return response(snapshot());
    });
    addTearDown(service.close);
    await show(tester, FamilyTreePage(api: service, groupId: 'a'));
    await tapText(tester, 'Manage');
    final code =
        find.widgetWithText(TextFormField, 'Destination tree connection code');
    await tester.enterText(code, 'DESTINATION');
    await tapText(tester, 'Preview family');
    final send = find.widgetWithText(FilledButton, 'Send connection request');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    final checkbox = find.byType(CheckboxListTile);
    await reveal(tester, checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tapText(tester, 'Send connection request');
    expect(sent.single['confirmed'], true);
    expect(sent.single['snapshot'], 'preview-version');
    expect(find.text('Check requests before retrying'), findsOneWidget);
    await tapText(tester, 'Manage');
    expect(tester.widget<TextFormField>(code).controller!.text, 'DESTINATION');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('editing a previewed code removes destination and consent',
      (tester) async {
    final service = api((r) async => response(r.url.path == '/families'
        ? {
            'primaryId': 'a',
            'groups': [group('a')]
          }
        : r.url.path.endsWith('/preview')
            ? {
                'id': 'b',
                'name': 'Family b',
                'requiredApprovals': 2,
                'snapshot': 'v'
              }
            : snapshot()));
    addTearDown(service.close);
    await show(tester, FamilyTreePage(api: service, groupId: 'a'));
    await tapText(tester, 'Manage');
    final field =
        find.widgetWithText(TextFormField, 'Destination tree connection code');
    await tester.enterText(field, 'FIRST');
    await tapText(tester, 'Preview family');
    expect(find.text('Send connection request'), findsOneWidget);
    await tester.enterText(field, 'SECOND');
    await tester.pumpAndSettle();
    expect(find.text('Send connection request'), findsNothing);
  });
  testWidgets(
      'approving one of three groups keeps request pending, not falsely connected',
      (tester) async {
    var approved = false;
    final service = api((r) async {
      if (r.url.path == '/families') {
        return response({
          'primaryId': 'a',
          'groups': [group('a')]
        });
      }
      if (r.method == 'POST') {
        expect(jsonDecode(r.body)['decision'], 'approve');
        approved = true;
        return response({'status': 'pending'});
      }
      return response(snapshot(requests: [
        {...pending(approved: approved), 'approvedCount': approved ? 2 : 1}
      ]));
    });
    addTearDown(service.close);
    await show(tester, FamilyTreePage(api: service, groupId: 'a'));
    await tapText(tester, 'Requests (1)');
    await tapText(tester, 'Approve');
    await tapText(tester, 'Confirm');
    expect(
        find.text('Your family approved. Waiting for the remaining families.'),
        findsOneWidget);
    expect(find.text('2 of 3 families approved'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });
  testWidgets(
      'group switch requests the new scope and clears old connection form',
      (tester) async {
    final paths = <String>[];
    final service = api((r) async {
      paths.add(r.url.path);
      return response(r.url.path == '/families'
          ? {
              'primaryId': 'a',
              'groups': [group('a'), group('b')]
            }
          : snapshot(id: r.url.path.contains('/b/') ? 'b' : 'a'));
    });
    addTearDown(service.close);
    await show(tester, FamilyTreePage(api: service, groupId: 'a'));
    await tapText(tester, 'Manage');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Destination tree connection code'),
        'OLD');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Family b');
    expect(paths, contains('/families/b/tree'));
    expect(
        tester
            .widget<TextFormField>(find.widgetWithText(
                TextFormField, 'Destination tree connection code'))
            .controller!
            .text,
        isEmpty);
  });
  testWidgets(
      'disconnection shows consequence and sends the viewed topology version',
      (tester) async {
    var disconnected = false;
    Map<String, dynamic>? posted;
    final service = api((r) async {
      if (r.url.path == '/families') {
        return response({
          'primaryId': 'a',
          'groups': [group('a')]
        });
      }
      if (r.method == 'POST') {
        posted = jsonDecode(r.body);
        disconnected = true;
        return response({'ok': true});
      }
      return response(disconnected
          ? snapshot()
          : {
              ...snapshot(),
              'nodes': [
                {'id': 'a', 'name': 'Family a', 'canOpen': true},
                {'id': 'b', 'name': 'Family b', 'canOpen': false}
              ],
              'connections': [
                {
                  'id': 'edge',
                  'a': 'a',
                  'b': 'b',
                  'label': 'Extended family',
                  'disconnectSizes': [1, 1]
                }
              ]
            });
    });
    addTearDown(service.close);
    await show(tester, FamilyTreePage(api: service, groupId: 'a'));
    await tapText(tester, 'Manage');
    await tapText(tester, 'Disconnect');
    expect(find.textContaining('splits the tree into 1 and 1 families'),
        findsOneWidget);
    await tapText(tester, 'Confirm');
    expect(posted!['version'], 'version-1');
    expect(find.text('No direct connections.'), findsOneWidget);
  });
  testWidgets(
      'mobile large text fits and remote groups do not expose Open family',
      (tester) async {
    final service = api((r) async => response(r.url.path == '/families'
        ? {
            'primaryId': 'a',
            'groups': [group('a')]
          }
        : {
            ...snapshot(),
            'nodes': [
              {'id': 'a', 'name': 'Family a', 'canOpen': true},
              {
                'id': 'b',
                'name': 'A long name for the extended family branch',
                'canOpen': false
              }
            ],
            'connections': [
              {
                'id': 'e',
                'a': 'a',
                'b': 'b',
                'label': 'A jointly approved relationship'
              }
            ]
          }));
    addTearDown(service.close);
    await show(tester, FamilyTreePage(api: service, groupId: 'a'), scale: 2);
    await reveal(tester, find.text('Open family'));
    expect(find.text('Open family'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Manage');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'failed loading is retryable and never appears as an empty valid tree',
      (tester) async {
    final service = api((r) async => r.url.path == '/families'
        ? response({
            'primaryId': 'a',
            'groups': [group('a')]
          })
        : response({'error': 'Session expired'}, 401));
    addTearDown(service.close);
    await show(tester, FamilyTreePage(api: service, groupId: 'a'));
    expect(find.text('Session expired'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No connected families yet'), findsNothing);
  });
}
