process.env.NODE_ENV = 'test';
process.env.DATABASE_URL ||= 'postgres://postgres:postgres@localhost:5432/cvav_test';
process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-1234';
process.env.RESPONSABLE_SIGNUP_CODE = 'CODE-RESP-2026';
process.env.WAVE_WEBHOOK_SECRET = 'wave-test-secret';
process.env.WAVE_MERCHANT_LINK = 'https://pay.wave.com/m/M_ci_test/c/ci/';
process.env.SMS_PROVIDER = 'console';

const { pool } = await import('../src/db.js');
const { migrate } = await import('../src/migrate.js');
const { createApp } = await import('../src/app.js');
const { resetYearCache } = await import('../src/services/year.js');
const { resetSettingsCache } = await import('../src/services/settings.js');
const { resetBlockedCache } = await import('../src/services/security.js');
const { consoleOutbox } = await import('../src/services/sms.js');
const supertest = (await import('supertest')).default;

export async function freshApp() {
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  resetYearCache();
  resetSettingsCache();
  resetBlockedCache();
  await migrate();
  return supertest(createApp());
}

export async function register(api, { role = 'parent', phone, name = 'Test User', password = 'motdepasse1', legion } = {}) {
  const res = await api.post('/api/auth/register').send({
    role, phone, fullName: name, password, legion,
    signupCode: role === 'responsable' ? 'CODE-RESP-2026' : undefined,
  });
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${JSON.stringify(res.body)}`);
  return { token: res.body.token, user: res.body.user, auth: { Authorization: `Bearer ${res.body.token}` } };
}

export { pool, consoleOutbox };
