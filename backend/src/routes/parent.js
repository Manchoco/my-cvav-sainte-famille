import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { query } from '../db.js';
import { HttpError, badRequest, notFound, parseBody, parseId } from '../errors.js';
import { childDtoForParent } from '../services/children.js';
import { ensureYear, resolveYear } from '../services/year.js';
import { waveMode } from '../services/wave.js';

const router = Router();

// Limite les essais de codes enfants (anti force brute).
const linkLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 20,
  keyGenerator: (req) => `link:${req.user.id}`,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Trop de tentatives. Réessayez plus tard.' },
});

router.post('/link', linkLimiter, async (req, res) => {
  const { code } = parseBody(z.object({ code: z.string().trim().min(4).max(20) }), req.body);
  const normalized = code.toUpperCase().replace(/[^A-Z0-9]/g, '');
  const { rows } = await query('SELECT * FROM children WHERE link_code = $1', [normalized]);
  if (!rows[0]) throw new HttpError(404, 'Code enfant introuvable. Vérifiez-le auprès du responsable.');
  await query('INSERT INTO parent_children (parent_id, child_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [req.user.id, rows[0].id]);
  res.status(201).json({ child: childDtoForParent(rows[0]) });
});

router.delete('/children/:id', async (req, res) => {
  const { rowCount } = await query('DELETE FROM parent_children WHERE parent_id = $1 AND child_id = $2', [req.user.id, parseId(req.params.id)]);
  if (!rowCount) throw notFound('Enfant introuvable');
  res.status(204).end();
});

router.get('/children', async (req, res) => {
  const { rows } = await query(
    `SELECT c.* FROM children c JOIN parent_children pc ON pc.child_id = c.id
     WHERE pc.parent_id = $1 ORDER BY lower(c.last_name), lower(c.first_name)`,
    [req.user.id],
  );
  res.json({ children: rows.map(childDtoForParent) });
});

// Présences/absences des enfants du parent, par ordre alphabétique d'enfant puis par date.
router.get('/attendance', async (req, res) => {
  const year = resolveYear(req.query.year);
  const { rows } = await query(
    `SELECT c.id AS child_id, c.last_name, c.first_name, c.legion,
            e.id AS event_id, e.name, e.kind, e.event_date, a.status, a.marked_at, u.full_name AS marked_by
     FROM parent_children pc
     JOIN children c ON c.id = pc.child_id
     JOIN attendance a ON a.child_id = c.id
     JOIN events e ON e.id = a.event_id AND e.year = $2
     LEFT JOIN users u ON u.id = a.marked_by
     WHERE pc.parent_id = $1
     ORDER BY lower(c.last_name), lower(c.first_name), e.event_date NULLS LAST, e.position, e.id`,
    [req.user.id, year],
  );
  res.json({
    year,
    records: rows.map((r) => ({
      childId: r.child_id,
      childName: `${r.last_name} ${r.first_name}`,
      legion: r.legion,
      eventId: r.event_id,
      eventName: r.name,
      eventKind: r.kind,
      eventDate: r.event_date,
      status: r.status,
      markedAt: r.marked_at,
      markedBy: r.marked_by,
    })),
  });
});

// Cotisations de l'année pour chaque enfant lié (montant défini par les responsables).
router.get('/dues', async (req, res) => {
  const year = resolveYear(req.query.year);
  await ensureYear(year);
  const { rows } = await query(
    `SELECT c.id AS child_id, c.last_name, c.first_name,
            d.id AS due_id, d.kind, d.label, d.amount, e.event_date,
            p.status, p.method, p.updated_at
     FROM parent_children pc
     JOIN children c ON c.id = pc.child_id
     CROSS JOIN dues d
     LEFT JOIN events e ON e.id = d.event_id
     LEFT JOIN payments p ON p.due_id = d.id AND p.child_id = c.id
     WHERE pc.parent_id = $1 AND d.year = $2 AND d.amount IS NOT NULL AND d.amount > 0
     ORDER BY lower(c.last_name), lower(c.first_name),
       CASE d.kind WHEN 'paroissiale' THEN 0 WHEN 'diocesaine' THEN 1 ELSE 2 END, e.position, e.event_date NULLS LAST`,
    [req.user.id, year],
  );
  res.json({
    year,
    paymentMode: waveMode(),
    dues: rows.map((r) => ({
      childId: r.child_id,
      childName: `${r.last_name} ${r.first_name}`,
      dueId: r.due_id,
      kind: r.kind,
      label: r.label,
      amount: r.amount,
      eventDate: r.event_date,
      status: r.status ?? 'unpaid',
      method: r.method ?? null,
      updatedAt: r.updated_at ?? null,
    })),
  });
});

export async function assertParentOwnsChild(parentId, childId) {
  const { rowCount } = await query('SELECT 1 FROM parent_children WHERE parent_id = $1 AND child_id = $2', [parentId, childId]);
  if (!rowCount) throw badRequest('Enfant non rattaché à votre compte');
}

export default router;
