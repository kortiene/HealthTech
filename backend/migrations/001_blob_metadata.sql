-- Non-identifying blob metadata for the zero-knowledge proxy (#103, ADR 0004/0005).
-- Stores ONLY: uuid (anonymous index), ciphertext size, optimistic-concurrency version.
-- NEVER stores: plaintext, key material, PII, or any patient identifier.
-- Safe to run multiple times (CREATE TABLE IF NOT EXISTS).
CREATE TABLE IF NOT EXISTS blob_metadata (
    uuid        UUID        PRIMARY KEY,
    size        BIGINT      NOT NULL CHECK (size >= 0),
    version     BIGINT      NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
