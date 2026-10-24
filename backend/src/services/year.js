import { config } from '../config.js';
import { query } from '../db.js';
import { DEFAULT_ACTIVITIES, YEAR_PATTERN, currentPastoralYear } from '../domain.js';
import { badRequest } from '../errors.js';

export function resolveYear(value) {
  if (!value) return currentPastoralYear();
  if (!YEAR_PATTERN.test(value)) throw badRequest('Année invalide (format attendu : 2026-2027)');
  return value;
}

const ensured = new Set();

// Crée à la demande les cotisations de l'année et les activités habituelles.
export async function ensureYear(year) {
  if (ensured.has(year)) return;
  await query(
    `INSERT INTO dues (kind, year, label, amount) VALUES
       ('paroissiale', $1, 'Cotisation paroissiale', $2),
       ('diocesaine', $1, 'Cotisation diocésaine', NULL)
     ON CONFLICT DO NOTHING`,
    [year, config.parishDueDefault],
  );
  const { rowCount } = await query(`SELECT 1 FROM events WHERE year = $1 AND kind = 'activite' LIMIT 1`, [year]);
  if (!rowCount) {
    for (const [i, name] of DEFAULT_ACTIVITIES.entries()) {
      await query(
        `WITH e AS (
           INSERT INTO events (kind, name, year, position) VALUES ('activite', $1, $2, $3)
           ON CONFLICT DO NOTHING RETURNING id, name
         )
         INSERT INTO dues (kind, year, event_id, label, amount)
         SELECT 'activite', $2, e.id, e.name, NULL FROM e`,
        [name, year, i],
      );
    }
  }
  ensured.add(year);
}

export function resetYearCache() {
  ensured.clear();
}
