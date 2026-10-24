import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import ExcelJS from 'exceljs';
import JSZip from 'jszip';
import { freshApp, register, pool } from './helpers.js';

let api;
let resp;
let parent;
let otherParent;

before(async () => {
  api = await freshApp();
  resp = await register(api, { role: 'responsable', phone: '0700000001', name: 'Resp Un', legion: 'cadets' });
  parent = await register(api, { phone: '+225 07 00 00 00 02', name: 'Parent Un' });
  otherParent = await register(api, { phone: '0700000003', name: 'Parent Deux' });
});
after(() => pool.end());

test('inscription responsable refusée sans le bon code', async () => {
  const res = await api.post('/api/auth/register').send({
    role: 'responsable', phone: '0700000099', fullName: 'Intrus', password: 'motdepasse1', signupCode: 'faux',
  });
  assert.equal(res.status, 403);
});

test('numéro normalisé et doublon refusé', async () => {
  assert.equal(parent.user.phone, '0700000002');
  const res = await api.post('/api/auth/register').send({ role: 'parent', phone: '07 00 00 00 02', fullName: 'XX', password: 'motdepasse1' });
  assert.equal(res.status, 409);
});

test('connexion, puis blocage après 5 échecs', async () => {
  const ok = await api.post('/api/auth/login').send({ phone: '0700000003', password: 'motdepasse1' });
  assert.equal(ok.status, 200);
  assert.ok(ok.body.token);
  for (let i = 0; i < 5; i += 1) {
    const bad = await api.post('/api/auth/login').send({ phone: '0700000003', password: 'mauvais' });
    assert.equal(bad.status, 401);
  }
  const locked = await api.post('/api/auth/login').send({ phone: '0700000003', password: 'motdepasse1' });
  assert.equal(locked.status, 429);
});

test('un parent ne peut pas accéder aux routes responsable', async () => {
  for (const path of ['/api/children', '/api/events', '/api/dues', '/api/stats']) {
    const res = await api.get(path).set(parent.auth);
    assert.equal(res.status, 403, path);
  }
  assert.equal((await api.get('/api/children')).status, 401);
  assert.equal((await api.get('/api/children').set({ Authorization: 'Bearer abc' })).status, 401);
});

let childA;
let childB;

test('CRUD enfants avec filtre par légion', async () => {
  const a = await api.post('/api/children').set(resp.auth).send({
    lastName: 'kouassi', firstName: 'Aya', age: 8, legion: 'benjamins', parentPhone: '07 07 07 07 01', address: 'Riviera 2',
  });
  assert.equal(a.status, 201);
  assert.equal(a.body.child.lastName, 'KOUASSI');
  assert.match(a.body.child.linkCode, /^[A-Z2-9]{8}$/);
  childA = a.body.child;
  const b = await api.post('/api/children').set(resp.auth).send({ lastName: 'YAO', firstName: 'Emma', birthDate: '2014-03-02', legion: 'cadets' });
  childB = b.body.child;
  const bad = await api.post('/api/children').set(resp.auth).send({ lastName: 'X', firstName: 'Y', legion: 'pirates' });
  assert.equal(bad.status, 400);
  const list = await api.get('/api/children?legion=cadets').set(resp.auth);
  assert.deepEqual(list.body.children.map((c) => c.id), [childB.id]);
  const upd = await api.put(`/api/children/${childB.id}`).set(resp.auth).send({ ...childB, lastName: 'Yao', address: 'Riviera 3' });
  assert.equal(upd.body.child.address, 'Riviera 3');
});

test('import CSV : aperçu puis validation, doublons ignorés', async () => {
  const csv = "Nom;Prénoms;Âge;Contact des parents;Lieu d'habitation;Légion\nKONAN;Jean;9;0505050502;Palmeraie;Benjamins\nKOUASSI;Aya;8;0707070701;Riviera 2;benjamin\nTRAORE;Mariam;11;01 01 01 01 03;Riviera 3;\n";
  const prev = await api.post('/api/children/import/preview').set(resp.auth).attach('file', Buffer.from(csv), 'liste.csv');
  assert.equal(prev.status, 200, JSON.stringify(prev.body));
  assert.equal(prev.body.total, 3);
  assert.equal(prev.body.duplicates, 1);
  const traore = prev.body.children.find((c) => c.lastName === 'TRAORE');
  assert.equal(traore.legion, 'cadets');
  assert.equal(traore.parentPhone, '0101010103');
  const commit = await api.post('/api/children/import/commit').set(resp.auth).send({
    children: prev.body.children.map(({ warnings, duplicate, ...c }) => c),
  });
  assert.equal(commit.status, 201, JSON.stringify(commit.body));
  assert.deepEqual(commit.body, { created: 2, skipped: 1 });
});

test('import Excel avec feuilles par légion', async () => {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('Meneurs');
  ws.addRow(['N°', 'Nom et prénoms', 'Date de naissance', 'Contact', 'Quartier']);
  ws.addRow([1, 'BAMBA Ange Michel', new Date('2008-05-04'), '0101010107', 'Bonoumin']);
  const buf = Buffer.from(await wb.xlsx.writeBuffer());
  const res = await api.post('/api/children/import/preview').set(resp.auth).attach('file', buf, 'meneurs.xlsx');
  assert.equal(res.status, 200, JSON.stringify(res.body));
  const [c] = res.body.children;
  assert.equal(c.lastName, 'BAMBA');
  assert.equal(c.firstName, 'Ange Michel');
  assert.equal(c.legion, 'meneurs');
  assert.equal(c.birthDate, '2008-05-04');
});

test('import Word avec titres de légion et tableaux', async () => {
  const zip = new JSZip();
  const p = (t) => `<w:p><w:r><w:t xml:space="preserve">${t}</w:t></w:r></w:p>`;
  const row = (cells) => `<w:tr>${cells.map((c) => `<w:tc>${p(c)}</w:tc>`).join('')}</w:tr>`;
  zip.file('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>');
  zip.file('_rels/.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>');
  zip.file('word/document.xml', `<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
    ${p('LISTE CVAV SAINTE FAMILLE')}${p('Légion des Aînés')}
    <w:tbl>${row(['Nom', 'Prénoms', 'Âge', 'Contact', 'Habitation'])}${row(['N\'GUESSAN', 'Prisca', '14 ans', '05 05 05 05 05', 'Golf'])}</w:tbl>
    ${p('Cadets')}
    <w:tbl>${row(['Nom', 'Prénoms', 'Âge', 'Contact', 'Habitation'])}${row(['DIALLO', 'Awa', '10', '0707070709', 'Riviera 4'])}</w:tbl>
  </w:body></w:document>`);
  const buf = await zip.generateAsync({ type: 'nodebuffer' });
  const res = await api.post('/api/children/import/preview').set(resp.auth).attach('file', buf, 'liste.docx');
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.deepEqual(res.body.children.map((c) => [c.lastName, c.legion, c.age]), [["N'GUESSAN", 'aines', 14], ['DIALLO', 'cadets', 10]]);
});

test('format non pris en charge', async () => {
  const res = await api.post('/api/children/import/preview').set(resp.auth).attach('file', Buffer.from('x'), 'photo.png');
  assert.equal(res.status, 415);
});

test('activités par défaut, prix et pointage des présences', async () => {
  const ev = await api.get('/api/events?kind=activite').set(resp.auth);
  assert.equal(ev.status, 200);
  assert.equal(ev.body.events.length, 7);
  const rentree = ev.body.events[0];
  assert.equal(rentree.name, 'Rentrée pastorale');
  const priced = await api.put(`/api/events/${rentree.id}`).set(resp.auth).send({ price: 2000, date: '2026-10-10' });
  assert.equal(priced.body.event.price, 2000);
  assert.equal(priced.body.event.date, '2026-10-10');

  const meeting = await api.post('/api/events').set(resp.auth).send({ kind: 'reunion', name: 'Réunion du samedi', date: '2026-10-17' });
  assert.equal(meeting.status, 201);
  assert.equal(meeting.body.event.dueId, null);

  const save = await api.put(`/api/events/${rentree.id}/attendance`).set(resp.auth).send({
    entries: [{ childId: childA.id, status: 'present' }, { childId: childB.id, status: 'absent' }],
  });
  assert.equal(save.status, 200);
  const att = await api.get(`/api/events/${rentree.id}/attendance?legion=benjamins`).set(resp.auth);
  const aya = att.body.entries.find((e) => e.child.id === childA.id);
  assert.equal(aya.status, 'present');
  assert.equal(aya.markedBy, 'Resp Un');
});

test('cotisations : paroissiale 1500 F, cochage des enfants ayant payé', async () => {
  const dues = await api.get('/api/dues').set(resp.auth);
  const paroisse = dues.body.dues.find((d) => d.kind === 'paroissiale');
  assert.equal(paroisse.amount, 1500);
  assert.equal(dues.body.dues.filter((d) => d.kind === 'activite').length, 7);
  await api.put(`/api/dues/${paroisse.id}/payments`).set(resp.auth).send({ entries: [{ childId: childB.id, paid: true }] });
  const pay = await api.get(`/api/dues/${paroisse.id}/payments?legion=cadets`).set(resp.auth);
  const b = pay.body.entries.find((e) => e.child.id === childB.id);
  assert.equal(b.status, 'paid');
  const stats = await api.get('/api/stats').set(resp.auth);
  assert.equal(stats.body.collected, 1500);
});

test('espace parent : liaison par code, données limitées à ses enfants', async () => {
  const wrong = await api.post('/api/parent/link').set(parent.auth).send({ code: 'ZZZZZZZZ' });
  assert.equal(wrong.status, 404);
  const link = await api.post('/api/parent/link').set(parent.auth).send({ code: childA.linkCode.toLowerCase() });
  assert.equal(link.status, 201);
  assert.equal(link.body.child.linkCode, undefined);

  const kids = await api.get('/api/parent/children').set(parent.auth);
  assert.deepEqual(kids.body.children.map((c) => c.id), [childA.id]);
  const att = await api.get('/api/parent/attendance').set(parent.auth);
  assert.deepEqual(att.body.records.map((r) => [r.childId, r.status]), [[childA.id, 'present']]);
  const otherKids = await api.get('/api/parent/children').set(otherParent.auth);
  assert.equal(otherKids.body.children.length, 0);

  const dues = await api.get('/api/parent/dues').set(parent.auth);
  assert.equal(dues.body.paymentMode, 'merchant_link');
  // Diocésaine sans montant : non affichée ; paroissiale + rentrée (2000) affichées
  assert.deepEqual(dues.body.dues.map((d) => [d.label, d.amount, d.status]), [
    ['Cotisation paroissiale', 1500, 'unpaid'], ['Rentrée pastorale', 2000, 'unpaid'],
  ]);
});

test('paiement Wave : lien avec montant, déclaration, refus pour un enfant non lié', async () => {
  const dues = await api.get('/api/parent/dues').set(parent.auth);
  const paroisse = dues.body.dues[0];
  const checkout = await api.post('/api/payments/wave/checkout').set(parent.auth).send({ dueId: paroisse.dueId, childId: childA.id });
  assert.equal(checkout.status, 200, JSON.stringify(checkout.body));
  assert.equal(checkout.body.url, 'https://pay.wave.com/m/M_ci_test/c/ci/?amount=1500');

  const forbidden = await api.post('/api/payments/wave/checkout').set(otherParent.auth).send({ dueId: paroisse.dueId, childId: childA.id });
  assert.equal(forbidden.status, 400);

  const declare = await api.post('/api/payments/declare').set(parent.auth).send({ dueId: paroisse.dueId, childId: childA.id });
  assert.equal(declare.status, 201);
  const after = await api.get('/api/parent/dues').set(parent.auth);
  assert.equal(after.body.dues[0].status, 'pending');
});

test('webhook Wave : signature vérifiée, paiement confirmé', async () => {
  const { rows: [due] } = await pool.query(`SELECT id FROM dues WHERE label = 'Rentrée pastorale'`);
  await pool.query(`INSERT INTO wave_sessions (id, due_id, child_id, parent_id, amount) VALUES ('cos-1', $1, $2, $3, 2000)`, [due.id, childA.id, parent.user.id]);
  const body = JSON.stringify({ type: 'checkout.session.completed', data: { id: 'cos-1', amount: '2000', payment_status: 'succeeded', transaction_id: 'T123' } });
  const unsigned = await api.post('/api/payments/wave/webhook').set('Content-Type', 'application/json').send(body);
  assert.equal(unsigned.status, 401);
  const t = Math.floor(Date.now() / 1000);
  const sig = crypto.createHmac('sha256', 'wave-test-secret').update(t + body).digest('hex');
  const ok = await api.post('/api/payments/wave/webhook').set('Content-Type', 'application/json').set('Wave-Signature', `t=${t},v1=${sig}`).send(body);
  assert.equal(ok.status, 200);
  const dues = await api.get('/api/parent/dues').set(parent.auth);
  const rentree = dues.body.dues.find((d) => d.label === 'Rentrée pastorale');
  assert.deepEqual([rentree.status, rentree.method], ['paid', 'wave']);
});

test('informations : publiées par un responsable, lues par les parents', async () => {
  const denied = await api.post('/api/posts').set(parent.auth).send({ title: 'Hack', body: 'x' });
  assert.equal(denied.status, 403);
  const created = await api.post('/api/posts').set(resp.auth).send({ title: 'Camp de jumelage', body: 'Départ samedi 8h.', pinned: true });
  assert.equal(created.status, 201);
  const list = await api.get('/api/posts').set(parent.auth);
  assert.equal(list.body.posts[0].title, 'Camp de jumelage');
});

test('nouveau code enfant : les parents liés perdent l\'accès', async () => {
  const res = await api.post(`/api/children/${childA.id}/regenerate-code`).set(resp.auth);
  assert.notEqual(res.body.child.linkCode, childA.linkCode);
  const kids = await api.get('/api/parent/children').set(parent.auth);
  assert.equal(kids.body.children.length, 0);
});

test('changement de mot de passe : anciennes sessions invalidées', async () => {
  const res = await api.post('/api/auth/password').set(parent.auth).send({ currentPassword: 'motdepasse1', newPassword: 'nouveaumdp1' });
  assert.equal(res.status, 200);
  assert.equal((await api.get('/api/auth/me').set(parent.auth)).status, 401);
  assert.equal((await api.get('/api/auth/me').set({ Authorization: `Bearer ${res.body.token}` })).status, 200);
});
