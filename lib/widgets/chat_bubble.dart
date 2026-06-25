import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message.dart';
import '../theme.dart';
import '../services/tts_player.dart';
import 'typing_dots.dart';
import 'video_player_dialog.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onTtsTap;
  final TtsPlayer ttsPlayer;
  final String? autoPlayMessageId;
  final VoidCallback? onStopTts;

  const ChatBubble({
    required this.message,
    this.onTtsTap,
    required this.ttsPlayer,
    this.autoPlayMessageId,
    this.onStopTts,
    super.key,
  });

  String get _displayContent {
    var out = message.content.replaceAllMapped(
      RegExp(r'<image-url>(.*?)</image-url>'),
      (m) => '![](${m.group(1)})',
    );
    out = out.replaceAllMapped(
      RegExp(r"VIDEO:\s*(https?://[A-Za-z0-9._~:/?#@!&()*+,;=%-]+)"),
      (m) => '[📹 点击播放视频](${m.group(1)})\n',
    );
    return out;
  }

  void _copyText(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _saveImage(BuildContext context, String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      await Gal.putImageBytes(Uint8List.fromList(response.bodyBytes));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册'), duration: Duration(seconds: 1)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  Future<void> _openLink(BuildContext context, String text, String? href) async {
    final url = href ?? text;
    if (url.isEmpty) return;
    final isVideo = text.startsWith('📹') ||
        isVideoUrl(url) ||
        url.contains('/api/open-apis/files/');
    if (isVideo) {
      await VideoPlayerDialog.show(context, url);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAi = message.role == MessageRole.ai;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onLongPress: () => _copyText(context),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.88,
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
                        if (!isAi && message.imagePath != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.55,
                                maxHeight: 220,
                              ),
                              child: Image.file(
                                File(message.imagePath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  height: 60,
                                  child: Center(
                                    child: Icon(Icons.broken_image_outlined,
                                        size: 22, color: Colors.white54),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (isAi)
                          MarkdownBody(
                            data: _displayContent,
                            softLineBreak: true,
                            onTapLink: (text, href, title) =>
                                _openLink(context, text, href),
                            imageBuilder: (Uri uri, String? title, String? alt) => GestureDetector(
                              onLongPress: () => _saveImage(context, uri.toString()),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(uri.toString(), fit: BoxFit.cover),
                              ),
                            ),
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF555555)),
                              code: TextStyle(fontSize: 13, backgroundColor: const Color(0xFFF5F0FA), color: AppColors.primary),
                              codeblockDecoration: const BoxDecoration(
                                color: Color(0xFFF5F0FA),
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                              ),
                              blockquoteDecoration: const BoxDecoration(
                                border: Border(left: BorderSide(color: AppColors.primaryLight, width: 3)),
                              ),
                            ),
                          )
                        else
                          Text(
                            message.content,
                            style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.white),
                          ),
                        if (isAi && message.isStreaming) ...[
                          const SizedBox(height: 6),
                          const TypingDots(),
                        ],
                      ],
                    ),
                  ),
                ),
                if (isAi)
                  // The TTS button reacts to TtsPlayer state on its own so TTS
                  // state changes don't rebuild the streaming markdown body
                  // (which would re-parse the whole message and cause jitter).
                  ListenableBuilder(
                    listenable: ttsPlayer,
                    builder: (context, _) {
                      final isAuto =
                          ttsPlayer.isAutoPlaying && message.id == autoPlayMessageId;
                      final playing =
                          isAuto || ttsPlayer.playingMessageId == message.id;
                      if (message.content.trim().isEmpty) {
                        return const SizedBox.shrink();
                      }
                      if (message.isStreaming && !isAuto) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _TtsButton(
                          isPlaying: playing,
                          onTap: playing ? onStopTts : onTtsTap,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
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
          isPlaying ? '⏹ 停止' : '🔊 播放',
          style: TextStyle(
            fontSize: 12,
            color: isPlaying ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
