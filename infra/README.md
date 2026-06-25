# infra — Sovereign in-country hosting (IaC)

**Purpose.** Infrastructure-as-Code for the HealthTech platform's **sovereign, in-country
hosting** in Côte d'Ivoire. This package provisions the full data-path footprint
(Rust/Axum backend ×2, MinIO, PostgreSQL primary + replica, Caddy/TLS reverse proxy, WAF)
on rented bare-metal / VMs **physically located in Côte d'Ivoire**.

**Implements:** [ADR 0005 — Storage & sovereign hosting](../docs/adr/0005-storage-and-sovereign-hosting.md)
and [ADR 0007 — Secrets management & environments](../docs/adr/0007-secrets-and-environments.md) (#4).

## Environments & secrets (ADR 0007, issue #4)

### Environment matrix

| Env | Where | Data | Secrets | Residency |
| --- | --- | --- | --- | --- |
| `dev` | contributor laptop (`infra/dev/compose.yaml`: Postgres + MinIO) | synthetic only | generated **throwaway** (`.env` from `.env.example`) | N/A |
| `staging` | in-country (#8) | synthetic / test | SOPS bundle `secrets/staging/` | **CI** (ARTCI) |
| `prod` | in-country (#8) | real (encrypted blobs) | SOPS bundle `secrets/prod/` | **CI** (ARTCI) |

One selector drives everything: Terraform `-var-file=environments/<env>.tfvars`, Ansible
`-i inventories/<env>`, backend `APP_ENV`. Each environment has a **distinct** age recipient
(`/.sops.yaml`) so a dev key can never decrypt staging/prod (least privilege).

### Secret injection flow

```
secrets/<env>/services.sops.yaml   (encrypted at rest, committed)
        │  sops -d   (needs the env's age PRIVATE key — in-country for staging/prod)
        ▼
  decrypted values  ──► Terraform: TF_VAR_*  (e.g. `sops exec-env … 'terraform apply …'`)
                    └─► Ansible:   0600 systemd EnvironmentFile  ──► backend env (APP_ENV, DATABASE_URL, MINIO_*, …)
```

- **No plaintext secret is ever committed** — only encrypted `*.sops.yaml`, public recipients in
  `/.sops.yaml`, and `*.example` placeholder templates. `just secrets-lint` (gitleaks + the
  `scripts/check-secrets.sh` tripwire) fails closed on any leak, and runs in CI
  (`.github/workflows/secrets.yml`).
- **tfstate** can embed secret values; the state backend must be **encrypted and in-country**
  (TODO(#8)); local `*.tfstate` is gitignored but that alone is not enough.
- The backend redacts every secret field in `Debug`/`Display` (`backend/src/config.rs`), so a
  secret never reaches `tracing`.

### Bootstrap, unseal & rotation runbooks

- **Bootstrap (per env, on an in-country host).** Generate the env's age key
  (`age-keygen -o …`), paste its **public** recipient into `/.sops.yaml`, fill the bundle from
  `secrets/<env>/services.sops.yaml.example`, `sops -e -i` it, and commit **only** the encrypted
  file. The age **private** key never leaves the in-country host. See
  [`secrets/README.md`](../secrets/README.md). *Chicken-and-egg:* the first operator distributes
  the initial age key out-of-band via an in-country channel — never a foreign secret-distribution
  service.
- **Unseal after a power cut (ADR 0005 risk #5).** SOPS-at-boot needs the env's age private key
  present on the in-country host; there is **no** foreign auto-unseal KMS. If OpenBao is later
  adopted for prod (ADR 0007), its unseal is **manual / in-country** (HSM or transit). A staging/
  prod node must recover after a power cut without re-entering secrets beyond the documented unseal.
- **Rotation.** Rotate a DB password / MinIO key / presigned-URL key / TLS cert by editing the
  bundle (`just secrets-edit <env>`), re-running the IaC, and restarting the consumer. The
  presigned-URL signing key gates media access (#23) — rotate it deliberately. TLS/CA strategy
  (ACME vs in-country CA, cert lifetime) is flagged for #8.

### Reproducible staging (acceptance criterion)

```sh
# 1. inject secrets (decrypt the staging bundle to an in-country 0600 env file — no manual edits)
sops -d secrets/staging/services.sops.yaml > /run/healthtech/staging.env   # mode 0600
# 2. provision (env-scoped, residency-guarded)
terraform -chdir=infra/terraform apply -var-file=environments/staging.tfvars
# 3. configure
ansible-playbook -i infra/ansible/inventories/staging infra/ansible/playbook.yml -e env=staging
```

**Full live bring-up depends on #8** (sovereign hosting provisioning). The **credential-free
subset ships now** and is reproducible today:

```sh
just infra-residency    # data-residency tripwire (no foreign cloud in infra/, country pinned CI)
just infra-validate     # residency tripwire + terraform fmt/validate + ansible --syntax-check, per env
just dev-up             # local Postgres + MinIO (staging-shaped), throwaway secrets
just secrets-lint       # gitleaks + secret-hygiene tripwire
```

> This repo does **not** stand up live infrastructure; do not read the runbook above as implying a
> running staging cluster. It is the documented, idempotent path that #8 completes.

## Compliance — data residency (non-negotiable)

- All encrypted blobs and metadata are hosted on **Ivorian soil** to satisfy
  **ARTCI** and **loi n°2013-450** relative à la protection des données à caractère personnel.
- **NO foreign managed cloud anywhere in the data path** (no AWS / GCS / Azure for blobs,
  DB, compute, or backups). Target: ARTCI-eligible national datacenter (e.g.
  VITIB-Grand-Bassam / licensed local operator).
- In-country encrypted backups only. A data-localization attestation is produced for the
  homologation dossier (#30).
- **Availability SPOF accepted:** a single in-country datacenter has no foreign failover.
  Mitigated by in-country HA (Postgres primary + replica, warm standby) and offline-first
  clients so consultations survive outages.

### Residency guardrails (enforced)

Residency is defended at three layers, so a foreign-cloud regression is caught no matter where
it is introduced:

1. **Plan/run time — Terraform.** `country` is pinned to `CI` in `main.tf` (never exposed in any
   tfvars) and a `validation` rejects any other value.
2. **Run time — Ansible.** `playbook.yml` `assert`s `country == 'CI'` before configuring a host.
3. **Commit time — CI tripwire (#8).** [`scripts/check-residency.sh`](../scripts/check-residency.sh)
   fails closed if a foreign IaC provider (`aws`/`google`/`azurerm`/…), a foreign managed state
   backend (`gcs`/`azurerm`/…) or `s3` pointed at real AWS, a known foreign cloud endpoint
   (`amazonaws.com`, `googleapis.com`, `*.blob.core.windows.net`, …), or a non-CI `country`
   override ever enters `infra/`. It is credential-free and network-free, runs in CI alongside the
   secret-hygiene tripwire (`.github/workflows/secrets.yml`), and is the first step of
   `just infra-validate`. An in-country MinIO S3-compatible state backend (a `.ci`/private
   endpoint, no `amazonaws.com`) passes, so the gate does not block the real provisioning path
   once the operator (#8 / P0) is chosen. Run it directly with `just infra-residency`.

## Layout

```
infra/
├── README.md            # this file
├── dev/
│   └── compose.yaml     # local dev stack: Postgres + MinIO (throwaway creds)
├── terraform/           # provisioning of in-country VMs / bare-metal + networking
│   ├── README.md
│   ├── main.tf          # placeholder — NO real provider creds; env-parameterized
│   └── environments/    # per-env var-files: dev.tfvars / staging.tfvars / prod.tfvars
└── ansible/             # configuration of the provisioned hosts (services, TLS, WAF)
    ├── README.md
    ├── playbook.yml     # placeholder; env + residency guardrails
    ├── inventories/     # per-env inventories: dev / staging / prod
    └── group_vars/      # per-env vars (secret-free): dev.yml / staging.yml / prod.yml
```

The encrypted secret bundles live at the repo root in [`secrets/`](../secrets/README.md), with
SOPS rules in [`/.sops.yaml`](../.sops.yaml).

## Status

This is a **structure-only scaffold**. The files are non-functional placeholders with no
real provider credentials and no live resources.

> **TODO(#8):** real sovereign-hosting provisioning (long-lead procurement on the launch
> critical path). Wire Terraform to the chosen ARTCI-licensed local operator, define the
> network/security groups + WAF, and complete the Ansible roles for Axum / MinIO / Postgres
> HA / Caddy. Start early.

## Build + test command

These are config/IaC placeholders; the canonical "build" is a syntax/format check that
runs without any cloud credentials or network access. From the repo root:

```sh
just infra-validate
```

which runs, per environment:

```sh
terraform -chdir=infra/terraform fmt -check
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform validate
ansible-playbook --syntax-check -i infra/ansible/inventories/<env> infra/ansible/playbook.yml
```

(`terraform validate` needs **Terraform ≥ 1.9** — see the `required_version` in
`infra/terraform/main.tf`. `terraform plan -var-file=environments/<env>.tfvars` also runs
credential-free since no real resources are declared yet.)
