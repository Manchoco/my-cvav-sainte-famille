import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.details = const []});
  final String message;
  final int? status;
  final List<String> details;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => details.isEmpty ? message : '$message\n${details.join('\n')}';
}

/// Client HTTP minimal : JSON, jeton Bearer, messages d'erreur en français.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? token;
  void Function()? onUnauthorized;
  final http.Client _http = http.Client();
  // Large : un serveur gratuit (Render) peut mettre ~50 s à se réveiller.
  static const _timeout = Duration(seconds: 60);

  Uri _uri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.isNotEmpty) q[k] = v;
    });
    return Uri.parse('${AppConfig.apiUrl}/api$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, String?>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> put(String path, [Object? body]) =>
      _send(() => _http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> delete(String path) => _send(() => _http.delete(_uri(path), headers: _headers));

  Future<dynamic> upload(String path, Uint8List bytes, String fileName) {
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri(path));
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      return http.Response.fromStream(await _http.send(req));
    });
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on SocketException {
      throw ApiException('Pas de connexion internet. Vérifiez votre réseau.');
    } on TimeoutException {
      throw ApiException('Le serveur met trop de temps à répondre. Réessayez.');
    } on http.ClientException {
      throw ApiException('Impossible de joindre le serveur.');
    } on HandshakeException {
      throw ApiException('Connexion sécurisée impossible avec le serveur.');
    }
    dynamic body;
    if (res.body.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        body = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final message = body is Map && body['error'] is String ? body['error'] as String : 'Erreur ${res.statusCode}';
    final details = body is Map && body['details'] is List
        ? (body['details'] as List).map((d) => d is Map ? '${d['message']}' : '$d').toList()
        : <String>[];
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    throw ApiException(message, status: res.statusCode, details: details);
  }
}
