import 'dart:convert';
import 'package:http/http.dart' as http;

class TtsService {
  final String _apiKey;
  final String _voice;
  static const _url = 'https://www.sophnet.com/api/open-apis/projects/easyllms/voice/synthesize-audio';

  TtsService({required String apiKey, String voice = 'longjiqi'})
      : _apiKey = apiKey,
        _voice = voice;

  Future<List<int>> synthesize(String text) async {
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
          'voice': _voice,
          'format': 'MP3_16000HZ_MONO_128KBPS',
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
