// Codes à usage unique d'une application d'authentification (Google Authenticator, Microsoft Authenticator…).
// Norme TOTP (RFC 6238) : HMAC-SHA1, 6 chiffres, période de 30 s. Aucune dépendance, aucun réseau.
import crypto from 'node:crypto';
import { config } from '../config.js';

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const PERIOD = 30;
const DIGITS = 6;

export function base32Encode(buf) {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

export function base32Decode(str) {
  const clean = String(str).toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0;
  let value = 0;
  const out = [];
  for (const ch of clean) {
    value = (value << 5) | B32.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

export const generateSecret = () => base32Encode(crypto.randomBytes(20));

export function totpAt(secret, step) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const hmac = crypto.createHmac('sha1', base32Decode(secret)).update(counter).digest();
  const offset = hmac[hmac.length - 1] & 15;
  const bin = ((hmac[offset] & 127) << 24) | (hmac[offset + 1] << 16) | (hmac[offset + 2] << 8) | hmac[offset + 3];
  return String(bin % 10 ** DIGITS).padStart(DIGITS, '0');
}

export const currentStep = (now = Date.now()) => Math.floor(now / 1000 / PERIOD);

// Vérifie un code (tolérance d'une période avant/après pour l'horloge du téléphone).
// Renvoie la période utilisée, ou null. Un code déjà utilisé (période <= lastStep) est refusé (pas de rejeu).
export function verifyTotp(secret, code, lastStep = null, now = Date.now()) {
  if (!/^\d{6}$/.test(String(code))) return null;
  const step = currentStep(now);
  for (const s of [step - 1, step, step + 1]) {
    if (lastStep != null && s <= Number(lastStep)) continue;
    const expected = Buffer.from(totpAt(secret, s));
    if (crypto.timingSafeEqual(expected, Buffer.from(String(code)))) return s;
  }
  return null;
}

export function otpauthUri(secret, account) {
  const issuer = 'My CVAV';
  return `otpauth://totp/${encodeURIComponent(`${issuer}:${account}`)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}`
    + `&algorithm=SHA1&digits=${DIGITS}&period=${PERIOD}`;
}

// Le secret est chiffré en base (AES-256-GCM, clé dérivée du secret du serveur) : une fuite de la base ne suffit pas.
const KEY = Buffer.from(crypto.hkdfSync('sha256', config.jwtSecret, 'my-cvav', 'totp-secrets', 32));

export function encryptSecret(secret) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', KEY, iv);
  const data = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  return `v1:${iv.toString('base64')}:${cipher.getAuthTag().toString('base64')}:${data.toString('base64')}`;
}

export function decryptSecret(stored) {
  const [version, iv, tag, data] = String(stored).split(':');
  if (version !== 'v1') throw new Error('Format de secret inconnu');
  const decipher = crypto.createDecipheriv('aes-256-gcm', KEY, Buffer.from(iv, 'base64'));
  decipher.setAuthTag(Buffer.from(tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(data, 'base64')), decipher.final()]).toString('utf8');
}

// Codes de secours : 8 codes « XXXX-XXXX », chacun utilisable une fois, conservés sous forme d'empreinte.
const RECOVERY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const recoveryHash = (code) => crypto.createHmac('sha256', KEY).update(`recovery:${normalizeRecovery(code)}`).digest('hex');
export const normalizeRecovery = (code) => String(code).toUpperCase().replace(/[^A-Z0-9]/g, '');
export const isRecoveryFormat = (code) => /^[A-Z0-9]{8}$/.test(normalizeRecovery(code)) && !/^\d+$/.test(normalizeRecovery(code));

export function generateRecoveryCodes(n = 8) {
  const codes = Array.from({ length: n }, () => {
    const raw = Array.from({ length: 8 }, () => RECOVERY_ALPHABET[crypto.randomInt(RECOVERY_ALPHABET.length)]).join('');
    return `${raw.slice(0, 4)}-${raw.slice(4)}`;
  });
  return { codes, hashes: codes.map(recoveryHash) };
}

// Renvoie la liste des empreintes restantes si le code est valide, sinon null.
export function consumeRecoveryCode(hashes, code) {
  const h = recoveryHash(code);
  const list = Array.isArray(hashes) ? hashes : [];
  const idx = list.findIndex((x) => x.length === h.length && crypto.timingSafeEqual(Buffer.from(x), Buffer.from(h)));
  return idx === -1 ? null : list.filter((_, i) => i !== idx);
}
