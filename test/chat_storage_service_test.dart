import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/models/chat_model.dart';
import 'package:global_village_app/services/chat_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = ChatStorageService();
  });

  test('empty storage returns no sent messages', () async {
    final messages = await storage.loadSentMessages('Alex Tan');
    expect(messages, isEmpty);
  });

  test('text message survives a storage round-trip', () async {
    const chat = 'Alex Tan';
    const message = Message(
      text: 'Hello there!',
      time: '3:42 PM',
      isIncoming: false,
    );

    await storage.appendSentMessage(chat, message);

    final restored = await storage.loadSentMessages(chat);
    expect(restored, hasLength(1));
    expect(restored.first.text, 'Hello there!');
    expect(restored.first.time, '3:42 PM');
    expect(restored.first.isIncoming, isFalse);
    expect(restored.first.isVoice, isFalse);
  });

  test('voice message keeps audio data across a storage round-trip', () async {
    const chat = 'Mom';
    const message = Message(
      text: 'Voice message',
      time: '4:05 PM',
      isIncoming: false,
      isVoice: true,
      voicePath: 'blob:http://localhost/abc123',
      voiceData: 'AAAA-serialized-audio-bytes==',
      voiceMimeType: 'audio/mp4;codecs=mp4a.40.2',
      voiceDuration: 6,
    );

    await storage.appendSentMessage(chat, message);

    final restored = await storage.loadSentMessages(chat);
    expect(restored, hasLength(1));
    expect(restored.first.isVoice, isTrue);
    expect(restored.first.voiceDuration, 6);
    expect(restored.first.voiceData, 'AAAA-serialized-audio-bytes==');
    expect(restored.first.voiceMimeType, 'audio/mp4;codecs=mp4a.40.2');
    expect(restored.first.voicePath, isNull,
        reason: 'blob URLs must not be persisted');
  });

  test('messages accumulate in order and per chat', () async {
    const chatA = 'Alex Tan';
    const chatB = 'Mom';

    await storage.appendSentMessage(chatA,
        const Message(text: 'first', time: '1:00 PM', isIncoming: false));
    await storage.appendSentMessage(chatA,
        const Message(text: 'second', time: '1:01 PM', isIncoming: false));
    await storage.appendSentMessage(chatB,
        const Message(text: 'elsewhere', time: '1:02 PM', isIncoming: false));

    final restoredA = await storage.loadSentMessages(chatA);
    final restoredB = await storage.loadSentMessages(chatB);

    expect(restoredA.map((m) => m.text), ['first', 'second']);
    expect(restoredB.map((m) => m.text), ['elsewhere']);
  });

  test('clearSentMessages removes the stored history', () async {
    const chat = 'Alex Tan';
    await storage.appendSentMessage(
        chat, const Message(text: 'bye', time: '2:00 PM', isIncoming: false));

    await storage.clearSentMessages(chat);

    expect(await storage.loadSentMessages(chat), isEmpty);
  });

  test('corrupted storage data is ignored safely', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sent_messages_Alex Tan': 'not-json{{{',
    });

    final messages = await storage.loadSentMessages('Alex Tan');
    expect(messages, isEmpty);
  });
}
