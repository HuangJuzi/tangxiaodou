# Settings Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a settings page that persists Bot-API (streamUrl + apiSecret from base64/QR), ASR/TTS apiKey, and TTS voice via `flutter_secure_storage`, with hot-swap of services on save and forced first-launch setup when config is incomplete.

**Architecture:** A `SettingsService extends ChangeNotifier` reads/writes an encrypted `AppConfig` blob. `BellaApp` becomes stateful and subscribes; on config change it rebuilds `LlmService/AsrService/TtsService/OssService` and re-renders the subtree. `LlmConfig` is refactored from `(baseUrl, accountId, apiSecret)` to `(streamUrl, apiSecret)` to match the base64 payload directly.

**Tech Stack:** Flutter, `flutter_secure_storage` ^9.x, `mobile_scanner` ^5.x, `dio`, existing `record`/`audioplayers`/etc.

**Spec deviation (intentional):** The spec said "保存即清空消息历史、重建 ChatScreen". On reflection, old messages are already-complete history (no live streams), so keeping them after a settings change is harmless and better UX. This plan keeps messages across settings saves. Existing `messages.json` continues to load normally on rebuild. Call out if you'd prefer the spec's clear-on-save behavior.

---

## File Structure

| File | Responsibility | Status |
|---|---|---|
| `lib/models/app_config.dart` | `AppConfig` value type + JSON/base64 codecs | NEW |
| `lib/services/settings_service.dart` | `ChangeNotifier` over `flutter_secure_storage`; load/save `AppConfig` | NEW |
| `lib/services/llm_service.dart` | `LlmConfig` refactor + use `streamUrl` directly | MODIFY |
| `lib/screens/settings_screen.dart` | 3-section form: Bot-API / API Key / Voice; paste + scan base64 | NEW |
| `lib/screens/qr_scan_screen.dart` | Full-screen `MobileScanner` wrapper returning scanned string | NEW |
| `lib/main.dart` | Stateful `BellaApp`; subscribe to `SettingsService`; rebuild services on change | MODIFY |
| `lib/screens/chat_screen.dart` | Replace tune icon with settings gear; remove voice JSON persistence; route through `SettingsService` for voice/tts toggle | MODIFY |
| `test/app_config_test.dart` | Round-trip, `isComplete`, base64 decode | NEW |
| `test/settings_service_test.dart` | load/save/notify | NEW |
| `pubspec.yaml` | Add deps | MODIFY |

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add `flutter_secure_storage` and `mobile_scanner` to `pubspec.yaml`**

Open `pubspec.yaml` and add under `dependencies:` (after `dio: ^5.7.0`):

```yaml
  flutter_secure_storage: ^9.2.2
  mobile_scanner: ^5.2.3
```

- [ ] **Step 2: Run `flutter pub get`**

Run: `flutter pub get`
Expected: resolves successfully, no version conflicts.

- [ ] **Step 3: Android platform config for `mobile_scanner`**

In `android/app/src/main/AndroidManifest.xml`, ensure `<uses-permission android:name="android.permission.CAMERA"/>` is added inside `<manifest>` (next to existing microphone permission). If `android:name` application already has no `tools:replace` issues, also verify `minSdkVersion` ≥ 21 in `android/app/build.gradle` (mobile_scanner requires API 21+).

- [ ] **Step 4: iOS platform config (if you build for iOS)**

In `ios/Runner/Info.plist`, add inside `<dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>扫描二维码以导入 Bot-API 配置</string>
<key>NSMicrophoneUsageDescription</key>
<string>录音用于语音识别</string>
```

(Skip if you're only building Android. User confirmed phone connected is Android.)

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "chore: add flutter_secure_storage and mobile_scanner deps"
```

---

## Task 2: Create `AppConfig` model

**Files:**
- Create: `lib/models/app_config.dart`
- Create: `test/app_config_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/app_config_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/app_config_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'package:bella/models/app_config.dart'" or similar.

- [ ] **Step 3: Write `AppConfig` implementation**

Create `lib/models/app_config.dart`:

```dart
import 'dart:convert';

class AppConfig {
  final String botApiStreamUrl;
  final String botApiSecret;
  final String asrTtsApiKey;
  final String ttsVoice;
  final bool ttsEnabled;

  const AppConfig({
    required this.botApiStreamUrl,
    required this.botApiSecret,
    required this.asrTtsApiKey,
    required this.ttsVoice,
    required this.ttsEnabled,
  });

  factory AppConfig.defaults() => const AppConfig(
        botApiStreamUrl: '',
        botApiSecret: '',
        asrTtsApiKey: '',
        ttsVoice: 'longyumi_v2',
        ttsEnabled: true,
      );

  bool get isComplete =>
      botApiStreamUrl.isNotEmpty &&
      botApiSecret.isNotEmpty &&
      asrTtsApiKey.isNotEmpty;

  AppConfig copyWith({
    String? botApiStreamUrl,
    String? botApiSecret,
    String? asrTtsApiKey,
    String? ttsVoice,
    bool? ttsEnabled,
  }) =>
      AppConfig(
        botApiStreamUrl: botApiStreamUrl ?? this.botApiStreamUrl,
        botApiSecret: botApiSecret ?? this.botApiSecret,
        asrTtsApiKey: asrTtsApiKey ?? this.asrTtsApiKey,
        ttsVoice: ttsVoice ?? this.ttsVoice,
        ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      );

  Map<String, dynamic> toJson() => {
        'botApiStreamUrl': botApiStreamUrl,
        'botApiSecret': botApiSecret,
        'asrTtsApiKey': asrTtsApiKey,
        'ttsVoice': ttsVoice,
        'ttsEnabled': ttsEnabled,
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        botApiStreamUrl: json['botApiStreamUrl'] as String? ?? '',
        botApiSecret: json['botApiSecret'] as String? ?? '',
        asrTtsApiKey: json['asrTtsApiKey'] as String? ?? '',
        ttsVoice: json['ttsVoice'] as String? ?? 'longyumi_v2',
        ttsEnabled: json['ttsEnabled'] as bool? ?? true,
      );
}

/// Decoded Bot-API base64 payload (subset of fields we care about).
class BotApiBase64Result {
  final String streamUrl;
  final String apiSecret;
  const BotApiBase64Result({required this.streamUrl, required this.apiSecret});
}

/// Parses a base64-encoded JSON config string from QR code or clipboard paste.
/// Returns null on any failure (invalid base64, non-JSON, missing fields).
class BotApiBase64 {
  const BotApiBase64._();

  static BotApiBase64Result? parse(String input) {
    String decoded;
    try {
      decoded = utf8.decode(base64.decode(input.trim()));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(decoded) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
    final streamUrl = json['streamUrl'] as String?;
    final apiSecret = json['apiSecret'] as String?;
    if (streamUrl == null || streamUrl.isEmpty) return null;
    if (apiSecret == null || apiSecret.isEmpty) return null;
    return BotApiBase64Result(streamUrl: streamUrl, apiSecret: apiSecret);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/app_config_test.dart`
Expected: all 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/app_config.dart test/app_config_test.dart
git commit -m "feat: add AppConfig model with base64 decoding"
```

---

## Task 3: Create `SettingsService`

**Files:**
- Create: `lib/services/settings_service.dart`
- Create: `test/settings_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/settings_service_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/settings_service_test.dart`
Expected: FAIL (SettingsService doesn't exist yet).

- [ ] **Step 3: Write `SettingsService` implementation**

Create `lib/services/settings_service.dart`:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/app_config.dart';

class SettingsService extends ChangeNotifier {
  static const _storageKey = 'app_config';
  final FlutterSecureStorage _storage;

  AppConfig? _config;
  AppConfig? get config => _config;

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        _config = AppConfig.fromJson(decoded as Map<String, dynamic>);
      } else {
        _config = null;
      }
    } on FormatException {
      _config = null;
    } catch (e) {
      debugPrint('[Settings] load error: $e');
      _config = null;
    }
    notifyListeners();
  }

  Future<void> save(AppConfig cfg) async {
    _config = cfg;
    await _storage.write(key: _storageKey, value: jsonEncode(cfg.toJson()));
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/settings_service_test.dart`
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/settings_service.dart test/settings_service_test.dart
git commit -m "feat: add SettingsService with encrypted persistence"
```

---

## Task 4: Refactor `LlmConfig` to `(streamUrl, apiSecret)`

**Files:**
- Modify: `lib/services/llm_service.dart:6-17` (LlmConfig class)
- Modify: `lib/services/llm_service.dart:48-56` (use `_config.streamUrl` directly)

- [ ] **Step 1: Replace `LlmConfig` class definition**

In `lib/services/llm_service.dart`, replace the existing `LlmConfig` class (lines 6-18):

```dart
class LlmConfig {
  final String streamUrl;
  final String apiSecret;

  const LlmConfig({
    required this.streamUrl,
    required this.apiSecret,
  });
}
```

- [ ] **Step 2: Replace the POST URL in `chat()`**

In `lib/services/llm_service.dart`, find:

```dart
      response = await _dio.post<ResponseBody>(
        _config.streamUrl,
```

This already uses `_config.streamUrl` (was previously computed via a getter). After the refactor it's now a stored field — no further change needed. Verify by reading the surrounding code.

- [ ] **Step 3: Verify by running existing tests + analyzer**

Run: `flutter analyze lib/services/llm_service.dart`
Expected: no errors.

Run: `flutter test`
Expected: existing tests still pass (no LlmConfig-specific tests exist yet; the change is shape-only).

- [ ] **Step 4: Commit**

```bash
git add lib/services/llm_service.dart
git commit -m "refactor: LlmConfig uses full streamUrl instead of baseUrl+accountId"
```

---

## Task 5: Create `QrScanScreen`

**Files:**
- Create: `lib/screens/qr_scan_screen.dart`

This is a thin UI wrapper; no unit tests. Manual verification via end-to-end test (Task 9).

- [ ] **Step 1: Write `QrScanScreen`**

Create `lib/screens/qr_scan_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR scanner. Returns the scanned raw string via Navigator.pop.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final MobileScannerController _controller;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_returned) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    _returned = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyzer passes**

Run: `flutter analyze lib/screens/qr_scan_screen.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/qr_scan_screen.dart
git commit -m "feat: add QrScanScreen using mobile_scanner"
```

---

## Task 6: Create `SettingsScreen`

**Files:**
- Create: `lib/screens/settings_screen.dart`

No unit tests for UI; manual verification via Task 9.

- [ ] **Step 1: Write `SettingsScreen`**

Create `lib/screens/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart' show ttsVoices;
import '../theme.dart';
import 'qr_scan_screen.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;
  final bool isFirstLaunch;

  const SettingsScreen({
    required this.settingsService,
    this.isFirstLaunch = false,
    super.key,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _streamUrlCtrl;
  late final TextEditingController _apiSecretCtrl;
  late final TextEditingController _apiKeyCtrl;
  late String _voice;
  late bool _ttsEnabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cfg = widget.settingsService.config ?? AppConfig.defaults();
    _streamUrlCtrl = TextEditingController(text: cfg.botApiStreamUrl);
    _apiSecretCtrl = TextEditingController(text: cfg.botApiSecret);
    _apiKeyCtrl = TextEditingController(text: cfg.asrTtsApiKey);
    _voice = cfg.ttsVoice;
    _ttsEnabled = cfg.ttsEnabled;
  }

  @override
  void dispose() {
    _streamUrlCtrl.dispose();
    _apiSecretCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _streamUrlCtrl.text.trim().isNotEmpty &&
      _apiSecretCtrl.text.trim().isNotEmpty &&
      _apiKeyCtrl.text.trim().isNotEmpty;

  Future<void> _applyBase64(String raw) async {
    final parsed = BotApiBase64.parse(raw);
    if (parsed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的配置码')),
      );
      return;
    }
    setState(() {
      _streamUrlCtrl.text = parsed.streamUrl;
      _apiSecretCtrl.text = parsed.apiSecret;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板为空')),
      );
      return;
    }
    await _applyBase64(text);
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || result.isEmpty) return;
    await _applyBase64(result);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final cfg = AppConfig(
      botApiStreamUrl: _streamUrlCtrl.text.trim(),
      botApiSecret: _apiSecretCtrl.text.trim(),
      asrTtsApiKey: _apiKeyCtrl.text.trim(),
      ttsVoice: _voice,
      ttsEnabled: _ttsEnabled,
    );
    await widget.settingsService.save(cfg);
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.isFirstLaunch) {
      // SettingsService.notifyListeners will rebuild BellaApp into ChatScreen.
      return;
    }
    Navigator.of(context).pop();
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888888),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isFirstLaunch,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F5FA),
        appBar: AppBar(
          title: const Text('设置'),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            _sectionTitle('Bot-API'),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Stream URL', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
                  TextField(
                    controller: _streamUrlCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 15),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  const Text('API Secret', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
                  TextField(
                    controller: _apiSecretCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 15),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: const Text('粘贴 Base64'),
                          onPressed: _pasteFromClipboard,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          label: const Text('扫描二维码'),
                          onPressed: _scanQr,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _sectionTitle('ASR / TTS API Key'),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('API Key', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 15),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            _sectionTitle('TTS 音色'),
            Container(
              color: Colors.white,
              child: Column(
                children: ttsVoices.entries.map((e) {
                  final selected = e.value == _voice;
                  return RadioListTile<String>(
                    value: e.value,
                    groupValue: _voice,
                    title: Text(e.key),
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      if (v != null) setState(() => _voice = v);
                    },
                  );
                }).toList(),
              ),
            ),
            _sectionTitle('TTS 播放开关'),
            Container(
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('收到回复时自动播放语音'),
                value: _ttsEnabled,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _ttsEnabled = v),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton(
              onPressed: _canSave && !_saving ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('保存'),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyzer**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: no errors. If `AppColors.primary` or `AppColors.primaryLight` aren't exported, check `lib/theme.dart` and adjust import/usage.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: add SettingsScreen with base64 paste, QR scan, voice picker"
```

---

## Task 7: Wire up `main.dart` to `SettingsService` and rebuild services on change

**Files:**
- Modify: `lib/main.dart` (full rewrite of the file's logic)

- [ ] **Step 1: Replace `main.dart`**

Replace entire content of `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'theme.dart';
import 'models/app_config.dart';
import 'services/llm_service.dart';
import 'services/asr_service.dart';
import 'services/tts_service.dart';
import 'services/oss_service.dart';
import 'services/settings_service.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.load();
  runApp(BellaApp(settings: settings));
}

class BellaApp extends StatefulWidget {
  final SettingsService settings;
  const BellaApp({required this.settings, super.key});

  @override
  State<BellaApp> createState() => _BellaAppState();
}

class _BellaAppState extends State<BellaApp> {
  late LlmService _llmService;
  late AsrService _asrService;
  late TtsService _ttsService;
  late OssService _ossService;

  @override
  void initState() {
    super.initState();
    _buildServices(widget.settings.config);
    widget.settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _disposeServices();
    super.dispose();
  }

  void _buildServices(AppConfig? cfg) {
    _llmService = LlmService(
      config: LlmConfig(
        streamUrl: cfg?.botApiStreamUrl ?? '',
        apiSecret: cfg?.botApiSecret ?? '',
      ),
    );
    _asrService = AsrService(apiKey: cfg?.asrTtsApiKey ?? '');
    _ttsService = TtsService(
      apiKey: cfg?.asrTtsApiKey ?? '',
      voice: cfg?.ttsVoice ?? 'longyumi_v2',
    );
    _ossService = OssService(apiKey: cfg?.asrTtsApiKey ?? '');
  }

  void _disposeServices() {
    _llmService.dispose();
  }

  void _onSettingsChanged() {
    _disposeServices();
    _buildServices(widget.settings.config);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.settings.config;
    final showSettings = cfg == null || !cfg.isComplete;

    return MaterialApp(
      title: '糖小豆',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: showSettings
          ? SettingsScreen(
              settingsService: widget.settings,
              isFirstLaunch: true,
            )
          : ChatScreen(
              llmService: _llmService,
              asrService: _asrService,
              ttsService: _ttsService,
              ossService: _ossService,
              settingsService: widget.settings,
            ),
    );
  }
}
```

- [ ] **Step 2: Verify analyzer**

Run: `flutter analyze lib/main.dart`
Expected: errors about missing `settingsService` parameter on `ChatScreen` — that's expected, will be fixed in Task 8.

- [ ] **Step 3: Do not commit yet — Task 8 will modify ChatScreen in the same commit.**

---

## Task 8: Update `ChatScreen` — remove voice picker, add settings gear, route voice/tts persistence through `SettingsService`

**Files:**
- Modify: `lib/screens/chat_screen.dart:20-36` (add `settingsService` field)
- Modify: `lib/screens/chat_screen.dart:80` (remove `_loadVoiceConfig()`)
- Modify: `lib/screens/chat_screen.dart:116-141` (remove `_loadVoiceConfig` and `_saveVoiceConfig` methods)
- Modify: `lib/screens/chat_screen.dart:397-430` (remove `_showVoicePicker`)
- Modify: `lib/screens/chat_screen.dart:519-548` (replace tune icon with gear; update volume toggle to persist via SettingsService)
- Modify: `lib/screens/chat_screen.dart:49` (`_ttsEnabled` initial value comes from settings)

- [ ] **Step 1: Add `settingsService` field and update `_ttsEnabled` initial value**

In `lib/screens/chat_screen.dart`, change the `ChatScreen` widget constructor (around line 20-36) to accept `settingsService`:

```dart
class ChatScreen extends StatefulWidget {
  final LlmService llmService;
  final AsrService asrService;
  final TtsService ttsService;
  final OssService ossService;
  final SettingsService settingsService;

  const ChatScreen({
    required this.llmService,
    required this.asrService,
    required this.ttsService,
    required this.ossService,
    required this.settingsService,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
```

Add the import at the top:

```dart
import '../services/settings_service.dart';
import '../models/app_config.dart';
import '../screens/settings_screen.dart';
```

Change `_ttsEnabled` initialization (line 49) to read from settings:

```dart
bool _ttsEnabled = true;
```

→ In `initState`, set `_ttsEnabled` from the settings config before `_loadMessages()`:

```dart
@override
void initState() {
  super.initState();
  _ttsEnabled = widget.settingsService.config?.ttsEnabled ?? true;
  _ttsPlayer = TtsPlayer(ttsService: widget.ttsService, audioPlayer: _audioPlayer, onStateChanged: () {
    if (mounted) setState(() {});
  });
  _loadMessages().then((_) {
    if (_messages.isEmpty) {
      setState(() {
        _messages.add(Message(
          role: MessageRole.ai,
          content: '你好呀！我是糖小豆~ 今天过得怎么样？',
        ));
      });
    }
    _scrollToBottom();
  });
  _scrollController.addListener(_onScroll);
}
```

(removing the `_loadVoiceConfig()` call line)

- [ ] **Step 2: Remove `_loadVoiceConfig` and `_saveVoiceConfig` methods**

Delete the entire `_loadVoiceConfig` method (lines 116-133) and `_saveVoiceConfig` method (lines 135-141).

- [ ] **Step 3: Remove `_showVoicePicker` method**

Delete the entire `_showVoicePicker` method (lines 397-430).

- [ ] **Step 4: Replace AppBar actions — remove tune icon, add settings gear; volume toggle persists via SettingsService**

Find the `actions:` list in `build()` (lines 519-548). Replace the entire `actions:` array with:

```dart
        actions: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final wasPlaying =
                  _ttsPlayer.isPlaying || _ttsPlayer.isAutoPlaying;
              if (wasPlaying) {
                _ttsPlayer.stop();
              }
              final cfg = widget.settingsService.config;
              if (cfg == null) return;
              final newCfg = cfg.copyWith(ttsEnabled: !_ttsEnabled);
              widget.settingsService.save(newCfg);
              setState(() => _ttsEnabled = !_ttsEnabled);
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(
                _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                size: 24,
                color: _ttsEnabled ? AppColors.primaryLight : const Color(0xFFBDBDBD),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    settingsService: widget.settingsService,
                  ),
                ),
              );
            },
            child: const Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(Icons.settings, size: 24, color: AppColors.primaryLight),
            ),
          ),
        ],
```

**Important caveat:** calling `widget.settingsService.save(newCfg)` will trigger `_onSettingsChanged` in `_BellaAppState`, which disposes the current `_ttsService` and rebuilds. The current `ChatScreen` widget instance is also rebuilt with a new `ttsService` reference. The state survives because the widget type/key didn't change. However, `_ttsEnabled` is also stored locally — the `setState` after `save` updates it locally so the icon reflects the change immediately without waiting for the rebuild.

There's a subtle race: `save` triggers async notifyListeners → `_BellaAppState.setState` → ChatScreen rebuild with new services → `widget.ttsService` is now a fresh instance. The local `_ttsEnabled` we just `setState`'d is still valid in this State object. Good.

- [ ] **Step 5: Verify analyzer**

Run: `flutter analyze lib/`
Expected: no errors. Resolve any leftover references to removed methods (e.g., `_showVoicePicker`, `_saveVoiceConfig`).

- [ ] **Step 6: Run all tests**

Run: `flutter test`
Expected: all tests PASS (existing + new AppConfig + SettingsService tests).

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart lib/screens/chat_screen.dart
git commit -m "feat: wire SettingsService into main + ChatScreen, add settings gear"
```

---

## Task 9: Manual end-to-end verification on device

The user confirmed phone (Android) is connected. Run the app and verify each scenario. Capture issues and fix before declaring done.

- [ ] **Step 1: Build and install**

Run: `flutter run`
Expected: app installs and launches on the connected device.

- [ ] **Step 2: First-launch forced setup (cold start)**

Clear app data first (so storage is empty): `adb shell pm clear <package_id>` (package id from `android/app/build.gradle` `applicationId`, typically `com.example.bella`).

Then `flutter run` again.
Expected: app opens directly to SettingsScreen; back button does NOT exit (PopScope with `canPop: false`).

- [ ] **Step 3: Paste base64 → fields auto-fill**

Tap "粘贴 Base64". First copy this to clipboard on device:
```
eyJhZ2VudElkIjoiZGVwdC10b2tlbiIsImFwaVNlY3JldCI6Ijc4NDljYzRlZjAzYTM1MmNlMzY3MDNmZmEyYmZjMzI5NTk1YjQ3OGYzMTRmZjYyM2FlM2U1MjlhZGI0MjY3OTEiLCJzdHJlYW1VcmwiOiJodHRwczovL21vbHRib3QtMDAxNGM2MmI3Yzc5NDdjMy5zb3BobmV0LmNvbS9ib3QtYXBpL3YyL2RlcHQtdG9rZW4vY2hhdC1zdHJlYW0ifQ==
```
Then tap "粘贴 Base64".
Expected: Stream URL and API Secret fields populate. Save button becomes enabled (once API Key is also filled).

- [ ] **Step 4: Scan QR code (if QR available)**

Generate a QR from the same base64 string (any online QR generator). Tap "扫描二维码". Grant camera permission. Point at QR.
Expected: scanner closes, fields populate.

- [ ] **Step 5: Invalid base64 → SnackBar**

Tap "粘贴 Base64" with garbage in clipboard (e.g., "hello").
Expected: SnackBar "无效的配置码"; fields unchanged.

- [ ] **Step 6: Fill API Key, pick voice, save**

Type the existing apiKey `WGT8fpUL1g0kJkyZ-sdKGVHHHd_oPmfaPCCg06-I0-6GMzFyAiOVlKY6ZbnA6o8nPV97c-quDei6Hzh-7Pq6qw` into ASR/TTS API Key field. Pick a voice. Tap 保存.
Expected: app transitions to ChatScreen (because `BellaApp` rebuilds with complete config).

- [ ] **Step 7: Restart app — config persists**

Stop the app. `flutter run` again.
Expected: app opens directly to ChatScreen (config loaded from secure storage). No setup screen.

- [ ] **Step 8: Chat works end-to-end**

Send a text message. Verify:
- Bot-API reply streams into a bubble.
- TTS plays automatically (if enabled).
- Long-press a bubble, copy works.

- [ ] **Step 9: Voice input works**

Press-and-hold voice button, speak, release.
Expected: ASR returns recognized text; gets sent to bot.

- [ ] **Step 10: Open settings via gear, change voice, save → TTS uses new voice**

Tap gear icon. Change voice. Save. Trigger a TTS play (tap speaker icon on an AI bubble or send a new message).
Expected: TTS plays in the newly selected voice.

- [ ] **Step 11: TTS toggle persists**

Tap volume icon to mute. Restart app. Verify volume icon shows muted on startup.

- [ ] **Step 12: Capture any issues**

If anything fails, write down the symptom and root-cause before fixing. Do NOT declare done until all scenarios pass.

- [ ] **Step 13: Final commit (if any fix-ups needed)**

```bash
git add -A
git commit -m "fix: address issues found during settings e2e verification"
```

(Skip if no fix-ups needed.)

---

## Self-Review

**1. Spec coverage:**
- §1 数据模型 → Task 2 (AppConfig with 5 fields including ttsEnabled).
- §2 架构与组件 → Tasks 2, 3, 4, 7 (SettingsService, LlmConfig refactor, BellaApp stateful).
- §3 SettingsScreen UI → Task 6 (3 sections, paste/scan, voice radio list, save button). Plus Task 5 (QrScanScreen).
- §4 数据流与错误处理 → Task 7 (hot-swap on save), Task 6 (invalid base64 → SnackBar). Forced first-launch → Task 7 `showSettings` logic + Task 8 PopScope.
- §5 测试 → Tasks 2 and 3 (AppConfig + SettingsService unit tests with secure_storage mock). Manual e2e → Task 9.
- Entry point (gear icon) → Task 8 Step 4.
- Remove existing tune/voice picker → Task 8 Steps 2-4.

**2. Placeholder scan:** No TBD/TODO/ellipsis. All code blocks complete.

**3. Type consistency:**
- `AppConfig` fields: `botApiStreamUrl`, `botApiSecret`, `asrTtsApiKey`, `ttsVoice`, `ttsEnabled` — consistent in Task 2, 3, 6, 7, 8.
- `AppConfig.copyWith` used in Task 8 Step 4 — defined in Task 2 Step 3. ✓
- `AppConfig.defaults()` used in Task 6 Step 1 — defined in Task 2 Step 3. ✓
- `BotApiBase64.parse` returns nullable `BotApiBase64Result` with `streamUrl` + `apiSecret` — used consistently Task 2 test + Task 6 `_applyBase64`. ✓
- `SettingsService.config` getter — used in Task 6, 7, 8. ✓
- `SettingsService.save(AppConfig)` — used in Task 6, 8. ✓
- `ChatScreen.settingsService` parameter — added in Task 8 Step 1, used by Task 7. ✓
- `LlmConfig(streamUrl, apiSecret)` — Task 4 defines, Task 7 uses. ✓

One concern: Task 7 Step 2 expects analyzer errors because Task 8 hasn't run yet. That's by design (the two tasks are paired) — the plan instructs not to commit until Task 8 is done. Executing agent should follow this ordering.

Another: Task 8 Step 4 — `widget.settingsService.save(newCfg)` triggers `notifyListeners` synchronously, which calls `_BellaAppState._onSettingsChanged`. That method disposes `_ttsService` — but `ChatScreen` may still be holding the old reference mid-build. Mitigation: this is called from a tap handler, not during build, so the rebuild happens after the current frame. If problems arise during Task 9 Step 11, defer the save with `WidgetsBinding.instance.addPostFrameCallback`.
