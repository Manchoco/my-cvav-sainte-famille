// Tests d'intrusion automatisés (OWASP API Security Top 10 + injections).
// Chaque test simule une attaque et vérifie que l'API la bloque.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import JSZip from 'jszip';
import { freshApp, register, pool } from './helpers.js';

let api;
let admin;
let resp;
let parentA;
let parentB;
let childA;
let dueId;

const SQLI = [
  "' OR '1'='1",
  "1; DROP TABLE users; --",
  "' UNION SELECT password_hash, phone FROM users --",
  "1' AND pg_sleep(3)--",
  "%' OR 1=1 --",
  '\\\'; SELECT 1; --',
];

async function login(phone, password) {
  const res = await api.post('/api/auth/login').send({ phone, password });
  return { res, auth: { Authorization: `Bearer ${res.body.token}` } };
}

before(async () => {
  api = await freshApp();
  const hash = await bcrypt.hash('admin-pass-123', 10);
  await pool.query(`INSERT INTO users (role, full_name, phone, password_hash) VALUES ('admin', 'Admin', '0100000000', $1)`, [hash]);
  admin = (await login('0100000000', 'admin-pass-123')).auth;
  resp = await register(api, { role: 'responsable', phone: '0700000001', name: 'Resp' });
  parentA = await register(api, { phone: '0700000002', name: 'Parent A' });
  parentB = await register(api, { phone: '0700000003', name: 'Parent B' });
  const c = await api.post('/api/children').set(resp.auth).send({ lastName: 'KONE', firstName: 'Ali', age: 9, legion: 'benjamins' });
  childA = c.body.child;
  await api.post('/api/parent/link').set(parentA.auth).send({ code: childA.linkCode });
  const dues = await api.get('/api/dues').set(resp.auth);
  dueId = dues.body.dues.find((d) => d.kind === 'paroissiale').id;
});
after(() => pool.end());

// ---------- API1 : autorisation au niveau objet (BOLA / IDOR) ----------

test('API1 BOLA : un parent ne peut ni payer, ni déclarer, ni retirer l\'enfant d\'un autre', async () => {
  const pay = await api.post('/api/payments/wave/checkout').set(parentB.auth).send({ dueId, childId: childA.id });
  assert.equal(pay.status, 400);
  const declare = await api.post('/api/payments/declare').set(parentB.auth).send({ dueId, childId: childA.id });
  assert.equal(declare.status, 400);
  const unlink = await api.delete(`/api/parent/children/${childA.id}`).set(parentB.auth);
  assert.equal(unlink.status, 404);
  const kids = await api.get('/api/parent/children').set(parentA.auth);
  assert.equal(kids.body.children.length, 1, 'le lien de A est intact');
  const direct = await api.get(`/api/children/${childA.id}`).set(parentB.auth);
  assert.equal(direct.status, 403);
});

test('API1 : le code enfant n\'est jamais renvoyé aux parents', async () => {
  const kids = await api.get('/api/parent/children').set(parentA.auth);
  assert.equal(kids.body.children[0].linkCode, undefined);
  assert.equal(JSON.stringify(kids.body).includes(childA.linkCode), false);
});

// ---------- API2 : authentification ----------

test('API2 : jetons absents, malformés, falsifiés ou "alg: none" refusés', async () => {
  const none = `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${Buffer.from(JSON.stringify({ sub: '1', tv: 0 })).toString('base64url')}.`;
  const forged = jwt.sign({ sub: '1', tv: 0 }, 'mauvais-secret-mauvais-secret-mauvais');
  const hs512 = jwt.sign({ sub: '1', tv: 0 }, process.env.JWT_SECRET, { algorithm: 'HS512' });
  const expired = jwt.sign({ sub: '1', tv: 0, exp: Math.floor(Date.now() / 1000) - 10 }, process.env.JWT_SECRET);
  const badSub = jwt.sign({ sub: "1 OR 1=1", tv: 0 }, process.env.JWT_SECRET);
  for (const token of ['', 'abc', none, forged, hs512, expired, badSub]) {
    const res = await api.get('/api/admin/users').set({ Authorization: `Bearer ${token}` });
    assert.equal(res.status, 401, `jeton accepté : ${token.slice(0, 30)}`);
  }
  assert.equal((await api.get('/api/admin/users')).status, 401);
  assert.equal((await api.get('/api/admin/users').set({ Authorization: 'Basic YWRtaW46YWRtaW4=' })).status, 401);
});

test('API2 : les réponses de connexion ne révèlent pas si un numéro existe', async () => {
  const unknown = await api.post('/api/auth/login').send({ phone: '0799999999', password: 'x' });
  const known = await api.post('/api/auth/login').send({ phone: '0700000003', password: 'mauvais' });
  assert.equal(unknown.status, known.status);
  assert.equal(unknown.body.error, known.body.error);
});

test('API2 : un compte désactivé ou supprimé perd immédiatement l\'accès', async () => {
  const victim = await register(api, { phone: '0700000020', name: 'Temp' });
  const u = await api.get('/api/admin/users?q=0700000020').set(admin);
  const id = u.body.users[0].id;
  await api.patch(`/api/admin/users/${id}`).set(admin).send({ disabled: true });
  assert.equal((await api.get('/api/auth/me').set(victim.auth)).status, 401);
  const relog = await api.post('/api/auth/login').send({ phone: '0700000020', password: 'motdepasse1' });
  assert.equal(relog.status, 403);
  await api.delete(`/api/admin/users/${id}`).set(admin);
  assert.equal((await api.get('/api/auth/me').set(victim.auth)).status, 401);
});

// ---------- API3 : affectation de masse / exposition de propriétés ----------

test('API3 : impossible de s\'inscrire administrateur ou de forcer des champs internes', async () => {
  const asAdmin = await api.post('/api/auth/register').send({ role: 'admin', phone: '0700000030', fullName: 'Pirate', password: 'motdepasse1' });
  assert.equal(asAdmin.status, 400);
  const extra = await api.post('/api/auth/register').send({
    role: 'parent', phone: '0700000031', fullName: 'Pirate', password: 'motdepasse1',
    token_version: 99, disabled: false, must_change_password: false, id: 1, password_hash: 'x',
  });
  assert.equal(extra.status, 201);
  const { rows } = await pool.query(`SELECT role, token_version FROM users WHERE phone = '0700000031'`);
  assert.deepEqual(rows[0], { role: 'parent', token_version: 0 });
  const respSelf = await api.post('/api/auth/register').send({ role: 'responsable', phone: '0700000032', fullName: 'Pirate', password: 'motdepasse1' });
  assert.equal(respSelf.status, 403, 'responsable sans code d\'accès');
});

test('API3 : aucune empreinte de mot de passe ni secret dans les réponses', async () => {
  const bodies = [
    (await api.get('/api/auth/me').set(parentA.auth)).body,
    (await api.get('/api/admin/users').set(admin)).body,
    (await api.get('/api/children').set(resp.auth)).body,
  ];
  for (const b of bodies) {
    const s = JSON.stringify(b);
    assert.ok(!/password_hash|\$2[aby]\$|token_version|code_hash/.test(s), s.slice(0, 200));
  }
});

test('API3 : modifier un enfant ne permet pas de changer son id ni son code', async () => {
  const res = await api.put(`/api/children/${childA.id}`).set(resp.auth)
    .send({ ...childA, id: 999, link_code: 'AAAAAAAA', linkCode: 'AAAAAAAA', created_by: 1 });
  assert.equal(res.status, 200);
  assert.equal(res.body.child.id, childA.id);
  assert.equal(res.body.child.linkCode, childA.linkCode);
});

test('API4 : forçage d\'un compte limité par numéro, même en changeant d\'adresse IP', async () => {
  const statuses = [];
  for (let i = 0; i < 11; i += 1) {
    statuses.push((await api.post('/api/auth/login').send({ phone: '0700000088', password: `essai${i}` })).status);
  }
  assert.equal(statuses.at(-1), 429);
});

// ---------- API4 : consommation de ressources ----------

test('API4 : corps JSON géant, fichier trop gros et bombe zip refusés', async () => {
  const big = await api.post('/api/auth/login').set('Content-Type', 'application/json').send(`{"phone":"${'1'.repeat(3 * 1024 * 1024)}"}`);
  assert.equal(big.status, 413);
  const huge = await api.post('/api/children/import/preview').set(resp.auth).attach('file', Buffer.alloc(4.5 * 1024 * 1024, 65), 'liste.csv');
  assert.equal(huge.status, 413);
  const zip = new JSZip();
  zip.file('word/document.xml', Buffer.alloc(60 * 1024 * 1024, 32));
  const bomb = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE', compressionOptions: { level: 9 } });
  assert.ok(bomb.length < 1024 * 1024, 'la bombe tient en moins de 1 Mo');
  const res = await api.post('/api/children/import/preview').set(resp.auth).attach('file', bomb, 'liste.docx');
  assert.equal(res.status, 413);
});

test('API4 : pas de ReDoS sur l\'analyse des documents', async () => {
  const evil = `${'1 '.repeat(20000)}x\n${'-'.repeat(50000)}\n${'0.'.repeat(30000)}`;
  const t = Date.now();
  const res = await api.post('/api/children/import/preview').set(resp.auth).attach('file', Buffer.from(evil), 'liste.csv');
  assert.ok(Date.now() - t < 3000, `analyse trop lente : ${Date.now() - t} ms`);
  assert.ok([200, 400].includes(res.status));
});

// ---------- API5 : autorisation au niveau fonction ----------

test('API5 : chaque rôle reste dans son périmètre', async () => {
  const cases = [
    [parentA.auth, 'post', '/api/posts', 403],
    [parentA.auth, 'get', '/api/events', 403],
    [parentA.auth, 'get', '/api/admin/settings', 403],
    [resp.auth, 'get', '/api/admin/users', 403],
    [resp.auth, 'post', '/api/admin/settings/signup-code', 403],
    [resp.auth, 'put', '/api/admin/settings/maintenance', 403],
    [resp.auth, 'get', '/api/parent/children', 403],
  ];
  for (const [auth, method, path, status] of cases) {
    const res = await api[method](path).set(auth).send({});
    assert.equal(res.status, status, `${method.toUpperCase()} ${path}`);
  }
  // L'administrateur hérite des droits responsable
  assert.equal((await api.get('/api/children').set(admin)).status, 200);
});

// ---------- API6 : flux métier sensibles ----------

test('API6 : pas de double paiement ni de paiement sans montant', async () => {
  await api.put(`/api/dues/${dueId}/payments`).set(resp.auth).send({ entries: [{ childId: childA.id, paid: true }] });
  const again = await api.post('/api/payments/declare').set(parentA.auth).send({ dueId, childId: childA.id });
  assert.equal(again.status, 409);
  const { rows } = await pool.query(`SELECT id FROM dues WHERE kind = 'diocesaine'`);
  const noAmount = await api.post('/api/payments/wave/checkout').set(parentA.auth).send({ dueId: rows[0].id, childId: childA.id });
  assert.equal(noAmount.status, 400);
});

// ---------- Injections ----------

test('Injection SQL : recherche, identifiants, paramètres et connexion', async () => {
  const before = (await pool.query('SELECT count(*)::int AS n FROM users')).rows[0].n;
  for (const p of SQLI) {
    const t = Date.now();
    const search = await api.get('/api/children').query({ q: p }).set(resp.auth);
    assert.equal(search.status, 200);
    assert.equal(search.body.children.length, 0, `fuite via q=${p}`);
    assert.ok(Date.now() - t < 2500, 'pg_sleep exécuté');
    assert.equal((await api.get(`/api/children/${encodeURIComponent(p)}`).set(resp.auth)).status, 400);
    assert.equal((await api.get('/api/children').query({ legion: p }).set(resp.auth)).status, 400);
    assert.equal((await api.get('/api/dues').query({ year: p }).set(resp.auth)).status, 400);
    const log = await api.post('/api/auth/login').send({ phone: p, password: p });
    assert.equal(log.status, 401);
    assert.equal((await api.post('/api/parent/link').set(parentB.auth).send({ code: p })).status === 201, false);
  }
  const users = await api.get('/api/admin/users').query({ q: "%' OR '1'='1" }).set(admin);
  assert.equal(users.body.users.length, 0);
  const afterCount = (await pool.query('SELECT count(*)::int AS n FROM users')).rows[0].n;
  assert.equal(afterCount, before, 'aucune table modifiée');
});

test('Injection SQL de second ordre : les valeurs stockées restent des données', async () => {
  const name = "Robert'); DROP TABLE children;--";
  const c = await api.post('/api/children').set(resp.auth).send({ lastName: name, firstName: name, legion: 'cadets', address: name });
  assert.equal(c.status, 201);
  const search = await api.get('/api/children').query({ q: 'robert' }).set(resp.auth);
  assert.equal(search.body.children[0].address, name);
  await api.get(`/api/events/${(await api.get('/api/events').set(resp.auth)).body.events[0].id}/attendance`).set(resp.auth);
  assert.equal((await pool.query(`SELECT to_regclass('children') AS t`)).rows[0].t, 'children');
});

test('Injection « NoSQL » / types inattendus refusés par la validation', async () => {
  const payloads = [{ $gt: '' }, ['0700000002'], { toString: 1 }, null, 123];
  for (const phone of payloads) {
    const res = await api.post('/api/auth/login').send({ phone, password: { $ne: '' } });
    assert.equal(res.status, 400, JSON.stringify(phone));
  }
  const proto = await api.post('/api/auth/register').set('Content-Type', 'application/json')
    .send('{"role":"parent","phone":"0700000040","fullName":"Proto","password":"motdepasse1","__proto__":{"role":"admin"},"constructor":{"prototype":{"isAdmin":true}}}');
  assert.equal(proto.status, 201);
  assert.equal(proto.body.user.role, 'parent');
  assert.equal({}.isAdmin, undefined, 'prototype pollué');
});

test('XSS stockée : le contenu est renvoyé en JSON, jamais interprété en HTML', async () => {
  const xss = '<script>alert(document.cookie)</script><img src=x onerror=alert(1)>';
  const p = await api.post('/api/posts').set(resp.auth).send({ title: xss, body: xss });
  assert.equal(p.status, 201);
  const list = await api.get('/api/posts').set(parentA.auth);
  assert.match(list.headers['content-type'], /application\/json/);
  assert.equal(list.headers['x-content-type-options'], 'nosniff');
  // La page de retour Wave n'affiche aucune donnée fournie par l'utilisateur
  const ret = await api.get('/api/payments/wave/retour').query({ statut: xss });
  assert.equal(ret.text.includes('<script>alert'), false);
});

test('Téléversement : nom de fichier malveillant sans effet (traitement en mémoire)', async () => {
  const res = await api.post('/api/children/import/preview').set(resp.auth)
    .attach('file', Buffer.from('Nom;Prénoms;Légion\nTEST;Ok;cadets\n'), '../../../../etc/passwd.csv');
  assert.equal(res.status, 200);
  const exe = await api.post('/api/children/import/preview').set(resp.auth).attach('file', Buffer.from('MZ'), 'virus.exe');
  assert.equal(exe.status, 415);
  const fakeDocx = await api.post('/api/children/import/preview').set(resp.auth).attach('file', Buffer.from('pas un zip'), 'liste.docx');
  assert.equal(fakeDocx.status, 400);
});

// ---------- API8 : configuration ----------

test('API8 : en-têtes de sécurité, pas de CORS ouvert, erreurs sans détails internes', async () => {
  const res = await api.get('/api/health').set('Origin', 'https://site-pirate.example');
  assert.equal(res.headers['x-powered-by'], undefined);
  assert.equal(res.headers['access-control-allow-origin'], undefined);
  assert.ok(res.headers['strict-transport-security']);
  assert.equal(res.headers['x-frame-options'], 'SAMEORIGIN');
  const broken = await api.post('/api/auth/login').set('Content-Type', 'application/json').send('{"phone": ');
  assert.equal(broken.status, 400);
  assert.ok(!/at |node_modules|SyntaxError|pg|SELECT/.test(JSON.stringify(broken.body)));
  const notFound = await api.get('/api/../../etc/passwd');
  assert.equal(notFound.status, 404);
});

// ---------- API10 : consommation non sûre d'API tierces (webhook Wave) ----------

test('API10 : webhook Wave falsifié, rejoué ou trop ancien refusé', async () => {
  const body = JSON.stringify({ type: 'checkout.session.completed', data: { id: 'x', amount: '1500', payment_status: 'succeeded' } });
  const old = Math.floor(Date.now() / 1000) - 3600;
  const sig = (t, secret = 'wave-test-secret') => crypto.createHmac('sha256', secret).update(t + body).digest('hex');
  const cases = [
    undefined,
    `t=${old},v1=${sig(old)}`,
    `t=${Math.floor(Date.now() / 1000)},v1=${sig(Math.floor(Date.now() / 1000), 'autre')}`,
    `t=${Math.floor(Date.now() / 1000)},v1=${'0'.repeat(64)}`,
    'v1=abc',
  ];
  for (const header of cases) {
    const req = api.post('/api/payments/wave/webhook').set('Content-Type', 'application/json');
    if (header) req.set('Wave-Signature', header);
    assert.equal((await req.send(body)).status, 401, String(header));
  }
});

// ---------- Administration, maintenance ----------

test('Admin : compte créé avec mot de passe provisoire, changement obligatoire', async () => {
  const created = await api.post('/api/admin/users').set(admin).send({ role: 'responsable', fullName: 'Nouveau Resp', phone: '0700000050', legion: 'aines' });
  assert.equal(created.status, 201);
  const temp = created.body.temporaryPassword;
  assert.match(temp, /^[a-z2-9]{10}$/);
  const { res, auth } = await login('0700000050', temp);
  assert.equal(res.body.user.mustChangePassword, true);
  const blocked = await api.get('/api/children').set(auth);
  assert.equal(blocked.status, 403);
  assert.equal(blocked.body.code, 'PASSWORD_CHANGE_REQUIRED');
  const changed = await api.post('/api/auth/password').set(auth).send({ currentPassword: temp, newPassword: 'definitif-123' });
  assert.equal(changed.status, 200);
  assert.equal((await api.get('/api/children').set({ Authorization: `Bearer ${changed.body.token}` })).status, 200);
});

test('Admin : impossible de supprimer ou rétrograder le dernier administrateur', async () => {
  const me = (await api.get('/api/auth/me').set(admin)).body.user;
  assert.equal((await api.delete(`/api/admin/users/${me.id}`).set(admin)).status, 400);
  assert.equal((await api.patch(`/api/admin/users/${me.id}`).set(admin).send({ role: 'parent' })).status, 400);
  assert.equal((await api.patch(`/api/admin/users/${me.id}`).set(admin).send({ disabled: true })).status, 400);
});

test('Admin : rotation du code d\'accès responsable (l\'ancien ne marche plus)', async () => {
  const { body } = await api.post('/api/admin/settings/signup-code').set(admin);
  assert.match(body.signupCode, /^CVAV-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  const old = await api.post('/api/auth/register').send({ role: 'responsable', phone: '0700000060', fullName: 'X Y', password: 'motdepasse1', signupCode: 'CODE-RESP-2026' });
  assert.equal(old.status, 403);
  const ok = await api.post('/api/auth/register').send({ role: 'responsable', phone: '0700000060', fullName: 'X Y', password: 'motdepasse1', signupCode: body.signupCode });
  assert.equal(ok.status, 201);
  const audit = await api.get('/api/admin/audit').set(admin);
  assert.ok(audit.body.entries.some((e) => e.action === 'signup_code.rotate'));
});

test('Maintenance : seuls les administrateurs passent, le webhook Wave reste ouvert', async () => {
  const on = await api.put('/api/admin/settings/maintenance').set(admin).send({ enabled: true, message: 'Mise à jour en cours' });
  assert.equal(on.status, 200);
  const meta = await api.get('/api/meta');
  assert.equal(meta.body.maintenance.enabled, true);
  const blocked = await api.get('/api/parent/children').set(parentA.auth);
  assert.equal(blocked.status, 503);
  assert.equal(blocked.body.maintenance, true);
  assert.equal((await api.post('/api/auth/login').send({ phone: '0700000002', password: 'motdepasse1' })).status, 503);
  assert.equal((await api.post('/api/auth/register').send({ role: 'parent', phone: '0700000070', fullName: 'Z Z', password: 'motdepasse1' })).status, 503);
  assert.equal((await api.get('/api/admin/users').set(admin)).status, 200);
  assert.equal((await login('0100000000', 'admin-pass-123')).res.status, 200);
  assert.equal((await api.post('/api/payments/wave/webhook').send('{}')).status, 401, 'webhook joignable (refusé pour signature)');
  await api.put('/api/admin/settings/maintenance').set(admin).send({ enabled: false, message: 'Mise à jour en cours' });
  assert.equal((await api.get('/api/parent/children').set(parentA.auth)).status, 200);
});

test('Mise à jour : seuls les liens https sont acceptés (pas de lien piégé)', async () => {
  for (const url of ['javascript:alert(1)', 'http://pirate.example/app.apk', 'file:///etc/passwd']) {
    const res = await api.put('/api/admin/settings/app-update').set(admin).send({ latestBuild: 3, minBuild: 1, url, notes: '' });
    assert.equal(res.status, 400, url);
  }
  const ok = await api.put('/api/admin/settings/app-update').set(admin).send({ latestBuild: 3, minBuild: 2, url: 'https://exemple.org/app.apk', notes: 'Correctifs' });
  assert.equal(ok.status, 200);
  assert.equal((await api.get('/api/meta')).body.appUpdate.minBuild, 2);
});

test('Profil : changer de numéro exige le mot de passe actuel', async () => {
  const bad = await api.put('/api/auth/me').set(parentB.auth).send({ phone: '0700000099', currentPassword: 'faux' });
  assert.equal(bad.status, 400);
  const taken = await api.put('/api/auth/me').set(parentB.auth).send({ phone: '0700000002', currentPassword: 'motdepasse1' });
  assert.equal(taken.status, 409);
  const ok = await api.put('/api/auth/me').set(parentB.auth).send({ phone: '07 00 00 00 99', currentPassword: 'motdepasse1' });
  assert.equal(ok.body.user.phone, '0700000099');
});

// Dernier test : il épuise volontairement le quota de connexions de l'adresse IP de test.
test('API8 : X-Forwarded-For falsifié ne contourne pas la limitation (hors proxy de confiance)', async () => {
  let last;
  for (let i = 0; i < 101; i += 1) {
    last = await api.post('/api/auth/password/forgot').set('X-Forwarded-For', `10.0.${i}.1`).send({ phone: `07${String(10000000 + i)}` });
  }
  assert.equal(last.status, 429);
});
