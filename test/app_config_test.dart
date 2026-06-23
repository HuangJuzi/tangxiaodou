import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bella/models/app_config.dart';

void main() {
  group('AppConfig', () {
    test('isComplete is false when any required field is empty', () {
      expect(
        AppConfig(
          botApiStreamUrl: '',
          botApiSecret: 's',
          asrTtsApiKey: 'k',
          ttsVoice: 'longyumi_v2',
          ttsEnabled: true,
        ).isComplete,
        false,
      );
      expect(
        AppConfig(
          botApiStreamUrl: 'u',
          botApiSecret: '',
          asrTtsApiKey: 'k',
          ttsVoice: 'longyumi_v2',
          ttsEnabled: true,
        ).isComplete,
        false,
      );
      expect(
        AppConfig(
          botApiStreamUrl: 'u',
          botApiSecret: 's',
          asrTtsApiKey: '',
          ttsVoice: 'longyumi_v2',
          ttsEnabled: true,
        ).isComplete,
        false,
      );
    });

    test('isComplete is true when all required fields non-empty', () {
      expect(
        AppConfig(
          botApiStreamUrl: 'u',
          botApiSecret: 's',
          asrTtsApiKey: 'k',
          ttsVoice: 'longyumi_v2',
          ttsEnabled: false,
        ).isComplete,
        true,
      );
    });

    test('toJson / fromJson round-trip', () {
      final original = AppConfig(
        botApiStreamUrl: 'https://example.com/bot-api/v2/x/chat-stream',
        botApiSecret: 'secret123',
        asrTtsApiKey: 'apikey456',
        ttsVoice: 'longanwen',
        ttsEnabled: false,
      );
      final encoded = original.toJson();
      final decoded = AppConfig.fromJson(encoded);
      expect(decoded.botApiStreamUrl, original.botApiStreamUrl);
      expect(decoded.botApiSecret, original.botApiSecret);
      expect(decoded.asrTtsApiKey, original.asrTtsApiKey);
      expect(decoded.ttsVoice, original.ttsVoice);
      expect(decoded.ttsEnabled, original.ttsEnabled);
    });

    test('defaults creates incomplete config with default voice and tts on', () {
      final cfg = AppConfig.defaults();
      expect(cfg.botApiStreamUrl, '');
      expect(cfg.botApiSecret, '');
      expect(cfg.asrTtsApiKey, '');
      expect(cfg.ttsVoice, 'longyumi_v2');
      expect(cfg.ttsEnabled, true);
      expect(cfg.isComplete, false);
    });

    group('fromBase64', () {
      // Sample base64 decodes to:
      // {"agentId":"dept-token","apiSecret":"7849cc...","streamUrl":"https://moltbot-...sophnet.com/bot-api/v2/dept-token/chat-stream"}
      const sampleBase64 =
          'eyJhZ2VudElkIjoiZGVwdC10b2tlbiIsImFwaVNlY3JldCI6Ijc4NDljYzRlZjAzYTM1MmNlMzY3MDNmZmEyYmZjMzI5NTk1YjQ3OGYzMTRmZjYyM2FlM2U1MjlhZGI0MjY3OTEiLCJzdHJlYW1VcmwiOiJodHRwczovL21vbHRib3QtMDAxNGM2MmI3Yzc5NDdjMy5zb3BobmV0LmNvbS9ib3QtYXBpL3YyL2RlcHQtdG9rZW4vY2hhdC1zdHJlYW0ifQ==';

      test('parses valid base64 and extracts streamUrl + apiSecret', () {
        final result = BotApiBase64.parse(sampleBase64);
        expect(result, isNotNull);
        expect(result!.streamUrl, startsWith('https://moltbot-'));
        expect(result.streamUrl, contains('/bot-api/v2/dept-token/chat-stream'));
        expect(result.apiSecret, '7849cc4ef03a352ce36703ffa2bfc329595b478f314ff623ae3e529adb426791');
      });

      test('returns null on invalid base64', () {
        expect(BotApiBase64.parse('not-valid-base64!!!'), isNull);
      });

      test('returns null on valid base64 but non-JSON content', () {
        final raw = base64Encode(utf8.encode('hello world'));
        expect(BotApiBase64.parse(raw), isNull);
      });

      test('returns null when streamUrl missing from JSON', () {
        final raw = base64Encode(utf8.encode(jsonEncode({'apiSecret': 's'})));
        expect(BotApiBase64.parse(raw), isNull);
      });

      test('returns null when apiSecret missing from JSON', () {
        final raw = base64Encode(utf8.encode(jsonEncode({'streamUrl': 'u'})));
        expect(BotApiBase64.parse(raw), isNull);
      });
    });
  });
}
