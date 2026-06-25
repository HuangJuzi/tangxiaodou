import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import '../theme.dart';
import '../services/llm_service.dart';
import '../services/asr_service.dart';
import '../services/tts_service.dart';
import '../services/tts_player.dart';
import '../services/oss_service.dart';
import '../services/settings_service.dart';
import '../widgets/chat_bubble.dart';
import 'settings_screen.dart';

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

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  bool _isTextMode = false;
  bool _isSending = false;
  bool _isUploading = false;
  bool _showScrollBtn = false;
  int _displayCount = 20;
  bool _loadingMore = false;
  String? _autoPlayMessageId;
  bool _ttsEnabled = true;
  String? _pendingImagePath;
  Timer? _flushTimer;
  final _pendingText = StringBuffer();
  final _ttsBuffer = StringBuffer();

  late final TtsPlayer _ttsPlayer;

  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _senderId = 'zhiyi.huang';

  @override
  void initState() {
    super.initState();
    _ttsEnabled = widget.settingsService.config?.ttsEnabled ?? true;
    _ttsPlayer = TtsPlayer(ttsService: widget.ttsService, sink: AudioPlayerSink(_audioPlayer));
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (atBottom != !_showScrollBtn) {
      setState(() => _showScrollBtn = !atBottom);
    }
    if (_scrollController.position.pixels <= 200 && !_loadingMore) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (_displayCount >= _messages.length || _loadingMore) return;
    _loadingMore = true;
    final oldPixels = _scrollController.position.pixels;
    final oldMax = _scrollController.position.maxScrollExtent;
    setState(() {
      _displayCount = (_displayCount + 20).clamp(0, _messages.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final newMax = _scrollController.position.maxScrollExtent;
        final delta = newMax - oldMax;
        if (delta.abs() > 0.5) {
          _scrollController.jumpTo(oldPixels + delta);
        }
      }
      _loadingMore = false;
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _scrollController.dispose();
    _textController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// Jump to the newest message from anywhere in the list. A lazy
  /// [ListView.builder] with variable-height items only corrects
  /// [maxScrollExtent] as off-screen items are built, so a single
  /// [jumpTo] from far up can land short of the true bottom. Re-settle across
  /// frames so we follow the corrected extent and actually reach the latest
  /// message.
  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    var tries = 0;
    void settle() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        final before = pos.pixels;
        pos.jumpTo(pos.maxScrollExtent);
        if (pos.pixels != before && ++tries < 6) {
          settle();
        }
      });
    }
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    settle();
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
      final all = json
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList();
      if (all.isNotEmpty) {
        setState(() {
          _messages.addAll(all);
          _displayCount = _messages.length > 20 ? 20 : _messages.length;
        });
      }
    } on FormatException {
      // corrupted file, ignore
    }
  }

  Future<void> _saveMessages() async {
    final json = jsonEncode(_messages.map((m) => m.toJson()).toList());
    await File(await _messagesPath).writeAsString(json);
  }



  Future<void> _sendMessage(String text, {String? imagePath}) async {
    if (_isSending) return;
    setState(() => _isSending = true);
    final pendingPath = imagePath ?? _pendingImagePath;
    String? ossUrl;
    if (pendingPath != null) {
      setState(() => _isUploading = true);
      try {
        ossUrl = await widget.ossService.upload(pendingPath);
      } catch (_) {
        ossUrl = null;
      }
      if (ossUrl == null) {
        if (mounted) {
          setState(() {
            _isUploading = false;
            _isSending = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('图片上传失败，请重试')),
          );
        }
        return;
      }
      setState(() => _isUploading = false);
    }
    final llmText = ossUrl == null ? text : '$text\n\n原始图片链接：$ossUrl';

    _flushTimer?.cancel();
    _autoPlayMessageId = null;
    _ttsPlayer.stop();
    setState(() {
      _messages.add(Message(role: MessageRole.user, content: text, imagePath: pendingPath));
      _pendingImagePath = null;
    });
    await _saveMessages();
    _scrollToBottom();

    final aiMessage = Message(role: MessageRole.ai, content: '', isStreaming: true);
    _autoPlayMessageId = aiMessage.id;
    setState(() => _messages.add(aiMessage));
    _scrollToBottom();

    final myMsgId = aiMessage.id;
    final buffer = StringBuffer();
    final delimRe = RegExp(r'[，,。.！？!?；;]');
    final sentDelim = RegExp(r'[。.！？!?]');
    final speakableRe = RegExp(r'[一-鿿a-zA-Z0-9]');

    /// Drain [_ttsBuffer] into text that is safe to feed into TTS chunking.
    /// While streaming ([flushAll] false) a still-arriving URL/path/filename at
    /// the tail is pushed back into [_ttsBuffer] for later completion. On final
    /// flush ([flushAll] true) no tail is held back so the last word is never
    /// stuck. Complete links/paths are removed and file-name dots become 点
    /// before chunking, so the delimiter splitter can't break them into
    /// fragments.
    String _drainTtsBuffer({bool flushAll = false}) {
      var text = _ttsBuffer.toString();
      _ttsBuffer.clear();
      if (flushAll) {
        // nothing to hold back on final flush
      } else {
        // Hold back a still-arriving URL/path/filename at the tail.
        int holdAt = text.length;
        final tailIdx = TtsPlayer.inProgressTail(text);
        if (tailIdx >= 0) holdAt = tailIdx;
        if (holdAt < text.length) {
          _ttsBuffer.write(text.substring(holdAt));
          text = text.substring(0, holdAt);
        }
      }
      // Remove complete links/paths and protect file-name dots before chunking
      text = TtsPlayer.stripLinksAndPaths(text);
      text = TtsPlayer.protectDots(text);
      return text;
    }

    // Put unflushed [remainder] back ahead of any tail already held in
    // [_ttsBuffer], so streamed text keeps its original order.
    void _pushBackTts(String remainder) {
      final held = _ttsBuffer.toString();
      _ttsBuffer.clear();
      _ttsBuffer.write(remainder);
      _ttsBuffer.write(held);
    }

    bool isActive() => _autoPlayMessageId == myMsgId && _ttsEnabled;

    void _enqueueTts(String chunk) {
      if (isActive()) _ttsPlayer.enqueue(chunk);
    }
    int _tokenCount = 0;
    try {
      debugPrint('[SEND] entering await for loop');
      await for (final token in widget.llmService.chat(_senderId, llmText)) {
        _tokenCount++;
        buffer.write(token);

        // Collect raw token text; a helper below filters out tool-call
        // portions before they enter the TTS pipeline.
        _pendingText.write(token);

        final display = buffer.toString();
        setState(() {
          aiMessage.content = display;
        });
        if (!_showScrollBtn) {
          _scrollToBottom();
        }

        _ttsBuffer.write(_pendingText.toString());
        _pendingText.clear();

        var buf = _drainTtsBuffer();

        while (buf.isNotEmpty) {
          final matches = delimRe.allMatches(buf).toList();
          if (matches.isEmpty) {
            _pushBackTts(buf);
            _flushTimer?.cancel();
            _flushTimer = Timer(const Duration(seconds: 2), () {
              final tail = _drainTtsBuffer(flushAll: true);
              if (tail.isNotEmpty) _enqueueTts(tail);
            });
            break;
          }
          bool flushed = false;
          for (final m in matches) {
            final isSent = sentDelim.hasMatch(m.group(0)!);
            final speakableCount = speakableRe.allMatches(buf.substring(0, m.start)).length;
            if (isSent || speakableCount >= 50) {
              _enqueueTts(buf.substring(0, m.end));
              _flushTimer?.cancel();
              buf = buf.substring(m.end);
              flushed = true;
              break;
            }
          }
          if (!flushed) {
            _pushBackTts(buf);
            _flushTimer?.cancel();
            _flushTimer = Timer(const Duration(seconds: 2), () {
              final tail = _drainTtsBuffer(flushAll: true);
              if (tail.isNotEmpty) _enqueueTts(tail);
            });
            break;
          }
        }
      }
      // Drain any remaining buffered text
      var finalText = _drainTtsBuffer(flushAll: true);
      _flushTimer?.cancel();
      while (finalText.isNotEmpty) {
        _enqueueTts(finalText);
        finalText = _drainTtsBuffer(flushAll: true);
        // At this point there should be no more pending tool-call text
        // because the stream is done, so any remnant can be drained once.
        break;
      }
    } on HttpException {
      debugPrint('[SEND] HttpException, buffer empty=${buffer.isEmpty}, tokens=$_tokenCount');
      setState(() {
        aiMessage.content = buffer.isEmpty ? '网络断了，请重试' : '${buffer.toString()}...';
      });
    } catch (e) {
      debugPrint('[SEND] catch error: $e (${e.runtimeType}), buffer empty=${buffer.isEmpty}, tokens=$_tokenCount');
      setState(() {
        aiMessage.content = buffer.isEmpty ? '出错了，请重试' : '${buffer.toString()}...';
      });
    } finally {
      debugPrint('[SEND] finally, tokens=$_tokenCount, bufferLen=${buffer.length}, displayLen=${aiMessage.content.length}');
      _flushTimer?.cancel();
      var tail = _drainTtsBuffer(flushAll: true);
      while (tail.isNotEmpty) {
        _enqueueTts(tail);
        tail = _drainTtsBuffer(flushAll: true);
      }
      setState(() {
        aiMessage.isStreaming = false;
        _isSending = false;
      });
      await _saveMessages();
      _scrollToBottom();
    }
  }

  void _playTts(Message message) {
    if (!_ttsEnabled) return;
    _ttsPlayer.playFull(message);
  }

  void _hardstop() {
    _flushTimer?.cancel();
    _autoPlayMessageId = null;
    _ttsPlayer.stop();
    // chat() internally cancels the previous request's CancelToken,
    // so /hardstop is sent on a fresh connection.
    widget.llmService.chat(_senderId, '/hardstop').listen((_) {});
  }

  void _onRecordStart() async {
    _flushTimer?.cancel();
    _autoPlayMessageId = null;
    _ttsPlayer.stop();
    _pendingText.clear();
    _ttsBuffer.clear();

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
    HapticFeedback.lightImpact();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.pcm';
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
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
        await _sendMessage(text, imagePath: _pendingImagePath);
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NavDot(color: AppColors.primary, size: 7),
            SizedBox(width: 4),
            _NavDot(color: AppColors.primaryLight, size: 7),
          ],
        ),
        centerTitle: true,
        toolbarHeight: 44,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
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
            onTap: () async {
              final cleared = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    settingsService: widget.settingsService,
                  ),
                ),
              );
              if (cleared == true && mounted) {
                _ttsPlayer.stop();
                setState(() {
                  _messages.clear();
                  _displayCount = 0;
                  _messages.add(Message(
                    role: MessageRole.ai,
                    content: '你好呀！我是糖小豆~ 今天过得怎么样？',
                  ));
                  _displayCount = 1;
                });
                _scrollToBottom();
              }
            },
            child: const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Icon(Icons.tune, size: 24, color: AppColors.primaryLight),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ColoredBox(color: Color(0xFFF0E6F6)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  itemCount: _displayCount < _messages.length ? _displayCount : _messages.length,
                  itemBuilder: (_, i) {
                    final idx = _messages.length - (_displayCount < _messages.length ? _displayCount : _messages.length) + i;
                    final msg = _messages[idx];
                    return ChatBubble(
                      message: msg,
                      onTtsTap: () {
                        if (msg.role == MessageRole.ai && !msg.isStreaming) {
                          _playTts(msg);
                        }
                      },
                      ttsPlayer: _ttsPlayer,
                      autoPlayMessageId: _autoPlayMessageId,
                      onStopTts: _ttsPlayer.stop,
                    );
                },
              ),
                Positioned(
                    bottom: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: !_showScrollBtn,
                      child: AnimatedOpacity(
                        opacity: _showScrollBtn ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: GestureDetector(
                          onTap: _scrollToLatest,
                          child: Container(
                            height: 30,
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE1BEE7), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('↓', style: TextStyle(fontSize: 14, color: AppColors.primary)),
                                SizedBox(width: 3),
                                Text('最新', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                              ],
                            ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  static const _commands = ['/compact', '/new', '/hardstop'];
  static const _commandNotes = {
    '/compact': '压缩上下文',
    '/new': '清空上下文',
    '/hardstop': '停止当前对话',
  };

  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (xfile == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(xfile.path).copy(dest);
      if (mounted) setState(() => _pendingImagePath = dest);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(source == ImageSource.camera ? '拍照失败' : '选择图片失败')),
        );
      }
    }
  }

  void _clearPendingImage() {
    setState(() => _pendingImagePath = null);
  }

  Widget _buildInputArea() {
    final input = _textController.text.trim();
    final showCommands = _isTextMode && input.startsWith('/') && !input.contains(' ');
    var filtered = _commands.where((c) => c.startsWith(input)).toList();
    if (input == '/') filtered = _commands;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pendingImagePath != null)
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(_pendingImagePath!),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '已选择图片，发送时将上传',
                    style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                ),
                GestureDetector(
                  onTap: _clearPendingImage,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: Color(0xFF888888)),
                  ),
                ),
              ],
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: (showCommands && filtered.isNotEmpty)
              ? Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFEDE7F6))),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: filtered.map((c) {
                      final note = _commandNotes[c] ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () {
                            _textController.clear();
                            _sendMessage(c);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primaryLight, width: 1),
                            ),
                            child: Row(
                              children: [
                                Text(c, style: const TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(note, style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEDE7F6))),
          ),
          child: _isTextMode ? _buildTextInput() : _buildVoiceInput(),
        ),
      ],
    );
  }

  Widget _buildVoiceInput() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _isTextMode = true),
          child: Container(
            width: 48,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text('⌨', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onLongPressStart: (_) => _onRecordStart(),
            onLongPressEnd: (_) => _onRecordStop(),
            child: AnimatedScale(
              scale: _isRecording ? 0.96 : 1.0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
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
        ),
        const SizedBox(width: 8),
        _isSending
            ? _SendButton(isSending: true, onTap: _hardstop)
            : GestureDetector(
                onTap: _isUploading ? null : () => _pickImage(),
                onLongPress: _isUploading ? null : () => _pickImage(source: ImageSource.camera),
                child: Container(
                  width: 48,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _pendingImagePath != null
                        ? AppColors.primaryLight
                        : const Color(0xFFF3E5F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: _isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 22,
                          color: _pendingImagePath != null
                              ? Colors.white
                              : AppColors.primary,
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
            width: 48,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text('🎤', style: TextStyle(fontSize: 18)),
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
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '说点什么...',
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsetsDirectional.fromSTEB(4, 12, 18, 12),
                prefixIcon: _pendingImagePath != null
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        child: GestureDetector(
                          onTap: _clearPendingImage,
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_pendingImagePath!),
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const Positioned(
                                right: -2,
                                top: -2,
                                child: CircleAvatar(
                                  radius: 7,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      size: 10, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : IconButton(
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        visualDensity: VisualDensity.compact,
                        icon: _isUploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined,
                                size: 22, color: AppColors.primary),
                        onPressed: _isUploading ? null : () => _pickImage(),
                        onLongPress: _isUploading
                            ? null
                            : () => _pickImage(source: ImageSource.camera),
                      ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 25, minHeight: 25),
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
        _SendButton(
          isSending: _isSending,
          onTap: () {
            if (_isSending) {
              _hardstop();
            } else {
              final text = _textController.text.trim();
              if (text.isNotEmpty) {
                _sendMessage(text);
                _textController.clear();
              }
            }
          },
        ),
      ],
    );
  }
}

class _SendButton extends StatefulWidget {
  final bool isSending;
  final VoidCallback onTap;
  const _SendButton({required this.isSending, required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnim = Tween<double>(begin: 1, end: 0.92).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Transform.scale(scale: _scaleAnim.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: widget.isSending ? const Color(0xFFE53935) : null,
            gradient: widget.isSending ? null : const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
            ),
            boxShadow: [
              BoxShadow(
                color: (widget.isSending ? const Color(0xFFE53935) : AppColors.primary).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.isSending ? '停止' : '发送',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
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
