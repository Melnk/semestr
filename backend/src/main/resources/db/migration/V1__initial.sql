CREATE TABLE accounts (
 id uuid PRIMARY KEY, email text NOT NULL UNIQUE, password_hash text NOT NULL,
 verified boolean NOT NULL DEFAULT false, profile jsonb NOT NULL DEFAULT '{}',
 version bigint NOT NULL DEFAULT 0, revision bigint NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE sessions (
 token_hash text PRIMARY KEY, user_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 csrf text NOT NULL, expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user ON sessions(user_id);
CREATE TABLE email_tokens (
 token_hash text PRIMARY KEY, user_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 purpose text NOT NULL CHECK (purpose IN ('verify','reset')), expires_at timestamptz NOT NULL
);
CREATE TABLE rate_limits (key text PRIMARY KEY, count integer NOT NULL, expires_at timestamptz NOT NULL);
CREATE TABLE study_records (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('subject','task','debt','lesson','note')),
 subject_id uuid, debt_id uuid, lesson_id uuid,
 payload jsonb NOT NULL, version bigint NOT NULL DEFAULT 0,
 updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(user_id,id),
 FOREIGN KEY(user_id,subject_id) REFERENCES study_records(user_id,id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,debt_id) REFERENCES study_records(user_id,id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,lesson_id) REFERENCES study_records(user_id,id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
 CHECK ((kind='subject' AND subject_id IS NULL) OR (kind<>'subject' AND subject_id IS NOT NULL)),
 CHECK (payload->>'kind'=kind)
);
CREATE INDEX study_owner_kind ON study_records(user_id,kind,id);
CREATE INDEX study_subject ON study_records(user_id,subject_id);
CREATE INDEX study_deadline ON study_records(user_id,(payload->>'deadline'));
CREATE TABLE lesson_exceptions (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 lesson_id uuid NOT NULL, original_date date NOT NULL, starts_at timestamptz, ends_at timestamptz,
 version bigint NOT NULL DEFAULT 0, UNIQUE(user_id,lesson_id,original_date),
 FOREIGN KEY(user_id,lesson_id) REFERENCES study_records(user_id,id) ON DELETE CASCADE,
 CHECK ((starts_at IS NULL AND ends_at IS NULL) OR (starts_at IS NOT NULL AND ends_at IS NOT NULL AND ends_at>starts_at))
);
