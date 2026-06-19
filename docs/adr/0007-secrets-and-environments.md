# ADR 0007 — Secrets management & environments (dev / staging / prod)

**Status:** Accepted (2026-06-19) · Issue [#4](https://github.com/kortiene/HealthTech/issues/4) · Implements Epic E0 (#4) · Relates to #3 (CI), #8 (hosting), #9 (blob service), #23 (media)

## Context

The platform must run in distinct **dev / staging / prod** environments and handle
**operational secrets** (PostgreSQL passwords, MinIO access/secret keys, the presigned-URL
signing key, the TLS private key, backup-encryption keys) **without ever committing a secret in
clear text**. Acceptance criteria for #4: **(1)** secrets injected via a vault (*coffre-fort*),
none in clear; **(2)** `staging` is **reproducible from the IaC**.

Two hard constraints from the existing ADRs frame every choice:

- **Data residency (ARTCI / loi n°2013-450, [ADR 0005](./0005-storage-and-sovereign-hosting.md)).**
  The vault **and its root of trust** must be self-hosted **on Ivorian soil**. No foreign managed
  KMS / secret-store (AWS KMS / Secrets Manager, GCP Secret Manager, Azure Key Vault) may appear
  anywhere in the path — including as a SOPS key backend or a Vault auto-unseal mechanism.
- **Zero-knowledge boundary ([ADR 0004](./0004-backend-rust-axum.md), [ADR 0006](./0006-offline-storage-and-keys.md)).**
  This vault holds **operational secrets only**. Patient master keys, per-record data keys, and QR
  session keys are generated and held **client-side only** (Android Keystore / WASM-JS RAM) and
  **must never** enter the vault, the IaC, env files, or CI. The backend's "no key material, no
  decrypt path" property must be preserved.

The starting point: the backend hardcodes its bind address and reads no injected config; the
Terraform/Ansible scaffolds are structure-only; `.gitignore` already excludes `.env*`, `*.pem`,
`*.key`, and `*.tfstate*`, but there is no positive injection workflow and no CI leak tripwire.

## Decision

### 1. Vault tooling — SOPS + age (baseline), OpenBao deferred for prod

- **At-rest, git-stored secrets for IaC bootstrap → [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).**
  SOPS encrypts the *values* inside YAML files with per-environment **age** keys; the *encrypted*
  files are safe to commit, while the age **private keys live in-country** (operator host / HSM /
  operator laptop) and are **never** committed. A `.sops.yaml` `creation_rules` block maps
  `secrets/<env>/*` to the matching age recipient(s), giving per-environment isolation by
  construction. This is the lightest path to "secrets injected via a vault, none in clear, staging
  reproducible" without standing up a server, and is therefore the **baseline**.
- **At-runtime secret broker → self-hosted [OpenBao](https://openbao.org) (deferred to prod).**
  OpenBao (the Apache-2.0 community fork of Vault) is **preferred over HashiCorp Vault** given
  Vault's BUSL relicensing and this repo's AGPL posture. It is **optional for staging** (SOPS-injected
  env files are acceptable there) and recommended for prod once #8 stands up real hosting. Its
  unseal must be **manual / in-country** (HSM or transit) — **never** a foreign auto-unseal KMS.

`ansible-vault` (already name-dropped in the playbook) remains an acceptable *fallback* for the
Ansible layer but is weaker (single shared password, whole-file opacity); we prefer SOPS for
granular, reviewable diffs.

### 2. Environment topology — single `environment ∈ {dev, staging, prod}` input

- **Selection.** Drive everything off one environment selector: the Terraform `environment`
  variable (per-env **var-files** under `infra/environments/<env>.tfvars` — chosen over workspaces
  for reviewability), the Ansible `-e env=<env>` / per-env inventory under
  `infra/ansible/inventories/<env>`, and the backend `APP_ENV` variable.
- **Secret namespaces.** `secrets/dev/`, `secrets/staging/`, `secrets/prod/`, each encrypted to a
  **different** age recipient so a dev key can never decrypt prod (least privilege by construction).
- **Residency invariant.** `staging` **and** `prod` are in-country (the Terraform `country == "CI"`
  guard enforces this and is not exposed per-environment, so it cannot be overridden). `dev` is a
  developer's local machine with **synthetic data only** and **generated throwaway secrets** — never
  real patient data — so residency is N/A there.

### 3. Secret inventory (operational only)

| Secret | Consumer | Notes |
| --- | --- | --- |
| PostgreSQL app / replication / admin passwords | backend, Ansible | per-env; metadata DB only (no PII) |
| MinIO root + service access/secret keys | backend, Ansible | one service key signs presigned media URLs (#23) |
| Presigned-URL signing key | backend | short-TTL media URLs ([ADR 0005](./0005-storage-and-sovereign-hosting.md) / #23) |
| TLS private key + cert | Caddy / reverse proxy | injection point; CA strategy deferred to #8 |
| Backup-encryption key | backups | in-country encrypted backups (ADR 0005) |
| WAF / proxy admin secrets (if any) | Ansible | |
| Deploy / registry creds, SSH keys | CI/CD (#3) | this issue *provides* the store; #3 *consumes* it |

**Excluded — must never be present:** patient master keys, per-record data keys, QR session keys.
**KDF params (salt + iteration count) are public-by-design** (ADR 0005), live in Postgres metadata,
and are **not** secrets — they must not be placed in the vault.

### 4. Injection flow

- **Terraform** reads secret values from SOPS (or, later, the OpenBao provider) — never from
  committed plaintext. The **tfstate backend is encrypted and in-country** (state can embed secret
  values; gitignore alone is insufficient).
- **Ansible** reads via a SOPS lookup / `ansible-vault` and writes secrets into a **non-world-readable**
  systemd `EnvironmentFile=` (mode `0600`) or container env — never into a world-readable file or the
  process argv.
- **Backend** loads its config from the **environment** (`APP_ENV`, `BIND_ADDR`, `DATABASE_URL`,
  `MINIO_*`, `PRESIGNED_URL_SIGNING_KEY`) via `backend/src/config.rs`, which **fails fast** on a
  missing required secret (in `staging`/`prod`) and **redacts** every secret field in `Debug`/`Display`
  so `tracing` can never print a password or key.
- **Local dev** uses `infra/dev/compose.yaml` (Postgres + MinIO) with **throwaway** credentials from a
  gitignored `.env` (copied from the committed `.env.example` placeholders) — no real credential ever
  needed.

### 5. CI leak tripwire (consumed by #3)

- A fail-closed **secret-scan** (`gitleaks`, config `.gitleaks.toml`) runs on every PR.
- A small **house-style tripwire** `scripts/check-secrets.sh` (mirrors
  `scripts/check-adw-sdlc-env.sh`) asserts: no tracked `*.tfstate`, no tracked `.env`
  (non-example), no decrypted `secrets/**` (only `*.sops.yaml` / `*.example` committed), no tracked
  private keys, and that `.sops.yaml` covers every `secrets/<env>/` path. Wired as `just secrets-lint`
  and a CI step. #3 owns the eventual app/backend CI matrix; this issue *provides* the gate.

### 6. Reproducible staging

The documented, idempotent sequence (full bring-up depends on #8 hosting):

```sh
# 1. inject secrets (decrypt the staging bundle to an in-country 0600 env file — no manual edits)
sops -d secrets/staging/services.sops.yaml > /run/healthtech/staging.env   # mode 0600
# 2. provision (env-scoped, residency-guarded)
terraform -chdir=infra/terraform apply -var-file=environments/staging.tfvars
# 3. configure
ansible-playbook -i infra/ansible/inventories/staging infra/ansible/playbook.yml -e env=staging
```

The **credential-free subset** ships now: `terraform fmt -check` / `validate` / per-env `plan`,
`ansible-playbook --syntax-check`, the local `compose` bring-up, and SOPS decrypt to a temp `0600`
file. Full live staging is gated on **#8**; the docs say so explicitly and do not imply live infra
exists.

## Consequences

**Positive**
- Satisfies both acceptance criteria with **no server to operate** (SOPS+age is git-native).
- Per-env age recipients give least-privilege isolation by construction; a dev key cannot read prod.
- The backend gains a fail-fast, redacting config contract; no secret can reach `tracing`.
- The leak tripwire + gitleaks make "no plaintext secret in the repo" enforceable, not aspirational.

**Negative / risks**
- **Bootstrap chicken-and-egg:** who holds the first age key / OpenBao root, and how is it distributed
  to in-country operators without a foreign secret-distribution channel? Documented runbook required.
- **Unseal under power-cut (ADR 0005 risk #5):** a runtime broker needs an unseal step after restart;
  foreign auto-unseal is forbidden, so plan **manual/in-country unseal**. SOPS-at-boot avoids the
  unseal problem but needs the age key present at deploy time — captured as a trade-off.
- **TLS/CA:** ACME needs internet; an in-country CA or longer-lived certs may be needed. Flagged for #8.
- SOPS-encrypted files commit recipients in the open (public age keys) — acceptable; only the private
  keys are sensitive and they never enter the repo.

## Alternatives considered

- **HashiCorp Vault** as the runtime broker — rejected as the *default* over OpenBao given the BUSL
  relicensing vs. the AGPL posture of this repo; OpenBao is the drop-in, Apache-2.0 equivalent.
- **Foreign managed KMS / Secrets Manager** (AWS/GCP/Azure) — rejected outright: violates data
  residency (ARTCI / loi n°2013-450, ADR 0005).
- **`ansible-vault` only** — weaker than SOPS (single shared password, whole-file opacity, no
  granular diffs); kept as a fallback for the Ansible layer only.
- **Terraform workspaces** instead of per-env var-files — rejected for reviewability; per-env tfvars
  make the diff between environments explicit.
- **Plaintext `.env` committed / env vars in CI only** — rejected: fails acceptance criterion (1).
