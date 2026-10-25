-- Application d'authentification (codes TOTP) pour la double vérification administrateur
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_pending_secret TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_last_step BIGINT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS recovery_codes JSONB;
ALTER TABLE login_challenges ADD COLUMN IF NOT EXISTS method TEXT NOT NULL DEFAULT 'sms';
