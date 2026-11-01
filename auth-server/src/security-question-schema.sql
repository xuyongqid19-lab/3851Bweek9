-- Additive migration. Existing users, questions and answer hashes are untouched.
CREATE TABLE IF NOT EXISTS security_question_challenges (
  token_hash text PRIMARY KEY CHECK (length(token_hash) = 64),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  account_key text NOT NULL,
  session_version integer,
  verified boolean NOT NULL DEFAULT false,
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_security_question_challenges_expiry
  ON security_question_challenges(expires_at);
CREATE INDEX IF NOT EXISTS idx_security_question_challenges_user
  ON security_question_challenges(user_id);

-- Auth-only storage. Legacy users.security_* fields remain untouched and do not
-- count as a complete three-question configuration.
CREATE TABLE IF NOT EXISTS auth_security_questions (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  slot smallint NOT NULL CHECK (slot BETWEEN 1 AND 3),
  question text NOT NULL CHECK (length(question) BETWEEN 5 AND 200),
  normalized_question text NOT NULL,
  answer_hash text NOT NULL,
  PRIMARY KEY (user_id, slot),
  UNIQUE (user_id, normalized_question)
);
ALTER TABLE security_question_challenges ADD COLUMN IF NOT EXISTS question_set_hash text;
