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
    final buffer = StringBuffer();

    channel.stream.listen(
      (data) {
        if (data is String) {
          try {
            final json = jsonDecode(data);
            if (json['status'] == 'ok') return;
            final text = json['text'] as String?;
            if (text != null && json['is_sentence_end'] == true) {
              buffer.clear();
              buffer.write(text);
            }
          } on FormatException {
            // ignore malformed
          }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.complete(buffer.isNotEmpty ? buffer.toString() : '');
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(buffer.isNotEmpty ? buffer.toString() : '');
        }
      },
      cancelOnError: true,
    );

    await for (final chunk in audioStream) {
      channel.sink.add(chunk);
    }
    channel.sink.add('BYE');

    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => buffer.isNotEmpty ? buffer.toString() : '',
    );
    await channel.sink.close();
    return result;
  }
}
