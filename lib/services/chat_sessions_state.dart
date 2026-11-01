import 'package:flutter/foundation.dart';

import '../models/chat_model.dart';

class ChatSessionsState extends ChangeNotifier {
  ChatSessionsState._();

  static final ChatSessionsState instance = ChatSessionsState._();

  final Map<String, Message> _lastMessages = {};
  final Map<String, int> _unreadCounts = {};

  Message? lastMessageOf(String chatName) => _lastMessages[chatName];

  String previewOf(Chat chat) {
    final message = _lastMessages[chat.name];
    if (message == null) return chat.preview;
    if (message.isVoice) return 'Voice message';
    if (message.isLocation) return 'Location';
    return message.text;
  }

  String timeOf(Chat chat) => _lastMessages[chat.name]?.time ?? chat.time;

  int unreadCountOf(Chat chat) => _unreadCounts[chat.name] ?? 0;

  void markAsRead(String chatName) {
    if ((_unreadCounts[chatName] ?? 0) == 0) return;
    _unreadCounts[chatName] = 0;
    notifyListeners();
  }

  void updateLastMessage(String chatName, Message message) {
    _lastMessages[chatName] = message;
    notifyListeners();
  }
}
