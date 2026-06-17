import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme.dart';
import 'avatar_widget.dart';
import 'typing_dots.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onTtsTap;
  final String? playingMessageId;
  final String? userAvatarPath;
  final String? aiAvatarPath;
  final void Function(bool isUser)? onAvatarLongPress;

  const ChatBubble({
    required this.message,
    this.onTtsTap,
    this.playingMessageId,
    this.userAvatarPath,
    this.aiAvatarPath,
    this.onAvatarLongPress,
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
            AvatarWidget(
              imagePath: aiAvatarPath,
              onLongPress: onAvatarLongPress != null ? () => onAvatarLongPress!(false) : null,
            ),
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
            AvatarWidget(
              isUser: true,
              imagePath: userAvatarPath,
              onLongPress: onAvatarLongPress != null ? () => onAvatarLongPress!(true) : null,
            ),
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
