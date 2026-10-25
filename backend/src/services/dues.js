// Montants des cotisations par légion.
// Règle : le prix propre à la légion (due_legion_amounts) l'emporte ; sinon le montant commun (dues.amount).
import { LEGIONS } from '../domain.js';

// Expression SQL du montant dû pour un enfant (alias de la cotisation et de l'enfant en paramètres).
export const effectiveAmountSql = (d = 'd', c = 'c') =>
  `COALESCE((SELECT dla.amount FROM due_legion_amounts dla WHERE dla.due_id = ${d}.id AND dla.legion = ${c}.legion), ${d}.amount)`;

// Sous-requête : { legion: montant } des prix propres à chaque légion.
export const legionAmountsSql = (d = 'd') =>
  `(SELECT json_object_agg(dla.legion, dla.amount) FROM due_legion_amounts dla WHERE dla.due_id = ${d}.id)`;

export function amountsByLegion(commonAmount, legionAmounts) {
  return Object.fromEntries(LEGIONS.map((l) => [l, legionAmounts?.[l] ?? commonAmount ?? null]));
}

// Montant unique si toutes les légions paient la même somme, sinon null.
export function uniformAmount(amounts) {
  const values = LEGIONS.map((l) => amounts[l]);
  return values.every((v) => v === values[0]) ? values[0] : null;
}

// Enregistre les prix d'une cotisation. Même prix partout : stocké comme montant commun.
export async function saveDueAmounts(client, dueId, amounts, userId) {
  const uniform = uniformAmount(amounts);
  await client.query('DELETE FROM due_legion_amounts WHERE due_id = $1', [dueId]);
  if (uniform !== null) {
    await client.query('UPDATE dues SET amount = $2 WHERE id = $1', [dueId, uniform]);
    return;
  }
  await client.query('UPDATE dues SET amount = NULL WHERE id = $1', [dueId]);
  for (const legion of LEGIONS) {
    if (amounts[legion] == null) continue;
    await client.query(
      'INSERT INTO due_legion_amounts (due_id, legion, amount, updated_by) VALUES ($1, $2, $3, $4)',
      [dueId, legion, amounts[legion], userId],
    );
  }
}
