// Administration complète : comptes, maintenance, mises à jour de l'application, code d'accès, journal.
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import { z } from 'zod';
import { query } from '../db.js';
import { LEGIONS, normalizePhone } from '../domain.js';
import { HttpError, badRequest, notFound, parseBody, parseId } from '../errors.js';
import { audit } from '../services/audit.js';
import { getSettings, setSetting } from '../services/settings.js';
import { publicUser } from './auth.js';

const router = Router();
const ROLES = ['parent', 'responsable', 'admin'];
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const randomFrom = (alphabet, n) => Array.from({ length: n }, () => alphabet[crypto.randomInt(alphabet.length)]).join('');
const temporaryPassword = () => randomFrom('abcdefghjkmnpqrstuvwxyz23456789', 10);
const newSignupCode = () => `CVAV-${randomFrom(CODE_ALPHABET, 4)}-${randomFrom(CODE_ALPHABET, 4)}-${randomFrom(CODE_ALPHABET, 4)}`;

const adminUserDto = (u) => ({
  ...publicUser(u),
  disabled: u.disabled,
  lastLoginAt: u.last_login_at,
  createdAt: u.created_at,
  childrenCount: u.children_count != null ? Number(u.children_count) : undefined,
});

async function loadUser(id) {
  const { rows } = await query('SELECT * FROM users WHERE id = $1', [id]);
  if (!rows[0]) throw notFound('Compte introuvable');
  return rows[0];
}

async function assertOtherAdminRemains(user) {
  if (user.role !== 'admin') return;
  const { rows } = await query(`SELECT count(*)::int AS n FROM users WHERE role = 'admin' AND NOT disabled AND id <> $1`, [user.id]);
  if (rows[0].n === 0) throw badRequest('Impossible : ce compte est le dernier administrateur actif');
}

router.get('/overview', async (_req, res) => {
  const [{ rows: roles }, { rows: kids }, { rows: active }] = await Promise.all([
    query('SELECT role, count(*)::int AS n, count(*) FILTER (WHERE disabled)::int AS disabled FROM users GROUP BY role'),
    query('SELECT count(*)::int AS n FROM children'),
    query(`SELECT count(*)::int AS n FROM users WHERE last_login_at > now() - interval '30 days'`),
  ]);
  const settings = await getSettings();
  res.json({
    users: Object.fromEntries(roles.map((r) => [r.role, { total: r.n, disabled: r.disabled }])),
    children: kids[0].n,
    activeLast30Days: active[0].n,
    maintenance: settings.maintenance,
    appUpdate: settings.app_update,
  });
});

// ----- Comptes -----

router.get('/users', async (req, res) => {
  const params = [];
  const where = [];
  if (req.query.role) {
    if (!ROLES.includes(req.query.role)) throw badRequest('Rôle invalide');
    params.push(req.query.role);
    where.push(`u.role = $${params.length}`);
  }
  if (req.query.q) {
    const q = String(req.query.q).trim().toLowerCase().replace(/[\\%_]/g, (c) => `\\${c}`);
    params.push(`%${q}%`);
    where.push(`(lower(u.full_name) LIKE $${params.length} OR u.phone LIKE $${params.length})`);
  }
  const { rows } = await query(
    `SELECT u.*, (SELECT count(*) FROM parent_children pc WHERE pc.parent_id = u.id) AS children_count
     FROM users u ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
     ORDER BY CASE u.role WHEN 'admin' THEN 0 WHEN 'responsable' THEN 1 ELSE 2 END, lower(u.full_name)
     LIMIT 1000`,
    params,
  );
  res.json({ users: rows.map(adminUserDto) });
});

const createSchema = z.object({
  role: z.enum(ROLES),
  fullName: z.string().trim().min(2).max(120),
  phone: z.string().transform((v, ctx) => {
    const phone = normalizePhone(v);
    if (!phone) ctx.addIssue({ code: 'custom', message: 'Numéro de téléphone invalide' });
    return phone;
  }),
  legion: z.enum(LEGIONS).nullable().optional(),
});

// Création d'un compte par l'administrateur : mot de passe provisoire à changer à la première connexion.
router.post('/users', async (req, res) => {
  const data = parseBody(createSchema, req.body);
  const password = temporaryPassword();
  try {
    const { rows } = await query(
      `INSERT INTO users (role, full_name, phone, password_hash, legion, must_change_password)
       VALUES ($1, $2, $3, $4, $5, true) RETURNING *`,
      [data.role, data.fullName, data.phone, await bcrypt.hash(password, 10), data.role === 'parent' ? null : data.legion ?? null],
    );
    await audit(req, 'user.create', `user:${rows[0].id}`, { role: data.role });
    res.status(201).json({ user: adminUserDto(rows[0]), temporaryPassword: password });
  } catch (err) {
    if (err.code === '23505') throw new HttpError(409, 'Un compte existe déjà avec ce numéro');
    throw err;
  }
});

const updateSchema = z.object({
  role: z.enum(ROLES).optional(),
  legion: z.enum(LEGIONS).nullable().optional(),
  disabled: z.boolean().optional(),
  fullName: z.string().trim().min(2).max(120).optional(),
});

router.patch('/users/:id', async (req, res) => {
  const id = parseId(req.params.id);
  const data = parseBody(updateSchema, req.body);
  const user = await loadUser(id);
  if (id === req.user.id && (data.role && data.role !== 'admin' || data.disabled)) {
    throw badRequest('Vous ne pouvez pas retirer vos propres droits ni désactiver votre compte');
  }
  if ((data.role && data.role !== 'admin') || data.disabled) await assertOtherAdminRemains(user);
  const revoke = (data.role && data.role !== user.role) || data.disabled === true;
  const { rows } = await query(
    `UPDATE users SET role = COALESCE($2, role), legion = CASE WHEN $3 THEN $4 ELSE legion END,
       disabled = COALESCE($5, disabled), full_name = COALESCE($6, full_name),
       token_version = token_version + CASE WHEN $7 THEN 1 ELSE 0 END
     WHERE id = $1 RETURNING *`,
    [id, data.role ?? null, 'legion' in data, data.legion ?? null, data.disabled ?? null, data.fullName ?? null, revoke],
  );
  await audit(req, 'user.update', `user:${id}`, data);
  res.json({ user: adminUserDto(rows[0]) });
});

router.post('/users/:id/reset-password', async (req, res) => {
  const id = parseId(req.params.id);
  await loadUser(id);
  const password = temporaryPassword();
  await query(
    `UPDATE users SET password_hash = $2, must_change_password = true, token_version = token_version + 1,
       failed_logins = 0, locked_until = NULL WHERE id = $1`,
    [id, await bcrypt.hash(password, 10)],
  );
  await audit(req, 'user.reset_password', `user:${id}`);
  res.json({ temporaryPassword: password });
});

router.post('/users/:id/logout', async (req, res) => {
  const id = parseId(req.params.id);
  await loadUser(id);
  await query('UPDATE users SET token_version = token_version + 1 WHERE id = $1', [id]);
  await audit(req, 'user.logout', `user:${id}`);
  res.status(204).end();
});

router.delete('/users/:id', async (req, res) => {
  const id = parseId(req.params.id);
  if (id === req.user.id) throw badRequest('Vous ne pouvez pas supprimer votre propre compte');
  const user = await loadUser(id);
  await assertOtherAdminRemains(user);
  await query('DELETE FROM users WHERE id = $1', [id]);
  await audit(req, 'user.delete', `user:${id}`, { role: user.role, fullName: user.full_name });
  res.status(204).end();
});

// ----- Paramètres -----

router.get('/settings', async (_req, res) => {
  const s = await getSettings();
  res.json({ maintenance: s.maintenance, appUpdate: s.app_update, signupCode: s.signupCode });
});

const maintenanceSchema = z.object({ enabled: z.boolean(), message: z.string().trim().min(3).max(500) });

router.put('/settings/maintenance', async (req, res) => {
  const data = parseBody(maintenanceSchema, req.body);
  await setSetting('maintenance', data, req.user.id);
  await audit(req, data.enabled ? 'maintenance.on' : 'maintenance.off', null, { message: data.message });
  res.json({ maintenance: data });
});

const updateInfoSchema = z.object({
  latestBuild: z.number().int().min(0).max(100000),
  minBuild: z.number().int().min(0).max(100000),
  url: z.string().trim().max(500).refine((v) => v === '' || /^https:\/\//.test(v), 'Le lien doit commencer par https://'),
  notes: z.string().trim().max(1000).default(''),
}).refine((d) => d.minBuild <= d.latestBuild, { message: 'La version minimale ne peut pas dépasser la dernière version' });

router.put('/settings/app-update', async (req, res) => {
  const data = parseBody(updateInfoSchema, req.body);
  await setSetting('app_update', data, req.user.id);
  await audit(req, 'app_update.set', null, data);
  res.json({ appUpdate: data });
});

// Nouveau code d'accès responsable (l'ancien cesse immédiatement de fonctionner).
router.post('/settings/signup-code', async (req, res) => {
  const code = newSignupCode();
  await setSetting('signup_code', { code }, req.user.id);
  await audit(req, 'signup_code.rotate');
  res.json({ signupCode: code });
});

// ----- Journal -----

router.get('/audit', async (req, res) => {
  const limit = Math.min(Math.max(Number(req.query.limit) || 100, 1), 500);
  const { rows } = await query(
    `SELECT a.*, u.full_name AS actor FROM audit_log a LEFT JOIN users u ON u.id = a.actor_id
     ORDER BY a.created_at DESC LIMIT $1`,
    [limit],
  );
  res.json({
    entries: rows.map((r) => ({
      id: Number(r.id), action: r.action, target: r.target, details: r.details,
      actor: r.actor, createdAt: r.created_at,
    })),
  });
});

export default router;
