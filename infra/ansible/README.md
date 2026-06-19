# infra/ansible — host configuration (placeholder)

**Purpose.** Configure the in-country hosts that Terraform provisions: install and wire up
the Axum backend (×2), MinIO, PostgreSQL primary + replica, the Caddy/TLS reverse proxy,
and the WAF. Hosts are physically in Côte d'Ivoire — **no foreign managed cloud**.

**Implements:** [ADR 0005 — Storage & sovereign hosting](../../docs/adr/0005-storage-and-sovereign-hosting.md).

## Status

`playbook.yml` is a **placeholder** with no real tasks, hosts, or secrets. It only carries
the structure and the per-role TODO markers.

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
