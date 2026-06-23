import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class LlmConfig {
  final String streamUrl;
  final String apiSecret;

  const LlmConfig({
    required this.streamUrl,
    required this.apiSecret,
  });
}

class LlmService {
  final LlmConfig _config;
  final Dio _dio;
  CancelToken? _cancelToken;

  LlmService({required LlmConfig config, Dio? dio})
      : _config = config,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 5),
              responseType: ResponseType.stream,
            ));

  void cancel() {
    _cancelToken?.cancel();
  }

  Stream<String> chat(String senderId, String text) async* {
    debugPrint('[LLM] chat() called, text len=${text.length}');
    // Cancel any in-flight request before starting a new one
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    final cancelToken = _cancelToken!;

    Response<ResponseBody> response;
    try {
      debugPrint('[LLM] sending POST...');
      response = await _dio.post<ResponseBody>(
        _config.streamUrl,
        data: {'senderId': senderId, 'text': text},
        options: Options(
          headers: {'Authorization': 'Bearer ${_config.apiSecret}'},
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
      debugPrint('[LLM] POST response status=${response.statusCode}');
    } on DioException catch (e) {
      debugPrint('[LLM] DioException: type=${e.type}, isCancel=${CancelToken.isCancel(e)}');
      if (CancelToken.isCancel(e)) return;
      rethrow;
    }

    if (response.statusCode != 200) {
      debugPrint('[LLM] non-200 status: ${response.statusCode}');
      throw HttpException('LLM API error: ${response.statusCode}');
    }

    final stream = response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    int tokenCount = 0;
    try {
      await for (final line in stream) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') {
          debugPrint('[LLM] [DONE] after $tokenCount tokens');
          break;
        }
        if (data.isEmpty) continue;

        try {
          final chunk = jsonDecode(data);
          final choices = chunk['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            tokenCount++;
            yield content;
          }
        } on FormatException {
          continue;
        }
      }
      debugPrint('[LLM] stream ended, total tokens=$tokenCount');
    } on DioException catch (e) {
      debugPrint('[LLM] stream DioException: type=${e.type}, isCancel=${CancelToken.isCancel(e)}');
      if (CancelToken.isCancel(e)) return;
      rethrow;
    }
  }

  void dispose() {
    _cancelToken?.cancel();
    _dio.close(force: true);
  }
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
