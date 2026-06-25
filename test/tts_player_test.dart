import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:tangxiaodou/services/tts_service.dart';
import 'package:tangxiaodou/services/tts_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsPlayer state', () {
    const globalChannel = MethodChannel('xyz.luan/audioplayers.global');
    const playerChannel = MethodChannel('xyz.luan/audioplayers');
    late AudioPlayer audioPlayer;
    late TtsService ttsService;
    late TtsPlayer player;

    setUpAll(() {
      // Stub the platform method channels so AudioPlayer can be constructed in
      // the test VM (no native plugin). Kept for the whole group so async
      // create/stop replies don't leak into later tests. Event-channel errors
      // are swallowed by AudioPlayer's internal onError handlers.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(globalChannel, (_) async => null);
      messenger.setMockMethodCallHandler(playerChannel, (_) async => null);
    });

    tearDownAll(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(globalChannel, null);
      messenger.setMockMethodCallHandler(playerChannel, null);
    });

    setUp(() {
      audioPlayer = AudioPlayer();
      ttsService = TtsService(apiKey: 'test-key');
      player = TtsPlayer(ttsService: ttsService, sink: AudioPlayerSink(audioPlayer));
    });

    tearDown(() async {
      await audioPlayer.dispose();
    });

    test('TtsPlayer initial state: not playing', () {
      expect(player.isPlaying, false);
      expect(player.isAutoPlaying, false);
      expect(player.playingMessageId, null);
    });

    test('TtsPlayer stop resets all flags', () {
      player.stop();
      expect(player.isPlaying, false);
      expect(player.isAutoPlaying, false);
      expect(player.playingMessageId, null);
    });

    test('TtsPlayer multiple stops are safe (idempotent)', () {
      player.stop();
      player.stop();
      player.stop();
      expect(player.isPlaying, false);
      expect(player.isAutoPlaying, false);
    });
  });

  group('sanitize', () {
    test('removes bare URLs entirely', () {
      expect(TtsPlayer.sanitize('点击 https://foo.com/bar 查看'), '点击，查看');
    });

    test('removes absolute file paths', () {
      expect(TtsPlayer.sanitize('打开 /mnt/b/lib/main.dart 文件'), '打开，文件');
    });

    test('removes relative file paths with a slash', () {
      expect(TtsPlayer.sanitize('看 lib/main.dart 这里'), '看，这里');
    });

    test('keeps bare filename and reads dot as 点, lowercased', () {
      expect(TtsPlayer.sanitize('文件叫 MEMORY.MD'), '文件叫，memory点md');
    });

    test('reads version dot as 点', () {
      expect(TtsPlayer.sanitize('版本 v2.0 发布'), '版本，v2点0，发布');
    });

    test('lowercases ascii letters', () {
      expect(TtsPlayer.sanitize('HELLO World'), 'hello，world');
    });

    test('leaves plain CJK untouched', () {
      expect(TtsPlayer.sanitize('你好世界'), '你好世界');
    });
  });

  group('inProgressTail', () {
    test('holds a half-arrived URL at the tail', () {
      expect(TtsPlayer.inProgressTail('见 https://foo.co'), 2);
    });

    test('holds a half-arrived path at the tail', () {
      expect(TtsPlayer.inProgressTail('打开 /mnt/b/li'), 3);
    });

    test('holds an in-progress filename at the tail', () {
      expect(TtsPlayer.inProgressTail('看 memory.'), 2);
    });

    test('releases a URL terminated by whitespace', () {
      expect(TtsPlayer.inProgressTail('见 https://foo.com 了'), -1);
    });

    test('returns -1 when there is no link', () {
      expect(TtsPlayer.inProgressTail('你好世界'), -1);
    });
  });
}
