import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/app_config.dart';

class SettingsService extends ChangeNotifier {
  static const _storageKey = 'app_config';
  final FlutterSecureStorage _storage;

  AppConfig? _config;
  AppConfig? get config => _config;

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        _config = AppConfig.fromJson(decoded as Map<String, dynamic>);
      } else {
        _config = null;
      }
    } on FormatException {
      _config = null;
    } catch (e) {
      debugPrint('[Settings] load error: $e');
      _config = null;
    }
    notifyListeners();
  }

  Future<void> save(AppConfig cfg) async {
    _config = cfg;
    await _storage.write(key: _storageKey, value: jsonEncode(cfg.toJson()));
    notifyListeners();
  }
}
