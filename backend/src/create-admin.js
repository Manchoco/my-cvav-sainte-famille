// Crée (ou réinitialise) un compte administrateur :
//   ADMIN_PHONE=0700000000 ADMIN_PASSWORD='...' npm run create-admin
// Le mot de passe devra être changé à la première connexion.
import bcrypt from 'bcryptjs';
import { pool } from './db.js';
import { migrate } from './migrate.js';
import { normalizePhone } from './domain.js';

const phone = normalizePhone(process.env.ADMIN_PHONE);
const password = process.env.ADMIN_PASSWORD;
if (!phone || !password || password.length < 10) {
  console.error('ADMIN_PHONE et ADMIN_PASSWORD (10 caractères minimum) sont requis');
  process.exit(1);
}
await migrate();
const hash = await bcrypt.hash(password, 10);
await pool.query(
  `INSERT INTO users (role, full_name, phone, password_hash, must_change_password)
   VALUES ('admin', 'Administrateur', $1, $2, true)
   ON CONFLICT (phone) DO UPDATE SET role = 'admin', password_hash = EXCLUDED.password_hash, disabled = false,
     must_change_password = true, token_version = users.token_version + 1`,
  [phone, hash],
);
console.log(`Administrateur prêt : ${phone}`);
await pool.end();
