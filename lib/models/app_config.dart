import 'dart:convert';

class AppConfig {
  final String botApiStreamUrl;
  final String botApiSecret;
  final String asrTtsApiKey;
  final String ttsVoice;
  final bool ttsEnabled;

  const AppConfig({
    required this.botApiStreamUrl,
    required this.botApiSecret,
    required this.asrTtsApiKey,
    required this.ttsVoice,
    required this.ttsEnabled,
  });

  factory AppConfig.defaults() => const AppConfig(
        botApiStreamUrl: '',
        botApiSecret: '',
        asrTtsApiKey: '',
        ttsVoice: 'longyumi_v2',
        ttsEnabled: true,
      );

  bool get isComplete =>
      botApiStreamUrl.isNotEmpty &&
      botApiSecret.isNotEmpty &&
      asrTtsApiKey.isNotEmpty;

  AppConfig copyWith({
    String? botApiStreamUrl,
    String? botApiSecret,
    String? asrTtsApiKey,
    String? ttsVoice,
    bool? ttsEnabled,
  }) =>
      AppConfig(
        botApiStreamUrl: botApiStreamUrl ?? this.botApiStreamUrl,
        botApiSecret: botApiSecret ?? this.botApiSecret,
        asrTtsApiKey: asrTtsApiKey ?? this.asrTtsApiKey,
        ttsVoice: ttsVoice ?? this.ttsVoice,
        ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      );

  Map<String, dynamic> toJson() => {
        'botApiStreamUrl': botApiStreamUrl,
        'botApiSecret': botApiSecret,
        'asrTtsApiKey': asrTtsApiKey,
        'ttsVoice': ttsVoice,
        'ttsEnabled': ttsEnabled,
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        botApiStreamUrl: json['botApiStreamUrl'] as String? ?? '',
        botApiSecret: json['botApiSecret'] as String? ?? '',
        asrTtsApiKey: json['asrTtsApiKey'] as String? ?? '',
        ttsVoice: json['ttsVoice'] as String? ?? 'longyumi_v2',
        ttsEnabled: json['ttsEnabled'] as bool? ?? true,
      );
}

/// Decoded Bot-API base64 payload (subset of fields we care about).
class BotApiBase64Result {
  final String streamUrl;
  final String apiSecret;
  const BotApiBase64Result({required this.streamUrl, required this.apiSecret});
}

/// Parses a base64-encoded JSON config string from QR code or clipboard paste.
/// Returns null on any failure (invalid base64, non-JSON, missing fields).
class BotApiBase64 {
  const BotApiBase64._();

  static BotApiBase64Result? parse(String input) {
    String decoded;
    try {
      decoded = utf8.decode(base64.decode(input.trim()));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(decoded) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
    final streamUrl = json['streamUrl'] as String?;
    final apiSecret = json['apiSecret'] as String?;
    if (streamUrl == null || streamUrl.isEmpty) return null;
    if (apiSecret == null || apiSecret.isEmpty) return null;
    return BotApiBase64Result(streamUrl: streamUrl, apiSecret: apiSecret);
  }
}
