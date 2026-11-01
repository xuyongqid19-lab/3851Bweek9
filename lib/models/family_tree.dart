import 'family_group.dart';

/// Shared topology never contains another family's private member/record payloads.
class FamilyTreeSnapshot {
  FamilyTreeSnapshot(this.data);
  final FamilyJson data;
  String get groupId => data['groupId'] as String;
  String get role => data['role'] as String;
  bool get canManage => role == 'owner' || role == 'admin';
  String get version => data['version'] as String;
  String get code => data['code'] as String? ?? '';
  List<FamilyJson> rows(String key) => (data[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<FamilyJson> get nodes => rows('nodes');
  List<FamilyJson> get connections => rows('connections');
  List<FamilyJson> get requests => rows('requests');
  String name(String id) =>
      nodes
          .where((n) => n['id'] == id)
          .map((n) => n['name'] as String)
          .firstOrNull ??
      'Family';
  int get waiting => requests
      .where((r) => r['status'] == 'pending' && r['myApproval'] != true)
      .length;

  /// Viewpoint-relative traversal. Depth describes connection distance, not ancestry.
  List<FamilyJson> get outline {
    final result = <FamilyJson>[];
    final seen = <String>{};
    void visit(String id, int depth, String? parent, String? label) {
      if (!seen.add(id)) return;
      final node = nodes.where((n) => n['id'] == id).firstOrNull;
      if (node == null) return;
      result.add({...node, 'depth': depth, 'parent': parent, 'label': label});
      final edges = connections
          .where((e) => e['a'] == id || e['b'] == id)
          .toList()
        ..sort((a, b) => name(a['a'] == id ? a['b'] : a['a'])
            .compareTo(name(b['a'] == id ? b['b'] : b['a'])));
      for (final e in edges) {
        visit(e['a'] == id ? e['b'] : e['a'], depth + 1, id, e['label']);
      }
    }

    visit(groupId, 0, null, null);
    return result;
  }
}
