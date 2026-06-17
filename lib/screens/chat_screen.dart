import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme.dart';
import '../services/llm_service.dart';
import '../services/asr_service.dart';
import '../services/tts_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/avatar_widget.dart';
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
      // streaming flag handled by aiMessage.isStreaming
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
        // streaming complete
      });
      _scrollToBottom();

      if (aiMessage.content.isNotEmpty &&
          !aiMessage.content.startsWith('网络') &&
          !aiMessage.content.startsWith('出错')) {
        _playTts(aiMessage);
      }
    }
  }

  Future<void> _playTts(Message message) async {
    setState(() => _playingMessageId = message.id);
    try {
      final _ = await widget.ttsService.synthesize(message.content);
      // Audio playback wired in Task 14
      if (mounted) setState(() => _playingMessageId = null);
    } catch (_) {
      if (mounted) setState(() => _playingMessageId = null);
    }
  }

  void _onRecordStart() {
    setState(() => _isRecording = true);
  }

  void _onRecordStop() async {
    setState(() {
      _isRecording = false;
      _isProcessingVoice = true;
    });

    try {
      final text = await widget.asrService.recognize(
        Stream.fromIterable([<int>[]]),
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
                Text('豆豆',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text('AI 陪聊小助手',
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
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
