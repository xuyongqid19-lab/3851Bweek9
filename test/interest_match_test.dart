import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/models/profile_model.dart';
import 'package:global_village_app/pages/profile_page.dart';
import 'package:global_village_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

MatchUser candidate({
  required String id,
  required String name,
  int age = 25,
  String community = '',
  List<String> interests = const [],
  Map<String, String> custom = const {},
}) {
  return MatchUser(
    id: id,
    name: name,
    age: age,
    community: community,
    interestTags: interests,
    customInterestCategories: custom,
  );
}

ProfileData profile({
  int age = 25,
  String community = 'Riverside',
  List<String> interests = const ['Hiking', 'Photography'],
  Map<String, String> custom = const {},
}) {
  return ProfileData(
    name: 'You',
    username: '@you',
    age: age,
    email: 'you@example.com',
    phone: '+1 234 567 8900',
    community: community,
    interestTags: interests,
    customInterestCategories: custom,
  );
}

void main() {
  group('MatchUser.fromJson', () {
    test('maps a match candidate from the backend', () {
      final user = MatchUser.fromJson(const <String, dynamic>{
        'id': 'u-1',
        'fullName': '  Alex Johnson ',
        'username': 'alex',
        'email': 'alex@example.com',
        'birthDate': '2000-06-15',
        'community': 'Riverside',
        'interests': ['Hiking', 'Photography'],
        'customCategories': {'Hiking': 'Outdoors'},
        'googlePhotoUrl': 'https://example.com/a.png',
        'authProvider': 'google',
      });

      expect(user.id, 'u-1');
      expect(user.name, 'Alex Johnson');
      expect(user.username, 'alex');
      expect(user.email, 'alex@example.com');
      expect(user.community, 'Riverside');
      expect(user.interestTags, ['Hiking', 'Photography']);
      expect(user.customInterestCategories, {'Hiking': 'Outdoors'});
      expect(user.googlePhotoUrl, 'https://example.com/a.png');
      expect(user.authProvider, 'google');
      expect(user.age, greaterThan(0));
      expect(user.avatarInitial, 'A');
    });

    test('tolerates a sparse record without birth date or photo', () {
      final user = MatchUser.fromJson(const <String, dynamic>{
        'id': 'u-2',
        'fullName': 'Sam',
      });

      expect(user.age, 0);
      expect(user.googlePhotoUrl, isNull);
      expect(user.username, isNull);
      expect(user.email, isNull);
      expect(user.interestTags, isEmpty);
      expect(user.avatarInitial, 'S');
    });

    test('falls back to the legacy single interest field', () {
      final user = MatchUser.fromJson(const <String, dynamic>{
        'id': 'u-3',
        'fullName': 'Kim',
        'interest': 'Yoga',
      });

      expect(user.interestTags, ['Yoga']);
    });

    test('drops custom categories that are not a known interest', () {
      final user = MatchUser.fromJson(const <String, dynamic>{
        'id': 'u-4',
        'fullName': 'Pat',
        'interests': ['Yoga'],
        'customCategories': {'Yoga': 'Mind', 'Chess': 'Mind'},
      });

      expect(user.customInterestCategories, {'Yoga': 'Mind'});
    });
  });

  group('countSharedCategories', () {
    test('counts a shared big category from both custom maps', () {
      expect(
        countSharedCategories(
          ['Chess'],
          ['Chess'],
          {'Chess': 'Mind'},
          {'Chess': 'Mind'},
        ),
        1,
      );
      // 没有归类时，自定义标签不算大类重合。
      expect(countSharedCategories(['Chess'], ['Chess']), 0);
    });
  });

  group('interestMatch', () {
    test('scores and sorts the candidates passed in', () {
      final matches = interestMatch(profile(), [
        candidate(id: 'b', name: 'Bea', age: 40, community: 'Riverside', interests: ['Yoga']),
        candidate(
          id: 'a',
          name: 'Anna',
          age: 25,
          community: 'Downtown',
          interests: ['Hiking', 'Photography'],
        ),
      ]);

      expect(matches.map((u) => u.id).toList(), ['a', 'b']);
      expect(matches.first.matchScore, 100);
      // Bea 没有任何共同小标签，但 'Yoga' 与 'Photography' 同属 Mind 大类，仍拿到 0.05 大类加分。
      expect(matches.last.matchScore, 5);
      // 评分不改候选人本身的字段。
      expect(matches.first.name, 'Anna');
      expect(matches.first.community, 'Downtown');
    });

    test('orders equal scores by name so the list stays stable', () {
      final matches = interestMatch(
        profile(interests: const ['Hiking']),
        [
          candidate(id: 'z', name: 'Zoe'),
          candidate(id: 'a', name: 'Adam'),
        ],
      );

      expect(matches.map((u) => u.name).toList(), ['Adam', 'Zoe']);
      expect(matches.first.matchScore, matches.last.matchScore);
    });

    test('returns an empty list when there is nobody to match', () {
      expect(interestMatch(profile(), const []), isEmpty);
    });
  });

  group('recommendMatch', () {
    test('ranks the closer candidate first', () {
      final matches = recommendMatch(profile(), [
        candidate(id: 'far', name: 'Farah', age: 40, community: 'Downtown'),
        candidate(id: 'near', name: 'Nina', age: 25, community: 'Riverside'),
      ]);

      expect(matches.map((u) => u.id).toList(), ['near', 'far']);
      expect(matches.first.matchScore, 70);
      expect(matches.last.matchScore, 0);
    });

    test('uses both custom maps when awarding the category bonus', () {
      final p = profile(
        interests: const ['Chess'],
        custom: const {'Chess': 'Mind'},
      );

      final matches = recommendMatch(p, [
        candidate(id: 'plain', name: 'Plain', community: 'Riverside', interests: ['Chess']),
        candidate(
          id: 'tagged',
          name: 'Tagged',
          community: 'Riverside',
          interests: ['Chess'],
          custom: const {'Chess': 'Mind'},
        ),
      ]);

      expect(matches.map((u) => u.id).toList(), ['tagged', 'plain']);
      expect(matches.first.matchScore, 87);
      expect(matches.last.matchScore, 82);
    });
  });

  testWidgets('match tabs show a retry instead of the old fake people',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const ProfilePage(),
    ));
    await tester.pumpAndSettle();

    // 写死的候选人已经删除。
    expect(find.text('Alex Johnson'), findsNothing);
    expect(find.text('Sophie Chen'), findsNothing);

    await tester.tap(find.text('Interest Match'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Recommended'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
