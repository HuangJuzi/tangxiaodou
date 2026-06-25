import 'dart:typed_data';
import 'dart:math' show sqrt;

/// True if [bytes] starts with a RIFF/WAVE header.
bool isWav(List<int> bytes) {
  if (bytes.length < 12) return false;
  // 'RIFF' .... 'WAVE'
  return bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45;
}

class _WavPcm {
  final int sampleRate;
  final Int16List samples;
  _WavPcm(this.sampleRate, this.samples);
}

/// Parses a 16-bit mono PCM WAV, returning sample rate + int16 samples.
/// Returns null for anything else (non-WAV, stereo, 8/24/32-bit, etc.).
_WavPcm? _parsePcm16Mono(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (data.length < 12) return null;
  final bd = ByteData.sublistView(data);
  int off = 12; // first chunk starts after the 12-byte RIFF header
  int? sampleRate, bitsPerSample, channels, dataStart, dataLen;
  while (off + 8 <= data.length) {
    final id = String.fromCharCodes(data.sublist(off, off + 4));
    final size = bd.getUint32(off + 4, Endian.little);
    final bodyStart = off + 8;
    if (id == 'fmt ' && bodyStart + 16 <= data.length) {
      channels = bd.getUint16(bodyStart + 2, Endian.little);
      sampleRate = bd.getUint32(bodyStart + 4, Endian.little);
      bitsPerSample = bd.getUint16(bodyStart + 14, Endian.little);
    } else if (id == 'data') {
      dataStart = bodyStart;
      dataLen = size;
    }
    off = bodyStart + size + (size & 1); // chunks are word-aligned
  }
  if (sampleRate == null || bitsPerSample != 16 || channels != 1 ||
      dataStart == null || dataLen == null) {
    return null;
  }
  final wanted = dataLen ~/ 2;
  final available = (data.length - dataStart) ~/ 2;
  final count = wanted < available ? wanted : available;
  final samples = Int16List(count);
  final sampleBd = ByteData.sublistView(data, dataStart, dataStart + count * 2);
  for (int i = 0; i < count; i++) {
    samples[i] = sampleBd.getInt16(i * 2, Endian.little);
  }
  return _WavPcm(sampleRate, samples);
}

/// Target RMS for 16-bit mono speech (~-17 dBFS). Tuned for a comfortably
/// loud, non-clipping toddler-facing voice. Pure consistency is the goal —
/// any fixed value here flattens the "sometimes loud, sometimes quiet" swings.
const int _targetRms = 4500;
const double _maxGain = 8.0;
const double _minGain = 0.15;
const int _clipCeiling = 32000; // leave headroom below full-scale 32767

/// Normalize a 16-bit mono WAV to a fixed target loudness so every chunk
/// plays at a consistent perceived volume. Returns the original [bytes]
/// unchanged if it isn't a normalizable WAV (caller should then play as-is).
List<int> normalizeWav(List<int> bytes) {
  final pcm = _parsePcm16Mono(bytes);
  if (pcm == null || pcm.samples.isEmpty) return bytes;
  final s = pcm.samples;
  double sumSq = 0;
  int peak = 1;
  for (final v in s) {
    final av = v < 0 ? -v : v;
    if (av > peak) peak = av;
    sumSq += (v * v).toDouble();
  }
  final meanSq = sumSq / s.length;
  final rms = meanSq > 0 ? sqrt(meanSq) : 1.0;
  double gain = _targetRms / rms;
  if (gain < _minGain) gain = _minGain;
  if (gain > _maxGain) gain = _maxGain;
  // Never let gain push peaks into clipping.
  if (peak * gain > _clipCeiling) {
    gain = _clipCeiling / peak;
  }
  final out = Int16List(s.length);
  for (int i = 0; i < s.length; i++) {
    final scaled = (s[i] * gain).round();
    if (scaled > 32767) {
      out[i] = 32767;
    } else if (scaled < -32768) {
      out[i] = -32768;
    } else {
      out[i] = scaled;
    }
  }
  return _buildWav(pcm.sampleRate, out);
}

/// Rebuilds a minimal 44-byte-header 16-bit mono PCM WAV from samples.
List<int> _buildWav(int sampleRate, Int16List samples) {
  final dataSize = samples.length * 2;
  final out = Uint8List(44 + dataSize);
  final bd = ByteData.sublistView(out);
  // 'RIFF'
  out[0] = 0x52; out[1] = 0x49; out[2] = 0x46; out[3] = 0x46;
  bd.setUint32(4, 36 + dataSize, Endian.little);
  // 'WAVE'
  out[8] = 0x57; out[9] = 0x41; out[10] = 0x56; out[11] = 0x45;
  // 'fmt '
  out[12] = 0x66; out[13] = 0x6d; out[14] = 0x74; out[15] = 0x20;
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);            // PCM
  bd.setUint16(22, 1, Endian.little);            // mono
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bd.setUint16(32, 2, Endian.little);            // block align
  bd.setUint16(34, 16, Endian.little);           // bits per sample
  // 'data'
  out[36] = 0x64; out[37] = 0x61; out[38] = 0x74; out[39] = 0x61;
  bd.setUint32(40, dataSize, Endian.little);
  for (int i = 0; i < samples.length; i++) {
    bd.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return out;
}
