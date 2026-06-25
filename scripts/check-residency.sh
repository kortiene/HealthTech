#!/usr/bin/env bash
# Fail-closed DATA-RESIDENCY guardrail (issue #8, ADR 0005 / loi n°2013-450 / ARTCI).
#
# HealthTech is local-first / zero-knowledge, but even opaque encrypted blobs MUST
# reside physically in Côte d'Ivoire. The whole data path — compute, the Postgres
# metadata DB, the MinIO blob/media store, backups, AND the Terraform state backend
# (state can embed secret values) — stays in-country. NO foreign managed cloud is
# admitted anywhere in `infra/`.
#
# This is the anti-regression complement to the non-overridable `country == "CI"`
# guardrails already baked into Terraform (`main.tf`) and Ansible (`playbook.yml`):
# those reject a bad value at plan/run time; THIS script rejects a bad value at
# COMMIT time, before any plan/apply ever runs. It runs alongside `secrets-lint`
# and `infra-validate`, is credential-free, and touches no network.
#
# It scans TRACKED files under infra/ (plus the per-env tfvars / group_vars that
# carry the residency pin) and FAILS CLOSED on any of:
#
#   1. a foreign IaC provider in the data path (aws/google/azurerm/oci/… as a
#      `provider "<x>"` block or a `source = ".../<x>"` in required_providers);
#   2. a foreign managed state backend (`backend "gcs|azurerm|oss|cos"`), or an
#      `s3` backend pointing at real AWS (an amazonaws.com endpoint / no custom
#      endpoint) — an in-country MinIO S3-compatible backend is allowed because
#      it sets a `.ci`/private endpoint and never references amazonaws.com;
#   3. a known foreign cloud ENDPOINT/host anywhere under infra/ (amazonaws.com,
#      googleapis.com, *.blob.core.windows.net, digitaloceanspaces.com, …);
#   4. the residency pin `country` overridden to anything other than CI in any
#      tfvars or group_vars file.
#
# Scaffold-tolerant: passes quietly before infra/ or a git tree exist.
set -euo pipefail

cd "$(dirname "$0")/.."

# Enumerate tracked files (the only thing a residency gate cares about). Outside a
# git work tree (e.g. a tarball), fall back to a filesystem walk. Mirrors the
# house style of scripts/check-secrets.sh.
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

# Foreign managed-cloud IaC providers that must never appear in the data path.
# Matched only in their STRUCTURAL forms (`provider "<x>"`, `source = ".../<x>"`),
# so prose mentions in comments/READMEs (e.g. "no aws/google/azurerm") do not trip.
FOREIGN_PROVIDERS='aws|google|google-beta|azurerm|azuread|azapi|alicloud|tencentcloud|huaweicloud|oci|ibm|digitalocean|hcloud|linode|vultr|scaleway|ovh|exoscale|upcloud'

# Foreign managed state-backend TYPES (s3 is handled separately: it doubles as the
# in-country MinIO backend, so it is allowed unless it targets real AWS).
FOREIGN_BACKENDS='gcs|azurerm|oss|cos'

# Known foreign cloud endpoints/hosts. An in-country host uses a `.ci` domain or a
# private address and never matches these.
FOREIGN_ENDPOINTS='amazonaws\.com|\.aws\.amazon\.com|googleapis\.com|storage\.cloud\.google\.com|\.blob\.core\.windows\.net|\.azure\.com|\.azurewebsites\.net|digitaloceanspaces\.com|\.linodeobjects\.com|\.scw\.cloud|\.ovh\.(net|cloud)|backblazeb2\.com|\.wasabisys\.com'

is_self() {
  # Skip this script and (when added) its self-test fixture — both legitimately
  # contain the very patterns above. Keep in sync with the .gitleaks allowlist.
  case "$1" in
    scripts/check-residency.sh) return 0 ;;
    scripts/test-residency.sh) return 0 ;;
    backend/tests/check_residency_sh.rs) return 0 ;;
  esac
  return 1
}

while IFS= read -r -d '' f; do
  f=${f#./} # normalise the find-fallback's leading ./ so patterns match either source
  is_self "$f" && continue

  case "$f" in
    infra/*) ;;                         # the data-path IaC: full residency scan below
    *.tfvars | *.yml | *.yaml) ;;       # may carry the `country` residency pin
    *) continue ;;
  esac

  # --- 1. Foreign provider in the data path (Terraform only) ----------------
  case "$f" in
    *.tf | *.tf.json)
      if LC_ALL=C grep -nEi "provider[[:space:]]+\"($FOREIGN_PROVIDERS)\"" "$f" >/dev/null 2>&1; then
        note "foreign IaC provider in the data path: $f (no aws/google/azurerm/… — ADR 0005, ARTCI)"
      fi
      if LC_ALL=C grep -nEi "source[[:space:]]*=[[:space:]]*\"([^\"]*/)?($FOREIGN_PROVIDERS)\"" "$f" >/dev/null 2>&1; then
        note "foreign provider source in required_providers: $f (no aws/google/azurerm/… — ADR 0005, ARTCI)"
      fi
      # --- 2. Foreign managed state backend ---------------------------------
      if LC_ALL=C grep -nEi "backend[[:space:]]+\"($FOREIGN_BACKENDS)\"" "$f" >/dev/null 2>&1; then
        note "foreign managed state backend: $f (state may embed secrets; it must be encrypted + in-country — ADR 0005/0007)"
      fi
      ;;
  esac

  # --- 3. Foreign cloud endpoint/host in any infra/ CONFIG file -------------
  # Scoped to config, not docs: a README explaining "no amazonaws.com" is prose
  # about the rule, not a data-path endpoint, and must not trip the rule (same
  # reason this script skips itself). Markdown/text under infra/ is exempt.
  case "$f" in
    infra/*.md | infra/*/*.md | infra/*.txt | infra/*/*.txt) ;;
    infra/*)
      if LC_ALL=C grep -nEi "$FOREIGN_ENDPOINTS" "$f" >/dev/null 2>&1; then
        note "foreign cloud endpoint/host referenced: $f (the data path stays in Côte d'Ivoire — ADR 0005, ARTCI)"
      fi
      ;;
  esac

  # --- 4. Residency pin overridden to a non-CI country ----------------------
  # tfvars:  country = "XX"   |   yaml group_vars:  country: XX
  if LC_ALL=C grep -nE "^[[:space:]]*country[[:space:]]*=[[:space:]]*\"" "$f" 2>/dev/null \
      | grep -vqE "=[[:space:]]*\"CI\"" ; then
    note "residency pin overridden to a non-CI country in $f (country is pinned to CI and must not be overridden — ADR 0005/0007)"
  fi
  if LC_ALL=C grep -nE "^[[:space:]]*country[[:space:]]*:[[:space:]]*[A-Za-z\"']" "$f" 2>/dev/null \
      | grep -vqE ":[[:space:]]*[\"']?CI[\"']?([[:space:]]|#|$)" ; then
    note "residency pin overridden to a non-CI country in $f (country is pinned to CI and must not be overridden — ADR 0005/0007)"
  fi
done < <(tracked)

if [ "$fail" -ne 0 ]; then
  echo "FAILED: data-residency violations found (see above). The HealthTech data path must stay in Côte d'Ivoire (ADR 0005, loi n°2013-450, ARTCI)." >&2
  exit 1
fi

echo "ok: no foreign provider/state-backend/endpoint in infra/; country pin not overridden (data residency: Côte d'Ivoire)."
