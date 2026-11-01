import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/models/nearby_people_model.dart';
import 'package:global_village_app/services/nearby_people_service.dart';

void main() {
  test('records the current user location with a five minute expiry', () async {
    var now = DateTime(2026, 1, 1, 12);
    final store = NearbyLocationStore();
    final service = NearbyPeopleService(store: store, now: () => now);

    final result = await service.recordLocationAndFindNearbyPeople(
      latitude: 39.7817,
      longitude: -89.6501,
    );

    final record = store.recordFor(NearbyPeopleService.currentUserId);
    expect(record, isNotNull);
    expect(record!.recordedAt, now);
    expect(record.expiresAt, now.add(nearbyLocationRetention));
    expect(result.expiresAt, now.add(nearbyLocationRetention));

    service.stop();
    expect(
      store.recordFor(NearbyPeopleService.currentUserId)!.expiresAt,
      now.add(nearbyLocationRetention),
    );

    now = now.add(nearbyLocationRetention).add(const Duration(seconds: 1));
    expect(store.activeRecordCount(now), 0);
  });

  test('limits indexed candidates to 100 before distance filtering', () async {
    final now = DateTime(2026, 1, 1, 12);
    const latitude = 39.7817;
    const longitude = -89.6501;
    final records = [
      for (var i = 0; i < 120; i++)
        NearbyLocationRecord(
          userId: 'candidate-$i',
          name: 'Candidate $i',
          relationshipStatus: i.isEven
              ? NearbyRelationshipStatus.friend
              : NearbyRelationshipStatus.nonFriend,
          latitude: latitude + (i * 0.000001),
          longitude: longitude + (i * 0.000001),
          gridCell: NearbyGrid.cellFor(
            latitude + (i * 0.000001),
            longitude + (i * 0.000001),
          ),
          recordedAt: now.subtract(Duration(seconds: i)),
          expiresAt: now.add(nearbyLocationRetention),
        ),
    ];
    final service = NearbyPeopleService(
      store: NearbyLocationStore(records),
      now: () => now,
    );

    final result = await service.recordLocationAndFindNearbyPeople(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: 100,
    );

    expect(result.indexCellCount, 9);
    expect(result.candidateCount, nearbyCandidateLimit);
    expect(result.people, hasLength(nearbyResultLimit));
    expect(
        result.people.every((person) => person.distanceMeters <= 100), isTrue);
  });

  test('does not return expired nearby records', () async {
    final now = DateTime(2026, 1, 1, 12);
    const latitude = 39.7817;
    const longitude = -89.6501;
    final store = NearbyLocationStore([
      NearbyLocationRecord(
        userId: 'expired-user',
        name: 'Expired User',
        relationshipStatus: NearbyRelationshipStatus.friend,
        latitude: latitude + 0.0001,
        longitude: longitude + 0.0001,
        gridCell: NearbyGrid.cellFor(latitude + 0.0001, longitude + 0.0001),
        recordedAt: now.subtract(const Duration(minutes: 6)),
        expiresAt: now.subtract(const Duration(seconds: 1)),
      ),
    ]);
    final service = NearbyPeopleService(store: store, now: () => now);

    final result = await service.recordLocationAndFindNearbyPeople(
      latitude: latitude,
      longitude: longitude,
    );

    expect(result.people, isEmpty);
    expect(store.recordFor('expired-user'), isNull);
  });

  test('defaults to a maximum search radius of 100 metres', () async {
    final now = DateTime(2026, 1, 1, 12);
    const latitude = 39.7817;
    const longitude = -89.6501;
    final store = NearbyLocationStore([
      for (final offset in [0.00045, 0.00135])
        NearbyLocationRecord(
          userId: 'candidate-$offset',
          name: 'Candidate $offset',
          relationshipStatus: NearbyRelationshipStatus.nonFriend,
          latitude: latitude + offset,
          longitude: longitude,
          gridCell: NearbyGrid.cellFor(latitude + offset, longitude),
          recordedAt: now,
          expiresAt: now.add(nearbyLocationRetention),
        ),
    ]);
    final service = NearbyPeopleService(store: store, now: () => now);

    final result = await service.recordLocationAndFindNearbyPeople(
      latitude: latitude,
      longitude: longitude,
    );

    expect(result.people, hasLength(1));
    expect(result.people.single.distanceMeters, lessThanOrEqualTo(100));
  });
}
