import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';

class AvatarWidget extends StatelessWidget {
  final double size;
  final bool isUser;
  final String? imagePath;
  final VoidCallback? onLongPress;

  const AvatarWidget({
    this.size = 28,
    this.isUser = false,
    this.imagePath,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
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
        clipBehavior: Clip.antiAlias,
        child: _buildChild(),
      ),
    );
  }

  Widget _buildChild() {
    if (imagePath != null && File(imagePath!).existsSync()) {
      return Image.file(
        File(imagePath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    return Text(isUser ? '😊' : '🐤', style: TextStyle(fontSize: size * 0.55));
  }
}
