import 'api_config.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/nearby_people_model.dart';
import 'auth_service.dart';

const nearbyLocationUpdateInterval = Duration(minutes: 5);
const nearbyLocationRetention = Duration(minutes: 5);
const nearbyCandidateLimit = 100;
const nearbyResultLimit = 10;

class NearbyPeopleService {
  NearbyPeopleService({
    NearbyLocationStore? store,
    DateTime Function()? now,
    NearbyPeopleApi? api,
  })  : _store = store ?? NearbyLocationStore.demo(),
        _now = now ?? DateTime.now,
        _api = api ?? (store == null ? CommunityNearbyPeopleApi() : null);

  static const currentUserId = 'current-user';
  static const currentUserName = 'You';

  final NearbyLocationStore _store;
  final DateTime Function() _now;
  final NearbyPeopleApi? _api;

  Future<NearbyPeopleResult> recordLocationAndFindNearbyPeople({
    required double latitude,
    required double longitude,
    double radiusMeters = 100,
    int candidateLimit = nearbyCandidateLimit,
    int maximumResults = nearbyResultLimit,
  }) async {
    final effectiveRadiusMeters = radiusMeters.clamp(10.0, 100.0).toDouble();
    final api = _api;
    if (api != null) {
      return api.recordLocationAndFindNearbyPeople(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: effectiveRadiusMeters,
        candidateLimit: candidateLimit,
        maximumResults: maximumResults,
      );
    }

    final now = _now();
    final expiresAt = now.add(nearbyLocationRetention);

    _store.upsert(
      NearbyLocationRecord(
        userId: currentUserId,
        name: currentUserName,
        relationshipStatus: NearbyRelationshipStatus.friend,
        latitude: latitude,
        longitude: longitude,
        gridCell: NearbyGrid.cellFor(latitude, longitude),
        recordedAt: now,
        expiresAt: expiresAt,
      ),
    );

    final cells = NearbyGrid.nearbyCells(latitude, longitude);
    final candidates = _store.queryActiveCandidates(
      cells: cells,
      excludingUserId: currentUserId,
      limit: candidateLimit,
      now: now,
    );

    final people = [
      for (final record in candidates)
        _personFromRecord(
          record,
          _distanceMeters(
            latitude,
            longitude,
            record.latitude,
            record.longitude,
          ),
        ),
    ].where((person) => person.distanceMeters <= effectiveRadiusMeters).toList()
      ..sort((a, b) {
        return a.distanceMeters.compareTo(b.distanceMeters);
      });

    return NearbyPeopleResult(
      people: people.take(maximumResults).toList(),
      indexCellCount: cells.length,
      candidateCount: candidates.length,
      recordedAt: now,
      expiresAt: expiresAt,
    );
  }

  void keepCurrentUserForRetention() {
    _store.extendExpiry(
      currentUserId,
      _now().add(nearbyLocationRetention),
    );
  }

  void stop() {
    keepCurrentUserForRetention();
  }

  NearbyPerson _personFromRecord(
    NearbyLocationRecord record,
    double distanceMeters,
  ) {
    return NearbyPerson(
      name: record.name,
      relationshipStatus: record.relationshipStatus,
      proximityLabel: _proximityLabel(distanceMeters),
      latitude: record.latitude,
      longitude: record.longitude,
      distanceMeters: distanceMeters,
      lastSeenAt: record.recordedAt,
    );
  }

  String _proximityLabel(double meters) {
    if (meters < 80) return 'Very close';
    if (meters < 250) return 'Nearby';
    return '${meters.round()} m away';
  }

  double _distanceMeters(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _degreesToRadians(fromLatitude);
    final lat2 = _degreesToRadians(toLatitude);
    final deltaLat = _degreesToRadians(toLatitude - fromLatitude);
    final deltaLon = _degreesToRadians(toLongitude - fromLongitude);

    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;
}

abstract class NearbyPeopleApi {
  Future<NearbyPeopleResult> recordLocationAndFindNearbyPeople({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required int candidateLimit,
    required int maximumResults,
  });
}

class CommunityNearbyPeopleApi implements NearbyPeopleApi {
  CommunityNearbyPeopleApi({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _communityApiBaseUrl();

  final http.Client _client;
  final String baseUrl;

  @override
  Future<NearbyPeopleResult> recordLocationAndFindNearbyPeople({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required int candidateLimit,
    required int maximumResults,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/community/nearby/people'),
      headers: await AuthService.authHeaders(json: true),
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'candidateLimit': candidateLimit,
        'maximumResults': maximumResults,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Nearby people request failed with ${response.statusCode}.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawPeople = data['people'] as List<dynamic>? ?? const [];
    return NearbyPeopleResult(
      people: rawPeople
          .map((item) => NearbyPerson.fromJson(item as Map<String, dynamic>))
          .toList(),
      indexCellCount: data['indexCellCount'] as int? ?? 0,
      candidateCount: data['candidateCount'] as int? ?? 0,
      recordedAt: DateTime.parse(data['recordedAt'] as String),
      expiresAt: DateTime.parse(data['expiresAt'] as String),
    );
  }
}

String _communityApiBaseUrl() {
  final portable = portableApiUrl('community');
  if (portable != null) return portable;
  const configured = String.fromEnvironment('COMMUNITY_API_BASE_URL');
  if (configured.isNotEmpty) return configured;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://localhost:3000';
}

class NearbyLocationStore {
  NearbyLocationStore([List<NearbyLocationRecord> seedRecords = const []]) {
    for (final record in seedRecords) {
      _records[record.userId] = record;
    }
  }

  factory NearbyLocationStore.demo() {
    final now = DateTime.now();
    const baseLatitude = 39.7817;
    const baseLongitude = -89.6501;

    return NearbyLocationStore([
      _demoRecord(
        userId: 'emma-wilson',
        name: 'Emma Wilson',
        relationshipStatus: NearbyRelationshipStatus.friend,
        latitude: baseLatitude + 0.0009,
        longitude: baseLongitude + 0.0007,
        now: now,
      ),
      _demoRecord(
        userId: 'liam-smith',
        name: 'Liam Smith',
        relationshipStatus: NearbyRelationshipStatus.nonFriend,
        latitude: baseLatitude - 0.0011,
        longitude: baseLongitude + 0.0012,
        now: now,
      ),
      _demoRecord(
        userId: 'noah-jones',
        name: 'Noah Jones',
        relationshipStatus: NearbyRelationshipStatus.friend,
        latitude: baseLatitude + 0.0016,
        longitude: baseLongitude - 0.0012,
        now: now,
      ),
      _demoRecord(
        userId: 'olivia-brown',
        name: 'Olivia Brown',
        relationshipStatus: NearbyRelationshipStatus.friend,
        latitude: baseLatitude - 0.0018,
        longitude: baseLongitude - 0.0007,
        now: now,
      ),
      _demoRecord(
        userId: 'sophia-davis',
        name: 'Sophia Davis',
        relationshipStatus: NearbyRelationshipStatus.friend,
        latitude: baseLatitude + 0.0004,
        longitude: baseLongitude - 0.0019,
        now: now,
      ),
      _demoRecord(
        userId: 'james-wong',
        name: 'James Wong',
        relationshipStatus: NearbyRelationshipStatus.nonFriend,
        latitude: baseLatitude + 0.0049,
        longitude: baseLongitude + 0.0038,
        now: now,
      ),
    ]);
  }

  final Map<String, NearbyLocationRecord> _records = {};

  void upsert(NearbyLocationRecord record) {
    _records[record.userId] = record;
  }

  void extendExpiry(String userId, DateTime expiresAt) {
    final record = _records[userId];
    if (record == null) return;
    _records[userId] = NearbyLocationRecord(
      userId: record.userId,
      name: record.name,
      relationshipStatus: record.relationshipStatus,
      latitude: record.latitude,
      longitude: record.longitude,
      gridCell: record.gridCell,
      recordedAt: record.recordedAt,
      expiresAt: expiresAt,
    );
  }

  List<NearbyLocationRecord> queryActiveCandidates({
    required List<String> cells,
    required String excludingUserId,
    required int limit,
    required DateTime now,
  }) {
    removeExpired(now);

    final cellSet = cells.toSet();
    final candidates = _records.values
        .where(
          (record) =>
              record.userId != excludingUserId &&
              cellSet.contains(record.gridCell) &&
              !record.isExpired(now),
        )
        .toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    return candidates.take(limit).toList();
  }

  void removeExpired(DateTime now) {
    _records.removeWhere((_, record) => record.isExpired(now));
  }

  int activeRecordCount(DateTime now) {
    removeExpired(now);
    return _records.length;
  }

  NearbyLocationRecord? recordFor(String userId) => _records[userId];

  static NearbyLocationRecord _demoRecord({
    required String userId,
    required String name,
    required NearbyRelationshipStatus relationshipStatus,
    required double latitude,
    required double longitude,
    required DateTime now,
  }) {
    return NearbyLocationRecord(
      userId: userId,
      name: name,
      relationshipStatus: relationshipStatus,
      latitude: latitude,
      longitude: longitude,
      gridCell: NearbyGrid.cellFor(latitude, longitude),
      recordedAt: now.subtract(const Duration(minutes: 1)),
      expiresAt: now.add(nearbyLocationRetention),
    );
  }
}

class NearbyGrid {
  static const double cellSizeDegrees = 0.0045;

  static String cellFor(double latitude, double longitude) {
    final latIndex = (latitude / cellSizeDegrees).floor();
    final lonIndex = (longitude / cellSizeDegrees).floor();
    return '$latIndex:$lonIndex';
  }

  static List<String> nearbyCells(double latitude, double longitude) {
    final latIndex = (latitude / cellSizeDegrees).floor();
    final lonIndex = (longitude / cellSizeDegrees).floor();
    return [
      for (var latOffset = -1; latOffset <= 1; latOffset++)
        for (var lonOffset = -1; lonOffset <= 1; lonOffset++)
          '${latIndex + latOffset}:${lonIndex + lonOffset}',
    ];
  }
}
