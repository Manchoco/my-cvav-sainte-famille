import pg from 'pg';
import { config } from './config.js';

// Les colonnes DATE sont renvoyées telles quelles ("2026-10-24") pour éviter les décalages de fuseau.
pg.types.setTypeParser(1082, (v) => v);

export const pool = new pg.Pool({
  connectionString: config.databaseUrl,
  ssl: config.databaseSsl ? { rejectUnauthorized: false } : undefined,
  // En fonction serverless (Vercel), peu de connexions par instance : la base Neon utilise son pooler.
  max: process.env.VERCEL ? 3 : 10,
  idleTimeoutMillis: 10_000,
});

export const query = (text, params) => pool.query(text, params);

export async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
