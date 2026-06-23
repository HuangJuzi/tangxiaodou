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
  late final TextEditingController _apiKeyCtrl;
  late String _voice;
  late bool _ttsEnabled;
  bool _saving = false;
  bool _apiKeyObscured = true;
  String? _botApiBase64;

  @override
  void initState() {
    super.initState();
    final cfg = widget.settingsService.config;
    _apiKeyCtrl = TextEditingController(text: cfg?.asrTtsApiKey ?? '');
    _voice = cfg?.ttsVoice ?? 'longyumi_v2';
    _ttsEnabled = cfg?.ttsEnabled ?? true;
    // We don't reverse the saved config back to a base64 string; the masked
    // display reverts to '—' on settings re-open. User re-pastes/re-scans to
    // confirm intent before re-saving.
    _botApiBase64 = null;
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _botApiBase64 != null &&
      _apiKeyCtrl.text.trim().isNotEmpty &&
      !_saving;

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
    _applyBase64(text);
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || result.isEmpty) return;
    if (!mounted) return;
    _applyBase64(result);
  }

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
            _sectionTitle('TTS 音色'),
            Container(
              color: Colors.white,
              child: Column(
                children: ttsVoices.entries.map((e) {
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
