import 'package:flutter/material.dart';
import 'theme.dart';
import 'services/llm_service.dart';
import 'services/asr_service.dart';
import 'services/tts_service.dart';
import 'screens/chat_screen.dart';

const _llmUrl = 'https://moltbot-0014c62b7c7947c3.sophnet.com';
const _llmAccountId = 'parent-toddler';
const _llmSecret = 'oz8hIK-JMuNzIajz5KE50MI3XqgtT_5J';
const _apiKey = 'WGT8fpUL1g0kJkyZ-sdKGVHHHd_oPmfaPCCg06-I0-6GMzFyAiOVlKY6ZbnA6o8nPV97c-quDei6Hzh-7Pq6qw';

void main() {
  runApp(const BellaApp());
}

class BellaApp extends StatelessWidget {
  const BellaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final llmService = LlmService(
      config: LlmConfig(
        baseUrl: _llmUrl,
        accountId: _llmAccountId,
        apiSecret: _llmSecret,
      ),
    );

    return MaterialApp(
      title: '豆豆',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: ChatScreen(
        llmService: llmService,
        asrService: AsrService(apiKey: _apiKey),
        ttsService: TtsService(apiKey: _apiKey, voice: 'longanwen'),
      ),
    );
  }
}
