// Paramètres modifiables par l'administrateur depuis l'application (maintenance, mises à jour, code d'accès).
import { config } from '../config.js';
import { query } from '../db.js';

const DEFAULTS = {
  maintenance: { enabled: false, message: "L'application est en maintenance. Merci de réessayer un peu plus tard." },
  app_update: { latestBuild: 0, minBuild: 0, url: '', notes: '' },
  signup_code: null,
};

// Cache court : en serverless chaque instance relit la base au plus toutes les 5 secondes.
let cache = null;
let cachedAt = 0;
const TTL_MS = 5000;

export async function getSettings() {
  if (cache && Date.now() - cachedAt < TTL_MS) return cache;
  const { rows } = await query('SELECT key, value FROM app_settings');
  const stored = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  cache = {
    maintenance: { ...DEFAULTS.maintenance, ...(stored.maintenance || {}) },
    app_update: { ...DEFAULTS.app_update, ...(stored.app_update || {}) },
    // Le code enregistré par l'administrateur remplace celui de la variable d'environnement.
    signupCode: stored.signup_code?.code || config.responsableSignupCode || '',
  };
  cachedAt = Date.now();
  return cache;
}

export async function setSetting(key, value, userId) {
  await query(
    `INSERT INTO app_settings (key, value, updated_by, updated_at) VALUES ($1, $2, $3, now())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, updated_at = now()`,
    [key, JSON.stringify(value), userId],
  );
  cache = null;
}

export function resetSettingsCache() {
  cache = null;
}
