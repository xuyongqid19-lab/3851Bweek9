import 'package:flutter/foundation.dart';

class ProfileData {
  final String name;
  final String username;
  final int age;
  final DateTime? birthDate;
  final String email;
  final String phone;
  final String community;
  final String address;
  final List<String> interestTags;
  final Map<String, String> customInterestCategories;

  const ProfileData({
    required this.name,
    required this.username,
    required this.age,
    this.birthDate,
    required this.email,
    required this.phone,
    this.community = '',
    this.address = '',
    this.interestTags = const [],
    this.customInterestCategories = const {},
  });

  /// 展示用年龄：有出生日期时按出生日期实时计算，否则用存量 age。
  int get displayAge => birthDate == null ? age : calculateAge(birthDate!);

  ProfileData copyWith({
    String? name,
    String? username,
    int? age,
    DateTime? birthDate,
    String? email,
    String? phone,
    String? community,
    String? address,
    List<String>? interestTags,
    Map<String, String>? customInterestCategories,
  }) {
    return ProfileData(
      name: name ?? this.name,
      username: username ?? this.username,
      age: age ?? this.age,
      birthDate: birthDate ?? this.birthDate,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      community: community ?? this.community,
      address: address ?? this.address,
      interestTags: interestTags ?? this.interestTags,
      customInterestCategories:
          customInterestCategories ?? this.customInterestCategories,
    );
  }
}

/// 根据出生年月日计算周岁年龄。
int calculateAge(DateTime birthDate, [DateTime? asOf]) {
  final now = asOf ?? DateTime.now();
  var age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age--;
  }
  return age < 0 ? 0 : age;
}

/// 格式化为 yyyy-MM-dd，便于展示与填写。
String formatBirthDate(DateTime birthDate) {
  final y = birthDate.year.toString().padLeft(4, '0');
  final m = birthDate.month.toString().padLeft(2, '0');
  final d = birthDate.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class MatchUser {
  final String id;
  final String name;
  final String? username;
  final String? email;
  final String? googlePhotoUrl;
  final String? authProvider;
  final int age;
  final String community;
  final List<String> interestTags;
  final Map<String, String> customInterestCategories;
  final double matchScore;

  const MatchUser({
    required this.id,
    required this.name,
    this.username,
    this.email,
    this.googlePhotoUrl,
    this.authProvider,
    required this.age,
    this.community = '',
    this.interestTags = const [],
    this.customInterestCategories = const {},
    this.matchScore = 0,
  });

  /// 头像用名字首字母。有 Google 头像时调用方可自行使用 [googlePhotoUrl]。
  String get avatarInitial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  /// /auth/match/candidates 返回的一条用户记录转成 MatchUser。
  factory MatchUser.fromJson(Map<String, dynamic> json) {
    String str(String key) => json[key]?.toString().trim() ?? '';
    final name = str('fullName');
    final username = str('username');
    final email = str('email');
    final photo = str('googlePhotoUrl');
    final provider = str('authProvider');
    DateTime? birth;
    final birthStr = str('birthDate');
    if (birthStr.isNotEmpty) {
      try {
        birth = DateTime.parse(birthStr);
      } catch (_) {
        birth = null;
      }
    }
    var interests = <String>[];
    final rawInterests = json['interests'];
    if (rawInterests is List) {
      interests = rawInterests
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(10)
          .toList();
    } else if (str('interest').isNotEmpty) {
      // 老用户只有单个 interest 字段。
      interests = [str('interest')];
    }
    var custom = <String, String>{};
    final rawCustom = json['customCategories'];
    if (rawCustom is Map) {
      rawCustom.forEach((k, v) {
        if (k is String && v is String && interests.contains(k)) custom[k] = v;
      });
    }
    return MatchUser(
      id: str('id'),
      name: name,
      username: username.isEmpty ? null : username,
      email: email.isEmpty ? null : email,
      googlePhotoUrl: photo.isEmpty ? null : photo,
      authProvider: provider.isEmpty ? null : provider,
      age: birth == null ? 0 : calculateAge(birth),
      community: str('community'),
      interestTags: interests,
      customInterestCategories: custom,
    );
  }

  MatchUser copyWith({double? matchScore}) {
    return MatchUser(
      id: id,
      name: name,
      username: username,
      email: email,
      googlePhotoUrl: googlePhotoUrl,
      authProvider: authProvider,
      age: age,
      community: community,
      interestTags: interestTags,
      customInterestCategories: customInterestCategories,
      matchScore: matchScore ?? this.matchScore,
    );
  }
}

final availableInterests = [
  'Hiking',
  'Photography',
  'Basketball',
  'Cooking',
  'Travel',
  'Yoga',
  'Gaming',
  'Music',
  'Art',
  'Running',
  'Swimming',
  'Cycling',
  'Reading',
  'Writing',
  'Dancing',
  'Movies',
  'Gardening',
  'Fishing',
  'Painting',
  'Singing',
];

/// 大类 -> 小标签映射。小标签可归属多个大类，用于“大类相同也加分”。
const interestCategories = {
  'Sports': ['Basketball', 'Yoga', 'Running', 'Swimming', 'Cycling'],
  'Outdoors': [
    'Hiking',
    'Travel',
    'Gardening',
    'Fishing',
    'Cycling',
    'Running'
  ],
  'Arts': [
    'Photography',
    'Music',
    'Art',
    'Dancing',
    'Movies',
    'Painting',
    'Singing'
  ],
  'Life': ['Cooking', 'Gardening', 'Travel', 'Movies', 'Photography'],
  'Mind': ['Gaming', 'Reading', 'Writing', 'Yoga', 'Photography'],
};

/// 单个标签归属的大类集合。预设标签查表，自定义标签查 customMap。
Set<String> categoriesOfTag(String tag, [Map<String, String>? customMap]) {
  final result = <String>{};
  interestCategories.forEach((big, smalls) {
    if (smalls.contains(tag)) result.add(big);
  });
  final custom = customMap?[tag];
  if (custom != null && custom.isNotEmpty) result.add(custom);
  return result;
}

/// 一组标签展开成大类集合。
Set<String> tagsToCategories(List<String> tags,
    [Map<String, String>? customMap]) {
  final result = <String>{};
  for (final tag in tags) {
    result.addAll(categoriesOfTag(tag, customMap));
  }
  return result;
}

/// 双方大类重合数（用于加分）。[customMapA]/[customMapB] 分别是双方自己的自定义标签归类。
int countSharedCategories(List<String> a, List<String> b,
    [Map<String, String>? customMapA, Map<String, String>? customMapB]) {
  final catsA = tagsToCategories(a, customMapA);
  final catsB = tagsToCategories(b, customMapB);
  return catsA.intersection(catsB).length;
}

final availableCommunities = [
  'Riverside',
  'Central Park',
  'Downtown',
  'Sunset Village',
  'Pine Ridge',
  'Lakeview',
  'Greenwood',
  'Oakville',
];

/// Map backend /auth/me user JSON to local ProfileData.
/// Backend shape: fullName, birthDate (YYYY-MM-DD), interests (list),
/// customCategories (map), username, email, phone, community, address.
ProfileData profileFromAuthUser(Map<String, dynamic> user,
    {ProfileData? fallback}) {
  String str(String key) => user[key]?.toString() ?? '';
  final fullName = str('fullName').trim();
  final username = str('username').trim();
  final email = str('email').trim();
  final phone = str('phone');
  final community = str('community');
  final address = str('address');
  DateTime? birth;
  final birthStr = str('birthDate').trim();
  if (birthStr.isNotEmpty) {
    try {
      birth = DateTime.parse(birthStr);
    } catch (_) {
      birth = null;
    }
  }
  var interests = <String>[];
  final rawInterests = user['interests'];
  if (rawInterests is List) {
    interests = rawInterests
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(10)
        .toList();
  } else if (user['interest'] is String &&
      (user['interest'] as String).trim().isNotEmpty) {
    interests = [(user['interest'] as String).trim()];
  }
  var custom = <String, String>{};
  final rawCustom = user['customCategories'];
  if (rawCustom is Map) {
    rawCustom.forEach((k, v) {
      if (k is String && v is String && interests.contains(k)) {
        custom[k] = v;
      }
    });
  }
  final fb = fallback;
  final resolvedBirth = birth ?? fb?.birthDate;
  return ProfileData(
    name: fullName.isNotEmpty ? fullName : (fb?.name ?? 'You'),
    username: username.isNotEmpty ? username : (fb?.username ?? '@you'),
    age: resolvedBirth != null ? calculateAge(resolvedBirth) : (fb?.age ?? 25),
    birthDate: resolvedBirth,
    email: email.isNotEmpty ? email : (fb?.email ?? ''),
    phone: phone.isNotEmpty ? phone : (fb?.phone ?? ''),
    community: community.isNotEmpty ? community : (fb?.community ?? ''),
    address: address.isNotEmpty ? address : (fb?.address ?? ''),
    interestTags:
        interests.isNotEmpty ? interests : (fb?.interestTags ?? const []),
    customInterestCategories:
        custom.isNotEmpty ? custom : (fb?.customInterestCategories ?? const {}),
  );
}

final ValueNotifier<ProfileData> currentProfile = ValueNotifier<ProfileData>(
  ProfileData(
    name: 'You',
    username: '@you',
    age: 25,
    birthDate: DateTime(2001, 5, 20),
    email: 'you@example.com',
    phone: '+1 234 567 8900',
    community: 'Riverside',
    address: '123 Main St, Riverside',
    interestTags: ['Hiking', 'Photography', 'Music'],
  ),
);

List<MatchUser> interestMatch(ProfileData profile, List<MatchUser> candidates) {
  final scored = candidates.map((user) {
    final shared = profile.interestTags
        .where((tag) => user.interestTags.contains(tag))
        .length;
    final max = profile.interestTags.isEmpty
        ? 1
        : (profile.interestTags.length + user.interestTags.length) ~/ 2;
    final ageDiff = (profile.displayAge - user.age).abs();
    final ageBonus = ageDiff <= 5 ? 0.2 : (ageDiff <= 10 ? 0.1 : 0);
    // 大类加分：不同小标签但同大类也加分，0.05/个大类，上限0.15
    final sharedCats = countSharedCategories(
      profile.interestTags,
      user.interestTags,
      profile.customInterestCategories,
      user.customInterestCategories,
    );
    final categoryBonus = (sharedCats * 0.05).clamp(0, 0.15);
    final score = (max > 0 ? shared / max : 0) + ageBonus + categoryBonus;
    return user.copyWith(
      matchScore: double.parse((score.clamp(0, 1) * 100).toStringAsFixed(0)),
    );
  }).toList();
  scored.sort(byMatchScore);
  return scored;
}

List<MatchUser> recommendMatch(ProfileData profile, List<MatchUser> candidates) {
  final scored = candidates.map((user) {
    double score = 0;
    if (user.community == profile.community) score += 0.4;
    final ageDiff = (profile.displayAge - user.age).abs();
    if (ageDiff <= 3) {
      score += 0.3;
    } else if (ageDiff <= 7) {
      score += 0.15;
    }
    final shared = profile.interestTags
        .where((tag) => user.interestTags.contains(tag))
        .length;
    // 小标签相同 +0.12，大类相同 +0.05/个（上限0.15）
    score += shared * 0.12;
    final sharedCats = countSharedCategories(
      profile.interestTags,
      user.interestTags,
      profile.customInterestCategories,
      user.customInterestCategories,
    );
    score += (sharedCats * 0.05).clamp(0, 0.15);
    return user.copyWith(
      matchScore: double.parse((score.clamp(0, 1) * 100).toStringAsFixed(0)),
    );
  }).toList();
  scored.sort(byMatchScore);
  return scored;
}

/// 分数降序，同分按名字，保证列表顺序稳定（List.sort 不稳定）。
int byMatchScore(MatchUser a, MatchUser b) {
  final byScore = b.matchScore.compareTo(a.matchScore);
  if (byScore != 0) return byScore;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
