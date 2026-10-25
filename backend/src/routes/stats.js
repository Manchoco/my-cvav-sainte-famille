import { Router } from 'express';
import { query } from '../db.js';
import { LEGIONS } from '../domain.js';
import { ensureYear, resolveYear } from '../services/year.js';
import { effectiveAmountSql } from '../services/dues.js';

const router = Router();

router.get('/', async (req, res) => {
  const year = resolveYear(req.query.year);
  await ensureYear(year);
  const [{ rows: legions }, { rows: dues }, { rows: last }, { rows: pending }, { rows: posts }] = await Promise.all([
    query('SELECT legion, count(*)::int AS n FROM children GROUP BY legion'),
    query(
      `SELECT COALESCE(sum(COALESCE(p.amount, ${effectiveAmountSql('d', 'c')}, 0)), 0)::int AS collected
       FROM payments p JOIN dues d ON d.id = p.due_id JOIN children c ON c.id = p.child_id WHERE d.year = $1 AND p.status = 'paid'`,
      [year],
    ),
    query(
      `SELECT e.id, e.name, e.event_date,
         count(*) FILTER (WHERE a.status = 'present')::int AS present,
         count(*) FILTER (WHERE a.status = 'absent')::int AS absent
       FROM events e JOIN attendance a ON a.event_id = e.id
       WHERE e.year = $1 GROUP BY e.id ORDER BY max(a.marked_at) DESC LIMIT 1`,
      [year],
    ),
    query(`SELECT count(*)::int AS n FROM payments p JOIN dues d ON d.id = p.due_id WHERE d.year = $1 AND p.status = 'pending'`, [year]),
    query('SELECT count(*)::int AS n FROM posts'),
  ]);
  const byLegion = Object.fromEntries(LEGIONS.map((l) => [l, 0]));
  for (const r of legions) byLegion[r.legion] = r.n;
  res.json({
    year,
    totalChildren: Object.values(byLegion).reduce((a, b) => a + b, 0),
    byLegion,
    collected: dues[0].collected,
    pendingPayments: pending[0].n,
    postsCount: posts[0].n,
    lastEvent: last[0] ? { id: last[0].id, name: last[0].name, date: last[0].event_date, present: last[0].present, absent: last[0].absent } : null,
  });
});

export default router;
