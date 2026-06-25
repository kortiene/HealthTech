# ADR 0009 — Sovereign operator / national datacenter selection

**Status:** Proposed (2026-06-24) · Issue [#8](https://github.com/kortiene/HealthTech/issues/8) · Refines [ADR 0005](./0005-storage-and-sovereign-hosting.md) (Epic E7)

> ⚠️ **The final operator pick is a human procurement decision and is NOT yet made.** This ADR records
> the **selection criteria** and the **shortlist** so the choice is defensible and reproducible; the
> chosen operator (and the contract/DPA that proves in-country implantation) is filled in at sign-off.
> Until then, `infra/terraform/` keeps no real provider and the live in-country bring-up (#8.1) does
> not run. This is deliberate: ADR 0005 flags sovereign hosting as a **long-lead procurement** item.

## Context

[ADR 0005](./0005-storage-and-sovereign-hosting.md) fixed the **footprint** (Axum ×2 + MinIO + Postgres
primary/replica + TLS reverse proxy + WAF + in-country encrypted backups) and the non-negotiable rule:
the whole data path — compute, the Postgres metadata DB, the MinIO blob/media store, backups, **and the
Terraform state backend** (state can embed secrets) — must reside **physically in Côte d'Ivoire** to
satisfy ARTCI / loi n°2013-450. ADR 0005 did **not** pick the operator/datacenter. That choice is the
critical path for #8 because it determines:

- the **Terraform provider** to declare in `infra/terraform/main.tf` (`required_providers`), or whether
  there is no native provider and provisioning falls back to bare-metal driven over SSH by Ansible
  (`null_resource`/`remote-exec` / manual inventory);
- the **encrypted, in-country state backend** (e.g. an in-country MinIO S3-compatible bucket with a
  `.ci`/private endpoint — never a foreign managed backend);
- the real **inventory hosts** (`infra/ansible/inventories/{staging,prod}`) and network topology.

This ADR captures the decision **framework** so the eventual pick is auditable and so the ARTCI
homologation dossier (#30) carries the rationale, not just the result.

## Decision

**Select the national hosting operator against the weighted criteria grid below; record the chosen
operator, datacenter, and proof of in-country implantation at procurement sign-off.** No operator that
fails a *non-negotiable* criterion (ARTCI eligibility, verifiable physical implantation in CI,
in-country backups, no foreign cloud in the data path) is admissible regardless of score.

### Selection criteria grid

| # | Criterion | Type | Why it matters |
| --- | --- | --- | --- |
| C1 | **ARTCI eligibility / licence** (authorised national hosting) | **Non-negotiable** | Legal basis for data residency (loi 2013-450, ARTCI); feeds the attestation (#8.2). |
| C2 | **Verifiable physical implantation in Côte d'Ivoire** (datacenter address, audit/visit) | **Non-negotiable** | Residency is about physical location, not billing entity. Proof goes in the attestation. |
| C3 | **In-country backups** (no foreign replication/failover) | **Non-negotiable** | Backups are part of the data path (ADR 0005); a foreign backup target breaks residency. |
| C4 | **No foreign managed cloud in the data path** (compute, storage, state, KMS) | **Non-negotiable** | Core zero-knowledge/residency invariant; enforced by `scripts/check-residency.sh`. |
| C5 | **Bare-metal / VM capacity** sized for the ADR 0005 footprint | Weighted | Must host 2× Axum + MinIO + Postgres ×2 + proxy + WAF with headroom. |
| C6 | **Private networking + security groups** (least-privilege; expose only the proxy) | Weighted | Required to keep Postgres/MinIO/backends off the public internet. |
| C7 | **Terraform provider availability** (native provider vs SSH/bare-metal via Ansible) | Weighted | Decides P1 shape: native IaC vs `null_resource`/`remote-exec`. Risk #2. |
| C8 | **Encrypted in-country state-backend option** (e.g. in-country S3-compatible bucket) | Weighted | State can embed secrets; must be encrypted + in-country (ADR 0005/0007). Risk #3. |
| C9 | **SLA / availability** (single-DC SPOF is accepted; no foreign failover) | Weighted | ADR 0005 accepts the SPOF; mitigated by in-country HA + offline-first clients. |
| C10 | **Provisioning lead time / contractual terms (DPA)** | Weighted | #8 is long-lead; the DPA (CTRL-26 / PREUVE-07) carries the residency/sub-processing clauses. |
| C11 | **Power/network resilience + unseal story** (boot after outage) | Weighted | Degraded-network context (PRD); informs the unseal runbook (ADR 0007, Risk #4). |

### Shortlist (candidates — to confirm at procurement)

- **VITIB — Grand-Bassam** (technology park / national datacenter) — named in ADR 0005 as the reference
  candidate; pending confirmation of ARTCI eligibility, capacity, and Terraform-provider availability.
- **Other ARTCI-licensed national operators** — to be enumerated and scored against the grid during P0.

> The shortlist is **not** a decision. Scoring and the final pick are recorded here at sign-off,
> together with the implantation proof (operator licence / attestation) and the DPA reference.

## Consequences

**Positive**
- The operator choice is criteria-driven and auditable; the ARTCI dossier (#30) gets the rationale.
- The non-negotiable criteria mechanically exclude any foreign-cloud path, reinforcing the residency
  guardrails already in code (Terraform `country == "CI"`, Ansible `assert`, `scripts/check-residency.sh`).

**Negative / risks**
- The pick is **long-lead** and blocks the live bring-up (P1–P3, P5.2) and the *signed* attestation
  (#8.2). Until sign-off, `infra/` stays at validated scaffolding + the residency gate (no live cluster).
- If the chosen operator has **no Terraform provider** (C7), P1 shifts to Ansible/SSH bare-metal —
  decided after this ADR is accepted with a concrete operator.

## Alternatives considered

- **Foreign managed cloud (AWS/GCP/Azure) region in West Africa** — rejected outright: not in Côte
  d'Ivoire, foreign managed control plane; violates C1–C4 and ADR 0005.
- **Self-owned hardware in a generic colocation** — only admissible if the colocation itself is
  ARTCI-eligible and physically in CI (then it is just one candidate under the grid above).

## References

- [ADR 0005 — Storage & sovereign hosting](./0005-storage-and-sovereign-hosting.md)
- [ADR 0007 — Secrets & environments](./0007-secrets-and-environments.md)
- Data-localization attestation: [`docs/compliance/attestation-localisation-donnees.md`](../compliance/attestation-localisation-donnees.md) (PREUVE-05, #8.2)
- Legal-basis gap: [`docs/compliance/ecarts.md`](../compliance/ecarts.md) ECART-07
