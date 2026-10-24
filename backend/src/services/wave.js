// Intégration Wave (Côte d'Ivoire).
// Mode "checkout" : API Wave Business -> session de paiement + webhook signé (paiement confirmé automatiquement).
// Mode "lien marchand" : lien pay.wave.com avec le montant ; le parent déclare son paiement, un responsable confirme.
import crypto from 'node:crypto';
import { config } from '../config.js';

export function waveMode() {
  if (config.wave.apiKey) return 'checkout';
  if (config.wave.merchantLink) return 'merchant_link';
  return 'disabled';
}

export async function createCheckoutSession({ amount, clientReference }) {
  const res = await fetch(`${config.wave.apiBase}/v1/checkout/sessions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.wave.apiKey}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': clientReference,
    },
    body: JSON.stringify({
      amount: String(amount),
      currency: 'XOF',
      client_reference: clientReference,
      success_url: `${config.publicBaseUrl}/api/payments/wave/retour?statut=succes`,
      error_url: `${config.publicBaseUrl}/api/payments/wave/retour?statut=echec`,
    }),
    signal: AbortSignal.timeout(15_000),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.wave_launch_url) {
    const err = new Error('Wave indisponible pour le moment, réessayez plus tard');
    err.status = 502;
    err.cause = body;
    throw err;
  }
  return { id: body.id, launchUrl: body.wave_launch_url };
}

export function merchantLinkUrl(amount) {
  const url = new URL(config.wave.merchantLink);
  url.searchParams.set('amount', String(amount));
  return url.toString();
}

// En-tête "Wave-Signature: t=<timestamp>,v1=<hmac>[,v1=<hmac>]" ; HMAC-SHA256(secret, timestamp + corps brut).
export function verifyWaveSignature(rawBody, header, secret = config.wave.webhookSecret, toleranceSec = 300) {
  if (!secret || !header) return false;
  const parts = header.split(',').map((p) => p.trim().split('='));
  const timestamp = parts.find(([k]) => k === 't')?.[1];
  const signatures = parts.filter(([k]) => k === 'v1').map(([, v]) => v);
  if (!timestamp || signatures.length === 0) return false;
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > toleranceSec) return false;
  const expected = crypto.createHmac('sha256', secret).update(timestamp + rawBody).digest('hex');
  return signatures.some((sig) => sig.length === expected.length
    && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected)));
}
