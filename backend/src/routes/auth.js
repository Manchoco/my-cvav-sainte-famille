import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { config } from '../config.js';
import { query } from '../db.js';
import { LEGIONS, normalizePhone } from '../domain.js';
import { HttpError, badRequest, parseBody } from '../errors.js';
import { authenticate, signToken } from '../middleware/auth.js';

const router = Router();
const MAX_FAILED = 5;
const LOCK_MINUTES = 15;
// Hash factice pour que le temps de réponse ne révèle pas si un numéro existe.
const DUMMY_HASH = bcrypt.hashSync('dummy-password-for-timing', 10);

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Trop de tentatives, réessayez dans quelques minutes' },
});

const phoneSchema = z.string().transform((v, ctx) => {
  const phone = normalizePhone(v);
  if (!phone) ctx.addIssue({ code: 'custom', message: 'Numéro de téléphone invalide' });
  return phone;
});

const registerSchema = z.object({
  role: z.enum(['responsable', 'parent']),
  fullName: z.string().trim().min(2, 'Nom trop court').max(120),
  phone: phoneSchema,
  password: z.string().min(8, 'Le mot de passe doit contenir au moins 8 caractères').max(128),
  legion: z.enum(LEGIONS).optional().nullable(),
  signupCode: z.string().optional(),
});

function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

export function publicUser(u) {
  return { id: u.id, role: u.role, fullName: u.full_name, phone: u.phone, legion: u.legion };
}

router.post('/register', authLimiter, async (req, res) => {
  const data = parseBody(registerSchema, req.body);
  if (data.role === 'responsable') {
    if (!config.responsableSignupCode) {
      throw new HttpError(403, "L'inscription des responsables n'est pas encore ouverte. Contactez l'aumônerie.");
    }
    if (!data.signupCode || !safeEqual(data.signupCode.trim(), config.responsableSignupCode)) {
      throw new HttpError(403, "Code d'accès responsable incorrect");
    }
  }
  const hash = await bcrypt.hash(data.password, 10);
  try {
    const { rows } = await query(
      `INSERT INTO users (role, full_name, phone, password_hash, legion)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [data.role, data.fullName, data.phone, hash, data.role === 'responsable' ? data.legion ?? null : null],
    );
    const user = rows[0];
    res.status(201).json({ token: signToken(user), user: publicUser(user) });
  } catch (err) {
    if (err.code === '23505') throw new HttpError(409, 'Un compte existe déjà avec ce numéro');
    throw err;
  }
});

const loginSchema = z.object({ phone: z.string(), password: z.string().min(1).max(128) });

router.post('/login', authLimiter, async (req, res) => {
  const { phone: rawPhone, password } = parseBody(loginSchema, req.body);
  const phone = normalizePhone(rawPhone);
  const { rows } = phone ? await query('SELECT * FROM users WHERE phone = $1', [phone]) : { rows: [] };
  const user = rows[0];
  if (user?.locked_until && new Date(user.locked_until) > new Date()) {
    throw new HttpError(429, 'Compte temporairement bloqué après plusieurs échecs. Réessayez plus tard.');
  }
  const ok = await bcrypt.compare(password, user?.password_hash || DUMMY_HASH);
  if (!user || !ok) {
    if (user) {
      await query(
        `UPDATE users SET failed_logins = failed_logins + 1,
           locked_until = CASE WHEN failed_logins + 1 >= $2 THEN now() + ($3 || ' minutes')::interval ELSE NULL END
         WHERE id = $1`,
        [user.id, MAX_FAILED, String(LOCK_MINUTES)],
      );
    }
    throw new HttpError(401, 'Numéro ou mot de passe incorrect');
  }
  await query('UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = $1', [user.id]);
  res.json({ token: signToken(user), user: publicUser(user) });
});

router.get('/me', authenticate, (req, res) => {
  res.json({ user: publicUser(req.user) });
});

const passwordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8, 'Le mot de passe doit contenir au moins 8 caractères').max(128),
});

// Changer le mot de passe invalide toutes les sessions existantes (token_version).
router.post('/password', authenticate, authLimiter, async (req, res) => {
  const data = parseBody(passwordSchema, req.body);
  const { rows } = await query('SELECT password_hash FROM users WHERE id = $1', [req.user.id]);
  if (!(await bcrypt.compare(data.currentPassword, rows[0].password_hash))) {
    throw badRequest('Mot de passe actuel incorrect');
  }
  const hash = await bcrypt.hash(data.newPassword, 10);
  const { rows: updated } = await query(
    'UPDATE users SET password_hash = $2, token_version = token_version + 1 WHERE id = $1 RETURNING *',
    [req.user.id, hash],
  );
  res.json({ token: signToken(updated[0]) });
});

router.post('/logout-all', authenticate, async (req, res) => {
  await query('UPDATE users SET token_version = token_version + 1 WHERE id = $1', [req.user.id]);
  res.status(204).end();
});

export default router;
