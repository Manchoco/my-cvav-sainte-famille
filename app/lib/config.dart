import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adresse de l'API. Valeur par défaut fixée à la compilation :
///   flutter build apk --dart-define=API_URL=https://mon-api.exemple.com
/// et modifiable dans l'application (appui long sur le logo de l'écran d'accueil).
class AppConfig {
  static const String defaultApiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://my-cvav-sainte-famille-api-mamadoudibate-5976.vercel.app',
  );
  /// Numéro de build de cet APK (fourni par la compilation, cf. pubspec.yaml), pour les mises à jour.
  static const int appBuild = int.fromEnvironment('APP_BUILD', defaultValue: 2);
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.1.0');

  /// Changer de serveur n'est possible qu'en développement : en production, un tiers ne peut pas
  /// faire pointer l'application vers un faux serveur pour récupérer des mots de passe.
  static bool get canChangeServer => kDebugMode;

  static const _key = 'api_url';
  static String apiUrl = defaultApiUrl;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = canChangeServer ? (prefs.getString(_key) ?? defaultApiUrl) : defaultApiUrl;
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
