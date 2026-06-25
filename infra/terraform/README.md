# infra/terraform — provisioning (placeholder)

**Purpose.** Provision the in-country compute, storage volumes, and networking for the
HealthTech sovereign footprint. Targets an **ARTCI-eligible national datacenter / licensed
local operator** in Côte d'Ivoire — **no foreign managed cloud**.

**Implements:** [ADR 0005 — Storage & sovereign hosting](../../docs/adr/0005-storage-and-sovereign-hosting.md)
and [ADR 0007 — Secrets management & environments](../../docs/adr/0007-secrets-and-environments.md) (#4).

## Status

`main.tf` is a **placeholder**: it declares no real resources and carries **no provider
credentials**. The in-country resource inventory is documented as a comment block at the top
of `main.tf`. It **is** parameterized per environment (ADR 0007).

## Environments & secrets (ADR 0007)

Select an environment with its var-file (carries **non-secret** sizing only):

```sh
terraform -chdir=. plan  -var-file=environments/staging.tfvars
terraform -chdir=. apply -var-file=environments/staging.tfvars
```

Secret **values** are injected at apply time from the SOPS/age vault as `TF_VAR_*` — never from a
committed plaintext:

```sh
sops exec-env ../../secrets/staging/services.sops.yaml \
  'terraform apply -var-file=environments/staging.tfvars'
```

- `country` is **pinned to CI** in `main.tf` (not exposed in any tfvars) and cannot be overridden
  per environment — the validation rejects any non-CI value (residency, ADR 0005/0007). A
  **commit-time** gate ([`scripts/check-residency.sh`](../../scripts/check-residency.sh), `just
  infra-residency`) additionally fails closed if a foreign provider / state backend / cloud
  endpoint, or a non-CI `country`, is ever added here — before any `plan`/`apply` runs.
- The state backend must be **encrypted and in-country** (TODO(#8)); state can embed secrets. When
  configured, an in-country MinIO S3-compatible backend (a `.ci`/private endpoint, no
  `amazonaws.com`) satisfies the residency gate; a foreign managed backend (`gcs`/`azurerm`/`s3`
  on real AWS) is rejected.

> **TODO(#8):** select the ARTCI-licensed local operator's Terraform provider, define VMs /
> bare-metal, private networking, security groups, and encrypted backup volumes. Keep all
> resources physically in Côte d'Ivoire.

## Build + test command

```sh
# from infra/terraform/
terraform fmt -check
terraform init -backend=false
terraform validate
```

No `apply` is wired in this scaffold (no credentials, no remote state).
