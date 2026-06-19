# ADR 0005 — Storage & sovereign hosting

**Status:** Accepted (2026-06-19) · Issue [#1](https://github.com/kortiene/HealthTech/issues/1) · Implements Epics E7 (#8, #9), E5 (#23)

## Context

Encrypted blobs and metadata must be **hosted on Ivorian soil** to satisfy ARTCI / loi n°2013-450; a
foreign managed cloud anywhere in the data path is non-compliant. Heavy medical images must not live on the
patient device — only an ephemeral URL is embedded in the ≤500 KB text blob. The system targets a small
team operating in-country at 50k/500 scale.

## Decision

- **Encrypted-blob + media object store: self-hosted MinIO** (S3-compatible, single binary, runs entirely
  in-country). The Rust backend issues **short-TTL presigned/ephemeral URLs** for heavy media, tightly
  per-object scoped and revocable. Server-side encryption-at-rest is layered *under* the already
  client-encrypted blobs (defense in depth; confidentiality never depends on it).
- **Metadata DB: PostgreSQL 16**, self-hosted in-country, storing **only non-identifying** data — anonymous
  blob UUID, ciphertext version/size, timestamps, KDF params (salt + iteration count, public by design),
  sync bookkeeping. No PII, no plaintext, no keys, no CMU/phone in clear.
- **Hosting: sovereign, in-country only** (ARTCI-eligible national datacenter, e.g. VITIB-Grand-Bassam /
  licensed local operator), provisioned via **Terraform + Ansible** IaC. Footprint: Rust backend (2× for
  HA) + MinIO + Postgres (primary + replica) + TLS reverse proxy (Caddy/Nginx) + WAF, on rented bare-metal
  / VMs physically in Côte d'Ivoire. **No foreign managed cloud in the data path.** In-country encrypted
  backups; data-localization attestation for the homologation dossier (#30).

## Consequences

**Positive**
- Standard S3 API keeps backend code conventional; everything self-hostable for ARTCI compliance.
- Postgres gives proven reliability/backups at this scale with minimal ops.
- Presigned-URL discipline bounds media exposure.

**Negative / risks**
- **Single in-country datacenter is an availability SPOF** — no foreign failover is permitted. Mitigate
  with in-country HA (primary+replica, warm standby) and offline-first clients so consultations survive
  outages.
- Sovereign hosting is a **long-lead procurement** item (#8) on the launch critical path; start early.
- Self-managed MinIO/Postgres/HA is real ops work for a small team; IaC + runbooks are mandatory.

## Alternatives considered

- **Foreign managed object store (AWS S3 / GCS)** — non-compliant with data residency; rejected outright.
- **Single combined DB+blob in Postgres (bytea)** — simpler, but bloats the DB and loses presigned-URL
  media handling; rejected for the media offload requirement (#23).
