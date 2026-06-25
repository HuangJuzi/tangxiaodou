import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import 'tts_service.dart';
import 'wav_normalize.dart';

/// Minimal audio playback surface TtsPlayer depends on. Decouples it from
/// `audioplayers` so the play loop can be faked in tests.
abstract class TtsAudioSink {
  Future<void> setVolume(double volume);
  Future<void> playFile(String path);
  Future<void> stop();
  Stream<void> get onComplete;
}

/// Wraps a real `AudioPlayer` as a [TtsAudioSink].
class AudioPlayerSink implements TtsAudioSink {
  final AudioPlayer _player;
  AudioPlayerSink(this._player);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> playFile(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;
}

class _TtsJob {
  final int id;
  final String text;
  final int gen;
  List<int>? bytes;
  bool synthDone = false;
  _TtsJob({required this.id, required this.text, required this.gen});
}

class TtsPlayer extends ChangeNotifier {
  final TtsService _ttsService;
  final TtsAudioSink _sink;

  final List<_TtsJob> _queue = [];
  int _gen = 0;
  int _nextJobId = 0;
  bool _isProcessing = false;   // playback in progress
  bool _isSynthesizing = false; // synthesis in progress (at most one at a time)

  bool isPlaying = false;
  bool isAutoPlaying = false;
  String? playingMessageId;

  TtsPlayer({
    required TtsService ttsService,
    required TtsAudioSink sink,
  })  : _ttsService = ttsService,
        _sink = sink;

  void _notify() => notifyListeners();

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


  /// Enqueue a streamed chunk for synthesis + playback. Synthesis is serialized
  /// (at most one request in flight) with one-ahead prefetch, so the Sophnet
  /// API is never hit concurrently — concurrent requests return empty 200s
  /// and would silently drop the chunk. See [TtsService] for the API quirk.
  void enqueue(String text) {
    final clean = sanitize(text);
    if (clean.isEmpty) return;
    final gen = _gen;
    final id = _nextJobId++;
    _queue.add(_TtsJob(id: id, text: clean, gen: gen));
    _pumpSynth();
  }

  /// Synthesize the first not-yet-synthesized job, one at a time. Called after
  /// enqueue and after each synthesis completes (to prefetch the next chunk
  /// while the current one plays).
  void _pumpSynth() {
    if (_isSynthesizing) return;
    for (final job in _queue) {
      if (job.gen != _gen) continue;
      if (job.synthDone) continue;
      _isSynthesizing = true;
      _synthesizeJob(job);
      return;
    }
  }

  Future<void> _synthesizeJob(_TtsJob job) async {
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      // Stopped or superseded mid-synthesis — abandon without side effects.
      if (job.gen != _gen) break;
      try {
        final bytes = await _ttsService.synthesize(job.text);
        // The API sometimes returns HTTP 200 with an empty body under load.
        // Treat that as a transient failure and retry rather than dropping
        // the chunk silently.
        if (bytes.isNotEmpty) {
          job.bytes = bytes;
          break;
        }
        debugPrint('[TTS] synth empty (attempt $attempt) job=${job.id} "${job.text}"');
      } catch (e) {
        debugPrint('[TTS] synth error (attempt $attempt) job=${job.id}: $e');
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
    if (job.bytes == null) {
      debugPrint('[TTS] DROP job=${job.id} "${job.text}" (gave up after $maxAttempts attempts)');
      job.bytes = const [];
    }
    job.synthDone = true;
    _isSynthesizing = false;
    _playNext();
    _pumpSynth(); // prefetch next chunk while this one plays
  }

  void _playNext() {
    if (_isProcessing) return;
    while (_queue.isNotEmpty && _queue.first.bytes != null) {
      final job = _queue.removeAt(0);
      if (job.gen != _gen) continue;
      if (job.bytes!.isEmpty) continue; // failed synth — already logged, skip
      _isProcessing = true;
      isPlaying = true;
      isAutoPlaying = true;
      _notify();
      _playBytes(job.bytes!);
      return;
    }
    // Nothing playable right now. Only signal idle when the queue is fully
    // drained (no pending synthesis) so the UI doesn't flicker between chunks.
    if (_queue.isEmpty && !_isSynthesizing) {
      isAutoPlaying = false;
      isPlaying = false;
      _notify();
    }
  }

  Future<void> _playBytes(List<int> bytes) async {
    try {
      // Normalize loudness per chunk so every sentence plays at a consistent
      // volume. Only WAV bytes can be normalized; MP3 falls through as-is.
      final wav = isWav(bytes);
      final playBytes = wav ? normalizeWav(bytes) : bytes;
      final ext = wav ? 'wav' : 'mp3';
      debugPrint('[TTS] play ${playBytes.length}B ext=$wav');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(playBytes);
      await _sink.setVolume(1.0);
      await _sink.playFile(file.path);
      await _sink.onComplete.first;
    } catch (e) {
      debugPrint('[TTS] play error: $e');
    }
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
      final wav = isWav(bytes);
      final playBytes = wav ? normalizeWav(bytes) : bytes;
      final ext = wav ? 'wav' : 'mp3';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_${message.id}.$ext');
      await file.writeAsBytes(playBytes);
      await _sink.setVolume(1.0);
      await _sink.playFile(file.path);
      await _sink.onComplete.first;
    } catch (e) {
      debugPrint('[TTS] playFull error: $e');
    }
    isPlaying = false;
    playingMessageId = null;
    _notify();
  }

  void stop() {
    _gen++;
    _nextJobId = 0;
    _queue.clear();
    _isProcessing = false;
    _isSynthesizing = false;
    isPlaying = false;
    isAutoPlaying = false;
    playingMessageId = null;
    _sink.stop();
    _notify();
  }
}
