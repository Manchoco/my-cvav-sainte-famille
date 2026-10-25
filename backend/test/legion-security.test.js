// Prix des cotisations par légion, double vérification administrateur, surveillance de sécurité.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import { freshApp, register, pool, consoleOutbox } from './helpers.js';
import { resetBlockedCache } from '../src/services/security.js';

let api;
let resp;
let parent;
let benjamin;
let cadet;
let admin;

const lastCode = () => consoleOutbox.at(-1).message.match(/\b(\d{6})\b/)[1];

async function adminLogin(password = 'Admin-pass-2026') {
  const first = await api.post('/api/auth/login').send({ phone: '0100000000', password });
  assert.equal(first.status, 200);
  assert.equal(first.body.twoFactorRequired, true);
  const res = await api.post('/api/auth/login/verify').send({ challengeId: first.body.challengeId, code: lastCode() });
  return { res, auth: { Authorization: `Bearer ${res.body.token}` } };
}

before(async () => {
  api = await freshApp();
  await pool.query(
    `INSERT INTO users (role, full_name, phone, password_hash) VALUES ('admin', 'Admin', '0100000000', $1)`,
    [await bcrypt.hash('Admin-pass-2026', 10)],
  );
  admin = (await adminLogin()).auth;
  resp = await register(api, { role: 'responsable', phone: '0700000001', name: 'Resp' });
  parent = await register(api, { phone: '0700000002', name: 'Parent' });
  benjamin = (await api.post('/api/children').set(resp.auth).send({ lastName: 'KONE', firstName: 'Ali', age: 8, legion: 'benjamins' })).body.child;
  cadet = (await api.post('/api/children').set(resp.auth).send({ lastName: 'KONE', firstName: 'Awa', age: 11, legion: 'cadets' })).body.child;
  await api.post('/api/parent/link').set(parent.auth).send({ code: benjamin.linkCode });
  await api.post('/api/parent/link').set(parent.auth).send({ code: cadet.linkCode });
});
after(() => pool.end());

// ---------- Prix par légion ----------

test('cotisation : prix différents par légion, montant du parent selon la légion de chaque enfant', async () => {
  const dues = (await api.get('/api/dues').set(resp.auth)).body.dues;
  const paroisse = dues.find((d) => d.kind === 'paroissiale');
  assert.deepEqual(paroisse.amounts, { meneurs: 1500, aines: 1500, cadets: 1500, benjamins: 1500 }, 'montant commun par défaut');
  assert.equal(paroisse.amount, 1500);

  const put = await api.put(`/api/dues/${paroisse.id}`).set(resp.auth)
    .send({ amounts: { meneurs: 3000, aines: 2500, cadets: 2000, benjamins: 1000 } });
  assert.equal(put.status, 200);
  assert.deepEqual(put.body.due.amounts, { meneurs: 3000, aines: 2500, cadets: 2000, benjamins: 1000 });
  assert.equal(put.body.due.amount, null, 'prix différents : pas de montant unique');

  const mine = (await api.get('/api/parent/dues').set(parent.auth)).body.dues.filter((d) => d.dueId === paroisse.id);
  assert.equal(mine.find((d) => d.childId === benjamin.id).amount, 1000);
  assert.equal(mine.find((d) => d.childId === cadet.id).amount, 2000);

  const pay = await api.post('/api/payments/wave/checkout').set(parent.auth).send({ dueId: paroisse.id, childId: cadet.id });
  assert.equal(pay.body.amount, 2000);
  assert.match(pay.body.url, /amount=2000/);

  // Le responsable coche : le montant enregistré est celui de la légion.
  await api.put(`/api/dues/${paroisse.id}/payments`).set(resp.auth)
    .send({ entries: [{ childId: benjamin.id, paid: true }, { childId: cadet.id, paid: true }] });
  const list = (await api.get(`/api/dues/${paroisse.id}/payments`).set(resp.auth)).body;
  assert.equal(list.due.collected, 3000);
  assert.equal(list.entries.find((e) => e.child.id === cadet.id).amount, 2000);
  assert.equal((await api.get('/api/stats').set(resp.auth)).body.collected, 3000);

  // Changer le prix ensuite ne modifie pas ce qui a déjà été payé.
  await api.put(`/api/dues/${paroisse.id}`).set(resp.auth).send({ amounts: { meneurs: 9000, aines: 9000, cadets: 9000, benjamins: 9000 } });
  const after = (await api.get(`/api/dues/${paroisse.id}/payments`).set(resp.auth)).body;
  assert.equal(after.due.amount, 9000, 'même prix partout : redevient un montant unique');
  assert.equal(after.due.collected, 3000);
});

test('cotisation : légion sans prix = rien à payer pour ses enfants ; ancien format accepté', async () => {
  const diocese = (await api.get('/api/dues').set(resp.auth)).body.dues.find((d) => d.kind === 'diocesaine');
  await api.put(`/api/dues/${diocese.id}`).set(resp.auth).send({ amounts: { meneurs: null, aines: null, cadets: 500, benjamins: null } });
  const mine = (await api.get('/api/parent/dues').set(parent.auth)).body.dues.filter((d) => d.dueId === diocese.id);
  assert.deepEqual(mine.map((d) => d.childId), [cadet.id]);
  const refused = await api.post('/api/payments/declare').set(parent.auth).send({ dueId: diocese.id, childId: benjamin.id });
  assert.equal(refused.status, 400, 'pas de paiement sans montant fixé');

  const legacy = await api.put(`/api/dues/${diocese.id}`).set(resp.auth).send({ amount: 700 });
  assert.equal(legacy.status, 200);
  assert.deepEqual(Object.values(legacy.body.due.amounts), [700, 700, 700, 700]);

  for (const body of [{ amounts: { cadets: 500 } }, { amounts: { meneurs: -1, aines: 1, cadets: 1, benjamins: 1 } }, { amount: 5, amounts: {} }]) {
    assert.equal((await api.put(`/api/dues/${diocese.id}`).set(resp.auth).send(body)).status, 400, JSON.stringify(body));
  }
  assert.equal((await api.put(`/api/dues/${diocese.id}`).set(parent.auth).send({ amount: 0 })).status, 403);
});

test('activité : prix par légion, puis prix unique depuis la fiche activité', async () => {
  const created = await api.post('/api/events').set(resp.auth).send({ kind: 'activite', name: 'Sortie test', price: 1000 });
  const dueId = created.body.event.dueId;
  await api.put(`/api/dues/${dueId}`).set(resp.auth).send({ amounts: { meneurs: 5000, aines: 4000, cadets: 3000, benjamins: 2000 } });
  let ev = (await api.get('/api/events').set(resp.auth)).body.events.find((e) => e.id === created.body.event.id);
  assert.equal(ev.price, null);
  assert.equal(ev.pricesByLegion.aines, 4000);
  await api.put(`/api/events/${ev.id}`).set(resp.auth).send({ price: 1500 });
  ev = (await api.get('/api/events').set(resp.auth)).body.events.find((e) => e.id === created.body.event.id);
  assert.equal(ev.price, 1500);
  assert.deepEqual(Object.values(ev.pricesByLegion), [1500, 1500, 1500, 1500]);
});

// ---------- Administrateur : double vérification et règles strictes ----------

test('admin : sans le code SMS, aucun jeton ; code faux, réutilisé ou périmé refusé', async () => {
  const first = await api.post('/api/auth/login').send({ phone: '0100000000', password: 'Admin-pass-2026' });
  assert.equal(first.body.token, undefined, 'mot de passe seul : pas de session');
  assert.match(first.body.phoneHint, /^•• •• •• 00 00$/);
  const code = lastCode();
  const wrong = code === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i += 1) {
    assert.equal((await api.post('/api/auth/login/verify').send({ challengeId: first.body.challengeId, code: wrong })).status, 400);
  }
  const locked = await api.post('/api/auth/login/verify').send({ challengeId: first.body.challengeId, code });
  assert.equal(locked.status, 400, 'bon code refusé après 5 erreurs');
  assert.ok(consoleOutbox.some((m) => m.message.startsWith('Alerte My CVAV')), 'alerte SMS envoyée');

  const ok = await adminLogin();
  assert.equal(ok.res.status, 200);
  const challenge = await pool.query(`SELECT id FROM login_challenges WHERE used_at IS NOT NULL ORDER BY created_at DESC LIMIT 1`);
  const reuse = await api.post('/api/auth/login/verify').send({ challengeId: challenge.rows[0].id, code: lastCode() });
  assert.equal(reuse.status, 400, 'code à usage unique');
  for (const body of [{ challengeId: 'x', code: '123456' }, { challengeId: "' OR 1=1 --", code: '123456' }, { challengeId: 'a'.repeat(48), code: '12' }]) {
    assert.equal((await api.post('/api/auth/login/verify').send(body)).status, 400);
  }
});

test('admin : mot de passe fort exigé, réinitialisation SMS sans connexion directe, nomination confirmée', async () => {
  const weak = await api.post('/api/auth/password').set(admin).send({ currentPassword: 'Admin-pass-2026', newPassword: 'courtcourt' });
  assert.equal(weak.status, 400);
  assert.match(weak.body.error, /12 caractères/);
  // Les autres rôles gardent la règle de 8 caractères.
  assert.equal((await api.post('/api/auth/password').set(parent.auth).send({ currentPassword: 'motdepasse1', newPassword: 'motdepasse2' })).status, 200);

  await api.post('/api/auth/password/forgot').send({ phone: '0100000000' });
  const reset = await api.post('/api/auth/password/reset').send({ phone: '0100000000', code: lastCode(), newPassword: 'Nouveau-pass-2026' });
  assert.equal(reset.status, 200);
  assert.equal(reset.body.token, undefined, "pas de session : l'administrateur se reconnecte avec le code SMS");
  admin = (await adminLogin('Nouveau-pass-2026')).auth;

  const promote = await api.patch(`/api/admin/users/${resp.user.id}`).set(admin).send({ role: 'admin' });
  assert.equal(promote.status, 400, 'mot de passe de confirmation exigé');
  const bad = await api.patch(`/api/admin/users/${resp.user.id}`).set(admin).send({ role: 'admin', confirmPassword: 'faux' });
  assert.equal(bad.status, 400);
  const good = await api.patch(`/api/admin/users/${resp.user.id}`).set(admin).send({ role: 'admin', confirmPassword: 'Nouveau-pass-2026' });
  assert.equal(good.status, 200);
  await api.patch(`/api/admin/users/${resp.user.id}`).set(admin).send({ role: 'responsable' });
});

// ---------- Surveillance : détection, menaces, blocage ----------

test("sécurité : injections, accès interdits et force brute visibles par l'administrateur avec remèdes", async () => {
  await api.get('/api/children').query({ q: "' UNION SELECT password_hash FROM users --" }).set(resp.auth);
  await api.post('/api/posts').set(resp.auth).send({ title: '<script>alert(1)</script>', body: 'test' });
  await api.get('/api/admin/users').set(parent.auth);
  await api.get('/api/children').set({ Authorization: 'Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiIxIn0.' });
  for (let i = 0; i < 6; i += 1) await api.post('/api/auth/login').send({ phone: '0700000002', password: 'mauvais' });

  const sec = await api.get('/api/admin/security').set(admin);
  assert.equal(sec.status, 200);
  const types = new Set(sec.body.events.map((e) => e.type));
  for (const t of ['suspicious_input', 'forbidden', 'invalid_token', 'login_failed', 'account_locked']) assert.ok(types.has(t), t);
  assert.ok(sec.body.events.every((e) => e.label && e.advice), 'chaque événement a un libellé et un remède');
  assert.equal(sec.body.status, 'critical');
  const own = sec.body.threats.find((t) => t.title.includes(sec.body.viewerIp));
  assert.ok(own && own.action === null, "jamais de proposition de bloquer sa propre adresse");
  assert.ok(sec.body.threats.some((t) => t.action?.type === 'open_user' && t.action.userId === parent.user.id), 'compte ciblé signalé');
  const raw = JSON.stringify(sec.body);
  assert.ok(!raw.includes('mauvais'), 'aucun mot de passe dans le journal');
  assert.ok(!raw.includes('0700000002'), 'numéros masqués');
  // Réservé à l'administrateur (le responsable a été reconnecté : sa session a été révoquée au changement de rôle).
  const relog = await api.post('/api/auth/login').send({ phone: '0700000001', password: 'motdepasse1' });
  assert.equal((await api.get('/api/admin/security').set({ Authorization: `Bearer ${relog.body.token}` })).status, 403);
});

test("sécurité : blocage d'une adresse IP (jamais la sienne), effet immédiat, levée du blocage", async () => {
  const myIp = (await api.get('/api/admin/security').set(admin)).body.events.find((e) => e.ip)?.ip;
  assert.ok(myIp, 'adresse du client de test connue');
  for (const ip of [myIp, `::ffff:${myIp}`]) {
    assert.equal((await api.post('/api/admin/security/block').set(admin).send({ ip })).status, 400, 'impossible de se bloquer soi-même');
  }
  assert.equal((await api.post('/api/admin/security/block').set(admin).send({ ip: 'pas-une-ip' })).status, 400);
  const blocked = await api.post('/api/admin/security/block').set(admin).send({ ip: '203.0.113.7', hours: 24, reason: 'force brute' });
  assert.equal(blocked.status, 201);
  const sec = await api.get('/api/admin/security').set(admin);
  assert.equal(sec.body.blocked[0].ip, '203.0.113.7');

  // L'adresse du client de test bloquée directement en base : toutes ses requêtes sont refusées.
  await pool.query(`INSERT INTO blocked_ips (ip, reason) VALUES ($1, 'test')`, [myIp]);
  resetBlockedCache();
  assert.equal((await api.get('/api/meta')).status, 403);
  await pool.query('DELETE FROM blocked_ips WHERE ip = $1', [myIp]);
  resetBlockedCache();
  assert.equal((await api.get('/api/meta')).status, 200);

  assert.equal((await api.delete('/api/admin/security/block/203.0.113.7').set(admin)).status, 204);
  assert.equal((await api.get('/api/admin/security').set(admin)).body.blocked.length, 0);
});
