# infra/terraform — provisioning (placeholder)

**Purpose.** Provision the in-country compute, storage volumes, and networking for the
HealthTech sovereign footprint. Targets an **ARTCI-eligible national datacenter / licensed
local operator** in Côte d'Ivoire — **no foreign managed cloud**.

**Implements:** [ADR 0005 — Storage & sovereign hosting](../../docs/adr/0005-storage-and-sovereign-hosting.md).

## Status

`main.tf` is a **placeholder**: it declares no real resources and carries **no provider
credentials**. The in-country resource inventory is documented as a comment block at the top
of `main.tf`.

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
