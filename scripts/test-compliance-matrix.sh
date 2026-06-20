#!/usr/bin/env bash
# Tests unitaires pour scripts/check-compliance-matrix.sh.
#
# Chaque test crée un arbre documentaire synthétique minimal dans un répertoire
# temporaire, exécute le vérificateur dans ce contexte isolé, et contrôle le
# code de sortie (0 = succès attendu, non-0 = échec attendu).
#
# Couverture :
#   CHECK 1 — structure documentaire (fichiers requis)
#   CHECK 2 — schéma de la matrice (11 colonnes)
#   CHECK 3 — gate de complétude (Must : CTRL-NN, PREUVE-NN, responsable, statut ; Écart tracé)
#   CHECK 4 — intégrité des liens relatifs
#   CHECK 5 — traçabilité backlog (références #NN)
#   CHECK 6 — invariant anti-régression conformité (pas de déchiffrement/clé/PII côté serveur)
#   CHECK 7 — gate de validation juridique (journal exhaustif, cohérence « Validé = Oui »)
#   SMOKE    — artefacts livrés dans docs/compliance/ passent le gate sans modification
#
# Usage : bash scripts/test-compliance-matrix.sh
# Wired : just test-compliance-scripts
#
# Style : aligné sur check-compliance-matrix.sh (POSIX, fail-closed, note/ok helpers).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/check-compliance-matrix.sh"

tests_run=0
tests_failed=0

# ── helpers ────────────────────────────────────────────────────────────────────

note_fail() {
    tests_run=$((tests_run + 1))
    tests_failed=$((tests_failed + 1))
    echo "FAIL: $1"
}

assert_exits_zero() {
    local label="$1" tmp="$2"
    tests_run=$((tests_run + 1))
    if (cd "$tmp" && bash scripts/check-compliance-matrix.sh >/dev/null 2>&1); then
        echo "PASS: $label"
    else
        tests_failed=$((tests_failed + 1))
        echo "FAIL: $label (exit 0 attendu, obtenu non-0)"
    fi
}

assert_exits_nonzero() {
    local label="$1" tmp="$2"
    tests_run=$((tests_run + 1))
    if (cd "$tmp" && bash scripts/check-compliance-matrix.sh >/dev/null 2>&1); then
        tests_failed=$((tests_failed + 1))
        echo "FAIL: $label (exit non-0 attendu, obtenu 0)"
    else
        echo "PASS: $label"
    fi
}

cleanup() { rm -rf "$1"; }

# Construit un arbre de conformité valide minimal dans un répertoire temporaire.
# Une seule exigence Must (REQ-LEX-01) avec CTRL-NN, PREUVE-NN, responsable,
# statut Planifié, et toutes les références cohérentes.
make_valid_tree() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/docs/compliance" "$tmp/scripts"
    cp "$CHECKER" "$tmp/scripts/check-compliance-matrix.sh"

    cat > "$tmp/BACKLOG.md" <<'EOF'
# BACKLOG
- **#8** Hébergement souverain
EOF

    cat > "$tmp/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice de conformité

| REQ | Source légale | Exigence | Cat. | M/S | CTRL | ADR / Issue | Preuve | Statut | Resp. | Valid. jur. |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **REQ-LEX-01** | L.2013-450 | Résidence des données sur le territoire national | Résidence | Must | CTRL-08 | #8 | PREUVE-05 | **Planifié** | Infra | Non — en attente |
EOF

    cat > "$tmp/docs/compliance/exigences-legales.md" <<'EOF'
# Registre des exigences
| REQ-LEX-01 | L.2013-450 | Résidence sur le territoire national | Résidence | Must |
EOF

    cat > "$tmp/docs/compliance/controles.md" <<'EOF'
# Catalogue des contrôles
| CTRL-08 | Hébergement souverain in-country | Infra | #8 |
Le serveur ne peut pas déchiffrer les blobs patients (zero-knowledge).
EOF

    cat > "$tmp/docs/compliance/registre-des-traitements.md" <<'EOF'
# Registre des traitements
Finalité : suivi médical du patient. Aucune donnée médicale en clair hors de l'appareil.
EOF

    cat > "$tmp/docs/compliance/cartographie-donnees-et-flux.md" <<'EOF'
# Cartographie des données & flux
Le serveur ne stocke que des blobs opaques. Le serveur ne peut pas déchiffrer.
EOF

    cat > "$tmp/docs/compliance/ecarts.md" <<'EOF'
# Registre des écarts
Aucun écart pour l'instant.
EOF

    cat > "$tmp/docs/compliance/journal-validation-juridique.md" <<'EOF'
# Journal de validation juridique
| REQ-LEX-01 | Must | En attente |
EOF

    cat > "$tmp/docs/compliance/README.md" <<'EOF'
# README conformité
Voir [exigences](./exigences-legales.md) et [BACKLOG](../../BACKLOG.md).
EOF

    echo "$tmp"
}

# ── CHECK 1 : structure documentaire ──────────────────────────────────────────

echo "--- CHECK 1 : structure documentaire ---"

T=$(make_valid_tree)
assert_exits_zero "CHECK 1: arbre valide complet → succès" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/controles.md"
assert_exits_nonzero "CHECK 1: controles.md manquant → échec" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/ecarts.md"
assert_exits_nonzero "CHECK 1: ecarts.md manquant → échec" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/loi-2013-450-artci-matrix.md"
assert_exits_nonzero "CHECK 1: loi-2013-450-artci-matrix.md manquant → échec" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/journal-validation-juridique.md"
assert_exits_nonzero "CHECK 1: journal-validation-juridique.md manquant → échec" "$T"
cleanup "$T"

# ── CHECK 2 : schéma de la matrice ────────────────────────────────────────────

echo "--- CHECK 2 : schéma de la matrice ---"

# Ligne avec 10 colonnes (une de moins que les 11 requises)
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | PREUVE-05 | **Planifié** | Infra |
EOF
assert_exits_nonzero "CHECK 2: ligne REQ-LEX à 10 colonnes (11 attendues) → échec" "$T"
cleanup "$T"

# Ligne avec 12 colonnes (une de trop)
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | PREUVE-05 | **Planifié** | Infra | Non — en attente | Colonne extra |
EOF
assert_exits_nonzero "CHECK 2: ligne REQ-LEX à 12 colonnes (11 attendues) → échec" "$T"
cleanup "$T"

# ── CHECK 3 : gate de complétude ──────────────────────────────────────────────

echo "--- CHECK 3 : gate de complétude ---"

# Must sans aucun CTRL-NN
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | *(à définir)* | #8 | PREUVE-05 | **Planifié** | Infra | Non — en attente |
EOF
assert_exits_nonzero "CHECK 3: Must sans CTRL-NN → échec" "$T"
cleanup "$T"

# Must sans PREUVE-NN, statut non-Écart
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | *(à produire)* | **Planifié** | Infra | Non — en attente |
EOF
assert_exits_nonzero "CHECK 3: Must sans PREUVE-NN et statut Planifié → échec" "$T"
cleanup "$T"

# Must + statut Écart + sans PREUVE-NN + tracé dans ecarts.md → exempt de PREUVE-NN
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | *(à produire)* | **Écart** (à instruire) | Infra | Non — en attente |
EOF
cat > "$T/docs/compliance/ecarts.md" <<'EOF'
# Écarts
| ECART-01 | REQ-LEX-01 | Pas de preuve disponible | Gouvernance | à créer |
EOF
assert_exits_zero "CHECK 3: Must Écart sans PREUVE-NN mais tracé dans ecarts.md → succès" "$T"
cleanup "$T"

# Must + statut Écart + non tracé dans ecarts.md
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | *(à produire)* | **Écart** (à instruire) | Infra | Non — en attente |
EOF
# ecarts.md ne référence PAS REQ-LEX-01
assert_exits_nonzero "CHECK 3: Must Écart non tracé dans ecarts.md → échec" "$T"
cleanup "$T"

# Must avec responsable vide (tiret seul — valeur sentinelle reconnue)
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | PREUVE-05 | **Planifié** | — | Non — en attente |
EOF
assert_exits_nonzero "CHECK 3: Must avec responsable '—' (vide) → échec" "$T"
cleanup "$T"

# Should sans CTRL-NN — le gate de complétude ne vérifie que les Must
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | PREUVE-05 | **Planifié** | Infra | Non — en attente |
| **REQ-LEX-99** | L.2013-450 | Recommandation | Autre | Should | *(à définir)* | — | *(à définir)* | **Planifié** | — | Non — en attente |
EOF
assert_exits_zero "CHECK 3: Should sans CTRL-NN (non soumis au gate Must) → succès" "$T"
cleanup "$T"

# Matrice sans aucune ligne Must → gate lève une erreur
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice vide (aucune ligne REQ-LEX)
Texte introductif seulement.
EOF
assert_exits_nonzero "CHECK 3: aucune ligne Must REQ-LEX dans la matrice → échec" "$T"
cleanup "$T"

# ── CHECK 4 : intégrité des liens relatifs ────────────────────────────────────

echo "--- CHECK 4 : intégrité des liens relatifs ---"

# Lien vers un fichier inexistant
T=$(make_valid_tree)
cat > "$T/docs/compliance/README.md" <<'EOF'
# README conformité
Voir [fichier inexistant](./fichier-qui-nexiste-pas.md) et [BACKLOG](../../BACKLOG.md).
EOF
assert_exits_nonzero "CHECK 4: lien relatif brisé (./fichier-qui-nexiste-pas.md) → échec" "$T"
cleanup "$T"

# Lien valide vers un ADR parent (../adr/…) — le fichier doit exister dans l'arbre
T=$(make_valid_tree)
mkdir -p "$T/docs/adr"
touch "$T/docs/adr/0005-storage-and-sovereign-hosting.md"
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
Voir [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md) pour l'hébergement souverain.
EOF
assert_exits_zero "CHECK 4: lien ../adr/0005 vers fichier créé → succès" "$T"
cleanup "$T"

# ── CHECK 5 : traçabilité backlog ─────────────────────────────────────────────

echo "--- CHECK 5 : traçabilité backlog ---"

# Référence #99 absente du BACKLOG.md
T=$(make_valid_tree)
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #99 | PREUVE-05 | **Planifié** | Infra | Non — en attente |
EOF
assert_exits_nonzero "CHECK 5: référence #99 absente de BACKLOG.md → échec" "$T"
cleanup "$T"

# Toutes les références présentes dans BACKLOG.md
T=$(make_valid_tree)
cat >> "$T/BACKLOG.md" <<'EOF'
- **#9** Service zero-knowledge
EOF
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | PREUVE-05 | **Planifié** | Infra | Non — en attente |
| **REQ-LEX-02** | L.2013-450 | Zero-knowledge | Sécurité | Must | CTRL-08 | #9 | PREUVE-05 | **Planifié** | Backend | Non — en attente |
EOF
cat > "$T/docs/compliance/exigences-legales.md" <<'EOF'
# Registre
| REQ-LEX-01 | L.2013-450 | Résidence | Résidence | Must |
| REQ-LEX-02 | L.2013-450 | Zero-knowledge | Sécurité | Must |
EOF
cat > "$T/docs/compliance/journal-validation-juridique.md" <<'EOF'
# Journal
| REQ-LEX-01 | Must | En attente |
| REQ-LEX-02 | Must | En attente |
EOF
assert_exits_zero "CHECK 5: #8 et #9 présents dans BACKLOG.md → succès" "$T"
cleanup "$T"

# ── CHECK 6 : invariant anti-régression conformité ────────────────────────────

echo "--- CHECK 6 : invariant anti-régression conformité ---"

# Affirmation interdite : le serveur déchiffre (présent actif)
T=$(make_valid_tree)
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
CTRL-XX : le serveur déchiffre les données patient pour analyse en temps réel.
EOF
assert_exits_nonzero "CHECK 6: 'serveur déchiffre' (affirmation positive) → VIOLATION → échec" "$T"
cleanup "$T"

# Affirmation interdite : le serveur décrypte
T=$(make_valid_tree)
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
CTRL-XX : le serveur décrypte les blobs avant de les journaliser.
EOF
assert_exits_nonzero "CHECK 6: 'serveur décrypte' (affirmation positive) → VIOLATION → échec" "$T"
cleanup "$T"

# Assertion négative légitime : "le serveur ne peut pas déchiffrer" → pas de violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
CTRL-02 : architecture zero-knowledge — le serveur ne peut pas déchiffrer les blobs patients.
La preuve attendue est le test « le serveur ne peut pas déchiffrer ».
EOF
assert_exits_zero "CHECK 6: 'le serveur ne peut pas déchiffrer' (assertion négative) → pas de violation" "$T"
cleanup "$T"

# Affirmation interdite : stocker la clé côté serveur
T=$(make_valid_tree)
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
CTRL-XX : stocker la clé côté serveur pour permettre la récupération d'urgence.
EOF
assert_exits_nonzero "CHECK 6: 'stocker la clé côté serveur' → VIOLATION → échec" "$T"
cleanup "$T"

# Affirmation interdite : enregistrer la clé serveur (sans « côté »)
T=$(make_valid_tree)
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
CTRL-XX : enregistrer la clé serveur dans la base de données pour audit.
EOF
assert_exits_nonzero "CHECK 6: 'enregistrer la clé serveur' → VIOLATION → échec" "$T"
cleanup "$T"

# Affirmation interdite : stocker des données de santé en clair
T=$(make_valid_tree)
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
CTRL-XX : stocker les données de santé en clair côté serveur pour performances.
EOF
assert_exits_nonzero "CHECK 6: 'stocker données de santé en clair' → VIOLATION → échec" "$T"
cleanup "$T"

# Affirmation interdite : stocker PII en clair
T=$(make_valid_tree)
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
CTRL-XX : persister les PII en clair dans la base pour recherche.
EOF
assert_exits_nonzero "CHECK 6: 'persister PII en clair' → VIOLATION → échec" "$T"
cleanup "$T"

# Formulation correcte : clé stockée uniquement sur l'appareil (client-side only)
T=$(make_valid_tree)
cat > "$T/docs/compliance/controles.md" <<'EOF'
# Contrôles
CTRL-03 : clé maîtresse stockée uniquement sur l'appareil du patient (Android Keystore).
La clé n'est jamais transmise au serveur ni stockée hors de l'appareil.
EOF
assert_exits_zero "CHECK 6: 'clé stockée uniquement sur l'appareil' → pas de violation" "$T"
cleanup "$T"

# ── CHECK 7 : gate de validation juridique ────────────────────────────────────

echo "--- CHECK 7 : gate de validation juridique ---"

# REQ-LEX présent dans exigences-legales.md mais absent du journal → échec
T=$(make_valid_tree)
cat > "$T/docs/compliance/exigences-legales.md" <<'EOF'
# Registre
| REQ-LEX-01 | L.2013-450 | Résidence | Résidence | Must |
| REQ-LEX-02 | L.2013-450 | Consentement | Consentement | Must |
EOF
cat > "$T/docs/compliance/loi-2013-450-artci-matrix.md" <<'EOF'
# Matrice
| **REQ-LEX-01** | L.2013-450 | Résidence | Résidence | Must | CTRL-08 | #8 | PREUVE-05 | **Planifié** | Infra | Non — en attente |
| **REQ-LEX-02** | L.2013-450 | Consentement | Consentement | Must | CTRL-08 | #8 | PREUVE-05 | **Planifié** | Product | Non — en attente |
EOF
# Le journal ne couvre que REQ-LEX-01, pas REQ-LEX-02
cat > "$T/docs/compliance/journal-validation-juridique.md" <<'EOF'
# Journal
| REQ-LEX-01 | Must | En attente |
EOF
assert_exits_nonzero "CHECK 7: REQ-LEX-02 dans registre mais absent du journal → échec" "$T"
cleanup "$T"

# Incohérence : « Matrice validée = Oui » alors que aucun Must n'est signé
T=$(make_valid_tree)
cat > "$T/docs/compliance/journal-validation-juridique.md" <<'EOF'
# Journal
| REQ-LEX-01 | Must | En attente |
Matrice validée = **Oui**
EOF
assert_exits_nonzero "CHECK 7: 'Matrice validée = Oui' incohérent (0/1 Must signés) → échec" "$T"
cleanup "$T"

# Cohérence : Must signé (Validé) → statut matrice validée
T=$(make_valid_tree)
cat > "$T/docs/compliance/journal-validation-juridique.md" <<'EOF'
# Journal
| REQ-LEX-01 | Must | Validé |
EOF
assert_exits_zero "CHECK 7: REQ-LEX-01 Must signé Validé → gate cohérent → succès" "$T"
cleanup "$T"

# ── SMOKE : artefacts de la branche courante passent le gate ──────────────────

echo "--- SMOKE : artefacts livrés docs/compliance/ ---"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
tests_run=$((tests_run + 1))
if (cd "$REPO_ROOT" && bash scripts/check-compliance-matrix.sh >/dev/null 2>&1); then
    echo "PASS: SMOKE: docs/compliance/ de la branche passe le gate sans modification"
else
    tests_failed=$((tests_failed + 1))
    echo "FAIL: SMOKE: docs/compliance/ de la branche ECHOUE le gate"
    echo "  → relancer: bash scripts/check-compliance-matrix.sh"
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
echo "ok: tous les tests unitaires du vérificateur de conformité ont réussi."
