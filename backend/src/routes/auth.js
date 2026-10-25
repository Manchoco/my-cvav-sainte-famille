import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { config } from '../config.js';
import { query, withTransaction } from '../db.js';
import { LEGIONS, normalizePhone } from '../domain.js';
import { HttpError, badRequest, parseBody } from '../errors.js';
import { MaintenanceError, authenticate, signToken } from '../middleware/auth.js';
import { getSettings } from '../services/settings.js';
import { sendSms, smsProvider } from '../services/sms.js';
import { clientIp, rateLimitHandler, securityEvent } from '../services/security.js';

const router = Router();
const MAX_FAILED = 5;
const LOCK_MINUTES = 15;
// Hash factice pour que le temps de réponse ne révèle pas si un numéro existe.
const DUMMY_HASH = bcrypt.hashSync('dummy-password-for-timing', 10);

// Par adresse IP : volontairement large, car de nombreux abonnés mobiles (et le Wi-Fi d'une paroisse)
// partagent la même adresse publique.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 100,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Trop de tentatives, réessayez dans quelques minutes' },
  handler: rateLimitHandler,
});

// Par numéro visé : freine le forçage d'un compte précis, quelle que soit l'adresse de l'attaquant.
const perPhoneLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: (req) => !normalizePhone(req.body?.phone), // numéro invalide : refusé ensuite par la validation
  keyGenerator: (req) => `phone:${normalizePhone(req.body?.phone)}`,
  message: { error: 'Trop de tentatives pour ce numéro, réessayez dans quelques minutes' },
  handler: rateLimitHandler,
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

// Mot de passe administrateur : 12 caractères minimum, avec des lettres et des chiffres.
function assertPasswordPolicy(role, password) {
  if (role !== 'admin') return;
  if (password.length < 12 || !/[A-Za-z]/.test(password) || !/\d/.test(password)) {
    throw badRequest('Mot de passe administrateur : 12 caractères minimum, avec des lettres et des chiffres');
  }
}

function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

export function publicUser(u) {
  return {
    id: u.id, role: u.role, fullName: u.full_name, phone: u.phone, legion: u.legion,
    mustChangePassword: Boolean(u.must_change_password),
  };
}

async function assertNotInMaintenance(user) {
  if (user?.role === 'admin') return;
  const { maintenance } = await getSettings();
  if (maintenance.enabled) throw new MaintenanceError(maintenance.message);
}

router.post('/register', authLimiter, async (req, res) => {
  const data = parseBody(registerSchema, req.body);
  await assertNotInMaintenance(null);
  if (data.role === 'responsable') {
    const { signupCode } = await getSettings();
    if (!signupCode) {
      throw new HttpError(403, "L'inscription des responsables n'est pas encore ouverte. Contactez l'aumônerie.");
    }
    if (!data.signupCode || !safeEqual(data.signupCode.trim(), signupCode)) {
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

router.post('/login', authLimiter, perPhoneLimiter, async (req, res) => {
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
      const { rows: updated } = await query(
        `UPDATE users SET failed_logins = failed_logins + 1,
           locked_until = CASE WHEN failed_logins + 1 >= $2 THEN now() + ($3 || ' minutes')::interval ELSE NULL END
         WHERE id = $1 RETURNING locked_until`,
        [user.id, MAX_FAILED, String(LOCK_MINUTES)],
      );
      const isAdmin = user.role === 'admin';
      await securityEvent(req, isAdmin ? 'admin_login_failed' : 'login_failed', {
        severity: isAdmin ? 'critical' : 'warning', userId: user.id, phone,
      });
      if (updated[0]?.locked_until) {
        await securityEvent(req, 'account_locked', { severity: isAdmin ? 'critical' : 'warning', userId: user.id, phone });
      }
      if (isAdmin) await alertAdmin(req, user, 'tentatives de connexion échouées sur votre compte administrateur');
    } else {
      await securityEvent(req, 'login_failed', { phone, details: { compte: 'inexistant' } });
    }
    throw new HttpError(401, 'Numéro ou mot de passe incorrect');
  }
  if (user.disabled) {
    await securityEvent(req, 'disabled_account', { userId: user.id, phone });
    throw new HttpError(403, "Ce compte a été désactivé. Contactez l'administrateur.");
  }
  await assertNotInMaintenance(user);
  if (user.role === 'admin' && config.adminTwoFactor) {
    return res.json(await startAdminChallenge(req, user));
  }
  await completeLogin(req, user);
  res.json({ token: signToken(user), user: publicUser(user) });
});

async function completeLogin(req, user) {
  await query(
    'UPDATE users SET failed_logins = 0, locked_until = NULL, last_login_at = now(), last_login_ip = $2 WHERE id = $1',
    [user.id, clientIp(req)],
  );
}

// --- Double vérification administrateur : code à 6 chiffres envoyé par SMS ---

const CHALLENGE_TTL_MINUTES = 5;
const CHALLENGE_MAX_ATTEMPTS = 5;
const CHALLENGE_MAX_PER_15MIN = 5;

const phoneHint = (phone) => `•• •• •• ${String(phone).slice(-4, -2)} ${String(phone).slice(-2)}`;

async function startAdminChallenge(req, user) {
  if (smsProvider() === 'disabled') {
    throw new HttpError(503, "Connexion administrateur impossible : l'envoi de SMS n'est pas configuré sur le serveur.");
  }
  const { rows: recent } = await query(
    `SELECT count(*)::int AS n FROM login_challenges WHERE user_id = $1 AND created_at > now() - interval '15 minutes'`,
    [user.id],
  );
  if (recent[0].n >= CHALLENGE_MAX_PER_15MIN) {
    throw new HttpError(429, 'Trop de codes demandés. Réessayez dans 15 minutes.');
  }
  const id = crypto.randomBytes(24).toString('hex');
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  await query(
    `INSERT INTO login_challenges (id, user_id, code_hash, ip, expires_at)
     VALUES ($1, $2, $3, $4, now() + ($5 || ' minutes')::interval)`,
    [id, user.id, hashCode('login', user.id, code), clientIp(req), String(CHALLENGE_TTL_MINUTES)],
  );
  try {
    await sendSms(user.phone, `My CVAV : code de connexion administrateur ${code} (valable ${CHALLENGE_TTL_MINUTES} min). Si ce n'est pas vous, changez votre mot de passe.`);
  } catch (err) {
    console.error('Envoi du code administrateur échoué', err.message);
    throw new HttpError(502, "Le SMS de vérification n'a pas pu être envoyé. Réessayez dans quelques minutes.");
  }
  return { twoFactorRequired: true, challengeId: id, phoneHint: phoneHint(user.phone), expiresInMinutes: CHALLENGE_TTL_MINUTES };
}

const verifySchema = z.object({
  challengeId: z.string().regex(/^[a-f0-9]{48}$/, 'Demande invalide'),
  code: z.string().trim().regex(/^\d{6}$/, 'Le code contient 6 chiffres'),
});

router.post('/login/verify', authLimiter, async (req, res) => {
  const { challengeId, code } = parseBody(verifySchema, req.body);
  const invalid = () => new HttpError(400, 'Code incorrect ou expiré. Reconnectez-vous pour recevoir un nouveau code.');
  const { rows } = await query(
    `SELECT c.*, u.role FROM login_challenges c JOIN users u ON u.id = c.user_id
     WHERE c.id = $1 AND c.used_at IS NULL AND c.expires_at > now()`,
    [challengeId],
  );
  const challenge = rows[0];
  if (!challenge || challenge.attempts >= CHALLENGE_MAX_ATTEMPTS) throw invalid();
  const expected = Buffer.from(challenge.code_hash, 'hex');
  const given = Buffer.from(hashCode('login', challenge.user_id, code), 'hex');
  if (!crypto.timingSafeEqual(expected, given)) {
    await query('UPDATE login_challenges SET attempts = attempts + 1 WHERE id = $1', [challenge.id]);
    await securityEvent(req, 'admin_2fa_failed', { severity: 'critical', userId: challenge.user_id });
    const { rows: u } = await query('SELECT * FROM users WHERE id = $1', [challenge.user_id]);
    if (u[0]) await alertAdmin(req, u[0], 'mot de passe administrateur correct mais code SMS erroné');
    throw invalid();
  }
  // Usage unique, et seul le code le plus récent reste valable.
  await query('UPDATE login_challenges SET used_at = now() WHERE user_id = $1 AND used_at IS NULL', [challenge.user_id]);
  const { rows: users } = await query('SELECT * FROM users WHERE id = $1', [challenge.user_id]);
  const user = users[0];
  if (!user || user.disabled || user.role !== 'admin') throw invalid();
  const newAddress = Boolean(user.last_login_ip && clientIp(req) && user.last_login_ip !== clientIp(req));
  await completeLogin(req, user);
  await securityEvent(req, 'admin_login', { severity: newAddress ? 'warning' : 'info', userId: user.id, details: { nouvelleAdresse: newAddress } });
  res.json({ token: signToken(user), user: publicUser(user) });
});

// Alerte SMS à l'administrateur visé (au plus une par heure).
async function alertAdmin(req, user, reason) {
  try {
    if (smsProvider() === 'disabled') return;
    const { rows } = await query(
      `SELECT 1 FROM security_events WHERE type = 'admin_alert_sent' AND user_id = $1 AND created_at > now() - interval '1 hour' LIMIT 1`,
      [user.id],
    );
    if (rows.length) return;
    await securityEvent(req, 'admin_alert_sent', { severity: 'info', userId: user.id, details: { raison: reason } });
    await sendSms(user.phone, `Alerte My CVAV : ${reason}. Ouvrez Administration > Sécurité. Si ce n'est pas vous, changez votre mot de passe.`);
  } catch (err) {
    console.error('Alerte administrateur non envoyée', err.message);
  }
}

router.get('/me', authenticate, (req, res) => {
  res.json({ user: publicUser(req.user) });
});

const profileSchema = z.object({
  fullName: z.string().trim().min(2, 'Nom trop court').max(120).optional(),
  phone: phoneSchema.optional(),
  currentPassword: z.string().min(1, 'Mot de passe actuel requis').max(128),
});

// Modifier son nom ou son numéro (identifiant de connexion) : le mot de passe actuel est exigé.
router.put('/me', authenticate, authLimiter, async (req, res) => {
  const data = parseBody(profileSchema, req.body);
  const { rows } = await query('SELECT password_hash FROM users WHERE id = $1', [req.user.id]);
  if (!(await bcrypt.compare(data.currentPassword, rows[0].password_hash))) {
    throw badRequest('Mot de passe actuel incorrect');
  }
  try {
    const { rows: updated } = await query(
      'UPDATE users SET full_name = COALESCE($2, full_name), phone = COALESCE($3, phone) WHERE id = $1 RETURNING *',
      [req.user.id, data.fullName ?? null, data.phone ?? null],
    );
    res.json({ user: publicUser(updated[0]) });
  } catch (err) {
    if (err.code === '23505') throw new HttpError(409, 'Ce numéro est déjà utilisé par un autre compte');
    throw err;
  }
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
  assertPasswordPolicy(req.user.role, data.newPassword);
  const hash = await bcrypt.hash(data.newPassword, 10);
  const { rows: updated } = await query(
    `UPDATE users SET password_hash = $2, token_version = token_version + 1, must_change_password = false
     WHERE id = $1 RETURNING *`,
    [req.user.id, hash],
  );
  res.json({ token: signToken(updated[0]), user: publicUser(updated[0]) });
});

router.post('/logout-all', authenticate, async (req, res) => {
  await query('UPDATE users SET token_version = token_version + 1 WHERE id = $1', [req.user.id]);
  res.status(204).end();
});

// --- Mot de passe oublié : code à 6 chiffres envoyé par SMS ---

const RESET_TTL_MINUTES = 10;
const RESET_MAX_ATTEMPTS = 5;
const RESET_MAX_PER_HOUR = 3;

// Clé dérivée (HKDF) : le secret des jetons n'est pas réutilisé tel quel pour les codes SMS.
const RESET_KEY = Buffer.from(crypto.hkdfSync('sha256', config.jwtSecret, 'my-cvav', 'password-reset-codes', 32));
const hashCode = (scope, userId, code) =>
  crypto.createHmac('sha256', RESET_KEY).update(`${scope}:${userId}:${code}`).digest('hex');
const hashResetCode = (userId, code) => hashCode('reset', userId, code);

router.post('/password/forgot', authLimiter, perPhoneLimiter, async (req, res) => {
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
    `SELECT r.id, r.user_id, r.code_hash, r.attempts, u.role FROM password_resets r JOIN users u ON u.id = r.user_id
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
    await securityEvent(req, 'reset_code_failed', { severity: reset.role === 'admin' ? 'critical' : 'warning', userId: reset.user_id, phone });
    throw invalid();
  }
  assertPasswordPolicy(reset.role, data.newPassword);
  const hash = await bcrypt.hash(data.newPassword, 10);
  const user = await withTransaction(async (client) => {
    await client.query('UPDATE password_resets SET used_at = now() WHERE user_id = $1 AND used_at IS NULL', [reset.user_id]);
    const { rows: updated } = await client.query(
      `UPDATE users SET password_hash = $2, token_version = token_version + 1, failed_logins = 0, locked_until = NULL,
         must_change_password = false
       WHERE id = $1 RETURNING *`,
      [reset.user_id, hash],
    );
    return updated[0];
  });
  if (user.disabled) throw new HttpError(403, "Ce compte a été désactivé. Contactez l'administrateur.");
  // Administrateur : pas de connexion directe, il doit se reconnecter (mot de passe + code SMS).
  if (user.role === 'admin' && config.adminTwoFactor) return res.json({ reset: true, loginRequired: true });
  res.json({ token: signToken(user), user: publicUser(user) });
});

export default router;
