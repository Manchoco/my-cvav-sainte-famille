import { query } from '../db.js';

// Journal des actions sensibles (administration, suppressions, réinitialisations).
export async function audit(req, action, target = null, details = null) {
  try {
    await query(
      'INSERT INTO audit_log (actor_id, action, target, details, ip) VALUES ($1, $2, $3, $4, $5)',
      [req.user?.id ?? null, action, target, details ? JSON.stringify(details) : null, req.ip ?? null],
    );
  } catch (err) {
    console.error('Audit impossible', err.message);
  }
}
