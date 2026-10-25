// Surveillance de sécurité : journal des tentatives suspectes, détection des attaques, blocage d'adresses IP.
import { query } from '../db.js';

// Adresse IP normalisée (IPv4 « mappée » en IPv6 ramenée à sa forme courte).
export function clientIp(req) {
  const ip = req?.ip ?? null;
  return ip && ip.startsWith('::ffff:') ? ip.slice(7) : ip;
}

// Libellé et conduite à tenir pour chaque type d'événement (affichés dans l'administration).
export const EVENT_TYPES = {
  login_failed: {
    label: 'Échec de connexion',
    advice: "Isolé : sans gravité (erreur de saisie). Répété depuis la même adresse : tentative de deviner des mots de passe, bloquez l'adresse IP.",
  },
  account_locked: {
    label: 'Compte bloqué 15 min (5 échecs)',
    advice: "Prévenez le titulaire. S'il n'est pas à l'origine des essais, donnez-lui un nouveau mot de passe provisoire et bloquez l'adresse IP.",
  },
  admin_login_failed: {
    label: 'Échec de connexion sur un compte administrateur',
    advice: "Si ce n'est pas vous : changez immédiatement votre mot de passe (Profil) et bloquez l'adresse IP. La vérification par SMS empêche l'accès sans votre téléphone.",
  },
  admin_2fa_failed: {
    label: 'Code de vérification administrateur incorrect',
    advice: "Le mot de passe administrateur a été saisi correctement mais pas le code de vérification : si ce n'est pas vous, votre mot de passe est connu. Changez-le tout de suite.",
  },
  recovery_code_used: {
    label: 'Code de secours administrateur utilisé',
    advice: "Normal si vous avez perdu l'accès à votre application d'authentification. Sinon, vos codes de secours sont connus : régénérez-les (Profil) et changez votre mot de passe.",
  },
  totp_enabled: {
    label: "Application d'authentification activée",
    advice: "Vérifiez que c'est bien vous qui l'avez activée. Sinon, changez immédiatement votre mot de passe.",
  },
  totp_disabled: {
    label: "Application d'authentification désactivée",
    advice: "La connexion administrateur repasse au code SMS. Si ce n'est pas vous, changez votre mot de passe et réactivez l'application.",
  },
  admin_login: {
    label: 'Connexion administrateur',
    advice: "Vérifiez que c'est bien vous. Sinon : changez le mot de passe, utilisez « Déconnecter ses appareils » sur le compte et bloquez l'adresse IP.",
  },
  rate_limited: {
    label: 'Trop de requêtes (limitation automatique)',
    advice: "Les requêtes ont été freinées automatiquement. Si l'adresse revient souvent, bloquez-la.",
  },
  invalid_token: {
    label: 'Jeton de connexion falsifié',
    advice: "Quelqu'un a envoyé un jeton de session fabriqué : tentative d'usurpation, refusée. Bloquez l'adresse IP si cela se répète.",
  },
  forbidden: {
    label: 'Accès à une fonction non autorisée',
    advice: "Un compte a tenté d'utiliser une fonction réservée à un autre rôle (ex. un parent vers l'administration). Vérifiez ce compte et désactivez-le en cas de doute.",
  },
  disabled_account: {
    label: 'Utilisation d’un compte désactivé',
    advice: "Le compte reste bloqué. Si les essais continuent, bloquez l'adresse IP.",
  },
  suspicious_input: {
    label: "Tentative d'injection (SQL, script…)",
    advice: "Une requête contenait du code malveillant ; elle a été traitée sans danger (requêtes protégées). C'est un signe de piratage actif : bloquez l'adresse IP et vérifiez le compte concerné.",
  },
  reset_code_failed: {
    label: 'Code SMS de réinitialisation incorrect',
    advice: "Isolé : sans gravité. Répété : quelqu'un essaie de prendre le contrôle du compte ; prévenez le titulaire.",
  },
  link_code_failed: {
    label: 'Code enfant incorrect',
    advice: "Répété par le même compte parent : tentative d'accès aux données d'autres enfants. Désactivez ce compte.",
  },
  webhook_invalid: {
    label: 'Faux avis de paiement Wave',
    advice: "Quelqu'un a tenté de faire passer une cotisation pour payée. Rien n'a été enregistré. Bloquez l'adresse IP.",
  },
  admin_alert_sent: {
    label: "Alerte SMS envoyée à l'administrateur",
    advice: "Une alerte vous a été envoyée par SMS (au plus une par heure). Consultez les événements juste avant.",
  },
  blocked_ip: {
    label: 'Requête depuis une adresse bloquée',
    advice: "L'adresse est déjà bloquée : rien à faire.",
  },
};

// Garde-fou : au plus N événements écrits par minute et par instance (un attaquant ne doit pas pouvoir remplir la base).
const MAX_PER_MINUTE = 120;
let windowStart = 0;
let windowCount = 0;

export async function securityEvent(req, type, { severity = 'warning', userId = null, phone = null, details = null } = {}) {
  const now = Date.now();
  if (now - windowStart > 60_000) { windowStart = now; windowCount = 0; }
  if (windowCount >= MAX_PER_MINUTE) return;
  windowCount += 1;
  try {
    await query(
      `INSERT INTO security_events (type, severity, ip, user_id, phone, path, details) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [type, severity, clientIp(req), userId ?? req?.user?.id ?? null, phone, req?.originalUrl?.split('?')[0]?.slice(0, 200) ?? null,
        details ? JSON.stringify(details) : null],
    );
  } catch (err) {
    console.error('Journal de sécurité indisponible', err.message);
  }
}

// ----- Détection d'injections (journalisation seulement : les requêtes sont de toute façon paramétrées) -----

const INJECTION_PATTERNS = [
  /\bunion\b[\s\S]{0,20}\bselect\b/i,
  /'\s*(or|and)\s+'?\w*'?\s*=\s*'?\w*/i,
  /;\s*(drop|delete|truncate|alter|insert|update)\s+\w/i,
  /\b(pg_sleep|sleep|benchmark|waitfor\s+delay)\s*\(/i,
  /\binformation_schema\b|\bpg_catalog\b/i,
  /<\s*script\b|javascript\s*:|\bon(error|load|click)\s*=/i,
  /\.\.[\\/]\.\.[\\/]/,
];
const DANGEROUS_KEYS = /^(\$|__proto__$|constructor$|prototype$)/;

function findInjection(value, depth = 0) {
  if (depth > 6 || value == null) return null;
  if (typeof value === 'string') {
    const s = value.slice(0, 2000);
    const hit = INJECTION_PATTERNS.find((re) => re.test(s));
    return hit ? s.slice(0, 120) : null;
  }
  if (Array.isArray(value)) {
    for (const v of value.slice(0, 200)) {
      const hit = findInjection(v, depth + 1);
      if (hit) return hit;
    }
    return null;
  }
  if (typeof value === 'object') {
    for (const key of Object.keys(value).slice(0, 200)) {
      if (DANGEROUS_KEYS.test(key)) return `clé « ${key.slice(0, 40)} »`;
      const hit = findInjection(value[key], depth + 1);
      if (hit) return hit;
    }
  }
  return null;
}

export function detectInjection(req, _res, next) {
  // Les mots de passe ne sont jamais analysés ni enregistrés.
  const { password, newPassword, currentPassword, ...body } = (req.body && typeof req.body === 'object') ? req.body : {};
  const sample = findInjection(req.query) || findInjection(body) || findInjection(decodeURIComponentSafe(req.path));
  if (sample) securityEvent(req, 'suspicious_input', { severity: 'critical', details: { extrait: sample } });
  next();
}

function decodeURIComponentSafe(s) {
  try { return decodeURIComponent(s); } catch { return s; }
}

// ----- Blocage d'adresses IP -----

let blocked = new Map();
let blockedLoadedAt = 0;
const BLOCK_CACHE_MS = 15_000;

async function loadBlocked() {
  if (Date.now() - blockedLoadedAt < BLOCK_CACHE_MS) return blocked;
  const { rows } = await query('SELECT ip FROM blocked_ips WHERE expires_at IS NULL OR expires_at > now()');
  blocked = new Map(rows.map((r) => [r.ip, true]));
  blockedLoadedAt = Date.now();
  return blocked;
}

export function resetBlockedCache() {
  blockedLoadedAt = 0;
}

let lastBlockedLog = 0;
export async function blockIpGuard(req, res, next) {
  try {
    const list = await loadBlocked();
    const ip = clientIp(req);
    if (ip && list.has(ip)) {
      if (Date.now() - lastBlockedLog > 60_000) {
        lastBlockedLog = Date.now();
        securityEvent(req, 'blocked_ip', { severity: 'info' });
      }
      return res.status(403).json({ error: 'Accès refusé depuis cette connexion. Contactez un responsable CVAV.' });
    }
  } catch (err) {
    // Base indisponible : on laisse passer plutôt que de bloquer tout le monde.
    console.error('Liste des IP bloquées indisponible', err.message);
  }
  next();
}

// ----- Analyse : menaces détectées et actions recommandées -----

export async function securityOverview(viewerIp = null) {
  const [{ rows: byType }, { rows: topIps }, { rows: targeted }, { rows: events }, { rows: blockedRows }] = await Promise.all([
    query(`SELECT type, severity, count(*) FILTER (WHERE created_at > now() - interval '24 hours')::int AS day,
             count(*)::int AS week
           FROM security_events WHERE created_at > now() - interval '7 days' GROUP BY type, severity`),
    query(`SELECT ip, count(*)::int AS n, count(*) FILTER (WHERE severity = 'critical')::int AS critical,
             array_agg(DISTINCT type) AS types, max(created_at) AS last_seen
           FROM security_events
           WHERE created_at > now() - interval '24 hours' AND ip IS NOT NULL AND type NOT IN ('admin_login', 'blocked_ip', 'admin_alert_sent')
           GROUP BY ip ORDER BY n DESC LIMIT 20`),
    query(`SELECT e.user_id, u.full_name, u.role, count(*)::int AS n, count(DISTINCT e.ip)::int AS ips
           FROM security_events e JOIN users u ON u.id = e.user_id
           WHERE e.created_at > now() - interval '24 hours'
             AND e.type IN ('login_failed', 'admin_login_failed', 'admin_2fa_failed', 'reset_code_failed', 'account_locked')
           GROUP BY e.user_id, u.full_name, u.role HAVING count(*) >= 5 ORDER BY n DESC LIMIT 20`),
    query(`SELECT e.*, u.full_name AS user_name FROM security_events e LEFT JOIN users u ON u.id = e.user_id
           ORDER BY e.created_at DESC LIMIT 200`),
    query(`SELECT b.*, u.full_name AS blocked_by_name FROM blocked_ips b LEFT JOIN users u ON u.id = b.blocked_by
           WHERE b.expires_at IS NULL OR b.expires_at > now() ORDER BY b.created_at DESC`),
  ]);
  const blockedSet = new Set(blockedRows.map((b) => b.ip));
  const count = (type, period = 'day') => byType.filter((r) => r.type === type).reduce((s, r) => s + r[period], 0);

  const threats = [];
  for (const ip of topIps) {
    if (blockedSet.has(ip.ip)) continue;
    if (ip.critical > 0 || ip.n >= 20) {
      const mine = ip.ip === viewerIp;
      threats.push({
        level: ip.critical > 0 ? 'critical' : 'warning',
        title: ip.types.includes('suspicious_input') ? `Tentatives de piratage depuis ${ip.ip}`
          : ip.types.some((t) => t.includes('login')) ? `Force brute sur les mots de passe depuis ${ip.ip}`
            : `Activité anormale depuis ${ip.ip}`,
        detail: `${ip.n} événement(s) en 24 h : ${ip.types.map((t) => EVENT_TYPES[t]?.label ?? t).join(', ')}.`,
        remedy: mine
          ? "C'est l'adresse de votre propre connexion (vous, ou quelqu'un sur le même réseau). Si ce n'est pas vous, changez votre mot de passe ; changez de réseau (Wi-Fi / données mobiles) avant de bloquer."
          : "Bloquez cette adresse IP. Attention : plusieurs abonnés d'un même opérateur mobile peuvent partager une adresse ; préférez un blocage de 24 h.",
        action: mine ? null : { type: 'block_ip', ip: ip.ip },
      });
    }
  }
  for (const t of targeted) {
    threats.push({
      level: t.role === 'admin' ? 'critical' : 'warning',
      title: `Compte ciblé : ${t.full_name}${t.role === 'admin' ? ' (administrateur)' : ''}`,
      detail: `${t.n} échec(s) en 24 h depuis ${t.ips} adresse(s) différente(s).`,
      remedy: t.role === 'admin'
        ? 'Changez votre mot de passe administrateur (Profil). La vérification par SMS protège le compte tant que votre téléphone est en sécurité.'
        : 'Prévenez le titulaire, donnez-lui un nouveau mot de passe provisoire (Comptes) et bloquez les adresses IP concernées.',
      action: { type: 'open_user', userId: t.user_id },
    });
  }
  if (count('invalid_token') >= 3) {
    threats.push({
      level: 'warning',
      title: 'Jetons de connexion falsifiés',
      detail: `${count('invalid_token')} tentative(s) en 24 h d'utiliser une session fabriquée.`,
      remedy: "Elles ont toutes été refusées. Si cela continue, faites changer la clé secrète du serveur (JWT_SECRET dans Vercel) : tout le monde devra se reconnecter.",
    });
  }
  if (count('webhook_invalid') > 0) {
    threats.push({
      level: 'critical',
      title: 'Faux avis de paiement Wave',
      detail: `${count('webhook_invalid')} tentative(s) en 24 h.`,
      remedy: 'Aucune cotisation n’a été validée. Bloquez les adresses concernées et vérifiez les paiements « à confirmer » dans Wave Business avant de les cocher.',
    });
  }
  if (count('forbidden') >= 5) {
    threats.push({
      level: 'warning',
      title: 'Comptes qui explorent des fonctions interdites',
      detail: `${count('forbidden')} tentative(s) en 24 h.`,
      remedy: 'Consultez le journal ci-dessous pour identifier le compte, puis désactivez-le (Comptes).',
    });
  }

  return {
    status: threats.some((t) => t.level === 'critical') ? 'critical' : threats.length ? 'warning' : 'ok',
    threats,
    counts: Object.fromEntries(Object.keys(EVENT_TYPES).map((t) => [t, { day: count(t), week: count(t, 'week') }])),
    viewerIp,
    topIps: topIps.map((r) => ({ ip: r.ip, mine: r.ip === viewerIp, count: r.n, critical: r.critical, types: r.types, lastSeen: r.last_seen, blocked: blockedSet.has(r.ip) })),
    blocked: blockedRows.map((b) => ({ ip: b.ip, reason: b.reason, blockedBy: b.blocked_by_name, createdAt: b.created_at, expiresAt: b.expires_at })),
    events: events.map((e) => ({
      id: Number(e.id),
      type: e.type,
      label: EVENT_TYPES[e.type]?.label ?? e.type,
      advice: EVENT_TYPES[e.type]?.advice ?? null,
      severity: e.severity,
      ip: e.ip,
      user: e.user_name,
      phone: e.phone ? `•••• ${String(e.phone).slice(-4)}` : null,
      path: e.path,
      details: e.details,
      createdAt: e.created_at,
    })),
  };
}

// Nettoyage : les événements de plus de 90 jours sont supprimés (au plus une fois par heure et par instance).
let lastPurge = 0;
export async function purgeOldSecurityEvents() {
  if (Date.now() - lastPurge < 3_600_000) return;
  lastPurge = Date.now();
  await query(`DELETE FROM security_events WHERE created_at < now() - interval '90 days'`);
  await query(`DELETE FROM login_challenges WHERE created_at < now() - interval '1 day'`);
  await query(`DELETE FROM blocked_ips WHERE expires_at IS NOT NULL AND expires_at < now()`);
}

// Réponse des limiteurs de débit : journalise puis renvoie le message prévu.
export function rateLimitHandler(req, res, _next, options) {
  securityEvent(req, 'rate_limited', { details: { limite: options.limit } });
  res.status(options.statusCode).json(typeof options.message === 'object' ? options.message : { error: options.message });
}
