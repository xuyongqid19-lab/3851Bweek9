import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:global_village_app/models/nearby_people_model.dart';
import 'package:global_village_app/pages/community_page.dart';
import 'package:global_village_app/services/nearby_people_service.dart';

class _RecordingNearbyApi implements NearbyPeopleApi {
  _RecordingNearbyApi({this.people = const []});

  final List<NearbyPerson> people;
  int calls = 0;
  double? latitude;
  double? longitude;
  double? radiusMeters;

  @override
  Future<NearbyPeopleResult> recordLocationAndFindNearbyPeople({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required int candidateLimit,
    required int maximumResults,
  }) async {
    calls++;
    this.latitude = latitude;
    this.longitude = longitude;
    this.radiusMeters = radiusMeters;
    final now = DateTime.now();
    return NearbyPeopleResult(
      people: people,
      indexCellCount: 9,
      candidateCount: 0,
      recordedAt: now,
      expiresAt: now.add(nearbyLocationRetention),
    );
  }
}

NearbyPerson _person(String name, double meters) => NearbyPerson(
      name: name,
      relationshipStatus: NearbyRelationshipStatus.nonFriend,
      proximityLabel: '${meters.round()} m away',
      latitude: 51.5,
      longitude: -0.12,
      distanceMeters: meters,
      lastSeenAt: DateTime.now(),
    );

Position _position(double latitude, double longitude) => Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 15,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Future<void> _openPage(
  WidgetTester tester,
  _RecordingNearbyApi api,
  Future<Position?> Function() locationProvider,
) async {
  await tester.pumpWidget(MaterialApp(
    home: NearbyFriendsMapPage(
      nearbyService: NearbyPeopleService(api: api),
      locationProvider: locationProvider,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nearby map uses the actual position for the blue dot and center',
      (tester) async {
    final api = _RecordingNearbyApi();
    await _openPage(tester, api, () async => _position(51.5, -0.12));

    expect(api.calls, 1);
    expect(api.latitude, 51.5);
    expect(api.longitude, -0.12);

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter.latitude, 51.5);
    expect(map.options.initialCenter.longitude, -0.12);

    final markers =
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(markers.first.point.latitude, 51.5);
    expect(markers.first.point.longitude, -0.12);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing location does not publish demo coordinates or blue dot',
      (tester) async {
    final api = _RecordingNearbyApi();
    await _openPage(tester, api, () async => null);

    expect(api.calls, 0);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.textContaining('Location unavailable'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('location update moves the blue dot to the latest position',
      (tester) async {
    final api = _RecordingNearbyApi();
    var locationCalls = 0;
    await _openPage(tester, api, () async {
      locationCalls++;
      return locationCalls == 1
          ? _position(51.5, -0.12)
          : _position(51.51, -0.11);
    });

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(api.calls, 2);
    expect(api.latitude, 51.51);
    expect(api.longitude, -0.11);
    final markers =
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(markers.first.point.latitude, 51.51);
    expect(markers.first.point.longitude, -0.11);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('range choices filter cached people without another API call',
      (tester) async {
    final api = _RecordingNearbyApi(people: [
      _person('Eight', 8),
      _person('Eighteen', 18),
      _person('Forty', 40),
      _person('Ninety', 90),
    ]);
    await _openPage(tester, api, () async => _position(51.5, -0.12));

    expect(api.radiusMeters, 100);
    expect(find.text('Forty'), findsWidgets);
    expect(find.text('Ninety'), findsNothing);

    await tester.tap(find.text('10 m'));
    await tester.pumpAndSettle();
    expect(find.text('Eight'), findsWidgets);
    expect(find.text('Eighteen'), findsNothing);

    await tester.tap(find.text('20 m'));
    await tester.pumpAndSettle();
    expect(find.text('Eighteen'), findsWidgets);
    expect(find.text('Forty'), findsNothing);

    await tester.tap(find.text('100 m'));
    await tester.pumpAndSettle();
    expect(find.text('Ninety'), findsWidgets);
    expect(api.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('map zoom updates the discrete search range', (tester) async {
    final api = _RecordingNearbyApi(people: [
      _person('Eight', 8),
      _person('Forty', 40),
    ]);
    await _openPage(tester, api, () async => _position(51.5, -0.12));

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    map.options.onPositionChanged!(
      MapCamera.initialCamera(map.options).withPosition(zoom: 18.9),
      true,
    );
    await tester.pumpAndSettle();

    final radiusControl = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    expect(radiusControl.selected, {10});

    expect(find.text('Eight'), findsWidgets);
    expect(find.text('Forty'), findsNothing);
    expect(api.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('range controls fit a narrow mobile screen', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _RecordingNearbyApi(people: [_person('Eight', 8)]);
    await _openPage(tester, api, () async => _position(51.5, -0.12));
    expect(find.text('100 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
