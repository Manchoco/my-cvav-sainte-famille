import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_cvav/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('légions', () {
    expect(Legion.fromId('aines'), Legion.aines);
    expect(Legion.aines.label, 'Aînés');
    expect(Legion.fromId('inconnue'), isNull);
  });

  test('montants en F CFA', () {
    expect(formatMoney(null), 'À définir');
    expect(formatMoney(1500).replaceAll(RegExp(r'\s'), ' '), '1 500 F CFA');
  });

  test('ligne importée valide seulement avec nom, prénom et légion', () {
    final row = ImportRow.fromJson({'lastName': 'KOFFI', 'firstName': '', 'legion': null, 'warnings': []});
    expect(row.valid, isFalse);
    row
      ..firstName = 'Paul'
      ..legion = Legion.cadets;
    expect(row.valid, isTrue);
    expect(row.toJson()['legion'], 'cadets');
  });

  test('cotisation parent', () {
    final due = ParentDue.fromJson({
      'childId': 1, 'childName': 'KOFFI Paul', 'dueId': 2, 'kind': 'activite', 'label': 'Camp de jumelage',
      'amount': 5000, 'status': 'unpaid',
    });
    expect(due.kindLabel, "Cotisation d'activité");
  });
}
