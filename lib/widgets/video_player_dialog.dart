import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

bool isVideoUrl(String url) {
  final lower = url.toLowerCase().split('?').first.split('#').first;
  return lower.endsWith('.mp4') ||
      lower.endsWith('.m3u8') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.mkv');
}

class VideoPlayerDialog extends StatefulWidget {
  final String url;
  const VideoPlayerDialog({required this.url, super.key});

  static Future<void> show(BuildContext context, String url) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      useSafeArea: false,
      builder: (_) => VideoPlayerDialog(url: url),
    );
  }

  @override
  State<VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<VideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  bool _isFullscreen = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      _loading = false;
      _error = '无效的视频链接';
      return;
    }
    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _loading = false);
      controller.setLooping(true);
      controller.play();
      _scheduleHide();
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法播放视频：$e';
      });
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _exitFullscreen();
    _hardStop();
    super.dispose();
  }

  void _hardStop() {
    final c = _controller;
    if (c == null) return;
    try {
      c.setVolume(0);
      c.pause();
      c.setLooping(false);
      c.dispose();
    } catch (_) {}
  }

  Future<void> _cleanupAndExit() async {
    final c = _controller;
    if (c != null) {
      try {
        await c.setVolume(0);
        await c.pause();
        await c.setLooping(false);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _enterFullscreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      _isFullscreen = true;
      _controlsVisible = true;
    });
    _scheduleHide();
  }

  void _exitFullscreen() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) {
      setState(() => _isFullscreen = false);
    }
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cleanupAndExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _error != null
                ? _buildError()
                : _isFullscreen
                    ? _buildFullscreen()
                    : _buildNormal(),
      ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _cleanupAndExit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormal() {
    return SafeArea(
      child: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(_controller!),
                if (_controlsVisible) ...[
                  // Center play/pause button (always tappable)
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Close button (top-right, on video)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _CircleButton(
                      icon: Icons.close,
                      onTap: _cleanupAndExit,
                    ),
                  ),
                  // Fullscreen button (bottom-right, on video)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _enterFullscreen,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen,
                                color: Colors.white, size: 22),
                            SizedBox(width: 4),
                            Text(
                              '全屏',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreen() {
    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
          if (_controlsVisible) ...[
            // Center play/pause
            Center(
              child: GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // Exit fullscreen button (top-right)
            Positioned(
              top: 4,
              right: 4,
              child: _CircleButton(
                icon: Icons.fullscreen_exit,
                onTap: _exitFullscreen,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
