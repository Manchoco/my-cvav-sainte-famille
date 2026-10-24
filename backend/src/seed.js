// Données de démonstration (ne pas exécuter en production avec de vraies données).
import bcrypt from 'bcryptjs';
import { pool, query } from './db.js';
import { migrate } from './migrate.js';
import { currentPastoralYear } from './domain.js';
import { insertChild } from './services/children.js';
import { ensureYear } from './services/year.js';

await migrate();
const year = currentPastoralYear();
await ensureYear(year);

const hash = await bcrypt.hash('cvav2026', 10);
const { rows: [resp] } = await query(
  `INSERT INTO users (role, full_name, phone, password_hash, legion) VALUES ('responsable', 'Responsable Démo', '0700000001', $1, 'cadets')
   ON CONFLICT (phone) DO UPDATE SET full_name = EXCLUDED.full_name RETURNING *`, [hash]);
const { rows: [parent] } = await query(
  `INSERT INTO users (role, full_name, phone, password_hash) VALUES ('parent', 'Parent Démo', '0700000002', $1)
   ON CONFLICT (phone) DO UPDATE SET full_name = EXCLUDED.full_name RETURNING *`, [hash]);

const { rows: [{ n }] } = await query('SELECT count(*)::int AS n FROM children');
if (n === 0) {
  const kids = [
    ['KOUASSI', 'Aya Grâce', 8, 'benjamins', 'Mme Kouassi', '0707070701', 'Riviera 2, Cité Lauriers'],
    ['KONAN', 'Jean-Marc', 9, 'benjamins', 'M. Konan', '0505050502', 'Riviera Palmeraie'],
    ['TRAORÉ', 'Mariam', 11, 'cadets', 'Mme Traoré', '0101010103', 'Riviera 3'],
    ['YAO', 'Emmanuel', 12, 'cadets', 'M. Yao', '0707070701', 'Riviera 2, Cité Lauriers'],
    ['N\'GUESSAN', 'Prisca', 14, 'aines', 'Mme N\'Guessan', '0505050505', 'Riviera Golf'],
    ['DIBATÉ', 'Samuel', 15, 'aines', 'M. Dibaté', '0707070706', 'Riviera 2'],
    ['BAMBA', 'Ange', 17, 'meneurs', 'M. Bamba', '0101010107', 'Riviera Bonoumin'],
    ['ASSI', 'Fabrice', 18, 'meneurs', 'Mme Assi', '0505050508', 'Riviera 4'],
  ];
  const created = [];
  for (const [lastName, firstName, age, legion, parentName, parentPhone, address] of kids) {
    created.push(await insertChild({ query }, { lastName, firstName, age, legion, parentName, parentPhone, address }, resp.id));
  }
  await query('INSERT INTO parent_children (parent_id, child_id) VALUES ($1, $2), ($1, $3) ON CONFLICT DO NOTHING', [parent.id, created[0].id, created[3].id]);
  await query(`UPDATE dues SET amount = 1000 WHERE year = $1 AND kind = 'diocesaine'`, [year]);
  await query(`UPDATE dues SET amount = 2000 WHERE year = $1 AND label = 'Rentrée pastorale'`, [year]);
  await query(`UPDATE dues SET amount = 5000 WHERE year = $1 AND label = 'Camp de jumelage'`, [year]);
  const { rows: [ev] } = await query(`SELECT id FROM events WHERE year = $1 AND name = 'Rentrée pastorale'`, [year]);
  for (const [i, c] of created.entries()) {
    await query('INSERT INTO attendance (event_id, child_id, status, marked_by) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING', [ev.id, c.id, i % 4 === 3 ? 'absent' : 'present', resp.id]);
  }
  await query(`INSERT INTO posts (title, body, pinned, created_by) VALUES
    ('Bienvenue sur My CVAV !', 'Retrouvez ici les informations, les présences et les cotisations de vos enfants.', true, $1),
    ('Rentrée pastorale', 'La rentrée pastorale aura lieu samedi à 15h à la paroisse. Tenue CVAV exigée.', false, $1)`, [resp.id]);
}
console.log('Démo prête — responsable 0700000001 / parent 0700000002, mot de passe : cvav2026');
await pool.end();
