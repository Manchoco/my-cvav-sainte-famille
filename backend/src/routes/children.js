import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { LEGIONS, generateLinkCode, normalizePhone } from '../domain.js';
import { badRequest, notFound, parseBody, parseId } from '../errors.js';
import { childDto, insertChild } from '../services/children.js';
import { parseChildrenDocument } from '../services/importer.js';

const router = Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
});

const optionalText = z.string().trim().max(200).optional().nullable().transform((v) => (v ? v : null));

const childSchema = z.object({
  lastName: z.string().trim().min(1, 'Nom requis').max(80).transform((v) => v.toUpperCase()),
  firstName: z.string().trim().min(1, 'Prénom requis').max(120),
  birthDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date au format AAAA-MM-JJ').optional().nullable(),
  age: z.number().int().min(0).max(30).optional().nullable(),
  legion: z.enum(LEGIONS, { message: 'Légion invalide' }),
  parentName: optionalText,
  parentPhone: z.string().optional().nullable().transform((v, ctx) => {
    if (!v) return null;
    const phone = normalizePhone(v);
    if (!phone) ctx.addIssue({ code: 'custom', message: 'Contact invalide' });
    return phone;
  }),
  address: optionalText,
});

const SELECT = `SELECT c.*, (SELECT count(*) FROM parent_children pc WHERE pc.child_id = c.id) AS linked_parents FROM children c`;

router.get('/', async (req, res) => {
  const params = [];
  const where = [];
  if (req.query.legion) {
    if (!LEGIONS.includes(req.query.legion)) throw badRequest('Légion invalide');
    params.push(req.query.legion);
    where.push(`c.legion = $${params.length}`);
  }
  if (req.query.q) {
    params.push(`%${String(req.query.q).trim().toLowerCase()}%`);
    where.push(`(lower(c.last_name || ' ' || c.first_name) LIKE $${params.length} OR c.parent_phone LIKE $${params.length})`);
  }
  const sql = `${SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY lower(c.last_name), lower(c.first_name)`;
  const { rows } = await query(sql, params);
  res.json({ children: rows.map(childDto) });
});

router.get('/:id', async (req, res) => {
  const { rows } = await query(`${SELECT} WHERE c.id = $1`, [parseId(req.params.id)]);
  if (!rows[0]) throw notFound('Enfant introuvable');
  res.json({ child: childDto(rows[0]) });
});

router.post('/', async (req, res) => {
  const data = parseBody(childSchema, req.body);
  const row = await insertChild({ query }, data, req.user.id);
  res.status(201).json({ child: childDto(row) });
});

router.put('/:id', async (req, res) => {
  const data = parseBody(childSchema, req.body);
  const { rows } = await query(
    `UPDATE children SET last_name=$2, first_name=$3, birth_date=$4, age=$5, legion=$6,
       parent_name=$7, parent_phone=$8, address=$9, updated_at=now()
     WHERE id=$1 RETURNING *`,
    [parseId(req.params.id), data.lastName, data.firstName, data.birthDate ?? null, data.age ?? null,
      data.legion, data.parentName, data.parentPhone, data.address],
  );
  if (!rows[0]) throw notFound('Enfant introuvable');
  res.json({ child: childDto(rows[0]) });
});

router.delete('/:id', async (req, res) => {
  const { rowCount } = await query('DELETE FROM children WHERE id = $1', [parseId(req.params.id)]);
  if (!rowCount) throw notFound('Enfant introuvable');
  res.status(204).end();
});

// Nouveau code : coupe l'accès des parents déjà liés (en cas de code divulgué).
router.post('/:id/regenerate-code', async (req, res) => {
  const id = parseId(req.params.id);
  const row = await withTransaction(async (client) => {
    await client.query('DELETE FROM parent_children WHERE child_id = $1', [id]);
    const { rows } = await client.query('UPDATE children SET link_code = $2, updated_at = now() WHERE id = $1 RETURNING *', [id, generateLinkCode()]);
    return rows[0];
  });
  if (!row) throw notFound('Enfant introuvable');
  res.json({ child: childDto(row) });
});

// --- Import d'un document : 1) aperçu  2) validation ---

router.post('/import/preview', upload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Aucun fichier reçu');
  let children;
  try {
    children = await parseChildrenDocument(req.file.buffer, req.file.originalname, req.file.mimetype);
  } catch (err) {
    if (err.status) throw err;
    throw badRequest("Impossible de lire ce document. Vérifiez qu'il n'est pas protégé ou endommagé.");
  }
  if (children.length === 0) {
    throw badRequest("Aucun enfant reconnu dans ce document. Utilisez un tableau avec les colonnes Nom, Prénoms, Âge, Contact, Lieu d'habitation, Légion.");
  }
  const { rows: existing } = await query('SELECT lower(last_name) AS l, lower(first_name) AS f FROM children');
  const known = new Set(existing.map((r) => `${r.l}|${r.f}`));
  const preview = children.map((c) => ({ ...c, duplicate: known.has(`${c.lastName.toLowerCase()}|${c.firstName.toLowerCase()}`) }));
  res.json({ children: preview, total: preview.length, duplicates: preview.filter((c) => c.duplicate).length });
});

const commitSchema = z.object({
  children: z.array(childSchema).min(1).max(2000),
  skipDuplicates: z.boolean().default(true),
});

router.post('/import/commit', async (req, res) => {
  const { children, skipDuplicates } = parseBody(commitSchema, req.body);
  const result = await withTransaction(async (client) => {
    const { rows: existing } = await client.query('SELECT lower(last_name) AS l, lower(first_name) AS f FROM children');
    const known = new Set(existing.map((r) => `${r.l}|${r.f}`));
    let created = 0;
    let skipped = 0;
    for (const child of children) {
      const key = `${child.lastName.toLowerCase()}|${child.firstName.toLowerCase()}`;
      if (skipDuplicates && known.has(key)) { skipped += 1; continue; }
      await insertChild(client, child, req.user.id);
      known.add(key);
      created += 1;
    }
    return { created, skipped };
  });
  res.status(201).json(result);
});

export default router;
