import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { query } from '../db.js';
import { HttpError, forbidden } from '../errors.js';
import { getSettings } from '../services/settings.js';

export function signToken(user) {
  return jwt.sign({ sub: String(user.id), tv: user.token_version }, config.jwtSecret, {
    expiresIn: config.jwtExpiresIn,
    algorithm: 'HS256',
  });
}

export class MaintenanceError extends HttpError {
  constructor(message) {
    super(503, message);
    this.maintenance = true;
  }
}

// Routes accessibles tant que le mot de passe provisoire n'a pas été changé.
const PASSWORD_CHANGE_ALLOWED = ['/api/auth/me', '/api/auth/password'];

export async function authenticate(req, _res, next) {
  try {
    const header = req.get('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw new HttpError(401, 'Authentification requise');
    let payload;
    try {
      // Algorithme imposé : refuse "none" et toute confusion d'algorithme.
      payload = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
    } catch {
      throw new HttpError(401, 'Session expirée, veuillez vous reconnecter');
    }
    const id = Number(payload.sub);
    if (!Number.isInteger(id)) throw new HttpError(401, 'Session expirée, veuillez vous reconnecter');
    const { rows } = await query(
      `SELECT id, role, full_name, phone, legion, token_version, disabled, must_change_password
       FROM users WHERE id = $1`,
      [id],
    );
    const user = rows[0];
    if (!user || user.token_version !== payload.tv) throw new HttpError(401, 'Session expirée, veuillez vous reconnecter');
    if (user.disabled) throw new HttpError(403, 'Ce compte a été désactivé. Contactez l\'administrateur.');
    if (user.role !== 'admin') {
      const { maintenance } = await getSettings();
      if (maintenance.enabled) throw new MaintenanceError(maintenance.message);
    }
    const path = req.originalUrl.split('?')[0];
    if (user.must_change_password && !PASSWORD_CHANGE_ALLOWED.includes(path)) {
      const err = new HttpError(403, 'Vous devez choisir un nouveau mot de passe.');
      err.code = 'PASSWORD_CHANGE_REQUIRED';
      throw err;
    }
    req.user = user;
    next();
  } catch (err) {
    next(err);
  }
}

// L'administrateur a tous les droits d'un responsable.
export const requireRole = (...roles) => (req, _res, next) => {
  const role = req.user?.role;
  if (!role) return next(forbidden());
  if (roles.includes(role) || (role === 'admin' && roles.includes('responsable'))) return next();
  next(forbidden());
};
