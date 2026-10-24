import crypto from 'node:crypto';

export const LEGIONS = ['meneurs', 'aines', 'cadets', 'benjamins'];
export const LEGION_LABELS = { meneurs: 'Meneurs', aines: 'Aînés', cadets: 'Cadets', benjamins: 'Benjamins' };

export const DEFAULT_ACTIVITIES = [
  'Rentrée pastorale',
  'Accueil des nouveaux',
  'Camp de jumelage',
  'Happy New Year',
  'Ressourcement spirituel',
  "Cérémonie d'ascension personnelle",
  'Mini camp biblique + Journée sportive',
];

// Tranches d'âge indicatives, utilisées seulement quand un import ne précise pas la légion.
export function legionForAge(age) {
  if (age == null || Number.isNaN(age)) return null;
  if (age <= 9) return 'benjamins';
  if (age <= 12) return 'cadets';
  if (age <= 15) return 'aines';
  return 'meneurs';
}

// Année pastorale : de septembre à août ("2026-2027").
export function currentPastoralYear(date = new Date()) {
  const y = date.getFullYear();
  return date.getMonth() >= 8 ? `${y}-${y + 1}` : `${y - 1}-${y}`;
}

export const YEAR_PATTERN = /^\d{4}-\d{4}$/;

export function normalizePhone(raw) {
  if (raw == null) return null;
  let digits = String(raw).replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('225') && digits.length === 13) digits = digits.slice(3);
  digits = digits.replace(/\D/g, '');
  return digits.length >= 8 && digits.length <= 15 ? digits : null;
}

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export function generateLinkCode(length = 8) {
  let code = '';
  for (let i = 0; i < length; i += 1) code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  return code;
}

export function ageFrom(birthDate, fallbackAge, now = new Date()) {
  if (!birthDate) return fallbackAge ?? null;
  const [y, m, d] = birthDate.split('-').map(Number);
  let age = now.getFullYear() - y;
  if (now.getMonth() + 1 < m || (now.getMonth() + 1 === m && now.getDate() < d)) age -= 1;
  return age;
}
