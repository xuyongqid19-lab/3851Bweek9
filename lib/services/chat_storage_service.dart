import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_model.dart';

class ChatStorageService {
  static const _prefix = 'sent_messages_';

  Future<List<Message>> loadSentMessages(String chatName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$chatName');
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((json) => Message.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> appendSentMessage(String chatName, Message message) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = (await loadSentMessages(chatName)).toList();
    stored.add(message);
    await prefs.setString(
      '$_prefix$chatName',
      jsonEncode(stored.map((msg) => msg.toJson()).toList()),
    );
  }

  Future<void> clearSentMessages(String chatName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$chatName');
  }
}
