CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  birth_date date,
  interest text,
  username text,
  email text NOT NULL,
  phone text,
  password_hash text,
  security_question text,
  security_answer_hash text,
  google_sub text,
  google_photo_url text,
  auth_provider text NOT NULL DEFAULT 'local',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_lower
ON users (lower(email));

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_lower
ON users (lower(username))
WHERE username IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_sub
ON users (google_sub)
WHERE google_sub IS NOT NULL;
