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
  runApp(TangxiaodouApp(settings: settings));
}

class TangxiaodouApp extends StatefulWidget {
  final SettingsService settings;
  const TangxiaodouApp({required this.settings, super.key});

  @override
  State<TangxiaodouApp> createState() => _TangxiaodouAppState();
}

class _TangxiaodouAppState extends State<TangxiaodouApp> {
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
