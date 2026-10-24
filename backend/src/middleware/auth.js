import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { query } from '../db.js';
import { HttpError, forbidden } from '../errors.js';

export function signToken(user) {
  return jwt.sign({ sub: String(user.id), role: user.role, tv: user.token_version }, config.jwtSecret, {
    expiresIn: config.jwtExpiresIn,
    algorithm: 'HS256',
  });
}

export async function authenticate(req, _res, next) {
  try {
    const header = req.get('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw new HttpError(401, 'Authentification requise');
    let payload;
    try {
      payload = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
    } catch {
      throw new HttpError(401, 'Session expirée, veuillez vous reconnecter');
    }
    const { rows } = await query(
      'SELECT id, role, full_name, phone, legion, token_version FROM users WHERE id = $1',
      [Number(payload.sub)],
    );
    const user = rows[0];
    if (!user || user.token_version !== payload.tv) throw new HttpError(401, 'Session expirée, veuillez vous reconnecter');
    req.user = user;
    next();
  } catch (err) {
    next(err);
  }
}

export const requireRole = (role) => (req, _res, next) => {
  if (req.user?.role !== role) return next(forbidden());
  next();
};
