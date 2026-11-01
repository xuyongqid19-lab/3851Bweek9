import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'voice_blob_reader_stub.dart'
    if (dart.library.js_interop) 'voice_blob_reader_web.dart';

class RecordedVoice {
  final String path;
  final String? dataBase64;
  final String? mimeType;
  final int durationSeconds;

  const RecordedVoice({
    required this.path,
    required this.durationSeconds,
    this.dataBase64,
    this.mimeType,
  });
}

class VoiceMessageService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Timer? _recordTicker;
  StreamSubscription<void>? _playerCompleteSubscription;

  bool _isRecording = false;
  int _recordSeconds = 0;
  String? _playingPath;

  bool get isRecording => _isRecording;
  int get recordSeconds => _recordSeconds;
  String? get playingPath => _playingPath;
  bool get isPlaying => _playingPath != null;

  final _recordSecondsController = StreamController<int>.broadcast();
  final _playingPathController = StreamController<String?>.broadcast();

  Stream<int> get recordSecondsStream => _recordSecondsController.stream;
  Stream<String?> get playingPathStream => _playingPathController.stream;

  VoiceMessageService() {
    _playerCompleteSubscription = _player.onPlayerComplete.listen((_) {
      _playingPath = null;
      _playingPathController.add(null);
    });
  }

  Future<bool> startRecording() async {
    if (_isRecording) return true;

    final granted = await _recorder.hasPermission();
    if (!granted) return false;

    final path = await _resolveOutputPath();
    await _recorder.start(const RecordConfig(), path: path);

    _isRecording = true;
    _recordSeconds = 0;
    _recordSecondsController.add(0);
    _recordTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        _recordSeconds++;
        _recordSecondsController.add(_recordSeconds);
      },
    );
    return true;
  }

  Future<RecordedVoice?> stopRecording() async {
    _recordTicker?.cancel();
    _recordTicker = null;
    _isRecording = false;
    final seconds = _recordSeconds;
    final path = await _recorder.stop();
    if (path == null) return null;

    if (kIsWeb) {
      final blob = await readBlobBytes(path);
      return RecordedVoice(
        path: path,
        dataBase64: blob == null ? null : base64Encode(blob.bytes),
        mimeType: blob?.mime,
        durationSeconds: seconds,
      );
    }
    return RecordedVoice(path: path, durationSeconds: seconds);
  }

  Future<void> cancelRecording() async {
    _recordTicker?.cancel();
    _recordTicker = null;
    _isRecording = false;
    await _recorder.cancel();
  }

  Future<void> togglePlayback(String url) async {
    if (_playingPath == url) {
      await _player.stop();
      _playingPath = null;
      _playingPathController.add(null);
      return;
    }
    await _player.stop();
    await _player.play(kIsWeb ? UrlSource(url) : DeviceFileSource(url));
    _playingPath = url;
    _playingPathController.add(url);
  }

  Future<void> stopPlayback() async {
    if (_playingPath == null) return;
    await _player.stop();
    _playingPath = null;
    _playingPathController.add(null);
  }

  Future<String> _resolveOutputPath() async {
    if (kIsWeb) {
      return 'voice_message_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/voice_message_'
        '${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  void dispose() {
    _recordTicker?.cancel();
    _recordSecondsController.close();
    _playingPathController.close();
    _playerCompleteSubscription?.cancel();
    _recorder.dispose();
    _player.dispose();
  }
}
