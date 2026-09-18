-- Users, households, agents, onboarding, e-mail codes and the audit log (SIGNUP-FOR-REAL.md §4.1).
-- Forward-only. Applied under an advisory lock at container start (src/db/migrate.ts).

CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE users (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid   text NOT NULL UNIQUE,
  email          citext UNIQUE,
  email_verified boolean NOT NULL DEFAULT false,
  display_name   text,
  providers      text[] NOT NULL DEFAULT '{}',
  created_at     timestamptz NOT NULL DEFAULT now(),
  last_seen_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz
);

CREATE TABLE households (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES users (id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE household_members (
  household_id uuid NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES users (id),
  role         text NOT NULL CHECK (role IN ('owner')),
  PRIMARY KEY (household_id, user_id)
);

CREATE INDEX household_members_user_idx ON household_members (user_id);

CREATE TABLE agents (
  household_id uuid PRIMARY KEY REFERENCES households (id) ON DELETE CASCADE,
  name         text,
  named_at     timestamptz
);

CREATE TABLE onboarding (
  user_id      uuid PRIMARY KEY REFERENCES users (id),
  stage        text NOT NULL CHECK (stage IN ('know', 'setup', 'chat')),
  completed_at timestamptz
);

CREATE TABLE email_codes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email       citext NOT NULL,
  code_hash   text NOT NULL,
  attempts    int NOT NULL DEFAULT 0,
  expires_at  timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX email_codes_email_created_idx ON email_codes (email, created_at DESC);

CREATE TABLE audit_log (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid REFERENCES users (id),
  event      text NOT NULL,
  detail     jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip         inet,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_log_event_ip_created_idx ON audit_log (event, ip, created_at DESC);
CREATE INDEX audit_log_user_idx ON audit_log (user_id);
