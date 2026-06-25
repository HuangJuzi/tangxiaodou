import 'dart:typed_data';
import 'dart:math' show sqrt, sin, pi;
import 'package:flutter_test/flutter_test.dart';
import 'package:tangxiaodou/services/wav_normalize.dart';

/// Build a 16-bit mono PCM WAV with a full-scale sine wave of given amplitude
/// and duration, so the RMS is known and deterministic.
Uint8List _buildSineWav({
  required int sampleRate,
  required double amplitude,
  required double seconds,
  required double freq,
}) {
  final n = (sampleRate * seconds).round();
  final samples = Int16List(n);
  for (int i = 0; i < n; i++) {
    samples[i] = (amplitude * sin(2 * pi * freq * i / sampleRate)).round();
  }
  // Build a 44-byte-header WAV.
  final out = Uint8List(44 + n * 2);
  final bd = ByteData.sublistView(out);
  out[0] = 0x52; out[1] = 0x49; out[2] = 0x46; out[3] = 0x46;
  bd.setUint32(4, 36 + n * 2, Endian.little);
  out[8] = 0x57; out[9] = 0x41; out[10] = 0x56; out[11] = 0x45;
  out[12] = 0x66; out[13] = 0x6d; out[14] = 0x74; out[15] = 0x20;
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  out[36] = 0x64; out[37] = 0x61; out[38] = 0x74; out[39] = 0x61;
  bd.setUint32(40, n * 2, Endian.little);
  for (int i = 0; i < n; i++) {
    bd.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return out;
}

void main() {
  test('isWav detects RIFF/WAVE header', () {
    expect(isWav([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]), isTrue);
    expect(isWav([0x49, 0x44, 0x33, 0x03]), isFalse); // MP3 ID3
    expect(isWav([]), isFalse);
  });

  test('normalizeWav scales a quiet WAV up toward target RMS', () {
    // amplitude 5000 -> RMS ~ 5000/sqrt(2) ~ 3535 (well below target 4500)
    final wav = _buildSineWav(sampleRate: 16000, amplitude: 5000, seconds: 1.0, freq: 220.0);
    final out = normalizeWav(wav);
    expect(isWav(out), isTrue);
    // Parse output RMS.
    final data = out is Uint8List ? out : Uint8List.fromList(out);
    final bd = ByteData.sublistView(data);
    final dataLen = bd.getUint32(40, Endian.little);
    final n = dataLen ~/ 2;
    double sumSq = 0;
    int peak = 0;
    for (int i = 0; i < n; i++) {
      final v = bd.getInt16(44 + i * 2, Endian.little);
      sumSq += v * v;
      final av = v < 0 ? -v : v;
      if (av > peak) peak = av;
    }
    final rms = sqrt(sumSq / n);
    // Normalized RMS should be close to the 4500 target (gain was applied, not
    // peak-limited since the source is quiet).
    expect(rms, closeTo(4500, 300));
    expect(peak, lessThan(32768));
  });

  test('normalizeWav scales a loud WAV down toward target RMS', () {
    // amplitude 32000 -> RMS ~ 22627 (well above target) -> gain < 1
    final wav = _buildSineWav(sampleRate: 16000, amplitude: 32000, seconds: 1.0, freq: 220.0);
    final out = normalizeWav(wav);
    final data = out is Uint8List ? out : Uint8List.fromList(out);
    final bd = ByteData.sublistView(data);
    final n = bd.getUint32(40, Endian.little) ~/ 2;
    double sumSq = 0;
    for (int i = 0; i < n; i++) {
      final v = bd.getInt16(44 + i * 2, Endian.little);
      sumSq += v * v;
    }
    final rms = sqrt(sumSq / n);
    expect(rms, closeTo(4500, 300));
  });

  test('normalizeWav leaves non-WAV bytes untouched', () {
    final mp3 = [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00];
    expect(normalizeWav(mp3), same(mp3));
  });
}
