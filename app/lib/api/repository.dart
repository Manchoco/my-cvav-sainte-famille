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
