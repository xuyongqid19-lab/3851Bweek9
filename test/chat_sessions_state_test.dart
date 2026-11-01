import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/models/chat_model.dart';
import 'package:global_village_app/services/chat_sessions_state.dart';

void main() {
  final state = ChatSessionsState.instance;

  test('unread count defaults to zero for a new chat', () {
    const chat = Chat(
      userId: 'u-1',
      name: 'Alex Tan',
      unreadCount: 2,
    );
    expect(state.unreadCountOf(chat), 0);
  });

  test('markAsRead is a no-op for chats without unread messages', () {
    var notified = false;
    void listener() => notified = true;
    state.addListener(listener);
    state.markAsRead('Alex Tan');
    state.removeListener(listener);
    expect(notified, isFalse);
  });

  test('updateLastMessage refreshes preview and time', () {
    const chat = Chat(
      userId: 'u-2',
      name: 'Emily Lim',
      preview: 'Thanks for sharing the info!',
    );

    const voiceMessage = Message(
      text: 'Voice message',
      time: '5:12 PM',
      isIncoming: false,
      isVoice: true,
      voiceDuration: 8,
    );
    state.updateLastMessage(chat.name, voiceMessage);

    expect(state.previewOf(chat), 'Voice message');
    expect(state.timeOf(chat), '5:12 PM');

    const locationMessage = Message(
      text: 'Pine Ridge Trail',
      time: '5:14 PM',
      isIncoming: true,
      isLocation: true,
    );
    state.updateLastMessage(chat.name, locationMessage);
    expect(state.previewOf(chat), 'Location');

    const textMessage = Message(
      text: 'See you tomorrow!',
      time: '5:16 PM',
      isIncoming: false,
    );
    state.updateLastMessage(chat.name, textMessage);
    expect(state.previewOf(chat), 'See you tomorrow!');
    expect(state.lastMessageOf(chat.name), textMessage);
  });
}
