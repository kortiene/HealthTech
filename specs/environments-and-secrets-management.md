# Environments & Secrets Management (dev / staging / prod) + IaC

> Spec for **GitHub issue #4 — Environnements & gestion des secrets** (Epic E0 — Socle
> projet & DevOps · Effort M · Priorité *Should* · labels `security` `infra`).
> Acceptance criteria from the issue: **(1)** secrets injected via a vault (*coffre-fort*),
> never committed in clear; **(2)** `staging` is **reproducible from the IaC**.
>
> This is a **planning/spec document only — do not implement here.** A later coding agent
> executes the checklist.

## Problem Statement

The repository must run in distinct **dev / staging / prod** environments and must handle
**operational secrets** (database passwords, object-store keys, TLS private keys, the
presigned-URL signing key, backup-encryption keys, etc.) without ever committing a secret
in clear text. Today:

- The backend (`backend/src/main.rs`) is a placeholder that reads no configuration except
  the `tracing` env-filter and **hardcodes** its bind address `0.0.0.0:8080`. It has no
  notion of environment or injected secrets yet (TODO(#8)/TODO(#9) markers in place).
- `infra/terraform/main.tf` and `infra/ansible/playbook.yml` are **structure-only
  placeholders**. Terraform already exposes an `environment` variable (default `"staging"`)
  and a `country` residency guardrail (`== "CI"`), and the Ansible header *mentions*
  `ansible-vault`, but **no secret-injection mechanism, no per-environment topology, and no
  reproducible-staging path exist**.
- `.gitignore` already excludes `.env`, `.env.*`, `*.pem`, `*.key`, `infra/**/*.tfstate*`,
  and `infra/**/.terraform/` — a good baseline, but there is no positive workflow telling a
  contributor *how* to obtain/inject secrets, and no CI tripwire that fails when a secret
  leaks anyway.

The gap: there is no decided, documented, reproducible way to (a) store secrets encrypted,
(b) inject them into each environment's IaC and services, and (c) stand `staging` up from
code. This issue closes that gap **for server-side operational secrets only** — it must not
touch, and must not be able to touch, the patient's cryptographic keys (zero-knowledge).

## Goals

1. **A decided secrets-management approach**, captured in a new ADR (proposed `0007`),
   covering: the vault/tool, where the encryption root-of-trust lives (in-country), the
   at-rest format, and the at-deploy injection flow. The vault and its root key must be
   **self-hosted on Ivorian soil** — no foreign managed KMS/secret-store (AWS KMS/Secrets
   Manager, GCP Secret Manager, Azure Key Vault) anywhere in the path (ARTCI / loi
   n°2013-450, ADR 0005).
2. **No plaintext secret in the repo, ever** — secrets live encrypted (or in the vault), and
   a **CI secret-scan gate** fails the build if a plaintext secret is introduced.
3. **A clear `dev` / `staging` / `prod` topology**: how each environment is selected,
   parameterized, and isolated (separate secret namespaces; no prod secret reachable from
   dev/staging).
4. **`staging` reproducible from the IaC** (acceptance criterion): a documented, repeatable
   sequence (`terraform … && ansible-playbook …` + secret injection) brings up a staging
   instance with no manual secret editing. Where full live bring-up depends on real
   provisioning (#8), make that dependency explicit and deliver everything reproducible
   *without* live cloud credentials (validate/plan + a local dev bring-up).
5. **A local `dev` environment that runs with throwaway, generated secrets** (e.g.
   `docker-compose` for Postgres + MinIO) so contributors never need a real credential.
6. **Backend reads its operational config from injected environment/secret sources**, with
   a config module that fails fast on a missing required secret and **never logs secret
   values**.
7. **Documentation + contributor workflow**: how to get dev secrets, how injection works,
   bootstrap/unseal/rotation runbooks, and the explicit operational-secret-vs-patient-key
   boundary.

## Non-Goals

- **Patient/client key material.** Master keys, per-record data keys, and QR session keys
  are generated and held **only** client-side (Android Keystore / WASM-JS RAM, ADR 0006).
  They are *never* sent to the server and *must never* enter this vault. This issue manages
  **operational secrets only**; preserving that boundary is a goal, holding patient keys is
  an explicit non-goal.
- **Real sovereign-hosting provisioning** (live VMs, the ARTCI-licensed local operator's
  Terraform provider, networking, WAF) — that is **#8** (long-lead procurement). This issue
  may *parameterize* the IaC for environments and secret injection, but does not stand up
  real production infrastructure.
- **CI build/test pipeline for the apps/backend** — that is **#3**. This issue *provides the
  secret store and the secret-scan gate* that #3 consumes; it does not build the app/backend
  CI matrix.
- **The zero-knowledge blob service internals** (MinIO/Postgres wiring) — that is **#9**.
  This issue defines *where its credentials come from*, not the service logic.
- **Cryptographic design changes** of any kind. No new crypto, no KDF/AEAD changes.
- **TLS/CA strategy deep-dive** beyond noting where the private key/cert secret lives and how
  it is injected (full ACME-vs-in-country-CA design can be deferred to #8, but flag it).

## Relevant Repository Context

**Stack is already decided.** Unlike the original BACKLOG framing of #1 as "open", issue #1
has since been **resolved** by ADRs `0001`–`0006` (committed `2d90073`, "decide the technical
stack", closing #1). This spec therefore builds on the *decided* stack rather than treating
the language/framework as open. The only genuinely-open decisions for **this** issue are the
**secrets-vault tool** and the **environment topology details** — flagged in *Open Questions*
and to be settled in ADR `0007`.

Decided, secrets-relevant facts (from the ADRs and the scaffold):

- **Backend:** Rust + Axum, single cargo workspace with `crypto-core` (ADR 0004). One static
  (musl) binary; deliberately a *dumb zero-knowledge proxy* with **no key material and no
  decrypt path**. Currently `backend/src/main.rs` only configures `tracing` and hardcodes the
  bind address.
- **Storage & hosting:** self-hosted **MinIO** (S3-compatible blobs + media) + **PostgreSQL
  16** (non-identifying metadata only), provisioned via **Terraform + Ansible**, **in-country
  only**, no foreign cloud in the data path; backend issues **short-TTL presigned media URLs**
  (ADR 0005). → The presigned-URL **signing credential** (a MinIO access/secret key) is a
  first-class secret this issue must manage.
- **IaC scaffold:** `infra/terraform/main.tf` (placeholder; `environment` and residency-guarded
  `country` vars, no resources), `infra/ansible/playbook.yml` (placeholder; mentions
  `ansible-vault`, no tasks). `infra/README.md` documents the intended footprint (Axum ×2,
  MinIO, Postgres primary+replica, Caddy/TLS, WAF, in-country encrypted backups) and the
  canonical "build" = `terraform fmt -check && validate` + `ansible-playbook --syntax-check`.
- **Offline & keys:** SQLCipher (patient/Android), AES-GCM-ciphertext IndexedDB (doctor web),
  Android Keystore master key, PBKDF2 recovery (ADR 0006). **All client-side**; informs the
  non-goal boundary only.
- **Conventions:** ADRs/READMEs/code-comments are in **English**; PRD/BACKLOG are in French.
  Status/Context/Decision/Consequences/Alternatives ADR format. AGPL-3.0. `justfile` is the
  task runner; `just test` is the canonical gate (`test-rust`/`test-web`/`test-flutter`).
- **Existing secret-boundary precedent:** the ADW tooling already ships a *secret-withholding
  lint gate* — `scripts/check-adw-sdlc-env.sh`, wired into CI as `npm run lint:env` in
  `.github/workflows/adw-sdlc.yml`. It fails CI if a runner spreads `process.env`. **Reuse
  this pattern**: a small, fail-closed shell tripwire that any later coding agent can extend,
  is the established house style for secret guardrails here.
- **Greenfield for app/backend secret config:** no application-level config loader, no env
  matrix, no vault, and **no `specs/` directory** exist yet — this is the first spec file.

## Proposed Implementation

A **layered** approach: encrypted-at-rest secrets in the repo for IaC bootstrap, an
**in-country runtime vault** for live services, env-scoped IaC, and a CI tripwire. Recommend
settling the tool in **ADR 0007** before coding; below is the recommended shape with
alternatives flagged.

### 1. Decide the vault/tool (ADR 0007) — recommended default

Two complementary layers (most teams need both; a single tool can cover both at a stretch):

- **At-rest, git-stored secrets for IaC bootstrap → SOPS + age.**
  [SOPS](https://github.com/getsops/sops) encrypts values inside YAML/JSON/`.env` files with
  per-environment **age** keys; the *encrypted* files are safe to commit, the age **private
  keys live in-country** (on the operator host / an in-country HSM or operator laptop), never
  in the repo. A `.sops.yaml` `creation_rules` block maps `secrets/<env>/*.yaml` →
  the matching age recipient(s), giving per-environment isolation by construction. This is the
  lightest path to "secrets injected via a vault, none in clear, staging reproducible" without
  standing up a server, so it is the recommended **baseline**.
- **At-runtime secret broker for live services → self-hosted HashiCorp Vault *or* OpenBao**,
  in-country. Services fetch secrets at boot from the vault rather than from env files. This
  is the production-grade layer; for staging it can be optional if SOPS-injected env files are
  acceptable. **OpenBao** (the Apache-2.0 community fork of Vault) is worth preferring given
  HashiCorp's BUSL relicensing and the AGPL posture of this repo — **confirm in ADR 0007.**

Either way: **no foreign managed KMS** as the SOPS key backend or Vault auto-unseal — the
root of trust stays on Ivorian soil. `ansible-vault` (already name-dropped in the playbook) is
an acceptable *fallback* for the Ansible layer but is weaker (single shared password, whole-file
opacity); prefer SOPS for granular, reviewable diffs.

### 2. Environment topology

- **Selection:** drive everything off a single `environment ∈ {dev, staging, prod}` input —
  reuse the existing Terraform `environment` variable, mirror it in Ansible
  (`group_vars/<env>` or `-e env=<env>`), and in the backend via an `APP_ENV` env var. Either
  **Terraform workspaces** or **per-env var-files** (`infra/environments/<env>.tfvars`) —
  pick one in the ADR; per-env tfvars dirs are easier to review.
- **Secret namespaces:** `secrets/dev/`, `secrets/staging/`, `secrets/prod/` (SOPS), each
  encrypted to a *different* age recipient so a dev key can never decrypt prod. In a runtime
  vault, mirror with per-env mounts/policies.
- **Residency invariant holds for staging *and* prod:** both are in-country (the
  `country == "CI"` Terraform guard already enforces this; extend it so it cannot be
  overridden per-environment). `dev` is a developer's local machine with **synthetic data
  only** and generated throwaway secrets — never real patient data, so residency is N/A there.

### 3. Secret inventory (what the vault holds — operational only)

Define and document the canonical set (exact list confirmed in ADR 0007):

| Secret | Consumer | Notes |
| --- | --- | --- |
| PostgreSQL app/replication/admin passwords | backend, Ansible | per-env; metadata DB only (no PII) |
| MinIO root + service access/secret keys | backend, Ansible | one service key signs presigned media URLs (#23) |
| Presigned-URL signing key | backend | short-TTL media URLs (ADR 0005/#23) |
| TLS private key + cert | Caddy/reverse proxy | injection point; CA strategy deferred to #8 |
| Backup-encryption key | backups | in-country encrypted backups (ADR 0005) |
| WAF / proxy admin secrets (if any) | Ansible | |
| (Deploy/registry creds, SSH keys) | CI/CD (#3) | vault *provides*; #3 *consumes* |

**Explicitly excluded (must never be present):** patient master keys, per-record data keys,
QR session keys. **KDF params (salt + iteration count) are public-by-design** (ADR 0005) and
live in Postgres metadata — they are **not** secrets and must not be put in the vault.

### 4. Injection flow

- **IaC:** Terraform reads secrets via a SOPS data source (`carlpett/sops` provider) **or**
  from the runtime vault provider — never from committed plaintext; the **tfstate backend is
  encrypted and in-country** (default local plaintext `*.tfstate` is already gitignored but
  must additionally be encrypted at rest, since state can contain secret values). Ansible
  reads via a SOPS lookup / `ansible-vault`, and writes secrets into **non-world-readable**
  systemd unit `EnvironmentFile=` (mode `0600`) or container env — *never* into a
  world-readable file or the process argv.
- **Backend:** add a `config` module that loads `APP_ENV`, the DB DSN, MinIO endpoint+creds,
  presigned-URL key, and bind address **from the environment**, with: required-vs-optional
  validation, **fail-fast** on a missing required secret, and a `Debug`/`Display` impl that
  **redacts** secret fields (so a config dump or a `tracing` line can never print a password).
  Keep the hardcoded `0.0.0.0:8080` only as a dev default.
- **Local dev:** a `docker-compose.yml` (Postgres + MinIO) plus a `dev` SOPS bundle (or a
  committed `.env.example` template that contains **only placeholders**, decrypted/filled
  locally into a gitignored `.env`). `just dev-up` / `just secrets-decrypt dev` recipes.

### 5. CI secret-scan + leak tripwire (consumed by #3)

- Add a **secret-scanning** step (e.g. `gitleaks`) over the repo on every PR — fail closed.
- Add a small **house-style tripwire** mirroring `scripts/check-adw-sdlc-env.sh`, e.g.
  `scripts/check-secrets.sh`: assert no `*.tfstate`, no decrypted `secrets/**` (only
  `*.sops.yaml`/`*.enc.*` committed), no `.env` (non-example) tracked, and that the
  `.sops.yaml` rules cover every `secrets/<env>/` path. Wire it as a `just secrets-lint`
  recipe and a CI step (coordinate placement with #3).
- Add a **pre-commit** hook (optional, documented) running gitleaks + the tripwire locally.

### 6. Reproducible staging (acceptance criterion)

Deliver a documented, idempotent sequence:

```
# 1. inject secrets (decrypt the staging bundle to an in-country runtime/vault — no manual edits)
sops -d secrets/staging/services.sops.yaml > /run/healthtech/staging.env   # 0600
# 2. provision (env-scoped)
terraform -chdir=infra/terraform workspace select staging   # or -var-file=environments/staging.tfvars
terraform -chdir=infra/terraform apply
# 3. configure
ansible-playbook -i infra/ansible/inventories/staging infra/ansible/playbook.yml -e env=staging
```

Because real provisioning is **#8**, ship the **reproducible, credential-free** subset now:
`terraform … validate`/`plan` per environment, `ansible-playbook --syntax-check`, the local
`docker-compose` staging-shaped bring-up, and the full runbook in `infra/README.md`. Make the
"full live staging depends on #8" dependency explicit in the docs (do **not** imply live infra
exists).

## Affected Files / Packages / Modules

**Create**
- `docs/adr/0007-secrets-and-environments.md` — the decision (vault tool, topology, injection).
- `.sops.yaml` — per-environment `creation_rules` (if SOPS chosen).
- `secrets/{dev,staging,prod}/*.sops.yaml` (or `*.enc.yaml`) — **encrypted** secret bundles
  (commit only the encrypted form) + a plaintext `*.example` template with placeholders.
- `infra/environments/{dev,staging,prod}.tfvars` **or** Terraform workspace config.
- `infra/ansible/inventories/{dev,staging,prod}` + `group_vars/<env>` (env-scoped, secret-free
  except SOPS/vault references).
- `backend/src/config.rs` (or `config/mod.rs`) — env/secret loader with redaction + fail-fast.
- `scripts/check-secrets.sh` — fail-closed secret/leak tripwire (mirrors
  `scripts/check-adw-sdlc-env.sh`).
- `docker-compose.yml` (dev Postgres + MinIO) — or `infra/dev/compose.yaml`.

**Modify**
- `backend/src/main.rs` — call the new config module; replace hardcoded bind addr with config;
  ensure no secret is ever passed to `tracing`.
- `infra/terraform/main.tf` — wire the SOPS/vault data source, per-env parameterization, keep
  and tighten the `country == "CI"` residency guard so it can't be overridden per env.
- `infra/ansible/playbook.yml` — SOPS/`ansible-vault` secret loading into `EnvironmentFile`
  (mode 0600), env-scoped vars.
- `infra/README.md` — env matrix, injection flow, bootstrap/unseal/rotation runbook,
  reproducible-staging steps, explicit #8 dependency.
- `.gitignore` — confirm/extend (decrypted `secrets/**` plaintext, `/run/**` env dumps, any
  SOPS-decrypted output paths).
- `justfile` — add `secrets-lint`, `secrets-decrypt <env>`, `infra-validate`, `dev-up` recipes.
- `.github/workflows/` — add the secret-scan + `secrets-lint` steps (coordinate with #3).
- `docs/adr/0000-index.md` — add the `0007` row.
- `CONTRIBUTING.md` — "never commit secrets; how to obtain/inject dev secrets; pre-commit hook".
- `BACKLOG.md` — mark #4 status / cross-link the ADR (optional).
- `PRD_HealthTech.md` — no change expected (operational concern, not product behavior).

## API / Interface Changes

- **Network/public API:** **none.** No new HTTP endpoints; the `/health` and `/blob/{uuid}`
  surface is unchanged. No QR / access-token surface changes.
- **Backend runtime/config interface:** the backend gains **environment-variable inputs**
  (`APP_ENV`, DB DSN, MinIO endpoint+keys, presigned-URL key, bind address). This is an
  internal operational contract — **document it** in `backend/README.md` and the ADR
  (variable names, required vs optional, redaction behaviour).
- **CLI / task runner:** new `just` recipes (`secrets-lint`, `secrets-decrypt <env>`,
  `infra-validate`, `dev-up`) and the documented `sops`/`terraform`/`ansible` sequences.
- **IaC inputs:** new Terraform variables / var-files and Ansible env-scoped inventories.

## Data Model / Protocol Changes

**None.** No change to the encrypted-blob format, the `/blob/{uuid}` wire protocol, record
schema, or serialization. KDF params remain public-by-design metadata in Postgres (not
secrets). The only new persisted artifacts are **encrypted secret bundles** (SOPS files) and
operator-side env files — neither is part of the application data model or protocol.

## Security & Compliance Considerations

- **Zero-knowledge boundary is paramount.** The vault holds **operational secrets only**.
  Patient master keys, per-record data keys, and QR session keys are client-side (Keystore /
  WASM-JS RAM, ADR 0006) and **must never** enter the vault, the IaC, env files, or CI. The
  server's "no key material, no decrypt path" property (ADR 0004) must be preserved — adding
  operational secrets must not introduce any patient-key handling. Add an assertion/checklist
  item that the secret inventory contains no patient-key class secret.
- **Data residency (ARTCI / loi n°2013-450).** The vault **and its root of trust** (SOPS age
  keys / Vault unseal keys) must be **self-hosted on Ivorian soil**. **No foreign managed
  KMS/secret-store** anywhere in the path (rules out AWS KMS auto-unseal, GCP/Azure secret
  stores). Encrypted secrets at rest, encrypted tfstate at rest, in-country only.
- **Never log/persist secrets or PII.** The backend config type must redact secret fields in
  `Debug`/`Display`; `tracing` must never receive a DSN-with-password or key. No secret in
  process argv, in world-readable files, or in CI logs. Reuse the existing redaction discipline
  and the `lint:env` precedent.
- **Encryption at rest of cleartext-secret-bearing artifacts:** `*.tfstate` can embed secret
  values — encrypt the state backend (or SOPS-encrypt local state); it is already gitignored
  but gitignore alone is insufficient.
- **Least privilege & isolation:** per-environment age recipients / vault policies so a
  dev/staging key cannot decrypt prod. Short-lived runtime tokens where the vault supports it.
- **Sovereign-SPOF / power-cut interaction (ADR risk #5):** a runtime vault needs an **unseal**
  step after a restart; auto-unseal usually relies on a cloud KMS, which is **forbidden** here.
  Plan for **manual/in-country unseal** (or in-country HSM/transit) and document the runbook;
  ensure a power cut doesn't strand staging/prod. SOPS-at-boot avoids the unseal problem but
  needs the age key present at deploy time — capture the trade-off in the ADR.
- **Rotation:** document DB-password, MinIO-key, presigned-URL-key, and TLS-cert rotation
  (TLS renewal/ACME needs internet — in degraded/sovereign settings consider an in-country CA
  or longer-lived certs; flag for #8). Bootstrap (chicken-and-egg: who holds the first age
  key / vault root) must be documented.
- **Media/≤500 KB constraints:** unaffected — but the presigned-URL signing key being a managed
  secret is what *enables* the "heavy images off-device, ephemeral URL only" rule (#23); note
  the linkage so rotation doesn't silently break media access.

## Testing Plan

- **Backend config unit tests:** missing required secret → clear, non-secret-leaking error;
  optional secrets default correctly; `Debug`/`Display` of the config **redacts** every secret
  field (assert the literal value never appears in the formatted output).
- **Secret-scan CI gate:** add `gitleaks` (or equivalent) on PRs; include a deliberately-fake
  decrypted secret in a test fixture to prove the gate trips, then ensure the real tree passes.
- **Tripwire test for `scripts/check-secrets.sh`:** unit-style shell test asserting it fails on
  a tracked `*.tfstate` / `.env` / decrypted `secrets/**`, and passes on the clean tree (mirror
  the scaffold-tolerant style of `check-adw-sdlc-env.sh`).
- **IaC validation per environment:** `terraform fmt -check`, `terraform validate`, and
  `terraform plan` for each env var-file/workspace (no live creds); `ansible-playbook
  --syntax-check`; assert the `country == "CI"` residency guard rejects any non-CI value
  (negative test) and cannot be overridden per environment.
- **Reproducible-staging smoke (credential-free subset):** a scripted run of the documented
  sequence up to the point that requires real #8 infra (validate/plan + `docker-compose` dev
  bring-up + SOPS decrypt to a temp 0600 file), asserting it completes with no manual secret
  edit. Document that full live staging bring-up is gated on #8.
- **Zero-knowledge invariant test:** assert the secret inventory / vault schema contains **no**
  patient-key-class entry, and that the backend still exposes no decrypt path (guard against
  regression).
- **Resilience/degraded:** document (and, where cheap, test) the unseal-after-restart /
  power-cut runbook so a staging node recovers without a foreign KMS and without manual secret
  re-entry beyond the documented unseal.
- **Docs/lint:** markdown link-check for the new ADR/index; ensure no secret appears in any
  committed `*.example`.

## Documentation Updates

- **New ADR `docs/adr/0007-secrets-and-environments.md`** (Status/Context/Decision/
  Consequences/Alternatives): chosen vault (SOPS+age and/or self-hosted Vault/OpenBao),
  environment topology, secret inventory, injection flow, unseal/rotation strategy,
  residency rationale, and the operational-secret-vs-patient-key boundary.
- **`docs/adr/0000-index.md`** — add the `0007` summary row.
- **`infra/README.md`** — env matrix (dev/staging/prod), injection flow, reproducible-staging
  runbook, bootstrap/unseal/rotation runbooks, explicit dependency on #8 and link to #3 for CI.
- **`backend/README.md`** — document the new config env vars (names, required/optional,
  redaction, dev defaults).
- **`CONTRIBUTING.md`** — secret hygiene: never commit secrets, how to obtain/decrypt dev
  secrets, the pre-commit hook, what the CI gate enforces.
- **`BACKLOG.md`** — optional: cross-link #4 → ADR 0007; note relationship to #3/#8/#9.
- **`PRD_HealthTech.md`** — no change expected (no product-behaviour change).

## Risks and Open Questions

1. **Vault tool choice (ADR 0007 decision):** SOPS+age (lightest, git-native, satisfies the
   acceptance criteria without a server) vs. self-hosted **Vault/OpenBao** (runtime broker,
   heavier ops). Recommend SOPS+age baseline now, OpenBao for prod later. **Confirm.** Given
   HashiCorp BUSL + repo AGPL posture, prefer **OpenBao** over Vault if a runtime broker is
   adopted — confirm licensing fit.
2. **Workspaces vs. per-env tfvars** for environment selection — pick one (recommend per-env
   tfvars for reviewability).
3. **Runtime-vault unseal under sovereign/power-cut constraints** (no foreign auto-unseal KMS):
   manual unseal vs in-country HSM/transit. Operationally sensitive; needs a runbook and #8
   alignment.
4. **TLS/CA strategy** (ACME needs internet; in-country CA vs long-lived certs) — flagged here,
   likely resolved in #8. Where does the TLS private key secret originate and rotate?
5. **Boundaries with #3 (CI) and #8 (hosting):** this issue *provides* the vault + secret-scan
   gate but #3 *places* CI steps and #8 *provisions* live infra. Confirm who owns the CI
   workflow file edits to avoid collisions (the only current workflow is `adw-sdlc.yml`, scoped
   to the pipeline tooling — app/backend CI does not exist yet).
6. **Bootstrap chicken-and-egg:** who holds the first age key / vault root, and how is it
   distributed to in-country operators without a foreign secret-distribution channel?
7. **`staging` reproducibility depth:** how much can be proven *without* live #8 infra?
   Recommend: validate/plan + local compose + documented runbook now; full live bring-up after
   #8. Confirm this is acceptable for the acceptance criterion, or whether a minimal real
   staging node is in scope.
8. **Dev data policy:** confirm `dev` uses only synthetic data and generated throwaway secrets
   (so residency/PII rules don't apply to a developer laptop).

## Implementation Checklist

1. **Write ADR `0007`** deciding the vault tool (recommend SOPS+age baseline, OpenBao optional
   for prod), environment topology, secret inventory, injection flow, unseal/rotation, and the
   operational-secret-vs-patient-key boundary; add the row to `docs/adr/0000-index.md`.
2. **Define the secret inventory** (table in §3) and confirm it excludes all patient-key-class
   secrets and the public KDF params.
3. **Add `.sops.yaml`** with per-environment `creation_rules` and **encrypted** bundles under
   `secrets/{dev,staging,prod}/`; commit only encrypted files + plaintext `*.example`
   placeholders. Store age private keys **in-country**, never in the repo.
4. **Parameterize the IaC by environment:** per-env tfvars (or workspaces) for Terraform;
   env-scoped inventories/`group_vars` for Ansible; keep & tighten the `country == "CI"`
   residency guard so it cannot be overridden per environment.
5. **Wire secret injection:** Terraform SOPS/vault data source + **encrypted tfstate backend**;
   Ansible SOPS/`ansible-vault` → `EnvironmentFile` (mode 0600); no plaintext, no argv, no
   world-readable secret files.
6. **Add `backend/src/config.rs`:** load `APP_ENV` + DB/MinIO/presigned/bind config from env,
   fail-fast on missing required secret, **redact** secret fields in `Debug`/`Display`; update
   `backend/src/main.rs` to use it and drop the hardcoded bind address (dev default only).
   Ensure `tracing` never receives a secret.
7. **Add the local dev environment:** `docker-compose` (Postgres + MinIO) + `dev` SOPS bundle /
   `.env.example`; `just dev-up`, `just secrets-decrypt dev`.
8. **Add the secret-scan + tripwire gate:** `scripts/check-secrets.sh` (fail-closed, mirrors
   `check-adw-sdlc-env.sh`), `gitleaks` step, `just secrets-lint`; wire into CI (coordinate
   placement with #3) and an optional documented pre-commit hook.
9. **Document reproducible staging** in `infra/README.md` (the `sops -d … && terraform … &&
   ansible-playbook …` sequence), with the explicit "full live bring-up depends on #8" note;
   add `just infra-validate`.
10. **Write the tests** from the Testing Plan: backend config redaction/fail-fast units, the
    tripwire test, per-env `terraform validate`/`plan` + `ansible --syntax-check`, the residency
    negative test, the zero-knowledge no-patient-key-in-vault assertion, and the credential-free
    staging smoke.
11. **Update docs:** `infra/README.md`, `backend/README.md`, `CONTRIBUTING.md`, ADR index, and
    optionally `BACKLOG.md`. Confirm `.gitignore` covers all decrypted/derived secret paths.
12. **Verify acceptance criteria:** (a) secrets are injected from the vault and **none** is in
    clear in the repo (CI gate green, scanner finds nothing); (b) `staging` is reproducible from
    the IaC per the documented sequence (validate/plan + compose now; full live after #8).
13. **Final sweep:** confirm no patient key material anywhere in vault/IaC/CI, no secret in
    logs, residency guard intact, and the backend still has no decrypt path.
