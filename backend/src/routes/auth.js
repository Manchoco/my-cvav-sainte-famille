import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { config } from '../config.js';
import { query, withTransaction } from '../db.js';
import { LEGIONS, normalizePhone } from '../domain.js';
import { HttpError, badRequest, parseBody } from '../errors.js';
import { authenticate, signToken } from '../middleware/auth.js';
import { sendSms, smsProvider } from '../services/sms.js';

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

// --- Mot de passe oublié : code à 6 chiffres envoyé par SMS ---

const RESET_TTL_MINUTES = 10;
const RESET_MAX_ATTEMPTS = 5;
const RESET_MAX_PER_HOUR = 3;

const hashResetCode = (userId, code) =>
  crypto.createHmac('sha256', config.jwtSecret).update(`reset:${userId}:${code}`).digest('hex');

router.post('/password/forgot', authLimiter, async (req, res) => {
  const { phone: raw } = parseBody(z.object({ phone: z.string() }), req.body);
  if (smsProvider() === 'disabled') {
    throw new HttpError(503, "L'envoi de SMS n'est pas encore configuré. Contactez un responsable CVAV.");
  }
  const phone = normalizePhone(raw);
  if (!phone) throw badRequest('Numéro de téléphone invalide');
  const { rows } = await query('SELECT id FROM users WHERE phone = $1', [phone]);
  const user = rows[0];
  // Même réponse que le numéro existe ou non (pas de divulgation des comptes).
  if (user) {
    const { rows: recent } = await query(
      `SELECT count(*)::int AS n FROM password_resets WHERE user_id = $1 AND created_at > now() - interval '1 hour'`,
      [user.id],
    );
    if (recent[0].n < RESET_MAX_PER_HOUR) {
      const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
      await query(
        `INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES ($1, $2, now() + ($3 || ' minutes')::interval)`,
        [user.id, hashResetCode(user.id, code), String(RESET_TTL_MINUTES)],
      );
      try {
        await sendSms(phone, `My CVAV : votre code de réinitialisation est ${code}. Il expire dans ${RESET_TTL_MINUTES} minutes. Ne le communiquez à personne.`);
      } catch (err) {
        console.error('Envoi SMS échoué', err.message);
        throw new HttpError(502, "Le SMS n'a pas pu être envoyé. Réessayez dans quelques minutes.");
      }
    }
  }
  res.json({ sent: true, expiresInMinutes: RESET_TTL_MINUTES });
});

const resetSchema = z.object({
  phone: z.string(),
  code: z.string().trim().regex(/^\d{6}$/, 'Le code contient 6 chiffres'),
  newPassword: z.string().min(8, 'Le mot de passe doit contenir au moins 8 caractères').max(128),
});

router.post('/password/reset', authLimiter, async (req, res) => {
  const data = parseBody(resetSchema, req.body);
  const phone = normalizePhone(data.phone);
  const invalid = () => new HttpError(400, 'Code incorrect ou expiré. Demandez un nouveau code.');
  if (!phone) throw invalid();
  const { rows } = await query(
    `SELECT r.id, r.user_id, r.code_hash, r.attempts FROM password_resets r JOIN users u ON u.id = r.user_id
     WHERE u.phone = $1 AND r.used_at IS NULL AND r.expires_at > now()
     ORDER BY r.created_at DESC LIMIT 1`,
    [phone],
  );
  const reset = rows[0];
  if (!reset || reset.attempts >= RESET_MAX_ATTEMPTS) throw invalid();
  const expected = Buffer.from(reset.code_hash, 'hex');
  const given = Buffer.from(hashResetCode(reset.user_id, data.code), 'hex');
  if (!crypto.timingSafeEqual(expected, given)) {
    await query('UPDATE password_resets SET attempts = attempts + 1 WHERE id = $1', [reset.id]);
    throw invalid();
  }
  const hash = await bcrypt.hash(data.newPassword, 10);
  const user = await withTransaction(async (client) => {
    await client.query('UPDATE password_resets SET used_at = now() WHERE user_id = $1 AND used_at IS NULL', [reset.user_id]);
    const { rows: updated } = await client.query(
      `UPDATE users SET password_hash = $2, token_version = token_version + 1, failed_logins = 0, locked_until = NULL
       WHERE id = $1 RETURNING *`,
      [reset.user_id, hash],
    );
    return updated[0];
  });
  res.json({ token: signToken(user), user: publicUser(user) });
});

export default router;
