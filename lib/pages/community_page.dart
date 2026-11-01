import '../services/api_config.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/chat_model.dart';
import '../models/nearby_people_model.dart';
import '../services/auth_service.dart';
import '../services/nearby_people_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_widgets.dart';
import 'chat_detail_page.dart';
import 'find_friends_page.dart';
import 'home_page.dart';

final ValueNotifier<List<CommunityActivity>> createdActivityNotifications =
    ValueNotifier<List<CommunityActivity>>([]);
final ValueNotifier<Position?> sharedUserLocation =
    ValueNotifier<Position?>(null);
final ValueNotifier<List<CommunityActivity>> communityActivityDatabase =
    ValueNotifier<List<CommunityActivity>>(_activities);
final ValueNotifier<Map<String, List<String>>> activityAttendees =
    ValueNotifier<Map<String, List<String>>>({});

const _demoLatitude = 39.7817;
const _demoLongitude = -89.6501;
const _nearbyPeopleMaxRadiusMeters = 100.0;
const _nearbyActivityRadiusMeters = 500.0;
const _nearbyRadiusSteps = <int>[10, 20, 50, 100];
const _communityBlue = Color(0xFF1769C2);
const _communityBlueSoft = Color(0xFFEAF3FF);
const _communityCanvas = Color(0xFFF6FAFF);
const _communityInk = Color(0xFF203047);
const _communityMuted = Color(0xFF58708B);
const _communityBorder = Color(0xFFD9E6F4);

double _mapZoomForRadius(int radiusMeters) => switch (radiusMeters) {
      10 => 18.9,
      20 => 18.4,
      50 => 17.8,
      _ => 17.2,
    };

int _radiusForMapZoom(double zoom) {
  if (zoom >= 18.65) return 10;
  if (zoom >= 18.1) return 20;
  if (zoom >= 17.5) return 50;
  return 100;
}

final ValueNotifier<List<NearbyPerson>> nearbyPeopleResults =
    ValueNotifier<List<NearbyPerson>>([]);

final _communityActivityRepository = CommunityActivityRepository();

class CommunityActivitySnapshot {
  const CommunityActivitySnapshot({
    required this.activities,
    required this.attendeesByActivity,
  });

  final List<CommunityActivity> activities;
  final Map<String, List<String>> attendeesByActivity;
}

class CommunityActivityRepository {
  CommunityActivityRepository({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _communityApiBaseUrl();

  final http.Client _client;
  final String baseUrl;

  Future<CommunityActivitySnapshot> fetchActivities({
    double? latitude,
    double? longitude,
  }) async {
    final query = <String, String>{};
    if (latitude != null && longitude != null) {
      query['lat'] = latitude.toString();
      query['lng'] = longitude.toString();
    }
    final uri = _uri('/community/activities', query);
    final response = await _client.get(
      uri,
      headers: await AuthService.authHeaders(requireAuth: false),
    );
    _throwIfFailed(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawActivities = data['activities'] as List<dynamic>;
    final activities = rawActivities
        .map((item) => CommunityActivity.fromJson(item as Map<String, dynamic>))
        .toList();
    final attendeesByActivity = <String, List<String>>{};
    for (final item in rawActivities) {
      final activityJson = item as Map<String, dynamic>;
      final attendees = activityJson['attendees'] as List<dynamic>? ?? const [];
      attendeesByActivity[activityJson['id'] as String] =
          attendees.map((name) => name as String).toList();
    }

    return CommunityActivitySnapshot(
      activities: activities,
      attendeesByActivity: attendeesByActivity,
    );
  }

  Future<CommunityActivity> createActivity(CommunityActivity activity) async {
    final response = await _client.post(
      _uri('/community/activities'),
      headers: await AuthService.authHeaders(json: true),
      body: jsonEncode(activity.toJson()),
    );
    _throwIfFailed(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return CommunityActivity.fromJson(data['activity'] as Map<String, dynamic>);
  }

  Future<CommunityActivity> updateActivity(CommunityActivity activity) async {
    final response = await _client.put(
      _uri('/community/activities/${activity.id}'),
      headers: await AuthService.authHeaders(json: true),
      body: jsonEncode(activity.toJson()),
    );
    _throwIfFailed(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return CommunityActivity.fromJson(data['activity'] as Map<String, dynamic>);
  }

  Future<void> deleteActivity(String activityId) async {
    final response = await _client.delete(
      _uri('/community/activities/$activityId'),
      headers: await AuthService.authHeaders(),
    );
    _throwIfFailed(response);
  }

  Future<void> joinActivity(String activityId) async {
    final response = await _client.post(
      _uri('/community/activities/$activityId/attendees'),
      headers: await AuthService.authHeaders(),
    );
    _throwIfFailed(response);
  }

  Future<void> leaveActivity(String activityId) async {
    final response = await _client.delete(
      _uri('/community/activities/$activityId/attendees/current'),
      headers: await AuthService.authHeaders(),
    );
    _throwIfFailed(response);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  void _throwIfFailed(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Community API failed with ${response.statusCode}.');
    }
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

class SelectedLocation {
  const SelectedLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String address;
  final double latitude;
  final double longitude;
}

enum ActivityCategory {
  sports('Sports', Icons.sports_basketball_outlined),
  study('Study', Icons.menu_book_outlined),
  volunteer('Volunteer', Icons.volunteer_activism_outlined),
  family('Family', Icons.family_restroom),
  social('Social', Icons.groups_outlined),
  health('Health', Icons.favorite_border),
  others('Others', Icons.more_horiz);

  const ActivityCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

ActivityCategory _categoryFromName(String? name) {
  return ActivityCategory.values.firstWhere(
    (category) => category.name == name,
    orElse: () => ActivityCategory.social,
  );
}

class CommunityActivity {
  const CommunityActivity({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.location,
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.groupName,
    this.isOwnedByCurrentUser = false,
  });

  final String id;
  final String title;
  final String dateTime;
  final String location;
  final ActivityCategory category;
  final String description;
  final double latitude;
  final double longitude;
  final String groupName;
  final bool isOwnedByCurrentUser;

  CommunityActivity copyWith({
    String? id,
    String? title,
    String? dateTime,
    String? location,
    ActivityCategory? category,
    String? description,
    double? latitude,
    double? longitude,
    String? groupName,
    bool? isOwnedByCurrentUser,
  }) {
    return CommunityActivity(
      id: id ?? this.id,
      title: title ?? this.title,
      dateTime: dateTime ?? this.dateTime,
      location: location ?? this.location,
      category: category ?? this.category,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      groupName: groupName ?? this.groupName,
      isOwnedByCurrentUser: isOwnedByCurrentUser ?? this.isOwnedByCurrentUser,
    );
  }

  factory CommunityActivity.fromJson(Map<String, dynamic> json) {
    return CommunityActivity(
      id: json['id'] as String,
      title: json['title'] as String,
      dateTime: json['dateTime'] as String,
      location: json['location'] as String,
      category: _categoryFromName(json['category'] as String?),
      description: json['description'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      groupName: json['groupName'] as String,
      isOwnedByCurrentUser: json['isOwnedByCurrentUser'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'dateTime': dateTime,
      'location': location,
      'category': category.name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'groupName': groupName,
    };
  }
}

const _activities = [
  CommunityActivity(
    id: 'basketball-match',
    title: 'Basketball Match',
    dateTime: 'Sun, May 25 - 9:00 AM',
    location: 'Riverside Park Basketball Court',
    category: ActivityCategory.sports,
    description:
        'Join us for a friendly match and fun together as a community.',
    latitude: _demoLatitude + 0.001,
    longitude: _demoLongitude + 0.001,
    groupName: 'Basketball Match Group',
  ),
  CommunityActivity(
    id: 'green-space-picnic',
    title: 'Green Space Picnic',
    dateTime: 'Sun, May 12 - 3:00 PM',
    location: 'Riverside Park - Main Lawn',
    category: ActivityCategory.social,
    description:
        'Bring snacks, blankets, and good energy for a relaxed afternoon together.',
    latitude: _demoLatitude + 0.002,
    longitude: _demoLongitude - 0.001,
    groupName: 'Green Space Picnic Group',
  ),
  CommunityActivity(
    id: 'morning-yoga',
    title: 'Morning Yoga in the Park',
    dateTime: 'Sat, May 25 - 7:00 AM',
    location: 'Central Park',
    category: ActivityCategory.health,
    description:
        'Start the morning with a relaxed community walk through the park.',
    latitude: _demoLatitude + 0.0025,
    longitude: _demoLongitude + 0.002,
    groupName: 'Morning Yoga Group',
  ),
  CommunityActivity(
    id: 'community-clean-up',
    title: 'Community Clean-Up',
    dateTime: 'Sat, May 31 - 10:00 AM',
    location: 'City Center',
    category: ActivityCategory.volunteer,
    description:
        'Help keep our shared spaces clean. Gloves and bags will be provided.',
    latitude: _demoLatitude + 0.003,
    longitude: _demoLongitude - 0.002,
    groupName: 'Community Clean-Up Group',
  ),
  CommunityActivity(
    id: 'book-club-meetup',
    title: 'Book Club Meetup',
    dateTime: 'May 15 - 7:00 PM',
    location: 'Community Library',
    category: ActivityCategory.study,
    description:
        'Discuss this month\'s book and vote for the next community read.',
    latitude: _demoLatitude - 0.0025,
    longitude: _demoLongitude + 0.0015,
    groupName: 'Book Club Meetup Group',
  ),
  CommunityActivity(
    id: 'hiking-adventure',
    title: 'Hiking Adventure',
    dateTime: 'Sun, May 26 - 8:00 AM',
    location: 'Pine Ridge Trail',
    category: ActivityCategory.sports,
    description:
        'Meet early for a scenic hike. Wear comfortable shoes and bring water.',
    latitude: _demoLatitude - 0.003,
    longitude: _demoLongitude - 0.002,
    groupName: 'Hiking Adventure Group',
  ),
];

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _communityCanvas,
      child: Column(
        children: [
          _CommunityHeader(
            onNotifications: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const NotificationsPage()),
            ),
          ),
          Expanded(
            child: _CommunityHomeContent(),
          ),
        ],
      ),
    );
  }
}

class ActivityListPage extends StatelessWidget {
  const ActivityListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _communityCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const _SimpleHeader(showBack: true),
            Expanded(
              child: ValueListenableBuilder<List<CommunityActivity>>(
                valueListenable: communityActivityDatabase,
                builder: (context, activities, _) {
                  final visibleActivities = activities
                      .where((a) => a.title != 'Basketball Match')
                      .toList();
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    itemCount: visibleActivities.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final activity = visibleActivities[index];
                      return _ActivityCard(
                        activity: activity,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ActivityDetailPage(activity: activity),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _communityBottomNav(context),
    );
  }
}

class _CommunityHomeContent extends StatefulWidget {
  @override
  State<_CommunityHomeContent> createState() => _CommunityHomeContentState();
}

class _CommunityHomeContentState extends State<_CommunityHomeContent> {
  final _searchController = TextEditingController();
  Position? _position;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _shareCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _shareCurrentLocation() async {
    final position = await _getCurrentPositionOrNull();
    await _loadCommunityActivities(position);
    if (!mounted || position == null) return;
    setState(() => _position = position);
    sharedUserLocation.value = position;
  }

  Future<void> _loadCommunityActivities(Position? position) async {
    try {
      final snapshot = await _communityActivityRepository.fetchActivities(
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      communityActivityDatabase.value = snapshot.activities;
      activityAttendees.value = snapshot.attendeesByActivity;
    } catch (_) {
      // Keep the seeded demo activities available when the local API is offline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      children: [
        _CommunitySearchField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: 16),
        _CommunityGroupCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const NearbyFriendsMapPage(),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionHeader(title: 'Nearby Members for You'),
        const SizedBox(height: 8),
        ValueListenableBuilder<List<NearbyPerson>>(
          valueListenable: nearbyPeopleResults,
          builder: (context, people, _) {
            final members = people
                .where((member) =>
                    q.isEmpty || member.name.toLowerCase().contains(q))
                .toList();
            if (members.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Open Find Community Friends to see people near your area.',
                  style: TextStyle(color: _communityMuted),
                ),
              );
            }
            return Column(
              children: [
                for (final member in members)
                  _SuggestedPersonTile(member: member),
              ],
            );
          },
        ),
        const Divider(height: 24, color: _communityBorder),
        _SectionHeader(
          title: 'Nearby Activities',
          actionLabel: 'View all',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ActivityListPage()),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<List<CommunityActivity>>(
          valueListenable: communityActivityDatabase,
          builder: (context, activities, _) {
            final nearbyActivities =
                _nearbyActivitiesWithin(_position, activities)
                    .where((activity) =>
                        q.isEmpty ||
                        activity.title.toLowerCase().contains(q) ||
                        activity.location.toLowerCase().contains(q))
                    .toList();
            return Column(
              children: [
                if (nearbyActivities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'No nearby activities found.',
                      style: TextStyle(color: _communityMuted),
                    ),
                  )
                else
                  for (final activity in nearbyActivities.take(3))
                    _CompactActivityTile(
                      activity: activity,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ActivityDetailPage(activity: activity),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            _position == null
                ? 'Allow location to see people within 100 m and nearby activities.'
                : 'People within 100 m · activities within 500 m.',
            style: const TextStyle(fontSize: 11, color: _communityMuted),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CreateActivityPage()),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _communityBlue,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            'Create Activity',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _CommunitySearchField extends StatelessWidget {
  const _CommunitySearchField({
    this.controller,
    this.onChanged,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search people or activities',
        prefixIcon: const Icon(Icons.search, size: 21, color: _communityBlue),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(7)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _communityBorder),
        ),
      ),
    );
  }
}

class _CommunityGroupCard extends StatelessWidget {
  const _CommunityGroupCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _communityBorder),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Row(
          children: [
            _CircleIcon(icon: Icons.location_on_outlined, size: 42),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find Community Friends',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: _communityInk),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Match nearby people by distance',
                    style: TextStyle(fontSize: 12, color: _communityMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 28, color: _communityBlue),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: _communityInk),
        ),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: _communityBlue,
              padding: EdgeInsets.zero,
              minimumSize: const Size(54, 32),
            ),
            child: Text(
              actionLabel!,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _SuggestedPersonTile extends StatelessWidget {
  const _SuggestedPersonTile({required this.member});

  final NearbyPerson member;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Stack(
            children: [
              const _CircleIcon(icon: Icons.person_outline, size: 38),
              Positioned(
                right: 0,
                bottom: 2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _relationshipColor(member.relationshipStatus),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${member.proximityLabel} - ${member.isFriend ? 'Friend' : 'Not Friend'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 60,
            height: 36,
            child: OutlinedButton(
              onPressed: () {
                if (member.isFriend) {
                  _openChat(context, member.name);
                } else {
                  _openAddFriend(context, member.name);
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _communityBlue,
                side: const BorderSide(color: _communityBorder),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                member.isFriend ? 'Chat' : 'Add',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactActivityTile extends StatelessWidget {
  const _CompactActivityTile({required this.activity, required this.onTap});

  final CommunityActivity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            _CircleIcon(icon: activity.category.icon, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(activity.dateTime, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            SizedBox(
              width: 60,
              height: 36,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _communityBlue,
                  side: const BorderSide(color: _communityBorder),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: const Text(
                  'Join',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NearbyFriendsMapPage extends StatefulWidget {
  const NearbyFriendsMapPage({
    this.nearbyService,
    this.locationProvider,
    super.key,
  });

  final NearbyPeopleService? nearbyService;
  final Future<Position?> Function()? locationProvider;

  @override
  State<NearbyFriendsMapPage> createState() => _NearbyFriendsMapPageState();
}

class _NearbyFriendsMapPageState extends State<NearbyFriendsMapPage>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  late final NearbyPeopleService _nearbyService;
  List<NearbyPerson> _people = const [];
  Timer? _locationUpdateTimer;
  Position? _position;
  String? _locationError;
  bool _isSearching = false;
  DateTime? _cooldownUntil;
  int _candidateCount = 0;
  int _indexCellCount = 0;
  int _selectedRadiusMeters = 50;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _nearbyService = widget.nearbyService ?? NearbyPeopleService();
    WidgetsBinding.instance.addObserver(this);
    _startLocationUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLocationUpdates();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLocationUpdates();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopLocationUpdates();
    }
  }

  void _startLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _findNearbyPeople(ignoreCooldown: true);
    _locationUpdateTimer = Timer.periodic(
      nearbyLocationUpdateInterval,
      (_) => _findNearbyPeople(ignoreCooldown: true),
    );
  }

  void _stopLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _nearbyService.stop();
  }

  Future<void> _findNearbyPeople({bool ignoreCooldown = false}) async {
    if (_isSearching) return;
    final cooldownUntil = _cooldownUntil;
    if (!ignoreCooldown &&
        cooldownUntil != null &&
        DateTime.now().isBefore(cooldownUntil)) {
      setState(() {
        _locationError = 'Please wait before refreshing nearby people.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _locationError = null;
    });

    try {
      final position = await (widget.locationProvider?.call() ??
          _getCurrentPositionOrNull());
      if (position == null) {
        if (!mounted) return;
        sharedUserLocation.value = null;
        nearbyPeopleResults.value = const [];
        setState(() {
          _position = null;
          _people = const [];
          _candidateCount = 0;
          _indexCellCount = 0;
          _locationError =
              'Location unavailable. Allow location access and refresh.';
          _isSearching = false;
        });
        return;
      }
      sharedUserLocation.value = position;
      final result = await _nearbyService.recordLocationAndFindNearbyPeople(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: _nearbyPeopleMaxRadiusMeters,
        candidateLimit: nearbyCandidateLimit,
        maximumResults: nearbyResultLimit,
      );
      if (!mounted) return;
      setState(() {
        _position = position;
        _people = result.people;
        _candidateCount = result.candidateCount;
        _indexCellCount = result.indexCellCount;
        _isSearching = false;
        _cooldownUntil = DateTime.now().add(const Duration(seconds: 20));
      });
      nearbyPeopleResults.value = result.people;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = error is AuthException
            ? error.message
            : 'Nearby search failed. Please check location permission.';
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final members = _people
        .where((member) =>
            member.distanceMeters <= _selectedRadiusMeters &&
            (q.isEmpty || member.name.toLowerCase().contains(q)))
        .toList();
    final mapHeight =
        (MediaQuery.of(context).size.height * 0.38).clamp(260.0, 340.0);
    return Scaffold(
      backgroundColor: _communityCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const _SimpleHeader(showBack: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search nearby friends',
                        prefixIcon:
                            const Icon(Icons.search, color: _communityBlue),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _communityBorder),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Search radius',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _communityInk),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        for (final radius in _nearbyRadiusSteps)
                          ButtonSegment(
                              value: radius, label: Text('$radius m')),
                      ],
                      style: SegmentedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _communityBlue,
                        selectedBackgroundColor: _communityBlue,
                        selectedForegroundColor: Colors.white,
                        side: const BorderSide(color: _communityBorder),
                      ),
                      selected: {_selectedRadiusMeters},
                      onSelectionChanged: (selection) {
                        setState(
                            () => _selectedRadiusMeters = selection.single);
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: mapHeight,
              child: ValueListenableBuilder<List<CommunityActivity>>(
                valueListenable: communityActivityDatabase,
                builder: (context, activities, _) {
                  final nearbyActivities = _nearbyActivitiesWithin(
                    _position,
                    activities,
                    radiusMeters: _selectedRadiusMeters.toDouble(),
                    fallbackToRecent: false,
                  ).take(8).toList();
                  return _NearbyMapCanvas(
                    position: _position,
                    radiusMeters: _selectedRadiusMeters,
                    onRadiusChanged: (radius) {
                      if (_selectedRadiusMeters != radius) {
                        setState(() => _selectedRadiusMeters = radius);
                      }
                    },
                    isSearching: _isSearching,
                    error: _locationError,
                    onRefresh: _findNearbyPeople,
                    members: members,
                    activities: nearbyActivities,
                    candidateCount: _candidateCount,
                    indexCellCount: _indexCellCount,
                  );
                },
              ),
            ),
            const _MapLegend(),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: _communityBorder)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nearby Community Friends',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _communityInk),
                      ),
                      const SizedBox(height: 12),
                      if (members.isEmpty)
                        const Text(
                          'No nearby people found.',
                          style: TextStyle(color: _communityMuted),
                        )
                      else
                        for (final member in members)
                          _NearbyFriendTile(member: member),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _communityBottomNav(context),
    );
  }
}

class ActivityDetailPage extends StatefulWidget {
  const ActivityDetailPage({required this.activity, super.key});

  final CommunityActivity activity;

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  late CommunityActivity _activity;

  @override
  void initState() {
    super.initState();
    _activity = widget.activity;
  }

  Future<void> _editActivity() async {
    final updated = await Navigator.of(context).push<CommunityActivity>(
      MaterialPageRoute<CommunityActivity>(
        builder: (_) => CreateActivityPage(initialActivity: _activity),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _activity = updated);
    _showSnack(context, 'Activity updated');
  }

  Future<void> _deleteActivity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete activity?'),
        content:
            Text('This will remove "${_activity.title}" from the community.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _communityActivityRepository.deleteActivity(_activity.id);
    } on AuthException catch (error) {
      if (!mounted) return;
      _showSnack(context, error.message);
      return;
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        context,
        'API offline. Activity deleted locally for this session.',
      );
    }
    _deleteCommunityActivity(_activity);
    if (!mounted) return;
    Navigator.of(context).pop();
    _showSnack(context, 'Activity deleted');
  }

  @override
  Widget build(BuildContext context) {
    final activity = _activity;
    return Scaffold(
      backgroundColor: _communityCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const _SimpleHeader(showBack: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 26, 26, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _CircleIcon(icon: activity.category.icon, size: 74),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activity.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.ink,
                                ),
                              ),
                              const SizedBox(height: 9),
                              _IconText(
                                  icon: Icons.calendar_today_outlined,
                                  text: activity.dateTime),
                              const SizedBox(height: 8),
                              _IconText(
                                  icon: Icons.location_on_outlined,
                                  text: activity.location),
                            ],
                          ),
                        ),
                        if (activity.isOwnedByCurrentUser) ...[
                          IconButton(
                            tooltip: 'Edit Activity',
                            onPressed: _editActivity,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete Activity',
                            onPressed: _deleteActivity,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 26),
                    const Divider(color: _communityBorder),
                    const SizedBox(height: 24),
                    const _SectionTitle('About'),
                    const SizedBox(height: 10),
                    Text(activity.description,
                        style: const TextStyle(fontSize: 14, height: 1.5)),
                    const SizedBox(height: 30),
                    ValueListenableBuilder<Map<String, List<String>>>(
                      valueListenable: activityAttendees,
                      builder: (context, attendeesByActivity, _) {
                        final attendees = attendeesByActivity[activity.id] ??
                            const <String>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Who\'s Going (${attendees.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: attendees.isEmpty
                                      ? null
                                      : () => _showAttendees(
                                            context,
                                            activity,
                                            attendees,
                                          ),
                                  style: TextButton.styleFrom(
                                      foregroundColor: _communityBlue),
                                  child: const Text('View all'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (attendees.isEmpty)
                              const Text(
                                'No one has joined yet.',
                                style: TextStyle(color: AppTheme.muted),
                              )
                            else
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final attendee in attendees.take(5))
                                    InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => UserProfilePage(
                                            memberName: attendee,
                                          ),
                                        ),
                                      ),
                                      child: const _CircleIcon(
                                          icon: Icons.person_outline, size: 42),
                                    ),
                                  if (attendees.length > 5)
                                    Container(
                                      width: 42,
                                      height: 42,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border:
                                            Border.all(color: AppTheme.muted),
                                      ),
                                      child: Text(
                                        '+${attendees.length - 5}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                    const _SectionTitle('What to Bring'),
                    const SizedBox(height: 10),
                    const Text(
                        'Bring water, comfortable clothes, and good vibes!'),
                    const SizedBox(height: 28),
                    const _SectionTitle('Activity Group'),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await _openActivityGroup(context, activity);
                        } on AuthException catch (error) {
                          if (!context.mounted) return;
                          _showSnack(context, error.message);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _communityBlue,
                        side: const BorderSide(color: _communityBorder),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        minimumSize: const Size(double.infinity, 46),
                      ),
                      icon: const Icon(Icons.group_add_outlined),
                      label: Text(
                        'Add Group: ${activity.groupName}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 10, 26, 20),
              child: ValueListenableBuilder<Map<String, List<String>>>(
                valueListenable: activityAttendees,
                builder: (context, attendeesByActivity, _) {
                  return FutureBuilder<String>(
                    future: AuthService.currentUserDisplayName(),
                    builder: (context, snapshot) {
                      final currentName = snapshot.data;
                      final joined = currentName != null &&
                          (attendeesByActivity[activity.id]
                                  ?.contains(currentName) ??
                              false);
                      return _PrimaryBlackButton(
                        label: joined ? 'Leave Activity' : 'Join Activity',
                        onPressed: () async {
                          try {
                            if (joined) {
                              await _leaveActivity(activity);
                              if (!context.mounted) return;
                              _showSnack(context, 'Left activity');
                            } else {
                              await _joinActivity(activity);
                              if (!context.mounted) return;
                              _showSnack(
                                  context, 'Joined activity and entered group');
                              _openActivityGroup(
                                context,
                                activity,
                                joinFirst: false,
                              );
                            }
                          } on AuthException catch (error) {
                            if (!context.mounted) return;
                            _showSnack(context, error.message);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _communityBottomNav(context),
    );
  }
}

class CreateActivityPage extends StatefulWidget {
  const CreateActivityPage({this.initialActivity, super.key});

  final CommunityActivity? initialActivity;

  @override
  State<CreateActivityPage> createState() => _CreateActivityPageState();
}

class _CreateActivityPageState extends State<CreateActivityPage> {
  final _titleController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  ActivityCategory? _category;
  bool _showCategories = false;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  SelectedLocation? _selectedLocation;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialActivity;
    if (initial == null) {
      _prefillCurrentLocation();
    } else {
      _titleController.text = initial.title;
      _addressController.text = initial.location;
      _descriptionController.text = initial.description;
      _category = initial.category;
      _selectedLocation = SelectedLocation(
        address: initial.location,
        latitude: initial.latitude,
        longitude: initial.longitude,
      );
      _syncCoordinateInputs(initial.latitude, initial.longitude);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _syncCoordinateInputs(double latitude, double longitude) {
    _latitudeController.text = latitude.toStringAsFixed(5);
    _longitudeController.text = longitude.toStringAsFixed(5);
  }

  void _useManualCoordinates() {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      _showSnack(context, 'Enter valid latitude and longitude');
      return;
    }

    setState(() {
      _selectedLocation = SelectedLocation(
        address: _addressController.text.trim().isEmpty
            ? 'Manual Location'
            : _addressController.text.trim(),
        latitude: latitude,
        longitude: longitude,
      );
    });
  }

  Future<void> _selectLocation() async {
    final location = await Navigator.of(context).push<SelectedLocation>(
      MaterialPageRoute<SelectedLocation>(
        builder: (_) => const SelectLocationPage(),
      ),
    );
    if (location != null && mounted) {
      setState(() {
        _selectedLocation = location;
        _addressController.text = location.address;
        _syncCoordinateInputs(location.latitude, location.longitude);
      });
    }
  }

  Future<void> _prefillCurrentLocation() async {
    final position = await _getCurrentPositionOrNull();
    if (!mounted || position == null) return;
    setState(() {
      _selectedLocation = SelectedLocation(
        address: 'Current Location',
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _addressController.text = 'Current Location';
      _syncCoordinateInputs(position.latitude, position.longitude);
    });
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(2026, 5, 25),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (date != null && mounted) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (time != null && mounted) {
      setState(() => _selectedTime = time);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _communityCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const _SimpleHeader(showBack: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FormLabel('Activity Title'),
                    _TextInput(
                        controller: _titleController,
                        hint: 'Enter activity title'),
                    const SizedBox(height: 16),
                    const _FormLabel('Category'),
                    _CategoryField(
                      selected: _category,
                      expanded: _showCategories,
                      onTap: () =>
                          setState(() => _showCategories = !_showCategories),
                      onSelected: (category) => setState(() {
                        _category = category;
                        _showCategories = false;
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(child: _FormLabel('Date')),
                        SizedBox(width: 18),
                        Expanded(child: _FormLabel('Time')),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: _FakePicker(
                                hint: _selectedDate == null
                                    ? 'Select date'
                                    : _formatDate(_selectedDate!),
                                icon: Icons.calendar_today_outlined,
                                onTap: _selectDate)),
                        const SizedBox(width: 18),
                        Expanded(
                            child: _FakePicker(
                                hint: _selectedTime == null
                                    ? 'Select time'
                                    : _selectedTime!.format(context),
                                icon: Icons.access_time,
                                onTap: _selectTime)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _FormLabel('Address'),
                    _TextInput(
                      controller: _addressController,
                      hint: 'Enter address or place name',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TextInput(
                            controller: _latitudeController,
                            hint: 'Latitude',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TextInput(
                            controller: _longitudeController,
                            hint: 'Longitude',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _useManualCoordinates,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _communityBlue,
                        side: const BorderSide(color: _communityBorder),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        minimumSize: const Size(double.infinity, 42),
                      ),
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: const Text(
                        'Use Coordinates',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _selectLocation,
                      child: _MapPreview(
                        height: 136,
                        latitude: _selectedLocation?.latitude ??
                            sharedUserLocation.value?.latitude ??
                            _demoLatitude,
                        longitude: _selectedLocation?.longitude ??
                            sharedUserLocation.value?.longitude ??
                            _demoLongitude,
                        label: _selectedLocation?.address ?? 'Tap to choose',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _FormLabel('Description'),
                    _TextInput(
                      controller: _descriptionController,
                      hint: 'Tell others about your activity...',
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
              child: _PrimaryBlackButton(
                  label: widget.initialActivity == null
                      ? 'Create Activity'
                      : 'Save Changes',
                  onPressed: () async {
                    final initial = widget.initialActivity;
                    final title = _titleController.text.trim().isEmpty
                        ? 'New Community Activity'
                        : _titleController.text.trim();
                    final activity = CommunityActivity(
                      id: initial?.id ??
                          'activity-${DateTime.now().microsecondsSinceEpoch}',
                      title: title,
                      dateTime: _selectedDate == null &&
                              _selectedTime == null &&
                              initial != null
                          ? initial.dateTime
                          : '${_selectedDate == null ? 'Selected date' : _formatDate(_selectedDate!)} - ${_selectedTime?.format(context) ?? 'Selected time'}',
                      location: _addressController.text.trim().isEmpty
                          ? 'Selected location'
                          : _addressController.text.trim(),
                      category: _category ?? ActivityCategory.social,
                      description: _descriptionController.text.trim().isEmpty
                          ? 'A new community activity has been created.'
                          : _descriptionController.text.trim(),
                      latitude: _selectedLocation?.latitude ??
                          sharedUserLocation.value?.latitude ??
                          _demoLatitude,
                      longitude: _selectedLocation?.longitude ??
                          sharedUserLocation.value?.longitude ??
                          _demoLongitude,
                      groupName: '$title Group',
                      isOwnedByCurrentUser: true,
                    );
                    if (initial == null) {
                      var savedActivity = activity;
                      try {
                        savedActivity =
                            await _communityActivityRepository.createActivity(
                          activity,
                        );
                      } on AuthException catch (error) {
                        if (!context.mounted) return;
                        _showSnack(context, error.message);
                        return;
                      } catch (_) {
                        if (!context.mounted) return;
                        _showSnack(
                          context,
                          'API offline. Activity saved locally for this session.',
                        );
                      }
                      communityActivityDatabase.value = [
                        savedActivity,
                        ...communityActivityDatabase.value,
                      ];
                      createdActivityNotifications.value = [
                        savedActivity,
                        ...createdActivityNotifications.value,
                      ];
                      if (!context.mounted) return;
                      _showSnack(context, 'Activity created');
                    } else {
                      var savedActivity = activity;
                      try {
                        savedActivity =
                            await _communityActivityRepository.updateActivity(
                          activity,
                        );
                      } on AuthException catch (error) {
                        if (!context.mounted) return;
                        _showSnack(context, error.message);
                        return;
                      } catch (_) {
                        if (!context.mounted) return;
                        _showSnack(
                          context,
                          'API offline. Changes saved locally for this session.',
                        );
                      }
                      _replaceCommunityActivity(savedActivity);
                      if (!context.mounted) return;
                      Navigator.of(context).pop(savedActivity);
                    }
                  }),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _communityBottomNav(context),
    );
  }
}

class SelectLocationPage extends StatefulWidget {
  const SelectLocationPage({super.key});

  @override
  State<SelectLocationPage> createState() => _SelectLocationPageState();
}

class _SelectLocationPageState extends State<SelectLocationPage> {
  final _addressSearchController = TextEditingController();
  SelectedLocation _location = const SelectedLocation(
    address: 'Riverside Park Basketball Court',
    latitude: _demoLatitude,
    longitude: _demoLongitude,
  );
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _addressSearchController.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final position = await _getCurrentPositionOrNull();
    if (!mounted) return;
    if (position != null) {
      setState(() {
        _location = SelectedLocation(
          address: 'Current Location',
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _locating = false;
      });
    } else {
      setState(() => _locating = false);
    }
  }

  void _useTypedAddress(String value) {
    final address = value.trim();
    if (address.isEmpty) return;
    setState(() {
      _location = SelectedLocation(
        address: address,
        latitude: _location.latitude,
        longitude: _location.longitude,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _communityCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const _SimpleHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: _SearchLocationField(
                controller: _addressSearchController,
                onSubmitted: _useTypedAddress,
              ),
            ),
            Expanded(
              child: _MapPreview(
                height: double.infinity,
                large: true,
                onLocate: _locate,
                latitude: _location.latitude,
                longitude: _location.longitude,
                label: _locating
                    ? 'Locating...'
                    : '${_location.latitude.toStringAsFixed(4)}, ${_location.longitude.toStringAsFixed(4)}',
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD6D6D6)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Selected Address',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 18),
                        Text(_location.address,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${_location.latitude.toStringAsFixed(5)}, ${_location.longitude.toStringAsFixed(5)}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: _PrimaryBlackButton(
                label: 'Confirm Location',
                onPressed: () => Navigator.of(context).pop(_location),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _communityBottomNav(context),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _communityCanvas,
      body: const SafeArea(
        child: Column(
          children: [
            _SimpleHeader(leadingIcon: Icons.notifications_none),
            Expanded(child: _NotificationsList()),
          ],
        ),
      ),
      bottomNavigationBar: _communityBottomNav(context),
    );
  }
}

class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({required this.onNotifications});

  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _communityBorder)),
      ),
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Center(
                child: IconButton(
                  tooltip: 'Notifications',
                  onPressed: onNotifications,
                  icon: const Icon(Icons.notifications_none,
                      size: 24, color: _communityBlue),
                ),
              ),
            ),
            const Expanded(
              child: Text(
                'Global Village',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _communityInk),
              ),
            ),
            const SizedBox(width: 56),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity, required this.onTap});

  final CommunityActivity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _communityBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _CircleIcon(icon: activity.category.icon, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _communityInk),
                  ),
                  const SizedBox(height: 5),
                  Text(activity.dateTime, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 5),
                  Text(
                    activity.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: _communityBlue,
                side: const BorderSide(color: _communityBlue),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7)),
                minimumSize: const Size(58, 42),
                padding: EdgeInsets.zero,
              ),
              child: const Text('Join',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyMapCanvas extends StatefulWidget {
  const _NearbyMapCanvas({
    required this.position,
    required this.radiusMeters,
    required this.onRadiusChanged,
    required this.isSearching,
    required this.error,
    required this.onRefresh,
    required this.members,
    required this.activities,
    required this.candidateCount,
    required this.indexCellCount,
  });

  final Position? position;
  final int radiusMeters;
  final ValueChanged<int> onRadiusChanged;
  final bool isSearching;
  final String? error;
  final VoidCallback onRefresh;
  final List<NearbyPerson> members;
  final List<CommunityActivity> activities;
  final int candidateCount;
  final int indexCellCount;

  @override
  State<_NearbyMapCanvas> createState() => _NearbyMapCanvasState();
}

class _NearbyMapCanvasState extends State<_NearbyMapCanvas> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(covariant _NearbyMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.position;
    final current = widget.position;
    if (previous != null &&
        current != null &&
        (previous.latitude != current.latitude ||
            previous.longitude != current.longitude ||
            oldWidget.radiusMeters != widget.radiusMeters)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(
          LatLng(current.latitude, current.longitude),
          oldWidget.radiusMeters != widget.radiusMeters
              ? _mapZoomForRadius(widget.radiusMeters)
              : _mapController.camera.zoom,
        );
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position;

    return Container(
      width: double.infinity,
      color: _communityBlueSoft,
      child: Stack(
        children: [
          if (position == null)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off_outlined, size: 32),
                  SizedBox(height: 8),
                  Text('Location unavailable'),
                  Text('Allow location access and tap Refresh.'),
                ],
              ),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(position.latitude, position.longitude),
                initialZoom: _mapZoomForRadius(widget.radiusMeters),
                minZoom: 16.8,
                maxZoom: 19,
                onPositionChanged: (camera, hasGesture) {
                  if (!hasGesture) return;
                  final radius = _radiusForMapZoom(camera.zoom);
                  if (radius == widget.radiusMeters) return;
                  widget.onRadiusChanged(radius);
                },
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.global_village_app',
                ),
                CircleLayer(circles: [
                  CircleMarker(
                    point: LatLng(position.latitude, position.longitude),
                    radius: widget.radiusMeters.toDouble(),
                    useRadiusInMeter: true,
                    color: const Color(0x241E6CCB),
                    borderColor: const Color(0xAA1E6CCB),
                    borderStrokeWidth: 1.5,
                  ),
                ]),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(position.latitude, position.longitude),
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (final member in widget.members)
                      Marker(
                        point: LatLng(member.latitude, member.longitude),
                        width: 74,
                        height: 64,
                        child: _MapFriendPin(member: member),
                      ),
                    for (final activity in widget.activities)
                      Marker(
                        point: LatLng(activity.latitude, activity.longitude),
                        width: 112,
                        height: 66,
                        child: _ActivityMapPin(activity: activity),
                      ),
                  ],
                ),
              ],
            ),
          if (position != null)
            Positioned(
              left: 16,
              top: 14,
              right: 16,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _communityBorder),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      )
                    ],
                  ),
                  child: Text(
                    widget.isSearching
                        ? 'Finding nearby people...'
                        : widget.error ??
                            '${widget.members.length} people within ${widget.radiusMeters} m',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          if (position != null)
            Positioned(
              right: 16,
              bottom: 70,
              child: IconButton.filledTonal(
                tooltip: 'Center on my location',
                onPressed: () => _mapController.move(
                  LatLng(position.latitude, position.longitude),
                  _mapController.camera.zoom,
                ),
                icon: const Icon(Icons.my_location),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: InkWell(
              onTap: widget.isSearching ? null : widget.onRefresh,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 104,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _communityBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.isSearching ? 'Finding' : 'Refresh',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _communityBlue,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapFriendPin extends StatelessWidget {
  const _MapFriendPin({required this.member});

  final NearbyPerson member;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (member.isFriend) {
          _openChat(context, member.name);
        } else {
          _openAddFriend(context, member.name);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFBDBDBD)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 7,
                  offset: Offset(0, 2),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.person_outline, size: 23),
                    Positioned(
                      right: -2,
                      bottom: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _relationshipColor(member.relationshipStatus),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _timeAgo(member.lastSeenAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: -7,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    right: BorderSide(color: Color(0xFFBDBDBD)),
                    bottom: BorderSide(color: Color(0xFFBDBDBD)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityMapPin extends StatelessWidget {
  const _ActivityMapPin({required this.activity});

  final CommunityActivity activity;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openActivityDetail(context, activity),
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 106),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.ink, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 7,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(activity.category.icon, size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      activity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 28,
            child: Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: AppTheme.ink,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 7,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child:
                  const Icon(Icons.location_on, size: 15, color: Colors.white),
            ),
          ),
          Positioned(
            top: 46,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppTheme.ink,
                  border: Border(
                    right: BorderSide(color: Colors.white, width: 1.4),
                    bottom: BorderSide(color: Colors.white, width: 1.4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _communityBorder)),
      ),
      child: const SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _LegendItem(color: Colors.green, label: 'Friend'),
            SizedBox(width: 10),
            _LegendItem(color: Colors.blue, label: 'Not Friend'),
            SizedBox(width: 10),
            Icon(Icons.location_on, size: 12),
            SizedBox(width: 3),
            Text('Activity', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _NearbyFriendTile extends StatelessWidget {
  const _NearbyFriendTile({required this.member});

  final NearbyPerson member;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        children: [
          const _CircleIcon(icon: Icons.person_outline, size: 42),
          Positioned(
            right: 0,
            bottom: 2,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: _relationshipColor(member.relationshipStatus),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      title: Text(member.name,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${member.proximityLabel} - Seen ${_timeAgo(member.lastSeenAt)}',
      ),
      trailing: OutlinedButton(
        onPressed: () {
          if (member.isFriend) {
            _openChat(context, member.name);
          } else {
            _openAddFriend(context, member.name);
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: _communityBlue,
          side: const BorderSide(color: _communityBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text(member.isFriend ? 'Chat' : 'Add'),
      ),
    );
  }
}

class _SimpleHeader extends StatelessWidget {
  const _SimpleHeader({this.showBack = false, this.leadingIcon});

  final bool showBack;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _communityBorder)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Center(
              child: IconButton(
                tooltip: showBack ? 'Back' : 'Notifications',
                onPressed: showBack ? () => Navigator.maybePop(context) : null,
                icon: Icon(showBack ? Icons.arrow_back_ios_new : leadingIcon,
                    size: 22, color: _communityBlue),
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Global Village',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _communityInk),
            ),
          ),
          const SizedBox(width: 56),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _communityBlueSoft,
        border: Border.all(color: _communityBorder),
      ),
      child: Icon(icon, size: size * 0.52, color: _communityBlue),
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: _communityInk));
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: _communityInk)),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _communityBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _communityBlue, width: 1.5),
        ),
      ),
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.onSelected,
  });

  final ActivityCategory? selected;
  final bool expanded;
  final VoidCallback onTap;
  final ValueChanged<ActivityCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                  color: expanded ? _communityBlue : _communityBorder),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected?.label ?? 'Select category',
                    style: TextStyle(
                        color: selected == null
                            ? const Color(0xFF9A9A9A)
                            : _communityInk),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: _communityBlue,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _communityBorder),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(7)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 4))
              ],
            ),
            child: Column(
              children: ActivityCategory.values.map((category) {
                final active = selected == category;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(category.icon, color: _communityBlue),
                  title: Text(category.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: active
                      ? const Icon(Icons.check, color: _communityBlue)
                      : null,
                  onTap: () => onSelected(category),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _FakePicker extends StatelessWidget {
  const _FakePicker({
    required this.hint,
    required this.icon,
    required this.onTap,
  });

  final String hint;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _communityBorder),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hint,
                style: TextStyle(
                  color: hint.startsWith('Select')
                      ? const Color(0xFF9A9A9A)
                      : _communityInk,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(icon, size: 19, color: _communityBlue),
          ],
        ),
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({
    required this.height,
    this.large = false,
    this.onLocate,
    this.label,
    this.latitude = _demoLatitude,
    this.longitude = _demoLongitude,
  });

  final double height;
  final bool large;
  final VoidCallback? onLocate;
  final String? label;
  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: FlutterMap(
        key: ValueKey('$latitude:$longitude:$large'),
        options: MapOptions(
          initialCenter: LatLng(latitude, longitude),
          initialZoom: large ? 15.5 : 14.8,
          interactionOptions: InteractionOptions(
            flags: large
                ? InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom
                : InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.global_village_app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(latitude, longitude),
                width: 48,
                height: 48,
                child: Icon(
                  Icons.location_on,
                  size: large ? 44 : 36,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () {},
              ),
            ],
          ),
          Stack(
            children: [
              if (label != null)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFD6D6D6)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      label!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 14,
                bottom: 14,
                child: InkWell(
                  onTap: onLocate,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Icon(Icons.my_location, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryBlackButton extends StatelessWidget {
  const _PrimaryBlackButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _communityBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _SearchLocationField extends StatelessWidget {
  const _SearchLocationField({
    required this.controller,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: 'Search address',
        prefixIcon: const Icon(Icons.search),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _NotificationsList extends StatelessWidget {
  const _NotificationsList();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CommunityActivity>>(
      valueListenable: createdActivityNotifications,
      builder: (context, createdActivities, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            const _NotificationSection('Upcoming Activities'),
            for (final activity in createdActivities)
              _NotificationTile(
                icon: activity.category.icon,
                title: activity.title,
                subtitle: '${activity.dateTime}\n${activity.location}',
                time: 'Just now',
                onTap: () => _openActivityDetail(context, activity),
              ),
            _NotificationTile(
              icon: Icons.sports_basketball_outlined,
              title: 'Basketball Match',
              subtitle:
                  'Sun, May 25 - 9:00 AM\nRiverside Park Basketball Court',
              time: 'In 1 day',
              onTap: () => _openActivityDetail(context, _activities[0]),
            ),
            _NotificationTile(
              icon: Icons.self_improvement_outlined,
              title: 'Morning Yoga',
              subtitle: 'Sun, May 25 - 7:00 AM\nGreenfield Park',
              time: 'In 1 day',
              onTap: () => _openActivityDetail(context, _activities[2]),
            ),
            const _NotificationSection('Activity Updates'),
            _NotificationTile(
              icon: Icons.menu_book_outlined,
              title: 'Book Club Meeting',
              subtitle: 'Location changed to Community Library.',
              time: 'Yesterday',
              onTap: () => _openActivityDetail(context, _activities[4]),
            ),
            const _NotificationSection('Health Check-in Reminders'),
            _NotificationTile(
              icon: Icons.water_drop_outlined,
              title: 'Water Intake',
              subtitle: 'Don\'t forget to drink water!',
              time: '8:15 AM',
              onTap: () => _openFamilyHealth(context),
            ),
            _NotificationTile(
              icon: Icons.directions_walk,
              title: 'Walk Goal',
              subtitle: 'You haven\'t logged your walk today.',
              time: '9:00 AM',
              onTap: () => _openFamilyHealth(context),
            ),
            const _NotificationSection('Messages'),
            _NotificationTile(
              icon: Icons.mark_unread_chat_alt_outlined,
              title: 'New Message',
              subtitle: 'Alex: Are you joining the basketball game?',
              time: '7:45 AM',
              onTap: () => _openChat(context, 'Alex Tan'),
            ),
            _NotificationTile(
              icon: Icons.groups_outlined,
              title: 'Group Update',
              subtitle: 'Volunteer Team: New event this Saturday.',
              time: 'Yesterday',
              onTap: () => _openChat(context, 'Volunteer Team'),
            ),
          ],
        );
      },
    );
  }
}

class _NotificationSection extends StatelessWidget {
  const _NotificationSection(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Text(title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.ink)),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CircleIcon(icon: icon, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 18),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: Colors.blue, shape: BoxShape.circle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UserProfilePage extends StatelessWidget {
  const UserProfilePage({required this.memberName, super.key});

  final String memberName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _communityCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const _SimpleHeader(showBack: true),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const SizedBox(height: 28),
                    const _CircleIcon(icon: Icons.person_outline, size: 92),
                    const SizedBox(height: 20),
                    Text(
                      memberName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Community Member',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 28),
                    _PrimaryBlackButton(
                      label: 'Message',
                      onPressed: () => _openChat(context, memberName),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _communityBottomNav(context),
    );
  }
}

Widget _communityBottomNav(BuildContext context) {
  return BottomNav(
    selectedIndex: 1,
    onSelected: (index) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => HomePage(initialTabIndex: index),
        ),
        (route) => false,
      );
    },
  );
}

Color _relationshipColor(NearbyRelationshipStatus status) {
  return switch (status) {
    NearbyRelationshipStatus.friend => Colors.green,
    NearbyRelationshipStatus.nonFriend => Colors.blue,
  };
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  final days = diff.inDays;
  return '$days day${days == 1 ? '' : 's'} ago';
}

Future<Position?> _getCurrentPositionOrNull() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  } catch (_) {
    return null;
  }
}

List<CommunityActivity> _nearbyActivitiesWithin(
  Position? position,
  List<CommunityActivity> activities, {
  double radiusMeters = _nearbyActivityRadiusMeters,
  bool fallbackToRecent = true,
}) {
  if (position == null) {
    return fallbackToRecent ? activities.take(3).toList() : const [];
  }
  final nearby = activities.where((activity) {
    final meters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      activity.latitude,
      activity.longitude,
    );
    return meters <= radiusMeters;
  }).toList();
  return nearby.isEmpty && fallbackToRecent
      ? activities.take(3).toList()
      : nearby;
}

void _openAddFriend(BuildContext context, String name) {
  Navigator.of(context).push(
    MaterialPageRoute<bool>(
      builder: (_) => FindFriendsPage(initialQuery: name),
    ),
  );
}

void _openChat(BuildContext context, String name) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatDetailPage(
        chat: Chat(
          userId: '',
          name: name,
          time: 'Now',
          unreadCount: 0,
          preview: 'Community chat',
        ),
      ),
    ),
  );
}

Future<void> _openActivityGroup(
  BuildContext context,
  CommunityActivity activity, {
  bool joinFirst = true,
}) async {
  if (joinFirst) {
    await _joinActivity(activity);
    if (!context.mounted) return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatDetailPage(
        chat: Chat(
          userId: '',
          name: activity.groupName,
          time: 'Now',
          unreadCount: 0,
          preview: 'All joined members are added automatically.',
          isGroup: true,
          category: 'Groups',
        ),
      ),
    ),
  );
}

void _openActivityDetail(BuildContext context, CommunityActivity activity) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ActivityDetailPage(activity: activity),
    ),
  );
}

void _openFamilyHealth(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => const HomePage(initialTabIndex: 2),
    ),
    (route) => false,
  );
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _joinActivity(CommunityActivity activity) async {
  final displayName = await AuthService.currentUserDisplayName();
  try {
    await _communityActivityRepository.joinActivity(activity.id);
  } on AuthException {
    rethrow;
  } catch (_) {
    // Keep the join usable during development if the Docker API is offline.
  }
  final current = Map<String, List<String>>.from(activityAttendees.value);
  final attendees = List<String>.from(current[activity.id] ?? const []);
  if (!attendees.contains(displayName)) {
    attendees.add(displayName);
  }
  current[activity.id] = attendees;
  activityAttendees.value = current;
}

Future<void> _leaveActivity(CommunityActivity activity) async {
  final displayName = await AuthService.currentUserDisplayName();
  try {
    await _communityActivityRepository.leaveActivity(activity.id);
  } on AuthException {
    rethrow;
  } catch (_) {
    // Keep the leave action usable during development if the Docker API is offline.
  }
  final current = Map<String, List<String>>.from(activityAttendees.value);
  final attendees = List<String>.from(current[activity.id] ?? const []);
  attendees.remove(displayName);
  if (attendees.isEmpty) {
    current.remove(activity.id);
  } else {
    current[activity.id] = attendees;
  }
  activityAttendees.value = current;
}

void _replaceCommunityActivity(CommunityActivity updated) {
  communityActivityDatabase.value = [
    for (final activity in communityActivityDatabase.value)
      if (activity.id == updated.id) updated else activity,
  ];
  createdActivityNotifications.value = [
    for (final activity in createdActivityNotifications.value)
      if (activity.id == updated.id) updated else activity,
  ];
}

void _deleteCommunityActivity(CommunityActivity activity) {
  communityActivityDatabase.value = [
    for (final existing in communityActivityDatabase.value)
      if (existing.id != activity.id) existing,
  ];
  createdActivityNotifications.value = [
    for (final existing in createdActivityNotifications.value)
      if (existing.id != activity.id) existing,
  ];
  final attendees = Map<String, List<String>>.from(activityAttendees.value)
    ..remove(activity.id);
  activityAttendees.value = attendees;
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

void _showAttendees(
  BuildContext context,
  CommunityActivity activity,
  List<String> attendees,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (context) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        shrinkWrap: true,
        children: [
          Text(
            '${activity.title} Attendees (${attendees.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final name in attendees)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const _CircleIcon(icon: Icons.person_outline, size: 42),
              title: Text(name),
              subtitle: const Text('Going'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => UserProfilePage(memberName: name),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}
