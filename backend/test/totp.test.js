// Double vérification administrateur par application d'authentification (TOTP) et codes de secours.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import { freshApp, register, pool, consoleOutbox } from './helpers.js';
import { totpAt, currentStep, verifyTotp, base32Decode, base32Encode } from '../src/services/totp.js';

let api;
let admin;
let secret;
let recoveryCodes;
const PASSWORD = 'Admin-pass-2026';

async function startLogin() {
  const res = await api.post('/api/auth/login').send({ phone: '0100000000', password: PASSWORD });
  assert.equal(res.status, 200);
  assert.equal(res.body.twoFactorRequired, true);
  return res.body;
}

before(async () => {
  api = await freshApp();
  await pool.query(
    `INSERT INTO users (role, full_name, phone, password_hash) VALUES ('admin', 'Admin', '0100000000', $1)`,
    [await bcrypt.hash(PASSWORD, 10)],
  );
  const first = await startLogin();
  const code = consoleOutbox.at(-1).message.match(/\b(\d{6})\b/)[1];
  const res = await api.post('/api/auth/login/verify').send({ challengeId: first.challengeId, code });
  admin = { Authorization: `Bearer ${res.body.token}` };
});
after(() => pool.end());

test('TOTP : conforme à la norme RFC 6238 (vecteur de test officiel)', () => {
  // Secret ASCII "12345678901234567890", T = 59 s -> 94287082 (8 chiffres) : les 6 derniers sont 287082.
  const rfcSecret = base32Encode(Buffer.from('12345678901234567890'));
  assert.equal(totpAt(rfcSecret, 1), '287082');
  assert.equal(base32Decode(rfcSecret).toString(), '12345678901234567890');
  assert.equal(verifyTotp(rfcSecret, '287082', null, 59_000), 1);
  assert.equal(verifyTotp(rfcSecret, '287082', 1, 59_000), null, 'pas de rejeu');
  assert.equal(verifyTotp(rfcSecret, '000000', null, 59_000), null);
});

test("activation : mot de passe exigé, premier code vérifié, codes de secours donnés une seule fois", async () => {
  assert.equal((await api.post('/api/auth/totp/setup').set(admin).send({ currentPassword: 'faux' })).status, 400);
  const setup = await api.post('/api/auth/totp/setup').set(admin).send({ currentPassword: PASSWORD });
  assert.equal(setup.status, 200);
  secret = setup.body.secret;
  assert.match(setup.body.uri, /^otpauth:\/\/totp\/.*secret=[A-Z2-7]+.*issuer=My%20CVAV/);
  const stored = await pool.query('SELECT totp_pending_secret FROM users WHERE phone = $1', ['0100000000']);
  assert.ok(!stored.rows[0].totp_pending_secret.includes(secret), 'secret chiffré en base');

  assert.equal((await api.post('/api/auth/totp/enable').set(admin).send({ code: '000000' })).status, 400);
  const ok = await api.post('/api/auth/totp/enable').set(admin).send({ code: totpAt(secret, currentStep()) });
  assert.equal(ok.status, 200);
  recoveryCodes = ok.body.recoveryCodes;
  assert.equal(recoveryCodes.length, 8);
  assert.match(recoveryCodes[0], /^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
  const me = await api.get('/api/auth/me').set(admin);
  assert.equal(me.body.user.totpEnabled, true);
});

test("connexion : plus de SMS, code de l'application exigé, sans rejeu", async () => {
  const smsBefore = consoleOutbox.length;
  const challenge = await startLogin();
  assert.equal(challenge.method, 'totp');
  assert.equal(consoleOutbox.length, smsBefore, 'aucun SMS envoyé');
  // Le code de la période courante a déjà servi à l'activation : on prend celui de la période suivante (tolérance ±1).
  const code = totpAt(secret, currentStep() + 1);
  const ok = await api.post('/api/auth/login/verify').send({ challengeId: challenge.challengeId, code });
  assert.equal(ok.status, 200);
  assert.ok(ok.body.token);
  const again = await startLogin();
  const replay = await api.post('/api/auth/login/verify').send({ challengeId: again.challengeId, code });
  assert.equal(replay.status, 400, 'un code déjà utilisé est refusé');
});

test('codes de secours : chacun ne sert qu’une fois, faux codes refusés et journalisés', async () => {
  const c1 = await startLogin();
  const used = await api.post('/api/auth/login/verify').send({ challengeId: c1.challengeId, code: recoveryCodes[0].toLowerCase() });
  assert.equal(used.status, 200, 'insensible à la casse');
  admin = { Authorization: `Bearer ${used.body.token}` };
  const c2 = await startLogin();
  assert.equal((await api.post('/api/auth/login/verify').send({ challengeId: c2.challengeId, code: recoveryCodes[0] })).status, 400);
  for (const code of ['ABCD-EFGH', "' OR 1=1--", '12345678', 'x'.repeat(19)]) {
    assert.equal((await api.post('/api/auth/login/verify').send({ challengeId: c2.challengeId, code })).status, 400, code);
  }
  const sec = await api.get('/api/admin/security').set(admin);
  const types = sec.body.events.map((e) => e.type);
  assert.ok(types.includes('recovery_code_used'));
  assert.ok(types.includes('totp_enabled'));
  assert.ok(types.includes('admin_2fa_failed'));
});

test('régénérer les codes de secours, puis désactiver : retour au SMS ; réservé aux administrateurs', async () => {
  const regen = await api.post('/api/auth/totp/recovery-codes').set(admin).send({ currentPassword: PASSWORD });
  assert.equal(regen.status, 200);
  assert.notEqual(regen.body.recoveryCodes[0], recoveryCodes[1]);

  const parent = await register(api, { phone: '0700000002', name: 'Parent' });
  assert.equal((await api.post('/api/auth/totp/setup').set(parent.auth).send({ currentPassword: 'motdepasse1' })).status, 403);

  assert.equal((await api.post('/api/auth/totp/disable').set(admin).send({ currentPassword: 'faux' })).status, 400);
  assert.equal((await api.post('/api/auth/totp/disable').set(admin).send({ currentPassword: PASSWORD })).status, 200);
  const challenge = await startLogin();
  assert.equal(challenge.method, 'sms');
});
