// Envoi de SMS. Fournisseurs : Orange SMS API (Côte d'Ivoire), Twilio, ou "console" (développement).
import { config } from '../config.js';

export function smsProvider() {
  const { provider } = config.sms;
  if (provider === 'console' && config.isProd) return 'disabled';
  return provider || 'disabled';
}

// Numéros stockés sur 10 chiffres (format ivoirien) -> E.164 (+225…)
export function toE164(phone) {
  return phone.length === 10 ? `+225${phone}` : `+${phone}`;
}

let orangeToken = null;
async function orangeAccessToken() {
  if (orangeToken && orangeToken.expiresAt > Date.now() + 60_000) return orangeToken.value;
  const basic = Buffer.from(`${config.sms.orangeClientId}:${config.sms.orangeClientSecret}`).toString('base64');
  const res = await fetch('https://api.orange.com/oauth/v3/token', {
    method: 'POST',
    headers: { Authorization: `Basic ${basic}`, 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
    body: 'grant_type=client_credentials',
    signal: AbortSignal.timeout(10_000),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) throw new Error(`Orange OAuth ${res.status}`);
  orangeToken = { value: body.access_token, expiresAt: Date.now() + Number(body.expires_in || 3600) * 1000 };
  return orangeToken.value;
}

async function sendOrange(to, message) {
  const sender = config.sms.orangeSender; // ex. tel:+2250000
  const res = await fetch(`https://api.orange.com/smsmessaging/v1/outbound/${encodeURIComponent(sender)}/requests`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${await orangeAccessToken()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      outboundSMSMessageRequest: {
        address: `tel:${to}`,
        senderAddress: sender,
        ...(config.sms.senderName ? { senderName: config.sms.senderName } : {}),
        outboundSMSTextMessage: { message },
      },
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`Orange SMS ${res.status}`);
}

async function sendTwilio(to, message) {
  const { twilioSid, twilioToken, twilioFrom } = config.sms;
  const params = new URLSearchParams({ To: to, Body: message });
  if (twilioFrom.startsWith('MG')) params.set('MessagingServiceSid', twilioFrom);
  else params.set('From', twilioFrom);
  const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Messages.json`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${twilioSid}:${twilioToken}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: params,
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`Twilio ${res.status}`);
}

// Pour les tests : derniers messages "envoyés" en mode console.
export const consoleOutbox = [];

export async function sendSms(phone, message) {
  const to = toE164(phone);
  switch (smsProvider()) {
    case 'orange': return sendOrange(to, message);
    case 'twilio': return sendTwilio(to, message);
    case 'console':
      consoleOutbox.push({ to, message });
      if (process.env.NODE_ENV !== 'test') console.log(`[SMS] ${to} : ${message}`);
      return undefined;
    default:
      throw new Error('SMS non configuré');
  }
}
