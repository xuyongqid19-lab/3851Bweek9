typedef FamilyJson = Map<String, dynamic>;

/// A server-authorized family snapshot. Membership IDs, not kinship labels, identify people.
class FamilyGroup {
  FamilyGroup(this.data);
  final FamilyJson data;
  String get id => data['id'] as String;
  String get name => data['name'] as String;
  String get description => data['description'] as String;
  FamilyJson get me => Map<String, dynamic>.from(data['me'] as Map);
  String get userId => me['userId'] as String;
  String get role => me['role'] as String;
  bool get canManage => role == 'owner' || role == 'admin';
  String? get invite => data['invite'] as String?;
  int get unread => data['unread'] as int? ?? 0;
  FamilyJson? get latest => data['latest'] == null
      ? null
      : Map<String, dynamic>.from(data['latest'] as Map);
  List<FamilyJson> rows(String key) => (data[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<FamilyJson> get members => rows('members');
  List<FamilyJson> get events => rows('events');
  List<FamilyJson> get checkins => rows('checkins');
  List<FamilyJson> records(String kind) =>
      rows('records').where((e) => e['kind'] == kind).toList();
  String activitySummary({DateTime? now}) {
    final all = records('activities');
    if (all.isEmpty) return 'Plan your first family activity';
    all.sort((a, b) =>
        a['body']['date'].toString().compareTo(b['body']['date'].toString()));
    final today = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    final next = all
            .where((a) => a['body']['date'].toString().compareTo(today) >= 0)
            .firstOrNull ??
        all.last;
    return '${next['body']['title']} · ${next['body']['date']}';
  }

  String person(String id) =>
      members
          .where((m) => m['userId'] == id)
          .map((m) => '${m['realName']} (${m['kinship']})')
          .firstOrNull ??
      'Former member';
  bool checked(String taskId, String memberId) =>
      checkins.any((c) => c['taskId'] == taskId && c['userId'] == memberId);
}

class FamilyInbox {
  FamilyInbox(FamilyJson data)
      : primaryId = data['primaryId'] as String?,
        groups = (data['groups'] as List)
            .map((e) => FamilyGroup(Map<String, dynamic>.from(e as Map)))
            .toList();
  final String? primaryId;
  final List<FamilyGroup> groups;
  FamilyGroup? get primary =>
      groups.where((g) => g.id == primaryId).firstOrNull;
}
