import 'dart:convert';
import 'package:http/http.dart' as http;
import 'wav_normalize.dart';

class TtsService {
  final String _apiKey;
  static const _url = 'https://www.sophnet.com/api/open-apis/projects/easyllms/voice/synthesize-audio';

  // WAV lets the client normalize loudness per chunk (see TtsPlayer). MP3 is
  // the fallback if the API ever stops honoring the WAV format string.
  static const _wavFormat = 'WAV_16000HZ_MONO_16BIT';
  static const _mp3Format = 'MP3_16000HZ_MONO_128KBPS';

  String _format = _wavFormat;
  bool _probed = false;

  TtsService({required String apiKey, String voice = 'longjiqi'})
      : _apiKey = apiKey,
        voice = voice;

  String voice;

  Future<List<int>> synthesize(String text) async {
    if (!_probed) {
      // First call: probe WAV. If it returns a real WAV header, lock it in.
      try {
        final bytes = await _synth(text, _wavFormat);
        if (isWav(bytes)) {
          _probed = true;
          return bytes;
        }
      } catch (_) {
        // fall through to MP3
      }
      _probed = true;
      _format = _mp3Format;
      return _synth(text, _mp3Format);
    }
    return _synth(text, _format);
  }

  Future<List<int>> _synth(String text, String format) async {
    final response = await http.post(
      Uri.parse(_url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'text': [text],
        'synthesis_param': {
          'model': 'cosyvoice-v2',
          'voice': voice,
          'format': format,
          'volume': 80,
          'speechRate': 1.0,
          'pitchRate': 1,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('TTS API error: ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}

const Map<String, String> ttsVoices = {
  '呆萌机器人': 'longjiqi',
  '优雅知性女': 'longanwen',
  '居家暖男': 'longanyun',
  '正经青年女': 'longyumi_v2',
  '知性积极女': 'longxiaochun_v2',
  '沉稳权威女声': 'longxiaoxia_v2',
  '沉稳青年男': 'longshu_v2',
  '精准干练女': 'loongbella_v2',
  '博才干练男': 'longshuo_v2',
  '沉稳播报女': 'longxiaobai_v2',
};
