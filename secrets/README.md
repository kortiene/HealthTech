# secrets/ — encrypted operational-secret bundles (SOPS + age)

**ADR:** [0007 — Secrets management & environments](../docs/adr/0007-secrets-and-environments.md) ·
**Issue:** #4

This directory holds the **operational** secret bundles for each environment, encrypted at rest
with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age). The
encryption rules live in [`/.sops.yaml`](../.sops.yaml).

> **Operational secrets only.** Patient master keys, per-record data keys, and QR session keys are
> generated and held **client-side only** (Android Keystore / WASM-JS RAM, ADR 0006). They **must
> never** appear in this directory, in the IaC, in env files, or in CI. See the zero-knowledge
> boundary in ADR 0007 §3.

## What is committed vs. what is not

| Committed | Never committed |
| --- | --- |
| `*.sops.yaml` — SOPS-**encrypted** bundles (values are ciphertext) | any **decrypted** `*.yaml` / `*.env` |
| `*.example` — plaintext **placeholder** templates (no real values) | age **private** keys |
| `/.sops.yaml` — public age **recipients** + rules | real secret values in clear |

`scripts/check-secrets.sh` (run by `just secrets-lint` and CI) fails closed if a decrypted bundle,
a private key, or a `*.tfstate` / non-example `.env` is ever staged.

## Layout

```
secrets/
├── README.md
├── dev/services.sops.yaml.example        # template; dev uses throwaway values
├── staging/services.sops.yaml.example
└── prod/services.sops.yaml.example
```

The real encrypted bundles (`services.sops.yaml`, **no** `.example` suffix) are produced by an
in-country operator at bootstrap — see below. They are committed **only** in encrypted form.

## Bootstrap (one-time, per environment, on an in-country host)

```sh
# 1. Generate the environment's age key IN-COUNTRY (never leaves the operator host).
age-keygen -o ~/.config/sops/age/healthtech-staging.txt

# 2. Print its public recipient and paste it into /.sops.yaml for this environment.
age-keygen -y ~/.config/sops/age/healthtech-staging.txt

# 3. Fill the bundle from the template and encrypt it in place.
cp secrets/staging/services.sops.yaml.example secrets/staging/services.sops.yaml
$EDITOR secrets/staging/services.sops.yaml        # replace placeholders with real values
sops --encrypt --in-place secrets/staging/services.sops.yaml

# 4. Commit ONLY the encrypted file. The age private key stays in-country, never in git.
```

## Day-to-day

```sh
just secrets-decrypt staging     # sops -d secrets/staging/services.sops.yaml  (to stdout)
just secrets-edit staging        # sops secrets/staging/services.sops.yaml      (edit in place)
just secrets-lint                # fail-closed leak tripwire
```

Decryption requires the environment's age private key to be present
(`SOPS_AGE_KEY_FILE=~/.config/sops/age/healthtech-<env>.txt`). A **dev** key may live on a
contributor laptop; **staging/prod** keys live only in-country.
