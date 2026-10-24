import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../models.dart';

/// Session utilisateur : jeton stocké dans le Keystore Android (flutter_secure_storage).
class Session extends ChangeNotifier {
  Session() {
    ApiClient.instance.onUnauthorized = () => logout(expired: true);
  }

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'token';
  static const _userKey = 'user';

  User? user;
  bool ready = false;
  bool expired = false;

  bool get isLoggedIn => user != null;

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
    ready = true;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    try {
      final res = await ApiClient.instance.get('/auth/me');
      user = User.fromJson(res['user'] as Map<String, dynamic>);
      await _storage.write(key: _userKey, value: jsonEncode(user!.toJson()));
      notifyListeners();
    } on ApiException catch (_) {
      // Hors ligne : on garde la session locale.
    }
  }

  Future<void> _save(Map<String, dynamic> res) async {
    final token = res['token'] as String;
    user = User.fromJson(res['user'] as Map<String, dynamic>);
    ApiClient.instance.token = token;
    expired = false;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user!.toJson()));
    notifyListeners();
  }

  Future<void> login(String phone, String password) async {
    final res = await ApiClient.instance.post('/auth/login', {'phone': phone, 'password': password});
    await _save(res as Map<String, dynamic>);
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

  Future<void> changePassword(String current, String next) async {
    final res = await ApiClient.instance.post('/auth/password', {'currentPassword': current, 'newPassword': next});
    final token = res['token'] as String;
    ApiClient.instance.token = token;
    await _storage.write(key: _tokenKey, value: token);
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
