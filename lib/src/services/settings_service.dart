import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class SettingsService {
  static const String _kSettingsKey = 'app_settings';

  static Future<AppSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kSettingsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(jsonStr) as Map<String, dynamic>;
        return AppSettings.fromJson(data);
      }
    } catch (_) {}
    return AppSettings.defaults();
  }

  static Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettingsKey, jsonEncode(settings.toJson()));
  }

  static Future<String> exportSettingsJson(AppSettings settings) async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(settings.toJson());
  }

  static AppSettings importSettingsJson(String jsonString) {
    final Map<String, dynamic> data = jsonDecode(jsonString) as Map<String, dynamic>;
    return AppSettings.fromJson(data);
  }
}
