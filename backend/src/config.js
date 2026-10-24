import 'dotenv/config';

const env = process.env;
const isProd = env.NODE_ENV === 'production';

function required(name, fallbackForDev) {
  const value = env[name];
  if (value) return value;
  if (!isProd && fallbackForDev !== undefined) return fallbackForDev;
  throw new Error(`Variable d'environnement manquante : ${name}`);
}

const jwtSecret = required('JWT_SECRET', 'dev-only-secret-change-me-dev-only-secret');
if (isProd && jwtSecret.length < 32) {
  throw new Error('JWT_SECRET doit contenir au moins 32 caractères');
}

export const config = {
  isProd,
  port: Number(env.PORT || 3000),
  databaseUrl: required('DATABASE_URL', 'postgres://localhost:5432/cvav'),
  databaseSsl: env.DATABASE_SSL === 'true',
  jwtSecret,
  jwtExpiresIn: env.JWT_EXPIRES_IN || '7d',
  // Sans ce code, l'inscription des responsables est fermée (sécurité par défaut).
  responsableSignupCode: env.RESPONSABLE_SIGNUP_CODE || '',
  corsOrigins: (env.CORS_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean),
  publicBaseUrl: (env.PUBLIC_BASE_URL || `http://localhost:${env.PORT || 3000}`).replace(/\/$/, ''),
  parishDueDefault: Number(env.PAROISSIALE_MONTANT || 1500),
  sms: {
    provider: (env.SMS_PROVIDER || '').toLowerCase(), // orange | twilio | console
    senderName: env.SMS_SENDER_NAME || '',
    orangeClientId: env.ORANGE_CLIENT_ID || '',
    orangeClientSecret: env.ORANGE_CLIENT_SECRET || '',
    orangeSender: env.ORANGE_SENDER_ADDRESS || 'tel:+2250000',
    twilioSid: env.TWILIO_ACCOUNT_SID || '',
    twilioToken: env.TWILIO_AUTH_TOKEN || '',
    twilioFrom: env.TWILIO_FROM || '',
  },
  wave: {
    apiKey: env.WAVE_API_KEY || '',
    webhookSecret: env.WAVE_WEBHOOK_SECRET || '',
    merchantLink: env.WAVE_MERCHANT_LINK || '',
    apiBase: env.WAVE_API_BASE || 'https://api.wave.com',
  },
};
