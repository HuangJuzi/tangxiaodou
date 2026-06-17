import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
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
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  String? _playingMessageId;
  bool _isTextMode = false;
  String? _userAvatarPath;
  String? _aiAvatarPath;
  final _imagePicker = ImagePicker();
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
    _loadAvatars();
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

  Future<String> get _avatarConfigPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/avatar_config.json';
  }

  Future<void> _loadAvatars() async {
    try {
      final file = File(await _avatarConfigPath);
      if (!await file.exists()) return;
      final cfg = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      setState(() {
        _userAvatarPath = cfg['user'] as String?;
        _aiAvatarPath = cfg['ai'] as String?;
      });
    } on FormatException {
      // ignore
    }
  }

  Future<void> _saveAvatarConfig() async {
    final cfg = {
      'user': _userAvatarPath,
      'ai': _aiAvatarPath,
    };
    await File(await _avatarConfigPath).writeAsString(jsonEncode(cfg));
  }

  Future<void> _pickAvatar(bool isUser) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _imagePicker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final destName = isUser ? 'user.png' : 'ai.png';
    final destPath = '${dir.path}/$destName';
    await File(picked.path).copy(destPath);

    setState(() {
      if (isUser) {
        _userAvatarPath = destPath;
      } else {
        _aiAvatarPath = destPath;
      }
    });
    _saveAvatarConfig();
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
    try {
      await for (final token in widget.llmService.chat(_senderId, text)) {
        buffer.write(token);
        _pendingText.write(token);
        setState(() {
          aiMessage.content = buffer.toString();
        });
        _scrollToBottom();

        final pending = _pendingText.toString();
        final delim = RegExp(r'[,，。！？~…!?\n]').firstMatch(pending);
        if (delim != null) {
          final end = delim.end;
          final sentence = pending.substring(0, end);
          _pendingText.clear();
          _pendingText.write(pending.substring(end));
          _enqueueTts(sentence);
        }
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
                userAvatarPath: _userAvatarPath,
                aiAvatarPath: _aiAvatarPath,
                onAvatarLongPress: (isUser) => _pickAvatar(isUser),
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

class _TtsJob {
  final String text;
  final int gen;
  List<int>? bytes;
  _TtsJob({required this.text, required this.gen});
}
