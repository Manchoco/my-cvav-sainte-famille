import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { notFound, parseBody, parseId } from '../errors.js';
import { requireRole } from '../middleware/auth.js';

const router = Router();

const postDto = (r) => ({
  id: r.id, title: r.title, body: r.body, pinned: r.pinned,
  author: r.author ?? null, createdAt: r.created_at, updatedAt: r.updated_at,
});

const postSchema = z.object({
  title: z.string().trim().min(2, 'Titre trop court').max(150),
  body: z.string().trim().min(1, 'Message vide').max(5000),
  pinned: z.boolean().optional().default(false),
});

router.get('/', async (_req, res) => {
  const { rows } = await query(
    `SELECT p.*, u.full_name AS author FROM posts p LEFT JOIN users u ON u.id = p.created_by
     ORDER BY p.pinned DESC, p.created_at DESC LIMIT 200`,
  );
  res.json({ posts: rows.map(postDto) });
});

router.post('/', requireRole('responsable'), async (req, res) => {
  const data = parseBody(postSchema, req.body);
  const { rows } = await query(
    'INSERT INTO posts (title, body, pinned, created_by) VALUES ($1,$2,$3,$4) RETURNING *',
    [data.title, data.body, data.pinned, req.user.id],
  );
  res.status(201).json({ post: postDto({ ...rows[0], author: req.user.full_name }) });
});

router.put('/:id', requireRole('responsable'), async (req, res) => {
  const data = parseBody(postSchema, req.body);
  const { rows } = await query(
    'UPDATE posts SET title=$2, body=$3, pinned=$4, updated_at=now() WHERE id=$1 RETURNING *',
    [parseId(req.params.id), data.title, data.body, data.pinned],
  );
  if (!rows[0]) throw notFound('Information introuvable');
  res.json({ post: postDto(rows[0]) });
});

router.delete('/:id', requireRole('responsable'), async (req, res) => {
  const { rowCount } = await query('DELETE FROM posts WHERE id = $1', [parseId(req.params.id)]);
  if (!rowCount) throw notFound('Information introuvable');
  res.status(204).end();
});

export default router;
