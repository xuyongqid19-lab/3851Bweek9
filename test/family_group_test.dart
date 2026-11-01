import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/models/family_group.dart';

void main() {
  test('home activity summary selects the next date rather than creation order',
      () {
    final group = FamilyGroup({
      'records': [
        {
          'kind': 'activities',
          'body': {'title': 'Later', 'date': '2026-09-20'}
        },
        {
          'kind': 'activities',
          'body': {'title': 'Past', 'date': '2026-09-01'}
        },
        {
          'kind': 'activities',
          'body': {'title': 'Next', 'date': '2026-09-12'}
        },
      ]
    });
    expect(
        group.activitySummary(now: DateTime(2026, 9, 9)), 'Next · 2026-09-12');
    expect(group.activitySummary(now: DateTime(2026, 10, 1)),
        'Later · 2026-09-20');
    expect(FamilyGroup({'records': []}).activitySummary(),
        'Plan your first family activity');
  });
}
