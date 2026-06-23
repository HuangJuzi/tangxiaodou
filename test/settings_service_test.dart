import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bella/models/app_config.dart';
import 'package:bella/services/settings_service.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SettingsService', () {
    test('load returns null when storage is empty', () async {
      final svc = SettingsService();
      await svc.load();
      expect(svc.config, isNull);
    });

    test('save writes to storage and updates config', () async {
      final svc = SettingsService();
      final cfg = AppConfig(
        botApiStreamUrl: 'u',
        botApiSecret: 's',
        asrTtsApiKey: 'k',
        ttsVoice: 'longyumi_v2',
        ttsEnabled: true,
      );
      await svc.save(cfg);
      expect(svc.config, cfg);

      final raw = await const FlutterSecureStorage().read(key: 'app_config');
      expect(raw, isNotNull);
      final decoded = AppConfig.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
      expect(decoded.botApiStreamUrl, 'u');
    });

    test('save notifies listeners', () async {
      final svc = SettingsService();
      var notifyCount = 0;
      svc.addListener(() => notifyCount++);
      await svc.save(AppConfig.defaults());
      expect(notifyCount, 1);
    });

    test('load reads previously saved config', () async {
      final cfg = AppConfig(
        botApiStreamUrl: 'url2',
        botApiSecret: 'secret2',
        asrTtsApiKey: 'key2',
        ttsVoice: 'longanwen',
        ttsEnabled: false,
      );
      await const FlutterSecureStorage().write(
        key: 'app_config',
        value: jsonEncode(cfg.toJson()),
      );

      final svc = SettingsService();
      await svc.load();
      expect(svc.config, isNotNull);
      expect(svc.config!.botApiStreamUrl, 'url2');
      expect(svc.config!.ttsVoice, 'longanwen');
      expect(svc.config!.ttsEnabled, false);
    });

    test('load with corrupt JSON leaves config null', () async {
      await const FlutterSecureStorage().write(
        key: 'app_config',
        value: 'not json',
      );
      final svc = SettingsService();
      await svc.load();
      expect(svc.config, isNull);
    });
  });
}
