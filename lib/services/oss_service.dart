import 'dart:convert';
import 'package:http/http.dart' as http;

class OssService {
  static const _url = 'https://www.sophnet.com/api/open-apis/projects/upload';

  final String apiKey;
  OssService({required this.apiKey});

  /// Uploads [filePath] to SophNet OSS and returns the signed short URL,
  /// or null on failure.
  Future<String?> upload(String filePath) async {
    final req = http.MultipartRequest('POST', Uri.parse(_url));
    req.headers['Authorization'] = 'Bearer $apiKey';
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final resp = await req.send();
    if (resp.statusCode != 200) return null;
    final body = await resp.stream.bytesToString();
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final result = json['result'];
      if (result is Map<String, dynamic>) {
        return result['shortUrl'] as String?;
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
