import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { LEGIONS } from '../domain.js';
import { badRequest, notFound, parseBody, parseId } from '../errors.js';
import { childDto } from '../services/children.js';
import { ensureYear, resolveYear } from '../services/year.js';
import { amountsByLegion, effectiveAmountSql, legionAmountsSql, saveDueAmounts, uniformAmount } from '../services/dues.js';
import { audit } from '../services/audit.js';

const router = Router();

export function dueDto(r) {
  const amounts = amountsByLegion(r.amount, r.legion_amounts);
  return {
    id: r.id,
    kind: r.kind,
    year: r.year,
    label: r.label,
    // Montant unique (même prix pour toutes les légions) ou null si les prix diffèrent.
    amount: uniformAmount(amounts),
    amounts,
    eventId: r.event_id,
    eventDate: r.event_date ?? null,
    paidCount: r.paid_count != null ? Number(r.paid_count) : undefined,
    pendingCount: r.pending_count != null ? Number(r.pending_count) : undefined,
    collected: r.collected != null ? Number(r.collected) : undefined,
  };
}

const DUE_SELECT = `
  SELECT d.*, e.event_date, e.position, ${legionAmountsSql('d')} AS legion_amounts,
    (SELECT count(*) FROM payments p WHERE p.due_id = d.id AND p.status = 'paid') AS paid_count,
    (SELECT count(*) FROM payments p WHERE p.due_id = d.id AND p.status = 'pending') AS pending_count,
    (SELECT COALESCE(sum(COALESCE(p.amount, ${effectiveAmountSql('d', 'c')}, 0)), 0)
       FROM payments p JOIN children c ON c.id = p.child_id WHERE p.due_id = d.id AND p.status = 'paid') AS collected
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

const amountValue = z.number().int().min(0).max(10_000_000).nullable();
const amountsSchema = z.union([
  // Ancien format (application < 1.2) : un seul montant pour toutes les légions.
  z.object({ amount: amountValue }).strict(),
  z.object({ amounts: z.object(Object.fromEntries(LEGIONS.map((l) => [l, amountValue]))).strict() }).strict(),
]);

// Prix d'une cotisation, légion par légion.
router.put('/:id', async (req, res) => {
  const id = parseId(req.params.id);
  const data = parseBody(amountsSchema, req.body);
  const amounts = 'amounts' in data ? data.amounts : Object.fromEntries(LEGIONS.map((l) => [l, data.amount]));
  await withTransaction(async (client) => {
    const { rowCount } = await client.query('SELECT 1 FROM dues WHERE id = $1 FOR UPDATE', [id]);
    if (!rowCount) throw notFound('Cotisation introuvable');
    await saveDueAmounts(client, id, amounts, req.user.id);
  });
  await audit(req, 'due.amounts', `due:${id}`, amounts);
  const { rows } = await query(`${DUE_SELECT} WHERE d.id = $1`, [id]);
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
    `SELECT c.*, p.status, p.method, p.reference, p.amount AS paid_amount, p.updated_at AS paid_at, u.full_name AS updated_by_name,
       ${effectiveAmountSql('d', 'c')} AS due_amount
     FROM children c
     JOIN dues d ON d.id = $1
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
      amount: r.paid_amount ?? r.due_amount ?? null,
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
           SELECT d.id, c.id, 'paid', 'manuel', ${effectiveAmountSql('d', 'c')}, $3
           FROM children c JOIN dues d ON d.id = $1 WHERE c.id = $2
           ON CONFLICT (due_id, child_id) DO UPDATE SET status = 'paid', updated_by = EXCLUDED.updated_by, updated_at = now(),
             amount = COALESCE(payments.amount, EXCLUDED.amount)`,
          [id, childId, req.user.id],
        );
      } else {
        await client.query(`DELETE FROM payments WHERE due_id = $1 AND child_id = $2 AND method <> 'wave'`, [id, childId]);
      }
    }
  });
  res.json({ saved: entries.length });
});

export default router;
