export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export const badRequest = (msg, details) => new HttpError(400, msg, details);
export const notFound = (msg = 'Ressource introuvable') => new HttpError(404, msg);
export const forbidden = (msg = 'Accès refusé') => new HttpError(403, msg);

export function parseBody(schema, data) {
  const result = schema.safeParse(data);
  if (!result.success) {
    const details = result.error.issues.map((i) => ({ champ: i.path.join('.'), message: i.message }));
    throw badRequest('Données invalides', details);
  }
  return result.data;
}

export function parseId(value) {
  const id = Number(value);
  if (!Number.isInteger(id) || id <= 0) throw badRequest('Identifiant invalide');
  return id;
}
