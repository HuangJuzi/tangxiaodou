import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LlmConfig {
  final String baseUrl;
  final String accountId;
  final String apiSecret;

  const LlmConfig({
    required this.baseUrl,
    required this.accountId,
    required this.apiSecret,
  });

  String get streamUrl => '$baseUrl/bot-api/v2/$accountId/chat-stream';
}

class LlmService {
  final LlmConfig _config;
  final http.Client _client;

  LlmService({required LlmConfig config, http.Client? client})
      : _config = config,
        _client = client ?? http.Client();

  Stream<String> chat(String senderId, String text) async* {
    final request = http.Request('POST', Uri.parse(_config.streamUrl));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer ${_config.apiSecret}';
    request.body = jsonEncode({'senderId': senderId, 'text': text});

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw HttpException('LLM API error: ${response.statusCode}');
    }

    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;
      if (data.isEmpty) continue;

      try {
        final chunk = jsonDecode(data);
        final choices = chunk['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield content;
        }
      } on FormatException {
        continue;
      }
    }
  }

  void dispose() {
    _client.close();
  }
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
