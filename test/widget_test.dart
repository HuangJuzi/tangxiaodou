import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tangxiaodou/main.dart';
import 'package:tangxiaodou/models/app_config.dart';
import 'package:tangxiaodou/services/settings_service.dart';

void main() {
  testWidgets('App renders chat screen with saved config', (WidgetTester tester) async {
    final cfg = AppConfig(
      botApiStreamUrl: 'https://example.com/bot-api/v2/test/chat-stream',
      botApiSecret: 'secret',
      asrTtsApiKey: 'apikey',
      ttsVoice: 'longyumi_v2',
      ttsEnabled: true,
    );
    FlutterSecureStorage.setMockInitialValues({
      'app_config': jsonEncode(cfg.toJson()),
    });

    final settings = SettingsService();
    await settings.load();

    await tester.pumpWidget(TangxiaodouApp(settings: settings));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('按住说话'), findsOneWidget);
  });
}
