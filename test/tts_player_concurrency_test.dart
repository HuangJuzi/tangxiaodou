import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tangxiaodou/services/tts_service.dart';
import 'package:tangxiaodou/services/tts_player.dart';

/// A TtsService fake that mimics the real Sophnet API's behavior under load:
/// when two synthesize calls overlap, the API returns HTTP 200 with an EMPTY
/// body (empirically confirmed — ~60% of 15 concurrent requests come back
/// empty). A lone call returns non-empty bytes.
class _ConcurrencySensitiveTtsService extends TtsService {
  _ConcurrencySensitiveTtsService() : super(apiKey: 'fake');

  int _inflight = 0;
  final List<String> synthOrder = [];

  @override
  Future<List<int>> synthesize(String text) async {
    synthOrder.add(text);
    // If another call is already in flight, the server returns an empty 200.
    if (_inflight > 0) {
      return <int>[];
    }
    _inflight++;
    await Future.delayed(const Duration(milliseconds: 20));
    _inflight--;
    return utf8.encode('audio:$text');
  }
}

/// A fake sink that records what would be played and drives completion so the
/// play loop can advance without a real native audio plugin.
class _RecordingSink implements TtsAudioSink {
  final List<String> played = [];
  final _ctrl = StreamController<void>.broadcast();
  double? volume;

  @override
  Future<void> setVolume(double v) async {
    volume = v;
  }

  @override
  Future<void> playFile(String path) async {
    played.add(path);
    // Emit completion on a later macrotask turn, AFTER TtsPlayer has registered
    // its `onComplete.first` listener (which happens once playFile returns).
    Future<void>.delayed(const Duration(milliseconds: 1), () => _ctrl.add(null));
  }

  @override
  Future<void> stop() async {}

  @override
  Stream<void> get onComplete => _ctrl.stream;

  Future<void> close() => _ctrl.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Stub path_provider so _playBytes can write its temp file in the test VM.
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall call) async {
      if (call.method == 'getTemporaryDirectory') return '/tmp';
      return null;
    });
  });

  test('all chunks play when synthesis is serialized (no drops under load)', () async {
    final service = _ConcurrencySensitiveTtsService();
    final sink = _RecordingSink();
    final player = TtsPlayer(ttsService: service, sink: sink);

    final chunks = [
      '你好呀小朋友。',
      '今天我们去公园玩。',
      '你想吃什么水果呢？',
      '苹果和香蕉都不错。',
      '讲个故事好不好。',
      '我们下次再讲吧。',
    ];
    for (final c in chunks) {
      player.enqueue(c);
    }

    // Give the pipeline time to synthesize + play all chunks.
    var waited = 0;
    while (sink.played.length < chunks.length && waited < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      waited += 50;
    }

    // The fix: every chunk must be played. The old all-concurrent design fired
    // every synthesize at once → the API returned empty for the overlapping
    // calls → those chunks were silently skipped (played.length < chunks.length).
    expect(sink.played.length, chunks.length,
        reason: 'some chunks were dropped (played ${sink.played.length}/${chunks.length})');

    await sink.close();
  });
}
