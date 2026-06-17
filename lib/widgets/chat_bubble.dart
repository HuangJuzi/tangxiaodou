import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import '../theme.dart';
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

  String get _displayContent {
    return message.content.replaceAllMapped(
      RegExp(r'<image-url>(.*?)</image-url>'),
      (m) => '![](${m.group(1)})',
    );
  }

  void _copyText(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _saveImage(BuildContext context, String url) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = 'img_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$name');
      final response = await http.get(Uri.parse(url));
      await file.writeAsBytes(response.bodyBytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片已保存到 $name'), duration: const Duration(seconds: 2)),
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
                        if (isAi)
                          MarkdownBody(
                            data: _displayContent,
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
                if (isAi && !message.isStreaming) ...[
                  const SizedBox(height: 4),
                  _TtsButton(isPlaying: _isPlaying, onTap: onTtsTap),
                ],
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
