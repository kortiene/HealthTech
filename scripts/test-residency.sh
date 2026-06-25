#!/usr/bin/env bash
# Tests unitaires pour scripts/check-residency.sh (issue #8, ADR 0005).
#
# Crée des arborescences synthétiques dans des répertoires temporaires isolés,
# exécute le vérificateur dans ce contexte, et contrôle le code de sortie
# (0 = succès attendu, non-0 = échec attendu).
#
# Couverture :
#   CHECK 1 — provider IaC étranger (aws/google/azurerm/… dans la liste)
#   CHECK 2 — state backend managé étranger (gcs/azurerm/oss/cos)
#   CHECK 3 — endpoint cloud étranger dans les fichiers de config infra/
#   CHECK 4 — country pin surchargé à une valeur non-CI
#   SMOKE    — le dépôt courant passe le garde-fou sans modification
#
# Usage : bash scripts/test-residency.sh
# Câblé : just test-residency-scripts
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/check-residency.sh"

tests_run=0
tests_failed=0

# ── helpers ────────────────────────────────────────────────────────────────────

assert_exits_zero() {
    local label="$1" tmp="$2"
    tests_run=$((tests_run + 1))
    if (cd "$tmp" && bash scripts/check-residency.sh >/dev/null 2>&1); then
        echo "PASS: $label"
    else
        tests_failed=$((tests_failed + 1))
        echo "FAIL: $label (exit 0 attendu, obtenu non-0)"
    fi
}

assert_exits_nonzero() {
    local label="$1" tmp="$2"
    tests_run=$((tests_run + 1))
    if (cd "$tmp" && bash scripts/check-residency.sh >/dev/null 2>&1); then
        tests_failed=$((tests_failed + 1))
        echo "FAIL: $label (exit non-0 attendu, obtenu 0)"
    else
        echo "PASS: $label"
    fi
}

# Crée un répertoire temporaire avec le script copié dans scripts/.
make_base() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/scripts"
    cp "$CHECKER" "$tmp/scripts/check-residency.sh"
    echo "$tmp"
}

cleanup() { rm -rf "$1"; }

# ── CHECK 1 : provider IaC étranger ───────────────────────────────────────────

echo "--- CHECK 1 : provider IaC étranger ---"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
provider "aws" { region = "us-east-1" }
EOF
assert_exits_nonzero 'CHECK 1: provider "aws" dans infra/*.tf → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
provider "google" { project = "my-project" }
EOF
assert_exits_nonzero 'CHECK 1: provider "google" dans infra/*.tf → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
  google = { source = "hashicorp/google" }
EOF
assert_exits_nonzero 'CHECK 1: source = "hashicorp/google" dans required_providers → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
  aws = { source = "hashicorp/aws", version = "~> 5.0" }
EOF
assert_exits_nonzero 'CHECK 1: source = "hashicorp/aws" dans required_providers → échec' "$T"
cleanup "$T"

# Commentaire prose — pas de forme structurelle provider "X"
T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
# No foreign cloud: no aws / no google / no azurerm — in-country operators only.
EOF
assert_exits_zero "CHECK 1: commentaire prose (sans forme structurelle) → succès" "$T"
cleanup "$T"

# Provider local inconnu (non dans la liste)
T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
provider "vitib-cloud" { endpoint = "https://api.vitib.ci" }
EOF
assert_exits_zero "CHECK 1: provider local non listé (opérateur in-country) → succès" "$T"
cleanup "$T"

# ── CHECK 2 : state backend managé étranger ────────────────────────────────────

echo "--- CHECK 2 : state backend managé étranger ---"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
backend "gcs" { bucket = "tf-state" }
EOF
assert_exits_nonzero 'CHECK 2: backend "gcs" → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
backend "azurerm" { storage_account_name = "tfstate" }
EOF
assert_exits_nonzero 'CHECK 2: backend "azurerm" → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
backend "oss" { bucket = "terraform-state" }
EOF
assert_exits_nonzero 'CHECK 2: backend "oss" → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
backend "cos" { bucket = "terraform-state" }
EOF
assert_exits_nonzero 'CHECK 2: backend "cos" → échec' "$T"
cleanup "$T"

# backend "s3" avec endpoint .ci (MinIO in-country) → autorisé par check 2
T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
backend "s3" {
  bucket   = "tf-state"
  endpoint = "https://minio.internal.vitib.ci"
  region   = "ci"
}
EOF
assert_exits_zero 'CHECK 2: backend "s3" avec endpoint .ci (MinIO in-country) → succès' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
backend "local" {}
EOF
assert_exits_zero 'CHECK 2: backend "local" → succès' "$T"
cleanup "$T"

# ── CHECK 3 : endpoint cloud étranger dans infra/ ──────────────────────────────

echo "--- CHECK 3 : endpoint cloud étranger dans infra/ ---"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
endpoint = "https://s3.amazonaws.com"
EOF
assert_exits_nonzero "CHECK 3: amazonaws.com dans infra/*.tf → échec" "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
url = "https://storage.googleapis.com/bucket"
EOF
assert_exits_nonzero "CHECK 3: googleapis.com dans infra/*.tf → échec" "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
url = "https://account.blob.core.windows.net/container"
EOF
assert_exits_nonzero "CHECK 3: blob.core.windows.net dans infra/*.tf → échec" "$T"
cleanup "$T"

# backend "s3" vers amazonaws.com : check 2 passe (s3 toléré), check 3 échoue
T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
backend "s3" {
  bucket   = "tf-state"
  endpoint = "https://s3.amazonaws.com"
}
EOF
assert_exits_nonzero 'CHECK 3: backend "s3" avec endpoint amazonaws.com → détecté par check 3 → échec' "$T"
cleanup "$T"

# Markdown infra/ : exempt du check 3
T=$(make_base)
mkdir -p "$T/infra"
cat > "$T/infra/README.md" <<'EOF'
Ne pas utiliser amazonaws.com — données en Côte d'Ivoire uniquement.
EOF
assert_exits_zero "CHECK 3: amazonaws.com dans infra/README.md (markdown exempt) → succès" "$T"
cleanup "$T"

# Fichier texte infra/ : exempt du check 3
T=$(make_base)
mkdir -p "$T/infra"
cat > "$T/infra/notes.txt" <<'EOF'
Reminder: no amazonaws.com — data stays in-country.
EOF
assert_exits_zero "CHECK 3: amazonaws.com dans infra/notes.txt (texte exempt) → succès" "$T"
cleanup "$T"

# Fichier hors infra/ : hors périmètre
T=$(make_base)
mkdir -p "$T/docs"
cat > "$T/docs/architecture.md" <<'EOF'
The system avoids amazonaws.com by design.
EOF
assert_exits_zero "CHECK 3: amazonaws.com hors infra/ (hors périmètre) → succès" "$T"
cleanup "$T"

# Endpoint .ci : domaine in-country
T=$(make_base)
mkdir -p "$T/infra/terraform"
cat > "$T/infra/terraform/main.tf" <<'EOF'
endpoint = "https://minio.internal.vitib.ci"
EOF
assert_exits_zero "CHECK 3: endpoint .ci dans infra/*.tf → succès" "$T"
cleanup "$T"

# ── CHECK 4 : country pin surchargé ───────────────────────────────────────────

echo "--- CHECK 4 : country pin surchargé ---"

T=$(make_base)
mkdir -p "$T/infra/terraform/environments"
cat > "$T/infra/terraform/environments/staging.tfvars" <<'EOF'
country = "FR"
environment = "staging"
EOF
assert_exits_nonzero 'CHECK 4: country = "FR" dans tfvars → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform/environments"
cat > "$T/infra/terraform/environments/prod.tfvars" <<'EOF'
country = "US"
environment = "prod"
EOF
assert_exits_nonzero 'CHECK 4: country = "US" dans tfvars → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/ansible/group_vars"
cat > "$T/infra/ansible/group_vars/staging.yml" <<'EOF'
env: staging
country: US
EOF
assert_exits_nonzero "CHECK 4: country: US dans group_vars YAML → échec" "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/ansible/group_vars"
cat > "$T/infra/ansible/group_vars/prod.yml" <<'EOF'
env: prod
country: "FR"
EOF
assert_exits_nonzero 'CHECK 4: country: "FR" (entre guillemets) dans YAML → échec' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/terraform/environments"
cat > "$T/infra/terraform/environments/staging.tfvars" <<'EOF'
environment = "staging"
country = "CI"
EOF
assert_exits_zero 'CHECK 4: country = "CI" dans tfvars → succès' "$T"
cleanup "$T"

T=$(make_base)
mkdir -p "$T/infra/ansible/group_vars"
cat > "$T/infra/ansible/group_vars/staging.yml" <<'EOF'
env: staging
country: CI
EOF
assert_exits_zero "CHECK 4: country: CI dans YAML → succès" "$T"
cleanup "$T"

# Forme exacte des group_vars réels (avec commentaire inline)
T=$(make_base)
mkdir -p "$T/infra/ansible/group_vars"
cat > "$T/infra/ansible/group_vars/prod.yml" <<'EOF'
env: prod
country: CI # residency pin (ARTCI / loi 2013-450); never override
EOF
assert_exits_zero "CHECK 4: country: CI avec commentaire inline (forme réelle group_vars) → succès" "$T"
cleanup "$T"

# Fichier YAML sans clé country → pas de violation
T=$(make_base)
mkdir -p "$T/infra/ansible/group_vars"
cat > "$T/infra/ansible/group_vars/dev.yml" <<'EOF'
env: dev
backend_instance_count: 1
EOF
assert_exits_zero "CHECK 4: YAML sans clé country → succès" "$T"
cleanup "$T"

# ── SMOKE : le dépôt courant passe le garde-fou ────────────────────────────────

echo "--- SMOKE : dépôt courant ---"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
tests_run=$((tests_run + 1))
if (cd "$REPO_ROOT" && bash scripts/check-residency.sh >/dev/null 2>&1); then
    echo "PASS: SMOKE: le dépôt courant passe le garde-fou de résidence sans modification"
else
    tests_failed=$((tests_failed + 1))
    echo "FAIL: SMOKE: le dépôt courant ÉCHOUE le garde-fou de résidence"
    echo "  → relancer : bash scripts/check-residency.sh"
fi

# ── Bilan ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== Bilan des tests ==="
echo "  Testés  : $tests_run"
echo "  Réussis : $((tests_run - tests_failed))"
echo "  Échoués : $tests_failed"
echo ""

if [ "$tests_failed" -gt 0 ]; then
    echo "ECHEC : $tests_failed test(s) ont échoué." >&2
    exit 1
fi
echo "ok: tous les tests unitaires du vérificateur de résidence ont réussi."
