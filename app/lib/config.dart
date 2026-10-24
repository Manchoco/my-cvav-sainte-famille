import 'package:shared_preferences/shared_preferences.dart';

/// Adresse de l'API. Valeur par défaut fixée à la compilation :
///   flutter build apk --dart-define=API_URL=https://mon-api.exemple.com
/// et modifiable dans l'application (appui long sur le logo de l'écran d'accueil).
class AppConfig {
  static const String defaultApiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://my-cvav-api.onrender.com',
  );
  static const _key = 'api_url';
  static String apiUrl = defaultApiUrl;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString(_key) ?? defaultApiUrl;
  }

  static Future<void> setApiUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    if (cleaned.isEmpty || cleaned == defaultApiUrl) {
      await prefs.remove(_key);
      apiUrl = defaultApiUrl;
    } else {
      await prefs.setString(_key, cleaned);
      apiUrl = cleaned;
    }
  }
}
