-- Accounts, sessions and the route sets they own.
--
-- Nothing here stores a secret it could give back. A session cookie, a
-- remember-me token and an invite code are all kept as their SHA-256, so a
-- copy of this database is not a set of working credentials. Passwords are
-- argon2id, which is the one case where the stored form is the verifier.

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username      text NOT NULL,
  password_hash text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_login    timestamptz,
  disabled      boolean NOT NULL DEFAULT false
);
-- Case-insensitively unique without the citext extension, which needs rights
-- the service's own role has no business having.
CREATE UNIQUE INDEX users_username_key ON users (lower(username));

CREATE TABLE sessions (
  id         bytea PRIMARY KEY,          -- sha256 of the cookie value
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  csrf       bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen  timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  ip         inet,
  user_agent text
);
CREATE INDEX sessions_user ON sessions (user_id);
CREATE INDEX sessions_expires ON sessions (expires_at);

-- Remember-me is a (series, token) pair. The series names the cookie for its
-- whole life; the token is replaced on every use. A token that has already
-- been spent coming back means the cookie was copied, and the series is burned
-- along with every session the user has.
CREATE TABLE remember_tokens (
  series       bytea PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash   bytea NOT NULL,
  -- The token this one replaced, honoured for a few seconds after rotation.
  -- Without it, two tabs restoring the same session at once look exactly like
  -- a stolen cookie and the account logs itself out.
  prev_hash    bytea,
  rotated_at   timestamptz,
  expires_at   timestamptz NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  ip           inet,
  user_agent   text
);
CREATE INDEX remember_user ON remember_tokens (user_id);
CREATE INDEX remember_expires ON remember_tokens (expires_at);

CREATE TABLE route_sets (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       text NOT NULL,
  routes     text[] NOT NULL DEFAULT '{}',
  ord        integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX route_sets_name ON route_sets (user_id, lower(name));
CREATE INDEX route_sets_user ON route_sets (user_id, ord);

CREATE TABLE user_prefs (
  user_id    uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  active_set uuid REFERENCES route_sets(id) ON DELETE SET NULL,
  data       jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE access_codes (
  code_hash  bytea PRIMARY KEY,
  note       text,
  uses_left  integer NOT NULL DEFAULT 1,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- What the operator needs to answer "was this account attacked, and did it
-- work". Written on every login, failure, remember-me use and theft.
CREATE TABLE auth_events (
  id      bigserial PRIMARY KEY,
  at      timestamptz NOT NULL DEFAULT now(),
  kind    text NOT NULL,
  user_id uuid,
  ip      inet,
  detail  text
);
CREATE INDEX auth_events_at ON auth_events (at DESC);
CREATE INDEX auth_events_user ON auth_events (user_id, at DESC);
