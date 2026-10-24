// Extraction d'une liste d'enfants depuis un document Word, PDF, Excel ou CSV.
// Le résultat est un aperçu : rien n'est enregistré tant que le responsable n'a pas validé.
import ExcelJS from 'exceljs';
import mammoth from 'mammoth';
import JSZip from 'jszip';
import { LEGIONS, legionForAge, normalizePhone } from '../domain.js';

const strip = (s) => String(s ?? '')
  .normalize('NFD').replace(/[̀-ͯ]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

const HEADER_SYNONYMS = {
  fullName: ['nom et prenoms', 'nom et prenom', 'nom prenoms', 'nom prenom', 'nom complet', 'noms et prenoms', 'enfant', 'nom de l enfant'],
  lastName: ['nom', 'noms', 'nom de famille'],
  firstName: ['prenom', 'prenoms'],
  age: ['age', 'ages', 'age ans'],
  birthDate: ['date de naissance', 'ne le', 'nee le', 'ne e le', 'naissance', 'date naissance'],
  parentPhone: ['contact', 'contacts', 'telephone', 'tel', 'numero', 'contact parent', 'contact des parents', 'contacts parents', 'tel parent', 'telephone parent', 'contact du parent', 'cel', 'cellulaire'],
  parentName: ['parent', 'parents', 'nom du parent', 'nom des parents', 'tuteur', 'nom du tuteur', 'pere mere'],
  address: ['lieu d habitation', 'habitation', 'quartier', 'domicile', 'adresse', 'commune', 'lieu de residence', 'residence', 'lieu'],
  legion: ['legion', 'legions', 'groupe', 'section'],
};

const LEGION_WORDS = {
  meneurs: ['meneur', 'meneurs'],
  aines: ['aine', 'aines', 'ainee', 'ainees'],
  cadets: ['cadet', 'cadets', 'cadette', 'cadettes'],
  benjamins: ['benjamin', 'benjamins', 'benjamine', 'benjamines'],
};

export function detectLegion(text) {
  const words = strip(text).split(' ');
  for (const legion of LEGIONS) {
    if (LEGION_WORDS[legion].some((w) => words.includes(w))) return legion;
  }
  return null;
}

function headerKey(cell) {
  const s = strip(cell);
  if (!s) return null;
  for (const [key, syns] of Object.entries(HEADER_SYNONYMS)) {
    if (syns.includes(s)) return key;
  }
  // Correspondances partielles ("contact des parents (tel)")
  if (s.includes('prenom') && s.includes('nom')) return 'fullName';
  if (s.includes('naissance')) return 'birthDate';
  if (s.includes('contact') || s.includes('tel') || s.includes('numero')) return 'parentPhone';
  if (s.includes('habitation') || s.includes('quartier') || s.includes('domicile') || s.includes('adresse')) return 'address';
  if (s.includes('prenom')) return 'firstName';
  if (s.includes('parent') || s.includes('tuteur')) return 'parentName';
  if (s.includes('legion')) return 'legion';
  if (s === 'n' || s === 'no' || s === 'num' || s === 'n o') return 'index';
  return null;
}

const PHONE_RE = /(?:\+?225[\s.-]?)?(?:\d[\s.-]?){8,10}/;
const DATE_RE = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$/;

export function parseDate(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value.toISOString().slice(0, 10);
  const s = String(value ?? '').trim();
  let m = s.match(DATE_RE);
  if (m) {
    let [, d, mo, y] = m.map(Number);
    if (y < 100) y += y > 50 ? 1900 : 2000;
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
  }
  m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  return null;
}

function parseAge(value) {
  const m = String(value ?? '').match(/\d{1,2}/);
  if (!m) return null;
  const age = Number(m[0]);
  return age >= 3 && age <= 30 ? age : null;
}

function splitName(full) {
  const parts = String(full).trim().split(/\s+/);
  // Convention ivoirienne : NOM Prénoms
  return { lastName: parts[0] || '', firstName: parts.slice(1).join(' ') };
}

function splitLine(line) {
  for (const sep of ['\t', ';', '|']) {
    if (line.includes(sep)) return line.split(sep);
  }
  if ((line.match(/,/g) || []).length >= 2) return line.split(',');
  return line.split(/\s{2,}/);
}

// ---------- Extraction brute : tableau de lignes de cellules ----------

async function rowsFromXlsx(buffer) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buffer);
  const rows = [];
  wb.eachSheet((sheet) => {
    // Le nom d'une feuille peut indiquer la légion ("Cadets")
    const sheetLegion = detectLegion(sheet.name);
    if (sheetLegion) rows.push([sheet.name]);
    sheet.eachRow((row) => {
      const cells = [];
      row.eachCell({ includeEmpty: true }, (cell) => {
        const v = cell.value;
        if (v instanceof Date) cells.push(v);
        else if (v && typeof v === 'object' && 'text' in v) cells.push(String(v.text));
        else if (v && typeof v === 'object' && 'result' in v) cells.push(String(v.result ?? ''));
        else if (v && typeof v === 'object' && 'richText' in v) cells.push(v.richText.map((t) => t.text).join(''));
        else cells.push(v == null ? '' : String(v));
      });
      rows.push(cells);
    });
  });
  return rows;
}

const decodeEntities = (s) => s
  .replace(/<[^>]+>/g, ' ')
  .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
  .replace(/\s+/g, ' ').trim();

async function rowsFromDocx(buffer) {
  const { value: html } = await mammoth.convertToHtml({ buffer });
  const rows = [];
  // On parcourt le document dans l'ordre : titres/paragraphes (légions) et lignes de tableau.
  const blockRe = /<(h\d|p)[^>]*>([\s\S]*?)<\/\1>|<tr[^>]*>([\s\S]*?)<\/tr>/g;
  let hasTable = false;
  let m;
  while ((m = blockRe.exec(html))) {
    if (m[3] !== undefined) {
      hasTable = true;
      const cells = [...m[3].matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/g)].map((c) => decodeEntities(c[1]));
      rows.push(cells);
    } else {
      const text = decodeEntities(m[2]);
      if (text) rows.push(hasTable || detectLegion(text) ? [text] : splitLine(text));
    }
  }
  return rows;
}

async function rowsFromPdf(buffer) {
  // Chargé à la demande : pdf.js dépend d'un module natif (canvas) qui ne doit pas bloquer le démarrage de l'API.
  const { PDFParse } = await import('pdf-parse');
  const parser = new PDFParse({ data: new Uint8Array(buffer) });
  try {
    const { text } = await parser.getText();
    return text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map(splitLine);
  } finally {
    await parser.destroy();
  }
}

function rowsFromText(buffer) {
  const text = buffer.toString('utf8').replace(/^﻿/, '');
  return text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map(splitLine);
}

// Protection « bombe zip » : un .docx/.xlsx de 4 Mo peut se décompresser en plusieurs Go et saturer le serveur.
const MAX_UNZIPPED_BYTES = 40 * 1024 * 1024;
const MAX_ZIP_ENTRIES = 2000;

async function assertSafeZip(buffer) {
  let zip;
  try {
    zip = await JSZip.loadAsync(buffer);
  } catch {
    const err = new Error("Document illisible : le fichier n'est pas un document Word ou Excel valide.");
    err.status = 400;
    throw err;
  }
  const entries = Object.values(zip.files);
  // eslint-disable-next-line no-underscore-dangle
  const total = entries.reduce((sum, f) => sum + (f._data?.uncompressedSize || 0), 0);
  if (entries.length > MAX_ZIP_ENTRIES || total > MAX_UNZIPPED_BYTES) {
    const err = new Error('Document trop volumineux une fois décompressé.');
    err.status = 413;
    throw err;
  }
}

export async function extractRows(buffer, filename, mimetype = '') {
  const ext = (filename.split('.').pop() || '').toLowerCase();
  if (['xlsx', 'docx'].includes(ext) || mimetype.includes('openxmlformats')) await assertSafeZip(buffer);
  if (ext === 'xlsx' || mimetype.includes('spreadsheetml')) return rowsFromXlsx(buffer);
  if (ext === 'docx' || mimetype.includes('wordprocessingml')) return rowsFromDocx(buffer);
  if (ext === 'pdf' || mimetype === 'application/pdf') return rowsFromPdf(buffer);
  if (['csv', 'txt', 'tsv'].includes(ext) || mimetype.startsWith('text/')) return rowsFromText(buffer);
  const err = new Error('Format non pris en charge. Utilisez Word (.docx), PDF, Excel (.xlsx) ou CSV.');
  err.status = 415;
  throw err;
}

// ---------- Interprétation ----------

function interpretCells(cells, mapping) {
  const out = {};
  if (mapping) {
    cells.forEach((cell, i) => {
      const key = mapping[i];
      if (key && key !== 'index' && String(cell ?? '').trim() !== '') out[key] = cell;
    });
    return out;
  }
  // Pas d'en-tête : on devine chaque cellule.
  const texts = [];
  for (const raw of cells) {
    const cell = raw instanceof Date ? raw : String(raw ?? '').trim();
    if (cell === '') continue;
    if (cell instanceof Date || parseDate(cell)) { out.birthDate ??= cell; continue; }
    if (!out.legion && detectLegion(cell) && strip(cell).split(' ').length <= 2) { out.legion = cell; continue; }
    if (!out.parentPhone && PHONE_RE.test(cell) && cell.replace(/\D/g, '').length >= 8) { out.parentPhone = cell; continue; }
    if (out.age == null && /^\d{1,2}\s*(ans?)?$/i.test(cell)) { out.age = cell; continue; }
    if (/^\d+[.)]?$/.test(cell)) continue; // numéro d'ordre
    texts.push(cell);
  }
  if (texts[0]) out.fullName = texts[0];
  if (texts[1]) out.address = texts[1];
  return out;
}

const FREE_HEADER_WORDS = new Set(['nom', 'noms', 'prenom', 'prenoms', 'age', 'contact', 'contacts', 'telephone', 'tel',
  'habitation', 'quartier', 'legion', 'adresse', 'domicile', 'naissance', 'parent', 'parents']);

// Ligne de texte sans séparateur exploitable (PDF, Word sans tableau) : "KOFFI Paul 8 0707070711 Riviera 2".
// Retourne null si la ligne ne contient ni âge, ni date, ni contact (titres, texte libre).
export function interpretFreeLine(line) {
  const words = strip(line).split(' ');
  if (words.filter((w) => FREE_HEADER_WORDS.has(w)).length >= 2) return null;
  let rest = ` ${line} `.replace(/\bn[ée]e?\s+le\b/gi, ' ');
  const out = {};
  const date = rest.match(/\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b/);
  if (date) { out.birthDate = date[0]; rest = rest.replace(date[0], ' | '); }
  const phone = rest.match(/(?:\+?225[\s.-]?)?\b\d{2}(?:[\s.-]?\d{2}){3,4}\b/);
  if (phone) { out.parentPhone = phone[0]; rest = rest.replace(phone[0], ' | '); }
  const pipe = rest.indexOf('|');
  const head = pipe >= 0 ? rest.slice(0, pipe) : rest;
  const age = head.match(/\s(\d{1,2})\s*(?:ans?)?\s/i);
  if (age && parseAge(age[1]) != null) { out.age = age[1]; rest = rest.replace(age[0], ' | '); }
  if (!out.birthDate && !out.parentPhone && out.age == null) return null;
  const legionWord = rest.split(/\s+/).find((w) => detectLegion(w));
  if (legionWord) { out.legion = legionWord; rest = rest.replace(legionWord, ' '); }
  const parts = rest.split('|').map((p) => p.trim()).filter(Boolean);
  if (parts[0]) out.fullName = parts[0].replace(/^\d+\s*[.)-]?\s*/, '');
  if (parts.length > 1) out.address = parts.slice(1).join(', ');
  return out;
}

function toChild(fields, sectionLegion) {
  const warnings = [];
  let { lastName, firstName } = fields;
  if (fields.fullName && !lastName) ({ lastName, firstName } = splitName(fields.fullName));
  else if (lastName && !firstName && String(lastName).trim().includes(' ') && !fields.firstName) ({ lastName, firstName } = splitName(lastName));
  lastName = String(lastName ?? '').trim().toUpperCase();
  firstName = String(firstName ?? '').trim();
  const birthDate = fields.birthDate ? parseDate(fields.birthDate) : null;
  let age = fields.age != null ? parseAge(fields.age) : null;
  if (age == null && birthDate) {
    const b = new Date(birthDate);
    age = new Date().getFullYear() - b.getFullYear();
  }
  const phoneRaw = fields.parentPhone ? String(fields.parentPhone).match(PHONE_RE)?.[0] : null;
  const parentPhone = phoneRaw ? normalizePhone(phoneRaw) : null;
  if (fields.parentPhone && !parentPhone) warnings.push('Contact illisible');
  let legion = fields.legion ? detectLegion(fields.legion) : null;
  legion ??= sectionLegion;
  if (!legion) {
    legion = legionForAge(age);
    if (legion) warnings.push("Légion déduite de l'âge, à vérifier");
  }
  if (!legion) warnings.push('Légion à préciser');
  if (!firstName) warnings.push('Prénom manquant');
  return {
    lastName,
    firstName,
    age,
    birthDate,
    parentName: fields.parentName ? String(fields.parentName).trim() : null,
    parentPhone,
    address: fields.address ? String(fields.address).trim() : null,
    legion,
    warnings,
  };
}

export function interpretRows(rows) {
  const children = [];
  let mapping = null;
  let sectionLegion = null;
  for (const raw of rows) {
    const cells = raw.map((c) => (c instanceof Date ? c : String(c ?? '').trim()));
    const filled = cells.filter((c) => c !== '');
    if (filled.length === 0) continue;

    // Ligne d'en-tête ?
    const keys = cells.map(headerKey);
    const known = keys.filter((k) => k && k !== 'index');
    if (known.length >= 2 && (known.includes('fullName') || known.includes('lastName'))) {
      mapping = keys;
      continue;
    }
    // Titre de section ("LÉGION DES CADETS", "Benjamins :")
    if (filled.length === 1 && detectLegion(filled[0]) && strip(filled[0]).split(' ').length <= 4) {
      sectionLegion = detectLegion(filled[0]);
      continue;
    }
    let fields;
    if (filled.length === 1 && !(filled[0] instanceof Date)) {
      fields = interpretFreeLine(filled[0]);
      if (!fields) continue; // titre ou texte libre
    } else {
      fields = interpretCells(cells, mapping);
    }
    const child = toChild(fields, sectionLegion);
    if (!child.lastName || child.lastName.length < 2 || !/[A-Z]/.test(child.lastName.normalize('NFD'))) continue;
    children.push(child);
  }
  return children;
}

export async function parseChildrenDocument(buffer, filename, mimetype) {
  const rows = await extractRows(buffer, filename, mimetype);
  return interpretRows(rows);
}
