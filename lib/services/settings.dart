import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const _kApiKey = 'anthropic_api_key';
  static const _kModel = 'model';
  static const _kMaxTokens = 'max_tokens';
  static const _kDebugEnabled = 'debug_enabled';
  static const _kDebugToken = 'debug_token';
  static const _kDebugPort = 'debug_port';

  static const defaultModel = 'claude-sonnet-4-6';
  static const defaultMaxTokens = 4096;
  static const defaultDebugPort = 8080;

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

  static Future<bool> getDebugEnabled() async {
    await _ensure();
    return _prefs!.getBool(_kDebugEnabled) ?? false;
  }

  static Future<void> setDebugEnabled(bool v) async {
    await _ensure();
    await _prefs!.setBool(_kDebugEnabled, v);
  }

  static Future<String> getDebugToken() async {
    await _ensure();
    var t = _prefs!.getString(_kDebugToken) ?? '';
    if (t.isEmpty) {
      final r = DateTime.now().microsecondsSinceEpoch;
      t = 'tok_${r.toRadixString(36)}';
      await _prefs!.setString(_kDebugToken, t);
    }
    return t;
  }

  static Future<void> setDebugToken(String v) async {
    await _ensure();
    await _prefs!.setString(_kDebugToken, v);
  }

  static Future<int> getDebugPort() async {
    await _ensure();
    return _prefs!.getInt(_kDebugPort) ?? defaultDebugPort;
  }

  static Future<void> setDebugPort(int v) async {
    await _ensure();
    await _prefs!.setInt(_kDebugPort, v);
  }
}
