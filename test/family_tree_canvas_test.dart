import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/models/family_tree.dart';
import 'package:global_village_app/pages/family_tree_canvas_page.dart';
import 'package:global_village_app/pages/family_tree_page.dart';
import 'family_tree_test.dart' as fixture;

FamilyTreeSnapshot graph(int count, {bool chain = false}) =>
    FamilyTreeSnapshot({
      ...fixture.snapshot(),
      'groupId': '0',
      'nodes': [
        for (var i = 0; i < count; i++)
          {
            'id': '$i',
            'name': i == 0 ? 'Chen Home' : 'Family $i',
            'canOpen': i == 0
          }
      ],
      'connections': [
        for (var i = 1; i < count; i++)
          {
            'id': 'e$i',
            'a': chain ? '${i - 1}' : '0',
            'b': '$i',
            'label': 'Extended family'
          }
      ],
    });

void main() {
  for (final count in [1, 5, 50]) {
    for (final chain in [false, true]) {
      test('layout fits $count nodes, chain=$chain without overlap', () {
        final l = FamilyTreeLayout(graph(count, chain: chain), textScale: 2);
        final rects = l.positions.values.map((p) => p & l.nodeSize).toList();
        expect(rects.length, count);
        for (var i = 0; i < rects.length; i++) {
          expect((Offset.zero & l.size).contains(rects[i].bottomRight), true);
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), false);
          }
        }
      });
    }
  }
  testWidgets('mobile enlarged text, fit, zoom, pan and connected-only details',
      (tester) async {
    final service = fixture.api((_) async => fixture.response(graph(5).data));
    addTearDown(service.close);
    await fixture.show(
        tester, FamilyTreeCanvasPage(api: service, initial: graph(5)),
        scale: 1.5);
    expect(tester.takeException(), null);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final controller = viewer.transformationController!;
    final original = controller.value.clone();
    await tester.tap(find.text('Zoom in'));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(),
        greaterThan(original.getMaxScaleOnAxis()));
    await tester.drag(find.byType(InteractiveViewer), const Offset(90, 30));
    await tester.pumpAndSettle();
    expect(controller.value.storage[12], isNot(original.storage[12]));
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(controller.value, original);
    await tester.tap(find.text('Family 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connected group only'), findsOneWidget);
    expect(find.text('Open family'), findsNothing);
    expect(find.text('Chen Home: Extended family'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100%'));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), 1);
    expect(tester.takeException(), null);
  });
  testWidgets('refresh replaces topology and revoked access hides old cards',
      (tester) async {
    var allowed = true;
    final service = fixture.api((_) async => allowed
        ? fixture.response(graph(2).data)
        : fixture.response({'error': 'Access revoked'}, 403));
    addTearDown(service.close);
    await fixture.show(
        tester, FamilyTreeCanvasPage(api: service, initial: graph(5)),
        width: 1280);
    await tester.tap(find.byTooltip('Refresh tree'));
    await tester.pumpAndSettle();
    expect(find.text('Family 4'), findsNothing);
    expect(find.text('Family 1'), findsOneWidget);
    allowed = false;
    await tester.tap(find.byTooltip('Refresh tree'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('Chen Home'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    allowed = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Chen Home'), findsOneWidget);
  });
  testWidgets('outline opens large tree and returns without changing primary',
      (tester) async {
    final requests = <String>[];
    final service = fixture.api((r) async {
      requests.add(r.url.path);
      return fixture.response(r.url.path == '/families'
          ? {
              'primaryId': '0',
              'groups': [fixture.group('0')]
            }
          : graph(3).data);
    });
    addTearDown(service.close);
    await fixture.show(tester, FamilyTreePage(api: service, groupId: '0'));
    await fixture.tapText(tester, 'Open large tree');
    expect(find.text('Large family tree'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open large tree'), findsOneWidget);
    expect(requests.any((p) => p.contains('/primary')), false);
  });
  testWidgets('long names and labels do not overflow', (tester) async {
    final data = graph(2).data;
    data['nodes'][1]['name'] =
        'A very long family name repeated to cover the entire permitted family name';
    data['connections'][0]['label'] =
        'An agreed extended household relationship label that has eighty characters in all.';
    final service = fixture.api((_) async => fixture.response(data));
    addTearDown(service.close);
    await fixture.show(tester,
        FamilyTreeCanvasPage(api: service, initial: FamilyTreeSnapshot(data)),
        scale: 2);
    expect(tester.takeException(), null);
    await tester.tap(find.text(data['nodes'][1]['name']));
    await tester.pumpAndSettle();
    expect(find.text('Chen Home: ${data['connections'][0]['label']}'),
        findsOneWidget);
    expect(tester.takeException(), null);
  });
}
