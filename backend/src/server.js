import { config } from './config.js';
import { createApp } from './app.js';
import { migrate } from './migrate.js';
import { pool } from './db.js';

await migrate();
const server = createApp().listen(config.port, () => {
  console.log(`API My CVAV Sainte Famille sur le port ${config.port}`);
});

const shutdown = () => server.close(() => pool.end().then(() => process.exit(0)));
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
