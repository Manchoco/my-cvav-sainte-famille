import 'dart:typed_data';

import '../models.dart';
import 'api_client.dart';

/// Accès typé aux endpoints de l'API.
class Repo {
  static final _api = ApiClient.instance;

  // ----- Responsable -----
  static Future<Map<String, dynamic>> stats() async => (await _api.get('/stats')) as Map<String, dynamic>;

  static Future<List<Child>> children({Legion? legion, String? q}) async {
    final res = await _api.get('/children', query: {'legion': legion?.name, 'q': q});
    return (res['children'] as List).map((j) => Child.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<Child> saveChild(Map<String, dynamic> data, {int? id}) async {
    final res = id == null ? await _api.post('/children', data) : await _api.put('/children/$id', data);
    return Child.fromJson(res['child'] as Map<String, dynamic>);
  }

  static Future<void> deleteChild(int id) => _api.delete('/children/$id');

  static Future<Child> regenerateCode(int id) async =>
      Child.fromJson((await _api.post('/children/$id/regenerate-code'))['child'] as Map<String, dynamic>);

  static Future<List<ImportRow>> importPreview(Uint8List bytes, String name) async {
    final res = await _api.upload('/children/import/preview', bytes, name);
    return (res['children'] as List).map((j) => ImportRow.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<Map<String, dynamic>> importCommit(List<ImportRow> rows, {bool skipDuplicates = true}) async =>
      (await _api.post('/children/import/commit', {
        'children': rows.map((r) => r.toJson()).toList(),
        'skipDuplicates': skipDuplicates,
      })) as Map<String, dynamic>;

  static Future<List<EventItem>> events({String? kind}) async {
    final res = await _api.get('/events', query: {'kind': kind});
    return (res['events'] as List).map((j) => EventItem.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<EventItem> createEvent({required String kind, required String name, String? date, int? price}) async {
    final res = await _api.post('/events', {'kind': kind, 'name': name, 'date': date, 'price': price});
    return EventItem.fromJson(res['event'] as Map<String, dynamic>);
  }

  static Future<EventItem> updateEvent(int id, Map<String, dynamic> data) async =>
      EventItem.fromJson((await _api.put('/events/$id', data))['event'] as Map<String, dynamic>);

  static Future<void> deleteEvent(int id) => _api.delete('/events/$id');

  static Future<List<AttendanceEntry>> attendance(int eventId) async {
    final res = await _api.get('/events/$eventId/attendance');
    return (res['entries'] as List).map((j) => AttendanceEntry.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<void> saveAttendance(int eventId, Map<int, String?> changes) => _api.put('/events/$eventId/attendance', {
        'entries': [for (final e in changes.entries) {'childId': e.key, 'status': e.value}],
      });

  static Future<List<Due>> dues() async {
    final res = await _api.get('/dues');
    return (res['dues'] as List).map((j) => Due.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<void> setDueAmount(int id, int? amount) => _api.put('/dues/$id', {'amount': amount});

  /// Prix par légion (vide = non fixé pour cette légion).
  static Future<void> setDueAmounts(int id, Map<Legion, int?> amounts) =>
      _api.put('/dues/$id', {'amounts': {for (final l in Legion.values) l.name: amounts[l]}});

  static Future<(Due, List<PaymentEntry>)> payments(int dueId) async {
    final res = await _api.get('/dues/$dueId/payments');
    return (
      Due.fromJson(res['due'] as Map<String, dynamic>),
      (res['entries'] as List).map((j) => PaymentEntry.fromJson(j as Map<String, dynamic>)).toList(),
    );
  }

  static Future<void> savePayments(int dueId, Map<int, bool> changes) => _api.put('/dues/$dueId/payments', {
        'entries': [for (final e in changes.entries) {'childId': e.key, 'paid': e.value}],
      });

  // ----- Administration -----
  static Future<Map<String, dynamic>> adminOverview() async => (await _api.get('/admin/overview')) as Map<String, dynamic>;

  static Future<List<AdminUser>> adminUsers({String? role, String? q}) async {
    final res = await _api.get('/admin/users', query: {'role': role, 'q': q});
    return (res['users'] as List).map((j) => AdminUser.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<(AdminUser, String)> adminCreateUser({required String role, required String fullName, required String phone, Legion? legion}) async {
    final res = await _api.post('/admin/users', {'role': role, 'fullName': fullName, 'phone': phone, 'legion': legion?.name});
    return (AdminUser.fromJson(res['user'] as Map<String, dynamic>), res['temporaryPassword'] as String);
  }

  static Future<AdminUser> adminUpdateUser(int id, Map<String, dynamic> data) async =>
      AdminUser.fromJson((await _api.patch('/admin/users/$id', data))['user'] as Map<String, dynamic>);

  static Future<String> adminResetPassword(int id) async =>
      (await _api.post('/admin/users/$id/reset-password'))['temporaryPassword'] as String;

  static Future<void> adminLogoutUser(int id) => _api.post('/admin/users/$id/logout');
  static Future<void> adminDeleteUser(int id) => _api.delete('/admin/users/$id');

  static Future<Map<String, dynamic>> adminSettings() async => (await _api.get('/admin/settings')) as Map<String, dynamic>;

  static Future<void> adminSetMaintenance(bool enabled, String message) =>
      _api.put('/admin/settings/maintenance', {'enabled': enabled, 'message': message});

  static Future<void> adminSetAppUpdate({required int latestBuild, required int minBuild, required String url, required String notes}) =>
      _api.put('/admin/settings/app-update', {'latestBuild': latestBuild, 'minBuild': minBuild, 'url': url, 'notes': notes});

  static Future<String> adminRotateSignupCode() async =>
      (await _api.post('/admin/settings/signup-code'))['signupCode'] as String;

  static Future<Map<String, dynamic>> adminSecurity() async => (await _api.get('/admin/security')) as Map<String, dynamic>;

  static Future<void> adminBlockIp(String ip, {int? hours, String? reason}) =>
      _api.post('/admin/security/block', {'ip': ip, 'hours': hours, 'reason': ?reason});

  static Future<void> adminUnblockIp(String ip) => _api.delete('/admin/security/block/${Uri.encodeComponent(ip)}');

  static Future<List<Map<String, dynamic>>> adminAudit() async =>
      ((await _api.get('/admin/audit', query: {'limit': '200'}))['entries'] as List).cast<Map<String, dynamic>>();

  // ----- Informations -----
  static Future<List<Post>> posts() async {
    final res = await _api.get('/posts');
    return (res['posts'] as List).map((j) => Post.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<void> savePost({int? id, required String title, required String body, required bool pinned}) {
    final data = {'title': title, 'body': body, 'pinned': pinned};
    return id == null ? _api.post('/posts', data) : _api.put('/posts/$id', data);
  }

  static Future<void> deletePost(int id) => _api.delete('/posts/$id');

  // ----- Parent -----
  static Future<List<Child>> myChildren() async {
    final res = await _api.get('/parent/children');
    return (res['children'] as List).map((j) => Child.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<Child> linkChild(String code) async =>
      Child.fromJson((await _api.post('/parent/link', {'code': code}))['child'] as Map<String, dynamic>);

  static Future<void> unlinkChild(int id) => _api.delete('/parent/children/$id');

  static Future<List<AttendanceRecord>> myAttendance() async {
    final res = await _api.get('/parent/attendance');
    return (res['records'] as List).map((j) => AttendanceRecord.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<(String, List<ParentDue>)> myDues() async {
    final res = await _api.get('/parent/dues');
    return (
      res['paymentMode'] as String,
      (res['dues'] as List).map((j) => ParentDue.fromJson(j as Map<String, dynamic>)).toList(),
    );
  }

  static Future<Map<String, dynamic>> waveCheckout(int dueId, int childId) async =>
      (await _api.post('/payments/wave/checkout', {'dueId': dueId, 'childId': childId})) as Map<String, dynamic>;

  static Future<void> declarePayment(int dueId, int childId, {String? reference}) =>
      _api.post('/payments/declare', {'dueId': dueId, 'childId': childId, if (reference != null && reference.isNotEmpty) 'reference': reference});
}
