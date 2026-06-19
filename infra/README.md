# infra — Sovereign in-country hosting (IaC)

**Purpose.** Infrastructure-as-Code for the HealthTech platform's **sovereign, in-country
hosting** in Côte d'Ivoire. This package provisions the full data-path footprint
(Rust/Axum backend ×2, MinIO, PostgreSQL primary + replica, Caddy/TLS reverse proxy, WAF)
on rented bare-metal / VMs **physically located in Côte d'Ivoire**.

**Implements:** [ADR 0005 — Storage & sovereign hosting](../docs/adr/0005-storage-and-sovereign-hosting.md).

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

## Layout

```
infra/
├── README.md            # this file
├── terraform/           # provisioning of in-country VMs / bare-metal + networking
│   ├── README.md
│   └── main.tf          # placeholder — NO real provider creds
└── ansible/             # configuration of the provisioned hosts (services, TLS, WAF)
    ├── README.md
    └── playbook.yml     # placeholder
```

## Status

This is a **structure-only scaffold**. The files are non-functional placeholders with no
real provider credentials and no live resources.

> **TODO(#8):** real sovereign-hosting provisioning (long-lead procurement on the launch
> critical path). Wire Terraform to the chosen ARTCI-licensed local operator, define the
> network/security groups + WAF, and complete the Ansible roles for Axum / MinIO / Postgres
> HA / Caddy. Start early.

## Build + test command

These are config/IaC placeholders; the canonical "build" is a syntax/format check that
runs without any cloud credentials or network access:

```sh
# from infra/
terraform -chdir=terraform fmt -check && terraform -chdir=terraform validate
ansible-playbook --syntax-check ansible/playbook.yml
```

(`terraform validate` may require `terraform -chdir=terraform init -backend=false` first.)
