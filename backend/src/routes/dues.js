import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { LEGIONS } from '../domain.js';
import { badRequest, notFound, parseBody, parseId } from '../errors.js';
import { childDto } from '../services/children.js';
import { ensureYear, resolveYear } from '../services/year.js';

const router = Router();

export function dueDto(r) {
  return {
    id: r.id,
    kind: r.kind,
    year: r.year,
    label: r.label,
    amount: r.amount,
    eventId: r.event_id,
    eventDate: r.event_date ?? null,
    paidCount: r.paid_count != null ? Number(r.paid_count) : undefined,
    pendingCount: r.pending_count != null ? Number(r.pending_count) : undefined,
    collected: r.collected != null ? Number(r.collected) : undefined,
  };
}

const DUE_SELECT = `
  SELECT d.*, e.event_date, e.position,
    (SELECT count(*) FROM payments p WHERE p.due_id = d.id AND p.status = 'paid') AS paid_count,
    (SELECT count(*) FROM payments p WHERE p.due_id = d.id AND p.status = 'pending') AS pending_count,
    (SELECT COALESCE(sum(COALESCE(p.amount, d.amount, 0)), 0) FROM payments p WHERE p.due_id = d.id AND p.status = 'paid') AS collected
  FROM dues d LEFT JOIN events e ON e.id = d.event_id`;

router.get('/', async (req, res) => {
  const year = resolveYear(req.query.year);
  await ensureYear(year);
  const { rows } = await query(
    `${DUE_SELECT} WHERE d.year = $1
     ORDER BY CASE d.kind WHEN 'paroissiale' THEN 0 WHEN 'diocesaine' THEN 1 ELSE 2 END, e.position, e.event_date NULLS LAST, d.id`,
    [year],
  );
  const { rows: count } = await query('SELECT count(*)::int AS n FROM children');
  res.json({ year, childrenCount: count[0].n, dues: rows.map(dueDto) });
});

router.put('/:id', async (req, res) => {
  const { amount } = parseBody(z.object({ amount: z.number().int().min(0).max(10_000_000).nullable() }), req.body);
  const { rows } = await query('UPDATE dues SET amount = $2 WHERE id = $1 RETURNING *', [parseId(req.params.id), amount]);
  if (!rows[0]) throw notFound('Cotisation introuvable');
  res.json({ due: dueDto(rows[0]) });
});

router.get('/:id/payments', async (req, res) => {
  const id = parseId(req.params.id);
  const { rows: due } = await query(`${DUE_SELECT} WHERE d.id = $1`, [id]);
  if (!due[0]) throw notFound('Cotisation introuvable');
  const params = [id];
  let filter = '';
  if (req.query.legion) {
    if (!LEGIONS.includes(req.query.legion)) throw badRequest('Légion invalide');
    params.push(req.query.legion);
    filter = 'WHERE c.legion = $2';
  }
  const { rows } = await query(
    `SELECT c.*, p.status, p.method, p.reference, p.updated_at AS paid_at, u.full_name AS updated_by_name
     FROM children c
     LEFT JOIN payments p ON p.child_id = c.id AND p.due_id = $1
     LEFT JOIN users u ON u.id = p.updated_by
     ${filter}
     ORDER BY lower(c.last_name), lower(c.first_name)`,
    params,
  );
  res.json({
    due: dueDto(due[0]),
    entries: rows.map((r) => ({
      child: childDto(r),
      status: r.status ?? 'unpaid',
      method: r.method ?? null,
      reference: r.reference ?? null,
      updatedAt: r.paid_at ?? null,
      updatedBy: r.updated_by_name ?? null,
    })),
  });
});

const paymentsSchema = z.object({
  entries: z.array(z.object({ childId: z.number().int().positive(), paid: z.boolean() })).min(1).max(2000),
});

// Le responsable coche / décoche les enfants ayant payé.
router.put('/:id/payments', async (req, res) => {
  const id = parseId(req.params.id);
  const { entries } = parseBody(paymentsSchema, req.body);
  const { rows: due } = await query('SELECT * FROM dues WHERE id = $1', [id]);
  if (!due[0]) throw notFound('Cotisation introuvable');
  await withTransaction(async (client) => {
    for (const { childId, paid } of entries) {
      if (paid) {
        await client.query(
          `INSERT INTO payments (due_id, child_id, status, method, amount, updated_by)
           SELECT $1, c.id, 'paid', 'manuel', $3, $4 FROM children c WHERE c.id = $2
           ON CONFLICT (due_id, child_id) DO UPDATE SET status = 'paid', updated_by = EXCLUDED.updated_by, updated_at = now(),
             amount = COALESCE(payments.amount, EXCLUDED.amount)`,
          [id, childId, due[0].amount, req.user.id],
        );
      } else {
        await client.query(`DELETE FROM payments WHERE due_id = $1 AND child_id = $2 AND method <> 'wave'`, [id, childId]);
      }
    }
  });
  res.json({ saved: entries.length });
});

export default router;
