import express, { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { HttpError, badRequest, notFound, parseBody } from '../errors.js';
import { authenticate, requireRole } from '../middleware/auth.js';
import { createCheckoutSession, merchantLinkUrl, verifyWaveSignature, waveMode } from '../services/wave.js';
import { assertParentOwnsChild } from './parent.js';
import { effectiveAmountSql } from '../services/dues.js';
import { securityEvent } from '../services/security.js';

const router = Router();
// Ce routeur est monté avant express.json() (webhook en corps brut) : JSON activé route par route.
const json = express.json({ limit: '20kb' });
const payBody = z.object({ dueId: z.number().int().positive(), childId: z.number().int().positive() });

async function loadPayableDue(parentId, { dueId, childId }) {
  await assertParentOwnsChild(parentId, childId);
  // Montant de la légion de l'enfant (ou montant commun).
  const { rows } = await query(
    `SELECT d.id, d.kind, d.label, ${effectiveAmountSql('d', 'c')} AS amount
     FROM dues d JOIN children c ON c.id = $2 WHERE d.id = $1`,
    [dueId, childId],
  );
  const due = rows[0];
  if (!due) throw notFound('Cotisation introuvable');
  if (!due.amount) throw badRequest("Le montant de cette cotisation n'est pas encore fixé");
  const { rows: paid } = await query(`SELECT status FROM payments WHERE due_id = $1 AND child_id = $2`, [dueId, childId]);
  if (paid[0]?.status === 'paid') throw new HttpError(409, 'Cette cotisation est déjà réglée');
  return due;
}

// Prépare le paiement Wave : renvoie l'URL qui ouvre l'application Wave.
router.post('/wave/checkout', json, authenticate, requireRole('parent'), async (req, res) => {
  const body = parseBody(payBody, req.body);
  const due = await loadPayableDue(req.user.id, body);
  const mode = waveMode();
  if (mode === 'disabled') throw new HttpError(503, "Le paiement Wave n'est pas encore configuré. Contactez un responsable.");
  if (mode === 'merchant_link') {
    return res.json({ mode, url: merchantLinkUrl(due.amount), amount: due.amount, label: due.label });
  }
  const reference = `cvav-${due.id}-${body.childId}-${Date.now()}`;
  const session = await createCheckoutSession({ amount: due.amount, clientReference: reference });
  await query(
    'INSERT INTO wave_sessions (id, due_id, child_id, parent_id, amount) VALUES ($1,$2,$3,$4,$5)',
    [session.id, due.id, body.childId, req.user.id, due.amount],
  );
  res.json({ mode, url: session.launchUrl, amount: due.amount, label: due.label });
});

// Mode lien marchand : le parent signale qu'il a payé ; un responsable confirme ensuite.
router.post('/declare', json, authenticate, requireRole('parent'), async (req, res) => {
  const body = parseBody(payBody.extend({ reference: z.string().trim().max(60).optional() }), req.body);
  const due = await loadPayableDue(req.user.id, body);
  await query(
    `INSERT INTO payments (due_id, child_id, status, method, amount, reference, updated_by)
     VALUES ($1, $2, 'pending', 'wave_declare', $3, $4, $5)
     ON CONFLICT (due_id, child_id) DO UPDATE SET reference = EXCLUDED.reference, updated_at = now()
     WHERE payments.status = 'pending'`,
    [due.id, body.childId, due.amount, body.reference || null, req.user.id],
  );
  res.status(201).json({ status: 'pending' });
});

// Webhook Wave : corps brut nécessaire pour vérifier la signature.
router.post('/wave/webhook', express.raw({ type: '*/*', limit: '100kb' }), async (req, res) => {
  const raw = Buffer.isBuffer(req.body) ? req.body.toString('utf8') : '';
  if (!verifyWaveSignature(raw, req.get('wave-signature'))) {
    await securityEvent(req, 'webhook_invalid', { severity: 'critical' });
    throw new HttpError(401, 'Signature invalide');
  }
  let event;
  try { event = JSON.parse(raw); } catch { throw badRequest('JSON invalide'); }
  if (event.type !== 'checkout.session.completed' || event.data?.payment_status !== 'succeeded') {
    return res.json({ received: true });
  }
  await withTransaction(async (client) => {
    const { rows } = await client.query('SELECT * FROM wave_sessions WHERE id = $1 FOR UPDATE', [event.data.id]);
    const session = rows[0];
    if (!session || session.status === 'completed') return;
    if (Number(event.data.amount) !== session.amount) {
      console.warn(`Montant Wave inattendu pour la session ${session.id}`);
      return;
    }
    await client.query(`UPDATE wave_sessions SET status = 'completed', completed_at = now() WHERE id = $1`, [session.id]);
    await client.query(
      `INSERT INTO payments (due_id, child_id, status, method, amount, reference, updated_by)
       VALUES ($1, $2, 'paid', 'wave', $3, $4, $5)
       ON CONFLICT (due_id, child_id) DO UPDATE SET status = 'paid', method = 'wave', amount = EXCLUDED.amount,
         reference = EXCLUDED.reference, updated_at = now()`,
      [session.due_id, session.child_id, session.amount, event.data.transaction_id || session.id, session.parent_id],
    );
  });
  res.json({ received: true });
});

const page = (title, message) => `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>body{font-family:system-ui,sans-serif;background:#eef7fc;color:#0b3a57;display:grid;place-items:center;min-height:100vh;margin:0}
main{background:#fff;padding:32px 24px;border-radius:20px;max-width:360px;text-align:center;box-shadow:0 8px 30px #0b3a5718}
h1{font-size:22px}a{display:inline-block;margin-top:16px;background:#1A9AD6;color:#fff;padding:12px 20px;border-radius:999px;text-decoration:none}</style>
</head><body><main><h1>${title}</h1><p>${message}</p><a href="mycvav://paiement">Retour à My CVAV</a></main></body></html>`;

router.get('/wave/retour', (req, res) => {
  const ok = req.query.statut === 'succes';
  res.type('html').send(ok
    ? page('Paiement effectué', 'Merci ! Votre cotisation sera marquée comme payée dans quelques instants.')
    : page('Paiement non abouti', "Le paiement n'a pas été finalisé. Vous pouvez réessayer depuis l'application."));
});

export default router;
