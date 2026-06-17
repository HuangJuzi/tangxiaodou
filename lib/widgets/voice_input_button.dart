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
