import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { config } from './config.js';
import { HttpError } from './errors.js';
import { authenticate, requireRole } from './middleware/auth.js';
import authRoutes from './routes/auth.js';
import childrenRoutes from './routes/children.js';
import eventsRoutes from './routes/events.js';
import duesRoutes from './routes/dues.js';
import postsRoutes from './routes/posts.js';
import parentRoutes from './routes/parent.js';
import paymentsRoutes from './routes/payments.js';
import statsRoutes from './routes/stats.js';
import { LEGIONS, LEGION_LABELS, currentPastoralYear } from './domain.js';
import { waveMode } from './services/wave.js';

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(helmet());
  // L'application mobile n'envoie pas d'en-tête Origin ; CORS ne concerne qu'un éventuel client web.
  app.use(cors({ origin: config.corsOrigins.length ? config.corsOrigins : false }));
  app.use(rateLimit({ windowMs: 60 * 1000, limit: 300, standardHeaders: 'draft-7', legacyHeaders: false }));

  // Le webhook Wave lit le corps brut : il est monté avant express.json().
  app.use('/api/payments', paymentsRoutes);
  app.use(express.json({ limit: '2mb' }));

  app.get('/api/health', (_req, res) => res.json({ status: 'ok' }));
  app.get('/api/meta', (_req, res) => res.json({
    name: 'My CVAV Sainte Famille',
    year: currentPastoralYear(),
    legions: LEGIONS.map((id) => ({ id, label: LEGION_LABELS[id] })),
    paymentMode: waveMode(),
    responsableSignupOpen: Boolean(config.responsableSignupCode),
  }));

  app.use('/api/auth', authRoutes);
  app.use('/api/children', authenticate, requireRole('responsable'), childrenRoutes);
  app.use('/api/events', authenticate, requireRole('responsable'), eventsRoutes);
  app.use('/api/dues', authenticate, requireRole('responsable'), duesRoutes);
  app.use('/api/stats', authenticate, requireRole('responsable'), statsRoutes);
  app.use('/api/posts', authenticate, postsRoutes);
  app.use('/api/parent', authenticate, requireRole('parent'), parentRoutes);

  app.use((_req, _res, next) => next(new HttpError(404, 'Route introuvable')));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err.code === 'LIMIT_FILE_SIZE') return res.status(413).json({ error: 'Fichier trop volumineux (5 Mo maximum)' });
    if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'JSON invalide' });
    if (err.type === 'entity.too.large') return res.status(413).json({ error: 'Requête trop volumineuse' });
    const status = err.status && err.status >= 400 && err.status < 600 ? err.status : 500;
    if (status >= 500) console.error(err);
    res.status(status).json({
      error: status >= 500 && !(err instanceof HttpError) && status !== 502 ? 'Erreur interne du serveur' : err.message,
      ...(err.details ? { details: err.details } : {}),
    });
  });

  return app;
}
