import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import '../theme.dart';
import '../services/llm_service.dart';
import '../services/asr_service.dart';
import '../services/tts_service.dart';
import '../widgets/chat_bubble.dart';


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
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  String? _playingMessageId;
  bool _isTextMode = false;
  final _pendingText = StringBuffer();
  final List<_TtsJob> _ttsQueue = [];
  int _ttsGen = 0;
  bool _isPlayingTts = false;

  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _senderId = 'user-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _loadMessages().then((_) {
      if (_messages.isEmpty) {
        _messages.add(Message(
          role: MessageRole.ai,
          content: '你好呀！我是豆豆~ 今天过得怎么样？',
        ));
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
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

  Future<String> get _messagesPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/messages.json';
  }

  Future<void> _loadMessages() async {
    try {
      final file = File(await _messagesPath);
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      final messages = json
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList();
      if (messages.isNotEmpty) {
        setState(() => _messages.addAll(messages));
      }
    } on FormatException {
      // corrupted file, ignore
    }
  }

  Future<void> _saveMessages() async {
    final json = jsonEncode(_messages.map((m) => m.toJson()).toList());
    await File(await _messagesPath).writeAsString(json);
  }



  Future<void> _sendMessage(String text) async {
    setState(() {
      _messages.add(Message(role: MessageRole.user, content: text));
    });
    _saveMessages();
    _scrollToBottom();

    final aiMessage = Message(role: MessageRole.ai, content: '', isStreaming: true);
    setState(() => _messages.add(aiMessage));
    _scrollToBottom();

    final buffer = StringBuffer();
    final delimRe = RegExp(r'[,，。！？~…!?\n]');
    try {
      await for (final token in widget.llmService.chat(_senderId, text)) {
        buffer.write(token);
        _pendingText.write(token);
        setState(() {
          aiMessage.content = buffer.toString();
        });
        _scrollToBottom();

        var pending = _pendingText.toString();
        _pendingText.clear();
        while (pending.isNotEmpty) {
          final delim = delimRe.firstMatch(pending);
          if (delim == null) break;
          _enqueueTts(pending.substring(0, delim.end));
          pending = pending.substring(delim.end);
        }
        _pendingText.write(pending);
      }
      if (_pendingText.isNotEmpty) {
        _enqueueTts(_pendingText.toString());
        _pendingText.clear();
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
      });
      _saveMessages();
      _scrollToBottom();
    }
  }

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

  void _enqueueTts(String text) {
    final gen = _ttsGen;
    final idx = _ttsQueue.length;
    _ttsQueue.add(_TtsJob(text: text, gen: gen));
    widget.ttsService.synthesize(text).then((bytes) {
      if (gen != _ttsGen) return;
      if (idx < _ttsQueue.length) {
        _ttsQueue[idx].bytes = bytes;
      }
      _playNextInQueue();
    });
  }

  void _playNextInQueue() {
    if (_isPlayingTts) return;

    while (_ttsQueue.isNotEmpty && _ttsQueue.first.bytes != null) {
      final job = _ttsQueue.removeAt(0);
      if (job.gen != _ttsGen) continue;

      _isPlayingTts = true;
      _playTtsBytes(job.bytes!).then((_) {
        _isPlayingTts = false;
        _playNextInQueue();
      });
      return;
    }
  }

  Future<void> _playTtsBytes(List<int> bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(bytes);
      await _audioPlayer.play(DeviceFileSource(file.path));
      await _audioPlayer.onPlayerComplete.first;
    } catch (_) {}
  }

  void _onRecordStart() async {
    _ttsGen++;
    _ttsQueue.clear();
    _pendingText.clear();
    _isPlayingTts = false;
    _audioPlayer.stop();

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

  void _onRecordStop() async {
    setState(() {
      _isRecording = false;
      _isProcessingVoice = true;
    });

    try {
      final path = await _audioRecorder.stop();
      if (path == null || !File(path).existsSync()) return;

      final fileBytes = await File(path).readAsBytes();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NavDot(color: AppColors.primary, size: 9),
            SizedBox(width: 5),
            _NavDot(color: AppColors.primaryLight, size: 9),
            SizedBox(width: 10),
            Text('豆豆', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ColoredBox(color: Color(0xFFF0E6F6)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              itemCount: _messages.length,
              itemBuilder: (_, i) => ChatBubble(
                message: _messages[i],
                onTtsTap: () {
                  if (_messages[i].role == MessageRole.ai &&
                      !_messages[i].isStreaming) {
                    _playTts(_messages[i]);
                  }
                },
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
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onLongPressStart: (_) => _onRecordStart(),
            onLongPressEnd: (_) => _onRecordStop(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 44,
              decoration: BoxDecoration(
                gradient: _isRecording
                    ? const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFEF5350)])
                    : const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? const Color(0xFFE53935) : AppColors.primary).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isRecording ? '●' : '🎤',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isProcessingVoice ? '识别中...' : (_isRecording ? '松开发送' : '按住说话'),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
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
            height: 44,
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
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
            child:
                const Text('→', style: TextStyle(color: Colors.white, fontSize: 18)),
          ),
        ),
      ],
    );
  }
}

class _TtsJob {
  final String text;
  final int gen;
  List<int>? bytes;
  _TtsJob({required this.text, required this.gen});
}

class _NavDot extends StatelessWidget {
  final Color color;
  final double size;
  const _NavDot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
