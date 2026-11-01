enum NearbyRelationshipStatus {
  friend,
  nonFriend,
}

class NearbyLocationRecord {
  const NearbyLocationRecord({
    required this.userId,
    required this.name,
    required this.relationshipStatus,
    required this.latitude,
    required this.longitude,
    required this.gridCell,
    required this.recordedAt,
    required this.expiresAt,
  });

  final String userId;
  final String name;
  final NearbyRelationshipStatus relationshipStatus;
  final double latitude;
  final double longitude;
  final String gridCell;
  final DateTime recordedAt;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  bool get isFriend => relationshipStatus == NearbyRelationshipStatus.friend;
}

class NearbyPerson {
  const NearbyPerson({
    required this.name,
    required this.relationshipStatus,
    required this.proximityLabel,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.lastSeenAt,
  });

  factory NearbyPerson.fromJson(Map<String, dynamic> json) {
    final relationship = json['relationshipStatus']?.toString();
    return NearbyPerson(
      name: json['name'] as String,
      relationshipStatus: relationship == NearbyRelationshipStatus.friend.name
          ? NearbyRelationshipStatus.friend
          : NearbyRelationshipStatus.nonFriend,
      proximityLabel: json['proximityLabel'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
    );
  }

  final String name;
  final NearbyRelationshipStatus relationshipStatus;
  final String proximityLabel;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final DateTime lastSeenAt;

  bool get isFriend => relationshipStatus == NearbyRelationshipStatus.friend;
}

class NearbyPeopleResult {
  const NearbyPeopleResult({
    required this.people,
    required this.indexCellCount,
    required this.candidateCount,
    required this.recordedAt,
    required this.expiresAt,
  });

  final List<NearbyPerson> people;
  final int indexCellCount;
  final int candidateCount;
  final DateTime recordedAt;
  final DateTime expiresAt;
}
