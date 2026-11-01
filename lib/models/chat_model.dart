class Chat {
  final String userId;
  final String name;
  final String time;
  final int unreadCount;
  final String preview;
  final bool isGroup;
  final String category;
  final String? groupId;
  final int memberCount;
  final String? groupCreatorId;

  const Chat({
    required this.userId,
    required this.name,
    this.time = '',
    this.unreadCount = 0,
    this.preview = '',
    this.isGroup = false,
    this.category = 'All',
    this.groupId,
    this.memberCount = 0,
    this.groupCreatorId,
  });
}

class Message {
  final String text;
  final String time;
  final bool isIncoming;
  final bool isLocation;
  final bool isVoice;
  final String? voicePath;
  final String? voiceData;
  final String? voiceMimeType;
  final int voiceDuration;
  final String? senderName;

  const Message({
    required this.text,
    required this.time,
    this.isIncoming = true,
    this.isLocation = false,
    this.isVoice = false,
    this.voicePath,
    this.voiceData,
    this.voiceMimeType,
    this.voiceDuration = 0,
    this.senderName,
  });

  Map<String, dynamic> toJson() {
    final persistablePath = voicePath;
    return {
      'text': text,
      'time': time,
      'isIncoming': isIncoming,
      'isLocation': isLocation,
      'isVoice': isVoice,
      'voicePath': (persistablePath == null || persistablePath.startsWith('blob:'))
          ? null
          : persistablePath,
      'voiceData': voiceData,
      'voiceMimeType': voiceMimeType,
      'voiceDuration': voiceDuration,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      text: json['text'] as String? ?? '',
      time: json['time'] as String? ?? '',
      isIncoming: json['isIncoming'] as bool? ?? true,
      isLocation: json['isLocation'] as bool? ?? false,
      isVoice: json['isVoice'] as bool? ?? false,
      voicePath: json['voicePath'] as String?,
      voiceData: json['voiceData'] as String?,
      voiceMimeType: json['voiceMimeType'] as String?,
      voiceDuration: json['voiceDuration'] as int? ?? 0,
    );
  }
}

