// Point d'entrée Vercel (fonction serverless) : migrations au premier appel de chaque instance.
import { createApp } from '../src/app.js';
import { migrate } from '../src/migrate.js';

const app = createApp();
let ready;

export default async function handler(req, res) {
  ready ??= migrate().catch((err) => {
    ready = undefined;
    throw err;
  });
  try {
    await ready;
  } catch (err) {
    console.error('Migration impossible', err);
    res.statusCode = 503;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Service momentanément indisponible' }));
    return;
  }
  return app(req, res);
}
