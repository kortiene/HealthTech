#!/usr/bin/env bash
# Fail-closed secret/leak tripwire (issue #4, ADR 0007).
#
# Mirrors scripts/check-adw-sdlc-env.sh: a small, house-style guardrail that any
# later coding agent can extend. It complements gitleaks (.gitleaks.toml) by
# asserting the repo's secret HYGIENE on TRACKED files:
#
#   1. no committed Terraform state (*.tfstate*) — it can embed secret values;
#   2. no committed real .env (only *.env.example placeholders);
#   3. under secrets/**, only encrypted bundles (*.sops.yaml), *.example
#      placeholders, READMEs and .sops.yaml — never a decrypted bundle;
#   4. no committed private key material (PEM private keys, age secret keys);
#   5. .sops.yaml has a creation rule covering every secrets/<env>/ namespace.
#
# It FAILS CLOSED: any hit exits non-zero. Scaffold-tolerant: passes quietly
# before secrets/ or a git tree exist.
set -euo pipefail

cd "$(dirname "$0")/.."

# Enumerate tracked files (the only thing a leak gate cares about). Outside a
# git work tree (e.g. a tarball), fall back to a filesystem walk.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked() { git ls-files -z; }
else
  echo "warn: not a git work tree; scanning the filesystem instead" >&2
  tracked() { find . -type f -not -path './.git/*' -print0; }
fi

fail=0
note() {
  echo "error: $1" >&2
  fail=1
}

# --- 1. Terraform state -----------------------------------------------------
while IFS= read -r -d '' f; do
  f=${f#./} # normalise the find-fallback's leading ./ so patterns match either source
  case "$f" in
    *.tfstate | *.tfstate.* | *.tfstate.backup)
      note "Terraform state is committed (may embed secrets): $f" ;;
  esac
done < <(tracked)

# --- 2. Real .env files (only *.env.example allowed) ------------------------
while IFS= read -r -d '' f; do
  f=${f#./}
  base=${f##*/}
  case "$base" in
    .env.example | *.env.example) : ;;                 # placeholder template: OK
    .env | .env.* | *.env)        note "real env file is committed: $f" ;;
  esac
done < <(tracked)

# --- 3. secrets/** — only encrypted bundles / placeholders ------------------
if [ -d secrets ]; then
  while IFS= read -r -d '' f; do
    f=${f#./}
    case "$f" in
      secrets/*) : ;;
      *) continue ;;
    esac
    case "$f" in
      secrets/README.md | secrets/*/README.md) : ;;    # docs: OK
      *.sops.yaml.example | *.sops.yml.example) : ;;   # placeholder template: OK
      *.example) : ;;                                  # any other placeholder: OK
      *.sops.yaml | *.sops.yml) : ;;                   # SOPS-encrypted bundle: OK
      *)
        note "unexpected file under secrets/ (decrypted secret?): $f — only *.sops.yaml and *.example are allowed" ;;
    esac
  done < <(tracked)
fi

# --- 4. Private key material anywhere in tracked text -----------------------
# age secret keys and PEM private-key blocks must never be committed.
key_hits=$(
  while IFS= read -r -d '' f; do
    f=${f#./}
    # skip this script itself (it names the key patterns in prose)
    case "$f" in
      scripts/check-secrets.sh) continue ;;
    esac
    if LC_ALL=C grep -lE 'AGE-SECRET-KEY-1|-----BEGIN [A-Z ]*PRIVATE KEY-----' "$f" 2>/dev/null; then :; fi
  done < <(tracked)
)
if [ -n "$key_hits" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && note "private key material committed: $f"
  done <<< "$key_hits"
fi

# --- 5. .sops.yaml covers every secrets/<env>/ namespace --------------------
if [ -d secrets ]; then
  if [ ! -f .sops.yaml ]; then
    note ".sops.yaml is missing but secrets/ exists — SOPS rules are required"
  else
    for d in secrets/*/; do
      env=$(basename "$d")
      if ! grep -qE "secrets/${env}/" .sops.yaml; then
        note ".sops.yaml has no creation rule for secrets/${env}/"
      fi
    done
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "FAILED: secret hygiene violations found (see above)." >&2
  exit 1
fi

echo "ok: no committed tfstate/.env/decrypted-secret/private-key; .sops.yaml covers every secrets/<env>/."
