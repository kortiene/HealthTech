-- Non-identifying media metadata for the zero-knowledge proxy (#23, ADR 0004/0005).
-- Mirrors blob_metadata but for heavy-media objects (radiographs, scans — up to 25 MB).
-- Stores ONLY: uuid (anonymous index), ciphertext size, optimistic-concurrency version.
-- NEVER stores: plaintext, content key, MIME type, patient identifier, or any PII.
-- The per-media content key and MIME type live inside the client's encrypted record only.
-- Safe to run multiple times (CREATE TABLE IF NOT EXISTS).
CREATE TABLE IF NOT EXISTS media_metadata (
    uuid        UUID        PRIMARY KEY,
    size        BIGINT      NOT NULL CHECK (size >= 0),
    version     BIGINT      NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
