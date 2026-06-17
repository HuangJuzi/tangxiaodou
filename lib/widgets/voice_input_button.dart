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
  late final AnimationController _floatController;
  late final Animation<double> _floatAnim;
  late final AnimationController _bounceController;
  late final List<Animation<double>> _bounceAnims;

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

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: 0, end: -3).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _bounceAnims = List.generate(3, (i) {
      return Tween<double>(begin: 0, end: -8).animate(
        CurvedAnimation(
          parent: _bounceController,
          curve: Interval(i * 0.15, 0.6 + i * 0.15, curve: Curves.easeInOut),
        ),
      );
    });
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
    _floatController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isRecording;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _floatController]),
          builder: (_, __) {
            return GestureDetector(
              onLongPressStart: (_) => widget.onRecordStart(),
              onLongPressEnd: (_) => widget.onRecordStop(),
              child: Transform.translate(
                offset: Offset(0, isActive ? 0 : _floatAnim.value),
                child: AnimatedScale(
                  scale: isActive ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.elasticOut,
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
                              .withValues(alpha: 0.3 + _pulseAnim.value * 0.2),
                          blurRadius: 20 + _pulseAnim.value * 16,
                          spreadRadius: _pulseAnim.value * 6,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('🎤', style: TextStyle(fontSize: 36)),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        if (widget.isProcessing)
          _buildProcessingDots()
        else ...[
          Text(
            isActive ? '● 录音中...' : '按住说话',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isActive ? const Color(0xFFE53935) : AppColors.primary,
            ),
          ),
          if (!isActive) ...[
            const SizedBox(height: 2),
            const Text(
              '松开发送 · 右下角可打字',
              style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildProcessingDots() {
    return AnimatedBuilder(
      animation: _bounceController,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Transform.translate(
              offset: Offset(0, _bounceAnims[i].value),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.5 + i * 0.2),
                      AppColors.primaryLight.withValues(alpha: 0.5 + i * 0.2),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
