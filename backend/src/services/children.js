import { ageFrom, generateLinkCode, LEGION_LABELS } from '../domain.js';

export function childDto(row) {
  return {
    id: row.id,
    lastName: row.last_name,
    firstName: row.first_name,
    fullName: `${row.last_name} ${row.first_name}`,
    birthDate: row.birth_date,
    age: ageFrom(row.birth_date, row.age),
    legion: row.legion,
    legionLabel: LEGION_LABELS[row.legion],
    parentName: row.parent_name,
    parentPhone: row.parent_phone,
    address: row.address,
    linkCode: row.link_code,
    linkedParents: row.linked_parents != null ? Number(row.linked_parents) : undefined,
  };
}

// Pour un parent : sans le code de liaison ni les autres coordonnées internes.
export function childDtoForParent(row) {
  const { linkCode, linkedParents, ...rest } = childDto(row);
  return rest;
}

export async function insertChild(client, data, userId) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      const { rows } = await client.query(
        `INSERT INTO children (last_name, first_name, birth_date, age, legion, parent_name, parent_phone, address, link_code, created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,
        [data.lastName, data.firstName, data.birthDate ?? null, data.age ?? null, data.legion,
          data.parentName ?? null, data.parentPhone ?? null, data.address ?? null, generateLinkCode(), userId],
      );
      return rows[0];
    } catch (err) {
      // Collision (très improbable) sur le code de liaison : on régénère.
      if (err.code === '23505' && err.constraint === 'children_link_code_key') continue;
      throw err;
    }
  }
  throw new Error('Impossible de générer un code enfant unique');
}
