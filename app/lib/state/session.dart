import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../models.dart';

/// Informations publiées par l'administrateur : maintenance et mises à jour de l'application.
class AppStatus {
  AppStatus({this.maintenance = false, this.maintenanceMessage = '', this.latestBuild = 0, this.minBuild = 0, this.updateUrl = '', this.updateNotes = ''});

  final bool maintenance;
  final String maintenanceMessage;
  final int latestBuild;
  final int minBuild;
  final String updateUrl;
  final String updateNotes;

  bool get updateRequired => minBuild > AppConfig.appBuild && updateUrl.isNotEmpty;
  bool get updateAvailable => latestBuild > AppConfig.appBuild && updateUrl.isNotEmpty;

  factory AppStatus.fromMeta(Map<String, dynamic> j) {
    final m = (j['maintenance'] as Map?) ?? const {};
    final u = (j['appUpdate'] as Map?) ?? const {};
    return AppStatus(
      maintenance: m['enabled'] == true,
      maintenanceMessage: (m['message'] as String?) ?? '',
      latestBuild: (u['latestBuild'] as num?)?.toInt() ?? 0,
      minBuild: (u['minBuild'] as num?)?.toInt() ?? 0,
      updateUrl: (u['url'] as String?) ?? '',
      updateNotes: (u['notes'] as String?) ?? '',
    );
  }
}

/// Session utilisateur : jeton stocké dans le Keystore Android (flutter_secure_storage).
class Session extends ChangeNotifier {
  Session() {
    final api = ApiClient.instance;
    api.onUnauthorized = () => logout(expired: true);
    api.onMaintenance = (message) {
      status = AppStatus(maintenance: true, maintenanceMessage: message);
      notifyListeners();
    };
    api.onPasswordChangeRequired = () {
      final u = user;
      if (u != null && !u.mustChangePassword) {
        user = User(id: u.id, role: u.role, fullName: u.fullName, phone: u.phone, legion: u.legion, mustChangePassword: true);
        notifyListeners();
      }
    };
  }

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'token';
  static const _userKey = 'user';

  User? user;
  bool ready = false;
  bool expired = false;
  AppStatus status = AppStatus();

  bool get isLoggedIn => user != null;

  /// Maintenance bloquante pour tout le monde sauf l'administrateur.
  bool get blockedByMaintenance => status.maintenance && !(user?.isAdmin ?? false);

  Future<void> restore() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final userJson = await _storage.read(key: _userKey);
      if (token != null && userJson != null) {
        ApiClient.instance.token = token;
        user = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        // Rafraîchit le profil en arrière-plan ; un 401 déclenche la déconnexion.
        refreshProfile();
      }
    } catch (_) {
      await _storage.deleteAll();
    }
    await refreshStatus();
    ready = true;
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    try {
      final meta = await ApiClient.instance.get('/meta');
      status = AppStatus.fromMeta(meta as Map<String, dynamic>);
      notifyListeners();
    } on ApiException catch (_) {
      // Hors ligne : on garde l'état connu.
    }
  }

  Future<void> refreshProfile() async {
    try {
      final res = await ApiClient.instance.get('/auth/me');
      await _storeUser(User.fromJson(res['user'] as Map<String, dynamic>));
    } on ApiException catch (_) {
      // Hors ligne : on garde la session locale.
    }
  }

  Future<void> _storeUser(User u) async {
    user = u;
    await _storage.write(key: _userKey, value: jsonEncode(u.toJson()));
    notifyListeners();
  }

  Future<void> _save(Map<String, dynamic> res) async {
    final token = res['token'] as String;
    ApiClient.instance.token = token;
    expired = false;
    await _storage.write(key: _tokenKey, value: token);
    await _storeUser(User.fromJson(res['user'] as Map<String, dynamic>));
  }

  Future<void> login(String phone, String password) async {
    final res = await ApiClient.instance.post('/auth/login', {'phone': phone, 'password': password});
    await _save(res as Map<String, dynamic>);
    await refreshStatus();
  }

  Future<void> register({
    required String role,
    required String fullName,
    required String phone,
    required String password,
    Legion? legion,
    String? signupCode,
  }) async {
    final res = await ApiClient.instance.post('/auth/register', {
      'role': role,
      'fullName': fullName,
      'phone': phone,
      'password': password,
      if (legion != null) 'legion': legion.name,
      if (signupCode != null && signupCode.isNotEmpty) 'signupCode': signupCode,
    });
    await _save(res as Map<String, dynamic>);
  }

  Future<void> requestPasswordReset(String phone) => ApiClient.instance.post('/auth/password/forgot', {'phone': phone});

  Future<void> resetPassword(String phone, String code, String newPassword) async {
    final res = await ApiClient.instance.post('/auth/password/reset', {'phone': phone, 'code': code, 'newPassword': newPassword});
    await _save(res as Map<String, dynamic>);
  }

  Future<void> changePassword(String current, String next) async {
    final res = await ApiClient.instance.post('/auth/password', {'currentPassword': current, 'newPassword': next});
    await _save(res as Map<String, dynamic>);
  }

  Future<void> updateProfile({String? fullName, String? phone, required String currentPassword}) async {
    final res = await ApiClient.instance.put('/auth/me', {
      'fullName': ?fullName,
      'phone': ?phone,
      'currentPassword': currentPassword,
    });
    await _storeUser(User.fromJson(res['user'] as Map<String, dynamic>));
  }

  Future<void> logout({bool expired = false}) async {
    this.expired = expired;
    user = null;
    ApiClient.instance.token = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    notifyListeners();
  }
}
