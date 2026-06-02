import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';

class ConfigStore {
  static const _key = 'arzu_code_config_v2';

  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      final oldRaw = prefs.getString('arzu_code_config_v1');
      if (oldRaw != null) {
        try {
          return AppConfig.fromJson(jsonDecode(oldRaw) as Map<String, dynamic>);
        } catch (_) {}
      }
      return const AppConfig();
    }
    try {
      return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppConfig();
    }
  }

  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}