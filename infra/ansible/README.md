# infra/ansible — host configuration (placeholder)

**Purpose.** Configure the in-country hosts that Terraform provisions: install and wire up
the Axum backend (×2), MinIO, PostgreSQL primary + replica, the Caddy/TLS reverse proxy,
and the WAF. Hosts are physically in Côte d'Ivoire — **no foreign managed cloud**.

**Implements:** [ADR 0005 — Storage & sovereign hosting](../../docs/adr/0005-storage-and-sovereign-hosting.md)
and [ADR 0007 — Secrets management & environments](../../docs/adr/0007-secrets-and-environments.md) (#4).

## Status

`playbook.yml` is a **placeholder** with no real service tasks, hosts, or secrets. It carries the
structure, per-role TODO markers, and **env + residency guardrails** (asserts that `env ∈
{dev,staging,prod}` and `country == CI`).

## Environments & secrets (ADR 0007)

Select an environment by pointing `-i` at its inventory; the group name (`dev`/`staging`/`prod`)
auto-loads the matching `group_vars/<env>.yml` (env-scoped, **secret-free**):

```sh
ansible-playbook --syntax-check -i inventories/staging playbook.yml
ansible-playbook -i inventories/staging playbook.yml          # real run (in-country, #8)
```

Secrets are **never** stored here. At run time they are decrypted from the SOPS/age vault
(`secrets/<env>/services.sops.yaml`) and written to a **0600** systemd `EnvironmentFile` — never a
world-readable file or process argv (`no_log: true`). The injection task is sketched (commented) in
`playbook.yml`; #8 fleshes it out. `ansible-vault` remains an acceptable fallback for the Ansible
layer (ADR 0007).

> **TODO(#8):** flesh out roles for Axum, MinIO, Postgres HA (streaming replication +
> warm standby), Caddy/TLS, WAF, and in-country encrypted backups. Inventory must point
> only at in-country hosts.

## Build + test command

```sh
# from infra/ansible/
ansible-playbook --syntax-check playbook.yml
```

No live run (`ansible-playbook -i <inventory> playbook.yml`) is wired in this scaffold —
there is no inventory and no vault.
