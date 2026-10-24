-- Schéma initial My CVAV Sainte Famille

CREATE TABLE IF NOT EXISTS users (
  id             SERIAL PRIMARY KEY,
  role           TEXT NOT NULL CHECK (role IN ('responsable', 'parent')),
  full_name      TEXT NOT NULL,
  phone          TEXT NOT NULL UNIQUE,
  password_hash  TEXT NOT NULL,
  legion         TEXT CHECK (legion IN ('meneurs', 'aines', 'cadets', 'benjamins')),
  token_version  INT NOT NULL DEFAULT 0,
  failed_logins  INT NOT NULL DEFAULT 0,
  locked_until   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS children (
  id            SERIAL PRIMARY KEY,
  last_name     TEXT NOT NULL,
  first_name    TEXT NOT NULL,
  birth_date    DATE,
  age           INT CHECK (age BETWEEN 0 AND 30),
  legion        TEXT NOT NULL CHECK (legion IN ('meneurs', 'aines', 'cadets', 'benjamins')),
  parent_name   TEXT,
  parent_phone  TEXT,
  address       TEXT,
  link_code     TEXT NOT NULL UNIQUE,
  created_by    INT REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS children_legion_idx ON children (legion);
CREATE INDEX IF NOT EXISTS children_name_idx ON children (lower(last_name), lower(first_name));

-- Lien parent <-> enfant (établi avec le code enfant fourni par un responsable)
CREATE TABLE IF NOT EXISTS parent_children (
  parent_id  INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  child_id   INT NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  linked_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (parent_id, child_id)
);
CREATE INDEX IF NOT EXISTS parent_children_child_idx ON parent_children (child_id);

-- Activités de l'année et réunions (support du pointage des présences)
CREATE TABLE IF NOT EXISTS events (
  id          SERIAL PRIMARY KEY,
  kind        TEXT NOT NULL CHECK (kind IN ('activite', 'reunion')),
  name        TEXT NOT NULL,
  event_date  DATE,
  year        TEXT NOT NULL,
  position    INT NOT NULL DEFAULT 100,
  created_by  INT REFERENCES users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS events_year_idx ON events (year, kind);
CREATE UNIQUE INDEX IF NOT EXISTS events_activity_uniq ON events (year, lower(name)) WHERE kind = 'activite';

CREATE TABLE IF NOT EXISTS attendance (
  event_id   INT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  child_id   INT NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  status     TEXT NOT NULL CHECK (status IN ('present', 'absent')),
  marked_by  INT REFERENCES users(id) ON DELETE SET NULL,
  marked_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, child_id)
);
CREATE INDEX IF NOT EXISTS attendance_child_idx ON attendance (child_id);

-- Cotisations : paroissiale / diocésaine (une par année) et une par activité
CREATE TABLE IF NOT EXISTS dues (
  id          SERIAL PRIMARY KEY,
  kind        TEXT NOT NULL CHECK (kind IN ('paroissiale', 'diocesaine', 'activite')),
  year        TEXT NOT NULL,
  event_id    INT UNIQUE REFERENCES events(id) ON DELETE CASCADE,
  label       TEXT NOT NULL,
  amount      INT CHECK (amount >= 0),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((kind = 'activite') = (event_id IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS dues_year_kind_uniq ON dues (year, kind) WHERE event_id IS NULL;

-- Absence de ligne = non payé. pending = paiement déclaré par le parent, à confirmer.
CREATE TABLE IF NOT EXISTS payments (
  due_id      INT NOT NULL REFERENCES dues(id) ON DELETE CASCADE,
  child_id    INT NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  status      TEXT NOT NULL CHECK (status IN ('pending', 'paid')),
  method      TEXT NOT NULL CHECK (method IN ('manuel', 'wave', 'wave_declare')),
  amount      INT,
  reference   TEXT,
  updated_by  INT REFERENCES users(id) ON DELETE SET NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (due_id, child_id)
);

CREATE TABLE IF NOT EXISTS wave_sessions (
  id          TEXT PRIMARY KEY,
  due_id      INT NOT NULL REFERENCES dues(id) ON DELETE CASCADE,
  child_id    INT NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  parent_id   INT REFERENCES users(id) ON DELETE SET NULL,
  amount      INT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'open',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS posts (
  id          SERIAL PRIMARY KEY,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  pinned      BOOLEAN NOT NULL DEFAULT false,
  created_by  INT REFERENCES users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS posts_created_idx ON posts (pinned DESC, created_at DESC);
