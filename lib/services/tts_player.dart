import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import 'tts_service.dart';

class _TtsJob {
  final int id;
  final String text;
  final int gen;
  List<int>? bytes;
  _TtsJob({required this.id, required this.text, required this.gen});
}

class TtsPlayer {
  final TtsService _ttsService;
  final AudioPlayer _audioPlayer;
  final VoidCallback? onStateChanged;

  final List<_TtsJob> _queue = [];
  int _gen = 0;
  int _nextJobId = 0;
  bool _isProcessing = false;

  bool isPlaying = false;
  bool isAutoPlaying = false;
  String? playingMessageId;

  TtsPlayer({required TtsService ttsService, required AudioPlayer audioPlayer, this.onStateChanged})
      : _ttsService = ttsService,
        _audioPlayer = audioPlayer;

  void _notify() => onStateChanged?.call();

  static final RegExp _imageUrlRe = RegExp(r'<image-url>.*?</image-url>', dotAll: true);
  static final RegExp _mediaRe = RegExp(r'(?:MEDIA|VIDEO):\s*https?://\S+', caseSensitive: false);
  static final RegExp _mdLinkRe = RegExp(r'\[([^\]]*)\]\((?:https?|wss?)://[^\)]*\)', caseSensitive: false);
  static final RegExp _urlRe = RegExp(r'(?:https?|wss?)://\S+', caseSensitive: false);
  static final RegExp _absPathRe = RegExp(r'(?:[A-Za-z]:[\\/]|~/|/)[^\s，。！？、：；)」』]+');
  static final RegExp _relPathRe = RegExp(r'[\w.~-]+(?:[\\/][\w.~-]+)+');
  static final RegExp _dotRe = RegExp(r'(?<=[A-Za-z0-9])\.(?=[A-Za-z0-9])');

  // Tail patterns anchored to end-of-string: a URL/path/filename still being
  // streamed in. The URL/path char classes exclude whitespace, CJK and
  // sentence punctuation, so a link counts as "finished" once such a char
  // follows it.
  static final RegExp _tailRe = RegExp(
    r'(?:https?|wss?)://[^\s一-鿿，。！？、：；)」』]*$'
    r'|(?:[A-Za-z]:[\\/]|~/|/)[^\s一-鿿，。！？、：；)」』]*$'
    r'|[\w.~-]+(?:[\\/][\w.~-]*)+$'
    r'|[A-Za-z0-9]+\.$',
    caseSensitive: false,
  );

  /// Remove URLs (markdown or bare), media/image tags, and file paths
  /// (absolute, or relative when they contain a slash). Non-link text stays.
  static String stripLinksAndPaths(String s) {
    return s
        .replaceAll(_imageUrlRe, '')
        .replaceAll(_mediaRe, '')
        .replaceAllMapped(_mdLinkRe, (m) => m.group(1) ?? '')
        .replaceAll(_urlRe, '')
        .replaceAll(_relPathRe, '')
        .replaceAll(_absPathRe, '');
  }

  /// Turn a dot between alphanumerics (file names / versions) into 点 so TTS
  /// reads "memory.md" as "memory点md" instead of spelling out the letters.
  static String protectDots(String s) => s.replaceAll(_dotRe, '点');

  /// Start index of a still-arriving URL/path/filename that runs to the end of
  /// [s] (so it must not be chunked yet), or -1 when the tail is safe to flush.
  static int inProgressTail(String s) => _tailRe.firstMatch(s)?.start ?? -1;

  static String sanitize(String text) {
    text = stripLinksAndPaths(text);
    text = protectDots(text);
    return text
        // Strip markdown inline code (often contains paths/commands)
        .replaceAllMapped(
          RegExp(r'`([^`]*)`'),
          (m) {
            final inner = m.group(1) ?? '';
            // Keep if it's plain text, drop if it looks like a path/command
            return RegExp(r'^[/~A-Za-z]:[\\/]|^[/~]').hasMatch(inner) ? '' : inner;
          },
        )
        // Strip emojis & pictographs
        .replaceAll(
          RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
              unicode: true),
          '',
        )
        // Everything not CJK/alphanumeric/space/sentence-end → soft separator
        .replaceAll(RegExp(r"[^一-鿿a-zA-Z0-9\s。！？]", unicode: true), '，')
        // Collapse any mix of whitespace and commas into single Chinese comma
        .replaceAll(RegExp(r'[\s，,]+'), '，')
        // Trim leading/trailing separators
        .replaceAll(RegExp(r'^，+|，+$'), '')
        .trim()
        // Lowercase so the engine reads "MEMORY" as a word, not letter-by-letter
        .toLowerCase();
  }


  void enqueue(String text) {
    final clean = sanitize(text);
    if (clean.isEmpty) return;
    final gen = _gen;
    final id = _nextJobId++;
    _queue.add(_TtsJob(id: id, text: clean, gen: gen));
    _ttsService.synthesize(clean).then((bytes) {
      if (gen != _gen) return;
      final idx = _queue.indexWhere((j) => j.id == id);
      if (idx != -1) _queue[idx].bytes = bytes;
      _playNext();
    }).catchError((_) {
      final idx = _queue.indexWhere((j) => j.id == id);
      if (idx != -1) _queue[idx].bytes = [];
      _playNext();
    });
  }

  void _playNext() {
    if (_isProcessing) return;
    while (_queue.isNotEmpty && _queue.first.bytes != null) {
      final job = _queue.removeAt(0);
      if (job.gen != _gen) continue;
      if (job.bytes!.isEmpty) {
        _playNext();
        return;
      }
      _isProcessing = true;
      isPlaying = true;
      isAutoPlaying = true;
      _notify();
      _playBytes(job.bytes!);
      return;
    }
    isAutoPlaying = false;
    _notify();
  }

  Future<void> _playBytes(List<int> bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(bytes);
      await _audioPlayer.play(DeviceFileSource(file.path));
      await _audioPlayer.onPlayerComplete.first;
    } catch (_) {}
    _isProcessing = false;
    isPlaying = false;
    _playNext();
  }

  Future<void> playFull(Message message) async {
    playingMessageId = message.id;
    isPlaying = true;
    _notify();
    try {
      final clean = sanitize(message.content);
      if (clean.isEmpty) return;
      final bytes = await _ttsService.synthesize(clean);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_${message.id}.mp3');
      await file.writeAsBytes(bytes);
      await _audioPlayer.play(DeviceFileSource(file.path));
      await _audioPlayer.onPlayerComplete.first;
    } catch (_) {}
    isPlaying = false;
    playingMessageId = null;
    _notify();
  }

  void stop() {
    _gen++;
    _nextJobId = 0;
    _queue.clear();
    _isProcessing = false;
    isPlaying = false;
    isAutoPlaying = false;
    playingMessageId = null;
    _audioPlayer.stop();
    _notify();
  }
}
