import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { LEGIONS } from '../domain.js';
import { badRequest, notFound, parseBody, parseId } from '../errors.js';
import { childDto } from '../services/children.js';
import { ensureYear, resolveYear } from '../services/year.js';

const router = Router();

export function eventDto(r) {
  return {
    id: r.id,
    kind: r.kind,
    name: r.name,
    date: r.event_date,
    year: r.year,
    price: r.amount ?? null,
    dueId: r.due_id ?? null,
    present: r.present != null ? Number(r.present) : undefined,
    absent: r.absent != null ? Number(r.absent) : undefined,
  };
}

const EVENT_SELECT = `
  SELECT e.*, d.id AS due_id, d.amount,
    (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.status = 'present') AS present,
    (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.status = 'absent') AS absent
  FROM events e LEFT JOIN dues d ON d.event_id = e.id`;

router.get('/', async (req, res) => {
  const year = resolveYear(req.query.year);
  await ensureYear(year);
  const params = [year];
  let filter = '';
  if (req.query.kind) {
    if (!['activite', 'reunion'].includes(req.query.kind)) throw badRequest('Type invalide');
    params.push(req.query.kind);
    filter = ` AND e.kind = $2`;
  }
  const { rows } = await query(
    `${EVENT_SELECT} WHERE e.year = $1${filter}
     ORDER BY e.kind, CASE WHEN e.kind = 'reunion' THEN e.event_date END DESC NULLS LAST, e.position, e.event_date NULLS LAST, e.id`,
    params,
  );
  res.json({ year, events: rows.map(eventDto) });
});

const eventSchema = z.object({
  kind: z.enum(['activite', 'reunion']),
  name: z.string().trim().min(2).max(120),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().nullable(),
  year: z.string().optional(),
  price: z.number().int().min(0).max(10_000_000).optional().nullable(),
});

router.post('/', async (req, res) => {
  const data = parseBody(eventSchema, req.body);
  const year = resolveYear(data.year);
  await ensureYear(year);
  const event = await withTransaction(async (client) => {
    const { rows } = await client.query(
      `INSERT INTO events (kind, name, event_date, year, created_by) VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [data.kind, data.name, data.date ?? null, year, req.user.id],
    );
    const e = rows[0];
    if (e.kind === 'activite') {
      const { rows: d } = await client.query(
        `INSERT INTO dues (kind, year, event_id, label, amount) VALUES ('activite', $1, $2, $3, $4) RETURNING id, amount`,
        [year, e.id, e.name, data.price ?? null],
      );
      Object.assign(e, { due_id: d[0].id, amount: d[0].amount });
    }
    return e;
  }).catch((err) => {
    if (err.code === '23505') throw badRequest('Cette activité existe déjà pour cette année');
    throw err;
  });
  res.status(201).json({ event: eventDto(event) });
});

const updateSchema = eventSchema.partial().omit({ kind: true, year: true });

router.put('/:id', async (req, res) => {
  const id = parseId(req.params.id);
  const data = parseBody(updateSchema, req.body);
  await withTransaction(async (client) => {
    const { rows } = await client.query(
      `UPDATE events SET name = COALESCE($2, name),
         event_date = CASE WHEN $4 THEN $3::date ELSE event_date END
       WHERE id = $1 RETURNING *`,
      [id, data.name ?? null, data.date ?? null, 'date' in data],
    );
    if (!rows[0]) throw notFound('Activité introuvable');
    if (rows[0].kind === 'activite') {
      if ('price' in data) await client.query('UPDATE dues SET amount = $2 WHERE event_id = $1', [id, data.price ?? null]);
      if (data.name) await client.query('UPDATE dues SET label = $2 WHERE event_id = $1', [id, data.name]);
    }
  });
  const { rows } = await query(`${EVENT_SELECT} WHERE e.id = $1`, [id]);
  res.json({ event: eventDto(rows[0]) });
});

router.delete('/:id', async (req, res) => {
  const { rowCount } = await query('DELETE FROM events WHERE id = $1', [parseId(req.params.id)]);
  if (!rowCount) throw notFound('Activité introuvable');
  res.status(204).end();
});

// --- Présences ---

router.get('/:id/attendance', async (req, res) => {
  const id = parseId(req.params.id);
  const { rows: ev } = await query(`${EVENT_SELECT} WHERE e.id = $1`, [id]);
  if (!ev[0]) throw notFound('Activité introuvable');
  const params = [id];
  let filter = '';
  if (req.query.legion) {
    if (!LEGIONS.includes(req.query.legion)) throw badRequest('Légion invalide');
    params.push(req.query.legion);
    filter = 'WHERE c.legion = $2';
  }
  const { rows } = await query(
    `SELECT c.*, a.status, a.marked_at, u.full_name AS marked_by_name
     FROM children c
     LEFT JOIN attendance a ON a.child_id = c.id AND a.event_id = $1
     LEFT JOIN users u ON u.id = a.marked_by
     ${filter}
     ORDER BY lower(c.last_name), lower(c.first_name)`,
    params,
  );
  res.json({
    event: eventDto(ev[0]),
    entries: rows.map((r) => ({
      child: childDto(r),
      status: r.status ?? null,
      markedAt: r.marked_at ?? null,
      markedBy: r.marked_by_name ?? null,
    })),
  });
});

const attendanceSchema = z.object({
  entries: z.array(z.object({
    childId: z.number().int().positive(),
    status: z.enum(['present', 'absent']).nullable(),
  })).min(1).max(2000),
});

router.put('/:id/attendance', async (req, res) => {
  const id = parseId(req.params.id);
  const { entries } = parseBody(attendanceSchema, req.body);
  const { rowCount } = await query('SELECT 1 FROM events WHERE id = $1', [id]);
  if (!rowCount) throw notFound('Activité introuvable');
  await withTransaction(async (client) => {
    for (const { childId, status } of entries) {
      if (status === null) {
        await client.query('DELETE FROM attendance WHERE event_id = $1 AND child_id = $2', [id, childId]);
      } else {
        await client.query(
          `INSERT INTO attendance (event_id, child_id, status, marked_by)
           SELECT $1, c.id, $3, $4 FROM children c WHERE c.id = $2
           ON CONFLICT (event_id, child_id) DO UPDATE SET status = EXCLUDED.status, marked_by = EXCLUDED.marked_by, marked_at = now()`,
          [id, childId, status, req.user.id],
        );
      }
    }
  });
  res.json({ saved: entries.length });
});

export default router;
