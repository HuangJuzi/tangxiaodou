# Settings UI 微调 + 保存验证 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict Bot-API input to paste/QR only (mask display as `first5***last5` of the raw base64), add a press-and-hold eye button to the API Key field, and on save run a parallel Bot-API + TTS test then a serial ASR test (using TTS mp3 output) — only persist and navigate when all three pass.

**Architecture:** SettingsScreen holds the raw base64 string in state; UI replaces the Bot-API TextFields with a masked display widget. On save, build an AppConfig from the parsed base64 + API key + voice, run `_testBotApi` + `_testTts` in `Future.wait`, then `_testAsr(ttsBytes)` if TTS passed. Each test uses a temporary service instance (not main.dart's). On failure, stay on the page and show which checks failed.

**Tech Stack:** Flutter, existing `LlmService`/`TtsService`/`AsrService`/`BotApiBase64`, no new deps.

---

## File Structure

| File | Responsibility | Status |
|---|---|---|
| `lib/models/app_config.dart` | Add `maskBase64` top-level function | MODIFY |
| `test/app_config_test.dart` | Add `maskBase64` tests | MODIFY |
| `lib/screens/settings_screen.dart` | Remove TextFields in Bot-API section, show masked base64; remove "API Key" title; add eye button; refactor `_save()` to run verification | MODIFY |
| `lib/screens/qr_scan_screen.dart` | No change | — |

---

## Task 1: Add `maskBase64` helper + tests

**Files:**
- Modify: `lib/models/app_config.dart`
- Modify: `test/app_config_test.dart`

- [ ] **Step 1: Add failing tests for `maskBase64`**

Open `test/app_config_test.dart`. Find the existing `group('fromBase64', ...)` block (search for `group('fromBase64'` in the file). Add this new top-level group at the end of `main()` (inside the outer `group('AppConfig', ...)` is fine, but it must be a sibling of `fromBase64`, not nested):

```dart
    group('maskBase64', () {
      test('shows first5 + *** + last5 for typical-length input', () {
        // 16-char string: '1234567890abcde' has length 15; use 16 for clarity
        expect(maskBase64('1234567890abcdef'), '12345***bcdef');
      });

      test('handles exactly 13-char input', () {
        expect(maskBase64('1234567890abc'), '12345***0abc');
      });

      test('returns *** for input shorter than 14 chars (degenerate)', () {
        expect(maskBase64('1234567890ab'), '***');
        expect(maskBase64(''), '***');
      });
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/app_config_test.dart`
Expected: FAIL with "Undefined function: maskBase64" or similar.

- [ ] **Step 3: Implement `maskBase64`**

Open `lib/models/app_config.dart`. After the closing `}` of the `BotApiBase64` class (at the very end of the file), add:

```dart

/// Masks a base64 string as `first5***last5` for display.
/// Returns `'***'` for input shorter than 14 chars (where masking loses meaning).
String maskBase64(String raw) {
  if (raw.length < 14) return '***';
  return '${raw.substring(0, 5)}***${raw.substring(raw.length - 5)}';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/app_config_test.dart`
Expected: all tests pass (existing 11 + new 3 = 14).

- [ ] **Step 5: Verify analyzer**

Run: `flutter analyze lib/models/app_config.dart test/app_config_test.dart`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/models/app_config.dart test/app_config_test.dart
git commit -m "feat: add maskBase64 helper for credential display"
```

---

## Task 2: Rewrite SettingsScreen — Bot-API masked display + API Key eye button

**Files:**
- Modify: `lib/screens/settings_screen.dart` (full rewrite of state + Bot-API + API Key sections)

This task only changes the UI; the verification flow comes in Task 3.

- [ ] **Step 1: Update imports**

Open `lib/screens/settings_screen.dart`. Replace the existing import block (lines 1-7):

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart' show ttsVoices;
import '../theme.dart';
import 'qr_scan_screen.dart';
```

Same imports, no change required here.

- [ ] **Step 2: Replace state fields**

Find the state fields block (lines 24-29):

```dart
  late final TextEditingController _streamUrlCtrl;
  late final TextEditingController _apiSecretCtrl;
  late final TextEditingController _apiKeyCtrl;
  late String _voice;
  late bool _ttsEnabled;
  bool _saving = false;
```

Replace with:

```dart
  late final TextEditingController _apiKeyCtrl;
  late String _voice;
  late bool _ttsEnabled;
  bool _saving = false;
  bool _apiKeyObscured = true;
  String? _botApiBase64;
```

- [ ] **Step 3: Update `initState`**

Find `initState` (lines 31-40). Replace with:

```dart
  @override
  void initState() {
    super.initState();
    final cfg = widget.settingsService.config;
    _apiKeyCtrl = TextEditingController(text: cfg?.asrTtsApiKey ?? '');
    _voice = cfg?.ttsVoice ?? 'longyumi_v2';
    _ttsEnabled = cfg?.ttsEnabled ?? true;
    // If config already saved, recover the raw base64 from streamUrl + apiSecret
    // by re-encoding. Settings doesn't store the original base64; show empty until user re-pastes.
    _botApiBase64 = null;
  }
```

(Note: we don't try to reverse the saved config back to a base64 string. The masked display will show `—` on settings re-open; user re-pastes/re-scans to verify. This matches the design: the user opens settings to *change* credentials.)

- [ ] **Step 4: Update `dispose`**

Find `dispose` (lines 42-48). Replace with:

```dart
  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }
```

- [ ] **Step 5: Update `_canSave`**

Find `_canSave` (lines 50-53). Replace with:

```dart
  bool get _canSave =>
      _botApiBase64 != null &&
      _apiKeyCtrl.text.trim().isNotEmpty &&
      !_saving;
```

- [ ] **Step 6: Update `_applyBase64`**

Find `_applyBase64` (lines 55-68). Replace with:

```dart
  void _applyBase64(String raw) {
    final parsed = BotApiBase64.parse(raw);
    if (parsed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的配置码')),
      );
      return;
    }
    setState(() {
      _botApiBase64 = raw;
    });
  }
```

- [ ] **Step 7: Verify analyzer**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: errors about removed `_streamUrlCtrl`/`_apiSecretCtrl` references in `build()` — these will be fixed in Step 8.

- [ ] **Step 8: Replace Bot-API section in `build()`**

Find the Bot-API section in `build()` (lines 141-194). It looks like:

```dart
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
                    ...
                  ),
                  const SizedBox(height: 8),
                  const Text('API Secret', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
                  TextField(
                    controller: _apiSecretCtrl,
                    obscureText: true,
                    ...
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
```

Replace with:

```dart
            _sectionTitle('Bot-API'),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _botApiBase64 == null
                          ? '—'
                          : maskBase64(_botApiBase64!),
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF666666),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: const Text('粘贴凭证'),
                          onPressed: _saving ? null : _pasteFromClipboard,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          label: const Text('扫描二维码'),
                          onPressed: _saving ? null : _scanQr,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
```

- [ ] **Step 9: Replace API Key section in `build()`**

Find the API Key section (lines 195-216). Replace with (removes "API Key" small title, adds eye button in suffix):

```dart
            _sectionTitle('ASR / TTS API Key'),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: TextField(
                controller: _apiKeyCtrl,
                obscureText: _apiKeyObscured,
                enabled: !_saving,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  suffixIcon: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => setState(() => _apiKeyObscured = false),
                    onTapUp: (_) => setState(() => _apiKeyObscured = true),
                    onTapCancel: () => setState(() => _apiKeyObscured = true),
                    child: Icon(
                      _apiKeyObscured ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: const Color(0xFF888888),
                    ),
                  ),
                ),
                style: const TextStyle(fontSize: 15),
                onChanged: (_) => setState(() {}),
              ),
            ),
```

- [ ] **Step 10: Update `_save()` to construct AppConfig from `_botApiBase64`**

Find `_save()` (lines 92-112). Replace with (this is the temporary stub before Task 3 wires in verification — keeps the simple save path so the build compiles):

```dart
  Future<void> _save() async {
    final parsed = BotApiBase64.parse(_botApiBase64!);
    if (parsed == null) {
      // Defensive: _canSave already guards this.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的配置码')),
      );
      return;
    }
    setState(() => _saving = true);
    final cfg = AppConfig(
      botApiStreamUrl: parsed.streamUrl,
      botApiSecret: parsed.apiSecret,
      asrTtsApiKey: _apiKeyCtrl.text.trim(),
      ttsVoice: _voice,
      ttsEnabled: _ttsEnabled,
    );
    try {
      await widget.settingsService.save(cfg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (widget.isFirstLaunch) {
      // SettingsService.notifyListeners will rebuild BellaApp into ChatScreen.
      return;
    }
    Navigator.of(context).pop();
  }
```

- [ ] **Step 11: Verify analyzer + existing tests**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: no errors.

Run: `flutter test`
Expected: all existing tests pass (14 from Task 1 + 30 from prior = 30 total, since Task 1 only added 3 to the existing app_config_test file).

(Note: `widget_test.dart` still passes — it doesn't open SettingsScreen.)

- [ ] **Step 12: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: SettingsScreen Bot-API masked display + API Key eye button"
```

---

## Task 3: Add verification flow on save

**Files:**
- Modify: `lib/screens/settings_screen.dart`

This task adds the three `_test*` methods and rewrites `_save()` to orchestrate them.

- [ ] **Step 1: Add imports**

In `lib/screens/settings_screen.dart`, after the existing imports, add:

```dart
import '../services/llm_service.dart';
import '../services/asr_service.dart';
```

(`tts_service.dart` is already imported via `show ttsVoices` — but we need the full class. Change line 5 from `import '../services/tts_service.dart' show ttsVoices;` to:)

```dart
import '../services/tts_service.dart';
```

- [ ] **Step 2: Add `_testBotApi`, `_testTts`, `_testAsr` methods**

Add these three private methods to `_SettingsScreenState` (place them right before `Widget _sectionTitle(...)`):

```dart
  /// Returns true if Bot-API responds with at least one non-empty token.
  /// Sends "/hardstop" after the first token to cancel the stream.
  Future<bool> _testBotApi(AppConfig cfg) async {
    final llm = LlmService(
      config: LlmConfig(
        streamUrl: cfg.botApiStreamUrl,
        apiSecret: cfg.botApiSecret,
      ),
    );
    try {
      final completer = Completer<bool>();
      final sub = llm.chat('settings-verify', '你好').listen(
        (token) {
          if (token.isNotEmpty && !completer.isCompleted) {
            completer.complete(true);
          }
        },
        onError: (Object _) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: true,
      );
      final result = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
      await sub.cancel();
      // Send /hardstop to cancel the underlying stream
      try {
        await llm.chat('settings-verify', '/hardstop').first;
      } catch (_) {
        // best-effort; ignore errors
      }
      llm.dispose();
      return result;
    } catch (_) {
      try {
        llm.dispose();
      } catch (_) {}
      return false;
    }
  }

  /// Returns non-empty MP3 bytes on success, null on failure.
  Future<List<int>?> _testTts(AppConfig cfg) async {
    final tts = TtsService(apiKey: cfg.asrTtsApiKey, voice: cfg.ttsVoice);
    try {
      final bytes = await tts.synthesize('你好').timeout(
        const Duration(seconds: 15),
        onTimeout: () => <int>[],
      );
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if ASR returns a non-empty string for the given MP3 bytes.
  Future<bool> _testAsr(AppConfig cfg, List<int> mp3Bytes) async {
    final asr = AsrService(apiKey: cfg.asrTtsApiKey);
    try {
      final text = await asr
          .recognize(Stream.fromIterable([mp3Bytes]), format: 'mp3')
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => '',
          );
      return text.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 3: Add `dart:async` import for `Completer`**

At the top of the file, add:

```dart
import 'dart:async';
```

- [ ] **Step 4: Rewrite `_save()` to run verification**

Find the `_save()` method (the one you wrote in Task 2 Step 10). Replace the entire method body with:

```dart
  Future<void> _save() async {
    final parsed = BotApiBase64.parse(_botApiBase64!);
    if (parsed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的配置码')),
      );
      return;
    }
    final cfg = AppConfig(
      botApiStreamUrl: parsed.streamUrl,
      botApiSecret: parsed.apiSecret,
      asrTtsApiKey: _apiKeyCtrl.text.trim(),
      ttsVoice: _voice,
      ttsEnabled: _ttsEnabled,
    );

    setState(() {
      _saving = true;
      _verifyError = null;
    });

    final failures = <String>[];

    // Run Bot-API and TTS in parallel
    final results = await Future.wait([
      _testBotApi(cfg),
      _testTts(cfg),
    ]);
    final botApiOk = results[0];
    final ttsBytes = results[1];

    if (!botApiOk) failures.add('Bot-API');
    if (ttsBytes == null) {
      failures.add('TTS');
    } else {
      final asrOk = await _testAsr(cfg, ttsBytes);
      if (!asrOk) failures.add('ASR');
    }

    if (!mounted) return;

    if (failures.isEmpty) {
      try {
        await widget.settingsService.save(cfg);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      if (!mounted) return;
      if (widget.isFirstLaunch) {
        // SettingsService.notifyListeners will rebuild BellaApp into ChatScreen.
        return;
      }
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _verifyError = '${failures.join('、')} 不可用';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接口验证失败：$_verifyError')),
      );
    }
  }
```

- [ ] **Step 5: Add `_verifyError` state field**

In the state fields block (the one you wrote in Task 2 Step 2), add `_verifyError`:

```dart
  late final TextEditingController _apiKeyCtrl;
  late String _voice;
  late bool _ttsEnabled;
  bool _saving = false;
  bool _apiKeyObscured = true;
  String? _botApiBase64;
  String? _verifyError;
```

- [ ] **Step 6: Show `_verifyError` above the save button**

Find the `bottomNavigationBar` block in `build()` (around lines 246-264 in the current file). It looks like:

```dart
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton(
              onPressed: _canSave ? _save : null,
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
```

Replace with (adds error text above the button + changes button label during verification):

```dart
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_verifyError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '接口验证失败：$_verifyError',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _saving
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 10),
                            Text('正在验证接口，请稍后...'),
                          ],
                        )
                      : const Text('保存'),
                ),
              ],
            ),
          ),
        ),
```

- [ ] **Step 7: Verify analyzer**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: no errors.

- [ ] **Step 8: Verify existing tests still pass**

Run: `flutter test`
Expected: all tests pass (no new tests for the verification flow — it requires network, manually verified in Task 4).

- [ ] **Step 9: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: save-time verification of Bot-API/TTS/ASR"
```

---

## Task 4: Manual end-to-end verification on device

Phone is connected (vivo V2502A). Build, install, run through the scenarios.

- [ ] **Step 1: Build and install**

Run: `flutter run -d 10AFAC1N5Q002N1 --release`
Expected: app installs and launches on the connected device.

- [ ] **Step 2: Clear app data**

Run: `adb -s 10AFAC1N5Q002N1 shell pm clear com.bella.bella`
Then restart the app: `adb -s 10AFAC1N5Q002N1 shell am start -n com.bella.bella/.MainActivity`
Expected: app opens directly to SettingsScreen (first-launch flow).

- [ ] **Step 3: Paste credential and verify Bot-API section shows masked**

Tap "粘贴凭证". With clipboard containing the valid base64:
```
eyJhZ2VudElkIjoiZGVwdC10b2tlbiIsImFwaVNlY3JldCI6Ijc4NDljYzRlZjAzYTM1MmNlMzY3MDNmZmEyYmZjMzI5NTk1YjQ3OGYzMTRmZjYyM2FlM2U1MjlhZGI0MjY3OTEiLCJzdHJlYW1VcmwiOiJodHRwczovL21vbHRib3QtMDAxNGM2MmI3Yzc5NDdjMy5zb3BobmV0LmNvbS9ib3QtYXBpL3YyL2RlcHQtdG9rZW4vY2hhdC1zdHJlYW0ifQ==
```
Expected: Bot-API section shows `eyJhZ***ifQ==` (or similar first5+***+last5). No TextFields.

- [ ] **Step 4: Verify QR scan still works**

Tap "扫描二维码". Camera permission prompt if needed. Point at a QR generated from the same base64 (e.g., via any online QR generator).
Expected: scanner closes, Bot-API section shows masked base64 (same as paste path).

- [ ] **Step 5: Verify invalid credential shows SnackBar**

Tap "粘贴凭证" with garbage in clipboard (e.g., "hello").
Expected: SnackBar "无效的配置码"; Bot-API section unchanged.

- [ ] **Step 6: Fill API Key, verify eye button**

Tap API Key field, type the existing apiKey: `WGT8fpUL1g0kJkyZ-sdKGVHHHd_oPmfaPCCg06-I0-6GMzFyAiOVlKY6ZbnA6o8nPV97c-quDei6Hzh-7Pq6qw`
Expected: field shows `****` (obscured). Press-and-hold the eye icon → key shows in plaintext. Release → back to `****`.

- [ ] **Step 7: Verify save-time verification flow (happy path)**

Pick a voice, tap "保存".
Expected: button shows spinner + "正在验证接口，请稍后..." for a few seconds. Then app transitions to ChatScreen (all three checks passed).

- [ ] **Step 8: Restart app, verify config persists**

Stop the app, relaunch.
Expected: opens directly to ChatScreen. Settings opened via gear shows masked base64 from saved config — wait, the design says we don't recover raw base64, so the Bot-API section shows `—` until user re-pastes. Verify this is acceptable behavior; if user wants to test changing settings, they re-paste.

(Note: the saved `AppConfig.botApiStreamUrl` and `botApiSecret` are still valid; only the masked *display* reverts to `—`. The "保存" button stays disabled until re-paste because `_canSave` requires `_botApiBase64 != null`. This is by design — user must re-paste to confirm intent before re-saving.)

- [ ] **Step 9: Verify failure path (wrong API key)**

Open settings via gear. Paste credential again. Type a wrong API key (e.g., add `x` at the end of the real key). Tap "保存".
Expected: button shows "正在验证..." briefly, then red text appears above button: "接口验证失败：TTS、ASR 不可用". SnackBar shows same message. User stays on settings page.

- [ ] **Step 10: Verify failure path (wrong Bot-API)**

Open settings. Paste a base64 with streamUrl deliberately broken (e.g., add `x` to the URL in the JSON, re-encode). Tap "保存".
Expected: button shows "正在验证..." then red text "接口验证失败：Bot-API 不可用". User stays on settings page.

(Generating this test base64: use python or any tool to re-encode a modified JSON.)

- [ ] **Step 11: Capture any issues**

If any scenario fails, write down the symptom and root-cause before fixing. Do NOT declare done until all scenarios pass.

If ASR test fails (e.g., `format=mp3` not accepted by Sophnet ASR), the failure message would be "ASR 不可用" even though TTS succeeded. In that case, the spec acknowledged this risk; the fix would be either to use a different format or skip ASR test. Decide with the user before changing.

- [ ] **Step 12: Final commit (if any fix-ups needed)**

```bash
git add -A
git commit -m "fix: address issues found during settings UI/verify e2e"
```

(Skip if no fix-ups needed.)

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| Bot-API only paste/QR, no manual input | Task 2 Step 8 (removes TextFields, keeps two buttons) |
| Masked display `first5***last5` | Task 1 `maskBase64` + Task 2 Step 8 |
| API Key TextField with eye button press-and-hold | Task 2 Step 9 |
| API Key no small title | Task 2 Step 9 (removed `Text('API Key', ...)`) |
| Save-time parallel Bot-API + TTS test | Task 3 Step 4 (`Future.wait`) |
| ASR test after TTS passes, using TTS mp3 | Task 3 Step 4 (`_testAsr(cfg, ttsBytes)`) |
| `/hardstop` after first token | Task 3 Step 2 (`_testBotApi`) |
| ASR uses `format=mp3` | Task 3 Step 2 (`_testAsr`) |
| All-pass → save + navigate | Task 3 Step 4 |
| Failure → stay on page, show which failed | Task 3 Step 4 (`failures` list) |
| Timeouts: Bot-API 15s, TTS 15s, ASR 10s | Task 3 Step 2 |
| "正在验证接口，请稍后..." button text | Task 3 Step 6 |
| Red error text above button | Task 3 Step 6 |
| SnackBar on failure | Task 3 Step 4 |
| Bot-API section buttons disabled during saving | Task 2 Step 8 (`onPressed: _saving ? null : ...`) |

**2. Placeholder scan:** No TBD/TODO/ellipsis. All code blocks complete.

**3. Type consistency:**
- `maskBase64(String raw) → String` — defined in Task 1, used in Task 2 Step 8. ✓
- `_botApiBase64` field type `String?` — Task 2 Step 2, used in Step 6 `_applyBase64`, Step 8 display, Step 10 `_save()`. ✓
- `_apiKeyObscured` field type `bool` — Task 2 Step 2, used in Step 9. ✓
- `_verifyError` field type `String?` — Task 3 Step 5, used in Step 4 `_save()`, Step 6 display. ✓
- `_testBotApi(AppConfig) → Future<bool>` — Task 3 Step 2, called in Step 4. ✓
- `_testTts(AppConfig) → Future<List<int>?>` — Task 3 Step 2, called in Step 4. ✓
- `_testAsr(AppConfig, List<int>) → Future<bool>` — Task 3 Step 2, called in Step 4. ✓
- `BotApiBase64.parse` returns `BotApiBase64Result?` with `.streamUrl` and `.apiSecret` — already exists from prior work; used in Task 2 Step 10 and Task 3 Step 4. ✓
- `LlmConfig(streamUrl, apiSecret)` — defined in prior work; used in Task 3 Step 2. ✓
- `LlmService(config:)` + `.chat(senderId, text)` returning `Stream<String>` + `.dispose()` — already exists; used in Task 3 Step 2. ✓
- `TtsService(apiKey:, voice:)` + `.synthesize(text)` returning `Future<List<int>>` — already exists; used in Task 3 Step 2. ✓
- `AsrService(apiKey:)` + `.recognize(stream, format:)` returning `Future<String>` — already exists; used in Task 3 Step 2. ✓

**One thing to watch:** Task 2 Step 7 expects analyzer errors after Step 6 (because `build()` still references removed controllers). Step 8 then fixes those errors by replacing the Bot-API section. The implementer should run analyzer at Step 7, see the expected errors, then proceed to Step 8. Task 3 doesn't have this transitional broken state because Step 4 replaces an entire method that already compiles.
