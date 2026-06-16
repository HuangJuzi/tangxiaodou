# 豆豆 - AI 陪聊小助手 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 Flutter AI 陪聊 App，支持语音输入、LLM 流式对话、TTS 语音播报，界面简单可爱（紫白色系 + 小鸟形象"豆豆"）。

**Architecture:** Flutter 单页面应用，StatefulWidget + setState 状态管理。lib/ 下按 models/services/widgets/screens 分层。LLM 通过 SSE 流式接入 Bot API，ASR/TTS 通过抽象服务类预留接口。零额外状态管理依赖。

**Tech Stack:** Flutter 3.44.2, Dart 3.12.2, dart:io (HTTP/SSE), record (录音), audioplayers (TTS 播放), permission_handler

**API 协议（来自 bot-api-status.md）:**
- 流式: `POST {BASEURL}/bot-api/v2/{account_id}/chat-stream`，SSE 格式，`data: {"choices":[{"delta":{"content":"..."}}]}` chunks，`data: "[DONE]"` 结束
- 鉴权: `Authorization: Bearer <API Secret>`

---

### Task 1: 初始化 Flutter 项目并添加依赖

**Files:**
- Create: Flutter project scaffold
- Modify: `pubspec.yaml` (add dependencies)
- Modify: `analysis_options.yaml` (relax strictness)
- Create: `assets/` directory for placeholder assets

- [ ] **Step 1: 创建 Flutter 项目**

```bash
cd /mnt/b/workdir/gitlab/Bella && \
export PATH="/mnt/b/flutter/bin:$PATH" && \
flutter create --project-name bella --org com.bella . --platforms android 2>&1 | tail -5
```

Expected: 项目文件生成，无错误。

- [ ] **Step 2: 添加依赖到 pubspec.yaml**

Read `pubspec.yaml`，在 `dependencies:` 下添加：

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^1.2.0
  web_socket_channel: ^3.0.0
  record: ^5.1.0
  audioplayers: ^6.1.0
  permission_handler: ^11.3.0
  uuid: ^4.5.1
  path_provider: ^2.1.0
```

- [ ] **Step 3: 安装依赖**

```bash
cd /mnt/b/workdir/gitlab/Bella && \
export PATH="/mnt/b/flutter/bin:$PATH" && \
flutter pub get 2>&1 | tail -3
```

Expected: 无错误。

- [ ] **Step 4: 放宽 analysis_options.yaml**

Read `analysis_options.yaml`，替换为：

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    avoid_print: false
    use_key_in_widget_constructors: false
    prefer_const_constructors: false
    prefer_const_literals_to_create_immutables: false
```

- [ ] **Step 5: 添加 Android 录音权限**

Read `android/app/src/main/AndroidManifest.xml`，在 `<manifest>` 下 `<application>` 前添加：

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

- [ ] **Step 6: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
chore: init Flutter project with dependencies

Flutter 3.44.2, Android-only. Dependencies: http, record, audioplayers,
permission_handler, uuid.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Message 数据模型

**Files:**
- Create: `lib/models/message.dart`

- [ ] **Step 1: 创建 Message 模型**

```dart
import 'package:uuid/uuid.dart';

enum MessageRole { user, ai }

class Message {
  final String id;
  final MessageRole role;
  String content;
  bool isStreaming;
  final DateTime createdAt;

  Message({
    String? id,
    required this.role,
    required this.content,
    this.isStreaming = false,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add Message model

Message with id, role (user/ai), content, isStreaming flag, createdAt.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 主题配置

**Files:**
- Create: `lib/theme.dart`

- [ ] **Step 1: 创建 theme.dart**

```dart
import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFFAB47BC);
  static const primaryLight = Color(0xFFCE93D8);
  static const primaryLighter = Color(0xFFB39DDB);
  static const primaryBg = Color(0xFFF5F0FA);
  static const aiBubbleBorder = Color(0xFFE1BEE7);
  static const accentGreen = Color(0xFFE8F5E9);
  static const userBubble = Color(0xFFCE93D8);

  AppColors._();
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.primary,
        scaffoldBackgroundColor: AppColors.primaryBg,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      );

  AppTheme._();
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add AppColors and AppTheme

Purple color scheme based on design spec.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Avatar 头像组件

**Files:**
- Create: `lib/widgets/avatar_widget.dart`

- [ ] **Step 1: 创建 avatar_widget.dart**

```dart
import 'package:flutter/material.dart';
import '../theme.dart';

class AvatarWidget extends StatelessWidget {
  final double size;
  final bool isUser;

  const AvatarWidget({this.size = 28, this.isUser = false, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(isUser ? '😊' : '🐤', style: TextStyle(fontSize: size * 0.55)),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add AvatarWidget

Circle avatar with bird emoji for AI, smiley for user.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: TypingDots 跳动动画组件

**Files:**
- Create: `lib/widgets/typing_dots.dart`

- [ ] **Step 1: 创建 typing_dots.dart**

```dart
import 'package:flutter/material.dart';
import '../theme.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _animations = List.generate(3, (i) {
      return Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(i * 0.15, 0.6 + i * 0.15, curve: Curves.easeInOut),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.translate(
              offset: Offset(0, _animations[i].value),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLighter,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add TypingDots animation widget

Three bouncing purple dots indicating AI is streaming.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: ChatBubble 聊天气泡组件

**Files:**
- Create: `lib/widgets/chat_bubble.dart`

- [ ] **Step 1: 创建 chat_bubble.dart**

```dart
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme.dart';
import 'avatar_widget.dart';
import 'typing_dots.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onTtsTap;
  final String? playingMessageId;

  const ChatBubble({
    required this.message,
    this.onTtsTap,
    this.playingMessageId,
    super.key,
  });

  bool get _isPlaying => playingMessageId == message.id;

  @override
  Widget build(BuildContext context) {
    final isAi = message.role == MessageRole.ai;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isAi) ...[
            const AvatarWidget(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isAi ? Colors.white : AppColors.userBubble,
                    border: isAi
                        ? Border.all(color: AppColors.aiBubbleBorder, width: 1.5)
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isAi ? 6 : 20),
                      bottomRight: Radius.circular(isAi ? 20 : 6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: isAi ? 0.06 : 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.content,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: isAi ? const Color(0xFF555555) : Colors.white,
                        ),
                      ),
                      if (isAi && message.isStreaming) ...[
                        const SizedBox(height: 6),
                        const TypingDots(),
                      ],
                    ],
                  ),
                ),
                if (isAi && !message.isStreaming) ...[
                  const SizedBox(height: 4),
                  _TtsButton(isPlaying: _isPlaying, onTap: onTtsTap),
                ],
              ],
            ),
          ),
          if (!isAi) ...[
            const SizedBox(width: 8),
            const AvatarWidget(isUser: true),
          ],
        ],
      ),
    );
  }
}

class _TtsButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback? onTap;

  const _TtsButton({required this.isPlaying, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primaryLight, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: isPlaying ? AppColors.primaryLight : null,
        ),
        child: Text(
          isPlaying ? '⏸ 播放中' : '🔊 播放',
          style: TextStyle(
            fontSize: 12,
            color: isPlaying ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add ChatBubble widget

AI bubble: white bg, purple border, left-aligned with avatar and TTS button.
User bubble: purple bg white text, right-aligned. Shows TypingDots when streaming.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: LLM 服务（Bot API SSE 流式）

**Files:**
- Create: `lib/services/llm_service.dart`

- [ ] **Step 1: 创建 llm_service.dart**

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LlmConfig {
  final String baseUrl;
  final String accountId;
  final String apiSecret;

  const LlmConfig({
    required this.baseUrl,
    required this.accountId,
    required this.apiSecret,
  });

  String get streamUrl => '$baseUrl/bot-api/v2/$accountId/chat-stream';
}

class LlmService {
  final LlmConfig _config;
  final http.Client _client;

  LlmService({required LlmConfig config, http.Client? client})
      : _config = config,
        _client = client ?? http.Client();

  Stream<String> chat(String senderId, String text) async* {
    final request = http.Request('POST', Uri.parse(_config.streamUrl));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer ${_config.apiSecret}';
    request.body = jsonEncode({'senderId': senderId, 'text': text});

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw HttpException('LLM API error: ${response.statusCode}');
    }

    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;
      if (data.isEmpty) continue;

      try {
        final chunk = jsonDecode(data);
        final choices = chunk['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield content;
        }
      } on FormatException {
        continue;
      }
    }
  }

  void dispose() {
    _client.close();
  }
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add LlmService with Bot API SSE streaming

Parses SSE chunks (data: {...}) extracting choices[0].delta.content.
Auth via Bearer token. Ends on data: "[DONE]".

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: ASR 语音识别服务（Sophnet WebSocket）

**Files:**
- Create: `lib/services/asr_service.dart`

- [ ] **Step 1: 创建 asr_service.dart**

```dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class AsrService {
  final String _apiKey;
  static const _url = 'wss://www.sophnet.com/api/open-apis/projects/easyllms/stream-speech';

  AsrService({required String apiKey}) : _apiKey = apiKey;

  /// Stream audio bytes and receive incremental recognition results.
  /// Send [audioBytes] chunks, receive text updates.
  /// Returns the final recognized text.
  Future<String> recognize(Stream<List<int>> audioStream, {String format = 'pcm', int sampleRate = 16000}) async {
    final wsUrl = Uri.parse('$_url?apikey=$_apiKey&format=$format&sample_rate=$sampleRate&heartbeat=true');
    final channel = WebSocketChannel.connect(wsUrl);

    final completer = Completer<String>();
    final buffer = StringBuffer();

    channel.stream.listen(
      (data) {
        if (data is String) {
          try {
            final json = jsonDecode(data);
            if (json['status'] == 'ok') return; // connection ok
            final text = json['text'] as String?;
            if (text != null) {
              // Track latest full sentence as final result
              if (json['is_sentence_end'] == true) {
                buffer.clear();
                buffer.write(text);
              }
            }
          } on FormatException { /* ignore malformed */ }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.complete(buffer.isNotEmpty ? buffer.toString() : '');
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(buffer.isNotEmpty ? buffer.toString() : '');
        }
      },
      cancelOnError: true,
    );

    // Send audio chunks
    await for (final chunk in audioStream) {
      channel.sink.add(chunk);
    }
    // Signal end of audio
    channel.sink.add('BYE');

    final result = await completer.future;
    await channel.sink.close();
    return result;
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add AsrService with Sophnet WebSocket streaming

Sends audio chunks via WebSocket, receives incremental recognition.
Returns final text when is_sentence_end=true.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: TTS 文字转语音服务（Sophnet REST）

**Files:**
- Create: `lib/services/tts_service.dart`

- [ ] **Step 1: 创建 tts_service.dart**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class TtsService {
  final String _apiKey;
  final String _voice;
  static const _url = 'https://www.sophnet.com/api/open-apis/projects/easyllms/voice/synthesize-audio';

  TtsService({required String apiKey, String voice = 'longjiqi'})
      : _apiKey = apiKey,
        _voice = voice;

  /// Synthesize text and return audio bytes (MP3).
  Future<List<int>> synthesize(String text) async {
    final response = await http.post(
      Uri.parse(_url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'text': [text],
        'synthesis_param': {
          'model': 'cosyvoice-v2',
          'voice': _voice,
          'format': 'MP3_16000HZ_MONO_128KBPS',
          'volume': 80,
          'speechRate': 1.0,
          'pitchRate': 1,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('TTS API error: ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add TtsService with Sophnet REST API

Sends text to Sophnet TTS API, receives MP3 audio bytes.
Default voice: longjiqi (呆萌机器人).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: VoiceInputButton 语音按钮组件

**Files:**
- Create: `lib/widgets/voice_input_button.dart`

- [ ] **Step 1: 创建 voice_input_button.dart**

```dart
import 'package:flutter/material.dart';
import '../theme.dart';

class VoiceInputButton extends StatefulWidget {
  final bool isRecording;
  final bool isProcessing;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;

  const VoiceInputButton({
    required this.isRecording,
    required this.isProcessing,
    required this.onRecordStart,
    required this.onRecordStop,
    super.key,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pulseAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(VoiceInputButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && old.isRecording) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isRecording;
    final label = widget.isProcessing ? '识别中...' : (isActive ? '● 录音中...' : '按住说话');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) {
            return GestureDetector(
              onLongPressStart: (_) => widget.onRecordStart(),
              onLongPressEnd: (_) => widget.onRecordStop(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Color(0xFFE53935), Color(0xFFEF5350)],
                        )
                      : const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: (isActive
                              ? const Color(0xFFE53935)
                              : AppColors.primary)
                          .withValues(alpha: 0.4 + _pulseAnim.value * 0.15),
                      blurRadius: 24 + _pulseAnim.value * 12,
                      spreadRadius: _pulseAnim.value * 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🎤', style: TextStyle(fontSize: 36)),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isActive ? const Color(0xFFE53935) : AppColors.primary,
          ),
        ),
        if (!isActive && !widget.isProcessing) ...[
          const SizedBox(height: 2),
          const Text(
            '松开发送 · 右下角可打字',
            style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add VoiceInputButton widget

80px purple circle mic button with pulse animation when recording.
Turns red on press, shows status label.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: ChatScreen 聊天主页面

**Files:**
- Create: `lib/screens/chat_screen.dart`

- [ ] **Step 1: 创建 chat_screen.dart**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme.dart';
import '../services/llm_service.dart';
import '../services/asr_service.dart';
import '../services/tts_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/voice_input_button.dart';

class ChatScreen extends StatefulWidget {
  final LlmService llmService;
  final AsrService asrService;
  final TtsService ttsService;

  const ChatScreen({
    required this.llmService,
    required this.asrService,
    required this.ttsService,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  bool _isAiReplying = false;
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  String? _playingMessageId;
  bool _isTextMode = false;

  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _senderId = 'user-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _messages.add(Message(
      role: MessageRole.ai,
      content: '你好呀！我是豆豆~ 今天过得怎么样？',
    ));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    setState(() {
      _messages.add(Message(role: MessageRole.user, content: text));
      _isAiReplying = true;
    });
    _scrollToBottom();

    final aiMessage = Message(role: MessageRole.ai, content: '', isStreaming: true);
    setState(() => _messages.add(aiMessage));
    _scrollToBottom();

    final buffer = StringBuffer();
    try {
      await for (final token in widget.llmService.chat(_senderId, text)) {
        buffer.write(token);
        setState(() {
          aiMessage.content = buffer.toString();
        });
        _scrollToBottom();
      }
    } on HttpException {
      setState(() {
        aiMessage.content = buffer.isEmpty ? '网络断了，请重试' : '${buffer.toString()}...';
      });
    } catch (e) {
      setState(() {
        aiMessage.content = buffer.isEmpty ? '出错了，请重试' : '${buffer.toString()}...';
      });
    } finally {
      setState(() {
        aiMessage.isStreaming = false;
        _isAiReplying = false;
      });
      _scrollToBottom();

      if (aiMessage.content.isNotEmpty && !aiMessage.content.startsWith('网络') && !aiMessage.content.startsWith('出错')) {
        await _playTts(aiMessage);
      }
    }
  }

  Future<void> _playTts(Message message) async {
    setState(() => _playingMessageId = message.id);
    try {
      final audioBytes = await widget.ttsService.synthesize(message.content);
      // TODO: play audioBytes via audioplayers package
    } catch (_) {
      // Silently skip TTS errors
    } finally {
      if (mounted) {
        setState(() => _playingMessageId = null);
      }
    }
  }

  void _onRecordStart() {
    setState(() => _isRecording = true);
    // Recording wired in Task 14
  }

  void _onRecordStop() async {
    setState(() {
      _isRecording = false;
      _isProcessingVoice = true;
    });

    try {
      // Audio bytes from recorder (wired in Task 14)
      final audioBytes = <int>[];
      final text = await widget.asrService.recognize(
        Stream.fromIterable([audioBytes]),
      );
      if (mounted) {
        setState(() => _isProcessingVoice = false);
        if (text.isNotEmpty) {
          await _sendMessage(text);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isProcessingVoice = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没听清，再试一次？')),
        );
      }
    }
  }

  void _onTtsTap(Message message) {
    _playTts(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryLighter, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Row(
          children: [
            AvatarWidget(size: 42),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('豆豆', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                Text('AI 陪聊小助手', style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              itemCount: _messages.length,
              itemBuilder: (_, i) => ChatBubble(
                message: _messages[i],
                onTtsTap: () => _onTtsTap(_messages[i]),
                playingMessageId: _playingMessageId,
              ),
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDE7F6))),
      ),
      child: _isTextMode ? _buildTextInput() : _buildVoiceInput(),
    );
  }

  Widget _buildVoiceInput() {
    return Stack(
      alignment: Alignment.center,
      children: [
        VoiceInputButton(
          isRecording: _isRecording,
          isProcessing: _isProcessingVoice,
          onRecordStart: _onRecordStart,
          onRecordStop: _onRecordStop,
        ),
        Positioned(
          right: 0,
          child: GestureDetector(
            onTap: () => setState(() => _isTextMode = true),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E5F5),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('⌨', style: TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextInput() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _isTextMode = false),
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFF3E5F5),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('🎤', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primaryLight, width: 2),
              borderRadius: BorderRadius.circular(22),
              color: const Color(0xFFFAFAFA),
            ),
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: '说点什么...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              style: const TextStyle(fontSize: 14),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) {
                  _sendMessage(text.trim());
                  _textController.clear();
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            final text = _textController.text.trim();
            if (text.isNotEmpty) {
              _sendMessage(text);
              _textController.clear();
            }
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x4D9C27B0),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text('→', style: TextStyle(color: Colors.white, fontSize: 18)),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add ChatScreen main page

Voice-first chat UI: voice button (default) + text input toggle.
Streaming AI replies, auto TTS, scroll-to-bottom, error handling.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: main.dart 入口 + 组装

**Files:**
- Write: `lib/main.dart` (overwrite generated)

- [ ] **Step 1: 重写 main.dart**

```dart
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
        ttsService: TtsService(apiKey: _apiKey, voice: 'longjiqi'),
      ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: add main.dart entry point

Assembles LlmService (configurable via env vars), StubAsrService, StubTtsService.
Launches ChatScreen with purple theme.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: 构建验证

- [ ] **Step 1: 运行 flutter analyze**

```bash
cd /mnt/b/workdir/gitlab/Bella && \
export PATH="/mnt/b/flutter/bin:$PATH" && \
flutter analyze 2>&1
```

Expected: 无 error（warning 可接受）。

- [ ] **Step 2: 运行 flutter build apk --debug**

```bash
cd /mnt/b/workdir/gitlab/Bella && \
export PATH="/mnt/b/flutter/bin:$PATH" && \
flutter build apk --debug 2>&1 | tail -5
```

Expected: 构建成功，输出 APK 路径。

- [ ] **Step 3: 提交（如有修改）**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git diff --cached --quiet || git commit -m "$(cat <<'EOF'
chore: fix analyze warnings and build issues

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: 对接真实录音功能（record + ASR + TTS 播放）

**Files:**
- Modify: `lib/screens/chat_screen.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: 添加 Android 存储权限（record package 需要）**

在 `AndroidManifest.xml` 的 `<manifest>` 下添加：

```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

- [ ] **Step 2: 更新 ChatScreen 集成真实录音 + ASR + TTS 播放**

Read `lib/screens/chat_screen.dart`，在 import 区添加：

```dart
import 'dart:io';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
```

在 `_ChatScreenState` 中添加：

```dart
final _audioRecorder = AudioRecorder();
final _audioPlayer = AudioPlayer();
```

替换 `_onRecordStart`：

```dart
void _onRecordStart() async {
  final status = await Permission.microphone.request();
  if (!status.isGranted) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请在设置中开启麦克风权限')),
      );
    }
    return;
  }
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
  await _audioRecorder.start(
    const RecordConfig(encoder: AudioEncoder.aacLc),
    path: path,
  );
  setState(() => _isRecording = true);
}
```

替换 `_onRecordStop`：

```dart
void _onRecordStop() async {
  setState(() {
    _isRecording = false;
    _isProcessingVoice = true;
  });

  try {
    final path = await _audioRecorder.stop();
    if (path == null || !File(path).existsSync()) return;

    final fileBytes = await File(path).readAsBytes();
    // Send as one chunk for short recordings
    final text = await widget.asrService.recognize(
      Stream.fromIterable([fileBytes]),
    );
    if (mounted && text.isNotEmpty) {
      setState(() => _isProcessingVoice = false);
      await _sendMessage(text);
    } else if (mounted) {
      setState(() => _isProcessingVoice = false);
    }
  } catch (_) {
    if (mounted) {
      setState(() => _isProcessingVoice = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没听清，再试一次？')),
      );
    }
  }
}
```

替换 `_playTts` 为真实播放：

```dart
Future<void> _playTts(Message message) async {
  setState(() => _playingMessageId = message.id);
  try {
    final audioBytes = await widget.ttsService.synthesize(message.content);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tts_${message.id}.mp3');
    await file.writeAsBytes(audioBytes);
    await _audioPlayer.play(DeviceFileSource(file.path));
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingMessageId = null);
    });
  } catch (_) {
    if (mounted) setState(() => _playingMessageId = null);
  }
}
```
```

- [ ] **Step 3: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
feat: wire real audio recording with record package

Hold mic button to record AAC, release to stop and send to ASR.
Permission check on first use.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: flutter analyze + build 最终验证

- [ ] **Step 1: 最终静态分析**

```bash
cd /mnt/b/workdir/gitlab/Bella && \
export PATH="/mnt/b/flutter/bin:$PATH" && \
flutter analyze 2>&1
```

Expected: No issues found.

- [ ] **Step 2: 构建 debug APK**

```bash
cd /mnt/b/workdir/gitlab/Bella && \
export PATH="/mnt/b/flutter/bin:$PATH" && \
flutter build apk --debug 2>&1 | tail -5
```

Expected: ✓ Built build/app/outputs/flutter-apk/app-debug.apk

- [ ] **Step 3: 提交**

```bash
cd /mnt/b/workdir/gitlab/Bella && git add -A && git commit -m "$(cat <<'EOF'
chore: final analyze and build verification

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```
