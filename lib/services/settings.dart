import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const _kApiKey = 'anthropic_api_key';
  static const _kModel = 'model';
  static const _kMaxTokens = 'max_tokens';

  static const defaultModel = 'claude-sonnet-4-6';
  static const defaultMaxTokens = 4096;

  static SharedPreferences? _prefs;

  static Future<void> _ensure() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<String> getApiKey() async {
    await _ensure();
    return _prefs!.getString(_kApiKey) ?? '';
  }

  static Future<void> setApiKey(String v) async {
    await _ensure();
    await _prefs!.setString(_kApiKey, v);
  }

  static Future<String> getModel() async {
    await _ensure();
    return _prefs!.getString(_kModel) ?? defaultModel;
  }

  static Future<void> setModel(String v) async {
    await _ensure();
    await _prefs!.setString(_kModel, v);
  }

  static Future<int> getMaxTokens() async {
    await _ensure();
    return _prefs!.getInt(_kMaxTokens) ?? defaultMaxTokens;
  }

  static Future<void> setMaxTokens(int v) async {
    await _ensure();
    await _prefs!.setInt(_kMaxTokens, v);
  }
}
