import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum Legion {
  meneurs('Meneurs', Color(0xFFD9472B), Icons.flag_rounded),
  aines('Aînés', Color(0xFF7B4BC4), Icons.star_rounded),
  cadets('Cadets', Color(0xFF1E9E6A), Icons.eco_rounded),
  benjamins('Benjamins', Color(0xFFF29F05), Icons.child_care_rounded);

  const Legion(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;

  static Legion? fromId(String? id) {
    for (final l in values) {
      if (l.name == id) return l;
    }
    return null;
  }
}

final _money = NumberFormat.decimalPattern('fr_FR');
String formatMoney(num? amount) => amount == null ? 'À définir' : '${_money.format(amount)} F CFA';

String formatDate(String? iso, {String pattern = 'd MMM yyyy'}) {
  if (iso == null || iso.isEmpty) return 'Date à préciser';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat(pattern, 'fr_FR').format(d.toLocal());
}

class User {
  User({required this.id, required this.role, required this.fullName, required this.phone, this.legion});
  final int id;
  final String role;
  final String fullName;
  final String phone;
  final Legion? legion;

  bool get isResponsable => role == 'responsable';

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as int,
        role: j['role'] as String,
        fullName: j['fullName'] as String,
        phone: j['phone'] as String,
        legion: Legion.fromId(j['legion'] as String?),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'role': role, 'fullName': fullName, 'phone': phone, 'legion': legion?.name};
}

class Child {
  Child({
    required this.id,
    required this.lastName,
    required this.firstName,
    required this.legion,
    this.birthDate,
    this.age,
    this.parentName,
    this.parentPhone,
    this.address,
    this.linkCode,
    this.linkedParents,
  });
  final int id;
  final String lastName;
  final String firstName;
  final Legion legion;
  final String? birthDate;
  final int? age;
  final String? parentName;
  final String? parentPhone;
  final String? address;
  final String? linkCode;
  final int? linkedParents;

  String get fullName => '$lastName $firstName';
  String get initials =>
      '${lastName.isNotEmpty ? lastName[0] : ''}${firstName.isNotEmpty ? firstName[0] : ''}'.toUpperCase();

  factory Child.fromJson(Map<String, dynamic> j) => Child(
        id: j['id'] as int,
        lastName: j['lastName'] as String,
        firstName: j['firstName'] as String,
        legion: Legion.fromId(j['legion'] as String?) ?? Legion.benjamins,
        birthDate: j['birthDate'] as String?,
        age: j['age'] as int?,
        parentName: j['parentName'] as String?,
        parentPhone: j['parentPhone'] as String?,
        address: j['address'] as String?,
        linkCode: j['linkCode'] as String?,
        linkedParents: j['linkedParents'] as int?,
      );
}

/// Ligne extraite d'un document importé (modifiable avant validation).
class ImportRow {
  ImportRow.fromJson(Map<String, dynamic> j)
      : lastName = j['lastName'] as String? ?? '',
        firstName = j['firstName'] as String? ?? '',
        age = j['age'] as int?,
        birthDate = j['birthDate'] as String?,
        parentName = j['parentName'] as String?,
        parentPhone = j['parentPhone'] as String?,
        address = j['address'] as String?,
        legion = Legion.fromId(j['legion'] as String?),
        warnings = ((j['warnings'] as List?) ?? []).cast<String>(),
        duplicate = j['duplicate'] as bool? ?? false;

  String lastName;
  String firstName;
  int? age;
  String? birthDate;
  String? parentName;
  String? parentPhone;
  String? address;
  Legion? legion;
  List<String> warnings;
  bool duplicate;
  bool selected = true;

  bool get valid => lastName.isNotEmpty && firstName.isNotEmpty && legion != null;

  Map<String, dynamic> toJson() => {
        'lastName': lastName,
        'firstName': firstName,
        'age': age,
        'birthDate': birthDate,
        'parentName': parentName,
        'parentPhone': parentPhone,
        'address': address,
        'legion': legion?.name,
      };
}

class EventItem {
  EventItem({required this.id, required this.kind, required this.name, this.date, this.price, this.dueId, this.present = 0, this.absent = 0});
  final int id;
  final String kind;
  final String name;
  final String? date;
  final int? price;
  final int? dueId;
  final int present;
  final int absent;

  bool get isActivity => kind == 'activite';

  factory EventItem.fromJson(Map<String, dynamic> j) => EventItem(
        id: j['id'] as int,
        kind: j['kind'] as String,
        name: j['name'] as String,
        date: j['date'] as String?,
        price: j['price'] as int?,
        dueId: j['dueId'] as int?,
        present: j['present'] as int? ?? 0,
        absent: j['absent'] as int? ?? 0,
      );
}

class AttendanceEntry {
  AttendanceEntry({required this.child, this.status, this.markedBy});
  final Child child;
  String? status; // present | absent | null
  final String? markedBy;

  factory AttendanceEntry.fromJson(Map<String, dynamic> j) => AttendanceEntry(
        child: Child.fromJson(j['child'] as Map<String, dynamic>),
        status: j['status'] as String?,
        markedBy: j['markedBy'] as String?,
      );
}

class Due {
  Due({required this.id, required this.kind, required this.label, this.amount, this.eventId, this.eventDate, this.paidCount = 0, this.pendingCount = 0, this.collected = 0});
  final int id;
  final String kind;
  final String label;
  final int? amount;
  final int? eventId;
  final String? eventDate;
  final int paidCount;
  final int pendingCount;
  final int collected;

  factory Due.fromJson(Map<String, dynamic> j) => Due(
        id: j['id'] as int,
        kind: j['kind'] as String,
        label: j['label'] as String,
        amount: j['amount'] as int?,
        eventId: j['eventId'] as int?,
        eventDate: j['eventDate'] as String?,
        paidCount: j['paidCount'] as int? ?? 0,
        pendingCount: j['pendingCount'] as int? ?? 0,
        collected: j['collected'] as int? ?? 0,
      );
}

class PaymentEntry {
  PaymentEntry({required this.child, required this.status, this.method, this.updatedBy});
  final Child child;
  String status; // unpaid | pending | paid
  final String? method;
  final String? updatedBy;

  bool get lockedByWave => method == 'wave' && status == 'paid';

  factory PaymentEntry.fromJson(Map<String, dynamic> j) => PaymentEntry(
        child: Child.fromJson(j['child'] as Map<String, dynamic>),
        status: j['status'] as String,
        method: j['method'] as String?,
        updatedBy: j['updatedBy'] as String?,
      );
}

class Post {
  Post({required this.id, required this.title, required this.body, required this.pinned, this.author, required this.createdAt});
  final int id;
  final String title;
  final String body;
  final bool pinned;
  final String? author;
  final String createdAt;

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'] as int,
        title: j['title'] as String,
        body: j['body'] as String,
        pinned: j['pinned'] as bool? ?? false,
        author: j['author'] as String?,
        createdAt: j['createdAt'] as String,
      );
}

class ParentDue {
  ParentDue.fromJson(Map<String, dynamic> j)
      : childId = j['childId'] as int,
        childName = j['childName'] as String,
        dueId = j['dueId'] as int,
        kind = j['kind'] as String,
        label = j['label'] as String,
        amount = j['amount'] as int,
        eventDate = j['eventDate'] as String?,
        status = j['status'] as String,
        method = j['method'] as String?;

  final int childId;
  final String childName;
  final int dueId;
  final String kind;
  final String label;
  final int amount;
  final String? eventDate;
  final String status;
  final String? method;

  String get kindLabel => switch (kind) {
        'paroissiale' => 'Cotisation paroissiale',
        'diocesaine' => 'Cotisation diocésaine',
        _ => "Cotisation d'activité",
      };
}

class AttendanceRecord {
  AttendanceRecord.fromJson(Map<String, dynamic> j)
      : childId = j['childId'] as int,
        childName = j['childName'] as String,
        legion = Legion.fromId(j['legion'] as String?),
        eventName = j['eventName'] as String,
        eventKind = j['eventKind'] as String,
        eventDate = j['eventDate'] as String?,
        status = j['status'] as String,
        markedBy = j['markedBy'] as String?;

  final int childId;
  final String childName;
  final Legion? legion;
  final String eventName;
  final String eventKind;
  final String? eventDate;
  final String status;
  final String? markedBy;
}
