-- Prix des cotisations par légion (sans ligne : le montant commun de la cotisation s'applique)
CREATE TABLE IF NOT EXISTS due_legion_amounts (
  due_id      INT NOT NULL REFERENCES dues(id) ON DELETE CASCADE,
  legion      TEXT NOT NULL CHECK (legion IN ('meneurs', 'aines', 'cadets', 'benjamins')),
  amount      INT NOT NULL CHECK (amount >= 0),
  updated_by  INT REFERENCES users(id) ON DELETE SET NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (due_id, legion)
);

-- Événements de sécurité (tentatives suspectes) consultables par l'administrateur
CREATE TABLE IF NOT EXISTS security_events (
  id          BIGSERIAL PRIMARY KEY,
  type        TEXT NOT NULL,
  severity    TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
  ip          TEXT,
  user_id     INT REFERENCES users(id) ON DELETE SET NULL,
  phone       TEXT,
  path        TEXT,
  details     JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS security_events_created_idx ON security_events (created_at DESC);
CREATE INDEX IF NOT EXISTS security_events_ip_idx ON security_events (ip, created_at DESC);

-- Adresses IP bloquées par l'administrateur
CREATE TABLE IF NOT EXISTS blocked_ips (
  ip          TEXT PRIMARY KEY,
  reason      TEXT,
  blocked_by  INT REFERENCES users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ
);

-- Double vérification par SMS de la connexion administrateur
CREATE TABLE IF NOT EXISTS login_challenges (
  id          TEXT PRIMARY KEY,
  user_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash   TEXT NOT NULL,
  ip          TEXT,
  attempts    INT NOT NULL DEFAULT 0,
  expires_at  TIMESTAMPTZ NOT NULL,
  used_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS login_challenges_user_idx ON login_challenges (user_id, created_at DESC);

ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_ip TEXT;
