import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class AsrService {
  final String _apiKey;
  static const _url = 'wss://www.sophnet.com/api/open-apis/projects/easyllms/stream-speech';

  AsrService({required String apiKey}) : _apiKey = apiKey;

  Future<String> recognize(Stream<List<int>> audioStream, {String format = 'pcm', int sampleRate = 16000}) async {
    final wsUrl = Uri.parse('$_url?apikey=$_apiKey&format=$format&sample_rate=$sampleRate&heartbeat=true');
    final channel = WebSocketChannel.connect(wsUrl);

    final completer = Completer<String>();
    String lastText = '';

    channel.stream.listen(
      (data) {
        if (data is String) {
          try {
            final json = jsonDecode(data);
            if (json['status'] == 'ok') return;
            final text = json['text'] as String?;
            if (text != null && text.isNotEmpty) {
              lastText = text;
            }
            if (json['is_sentence_end'] == true) {
              if (!completer.isCompleted) {
                completer.complete(lastText);
              }
            }
          } on FormatException {
            // ignore
          }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.complete(lastText.isNotEmpty ? lastText : '');
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(lastText.isNotEmpty ? lastText : '');
        }
      },
      cancelOnError: true,
    );

    await for (final chunk in audioStream) {
      // Send in small chunks like streaming audio
      const chunkSize = 3200;
      for (var i = 0; i < chunk.length; i += chunkSize) {
        final end = (i + chunkSize < chunk.length) ? i + chunkSize : chunk.length;
        channel.sink.add(chunk.sublist(i, end));
      }
    }
    channel.sink.add('BYE');

    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => lastText,
    );
    await channel.sink.close();
    return result;
  }
}
