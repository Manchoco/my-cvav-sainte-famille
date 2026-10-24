import { test } from 'node:test';
import assert from 'node:assert/strict';
import { interpretRows, parseDate } from '../src/services/importer.js';

test('lignes de texte libre (PDF) : nom, âge, contact, quartier, légion', () => {
  const rows = interpretRows([
    ['Liste de la paroisse'],
    ['Nom Prénoms Age Contact Habitation'],
    ['1. DIABATE Moussa Junior 12 ans 07 07 07 07 13 Riviera 2 cadet'],
    ['TOURE Ali né le 12/03/2015 0505050514 Palmeraie'],
    ['-- 1 of 1 --'],
  ]);
  assert.equal(rows.length, 2);
  assert.deepEqual(
    [rows[0].lastName, rows[0].firstName, rows[0].age, rows[0].parentPhone, rows[0].address, rows[0].legion],
    ['DIABATE', 'Moussa Junior', 12, '0707070713', 'Riviera 2', 'cadets'],
  );
  assert.equal(rows[1].firstName, 'Ali');
  assert.equal(rows[1].birthDate, '2015-03-12');
});

test('sections par légion sans colonne légion', () => {
  const rows = interpretRows([
    ['MENEURS'], ['Nom', 'Prénoms', 'Contact'], ['BAMBA', 'Ange', '0101010101'],
    ['BENJAMINS'], ['KOFFI', 'Paul', '0202020202'],
  ]);
  assert.deepEqual(rows.map((r) => r.legion), ['meneurs', 'benjamins']);
});

test('dates', () => {
  assert.equal(parseDate('04/05/2012'), '2012-05-04');
  assert.equal(parseDate('2012-05-04'), '2012-05-04');
  assert.equal(parseDate('demain'), null);
});
