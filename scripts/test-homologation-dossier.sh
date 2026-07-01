#!/usr/bin/env bash
# Tests unitaires pour scripts/check-homologation-dossier.sh (issue #30, Épic E6).
#
# Crée des arbres synthétiques dans des répertoires temporaires isolés,
# exécute le vérificateur dans ce contexte et contrôle le code de sortie
# (0 = succès attendu, non-0 = échec attendu).
#
# Couverture :
#   CHECK 1 — structure du dossier (5 fichiers requis)
#   CHECK 2 — pas de pièce orpheline (PIECE-NN → PREUVE-NN existant dans controles.md)
#   CHECK 3 — preuves obligatoires présentes dans piece-list.md
#   CHECK 4 — honnêteté de statut (« Prête » ⇒ preuve source « Existant »)
#   CHECK 5 — intégrité des liens relatifs du dossier
#   CHECK 6 — traçabilité backlog (#NN cités présents dans BACKLOG.md)
#   CHECK 7 — honnêteté globale (pas d'homologation prématurée ; invariant déchiffrement serveur)
#   SMOKE    — le dossier livré dans docs/compliance/homologation-artci/ passe le gate
#
# Usage : bash scripts/test-homologation-dossier.sh
# Câblé : just test-homologation-scripts
#
# Style : aligné sur test-compliance-matrix.sh et test-residency.sh (POSIX, fail-closed).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/check-homologation-dossier.sh"

tests_run=0
tests_failed=0

# ── helpers ────────────────────────────────────────────────────────────────────

assert_exits_zero() {
    local label="$1" tmp="$2"
    tests_run=$((tests_run + 1))
    if (cd "$tmp" && bash scripts/check-homologation-dossier.sh >/dev/null 2>&1); then
        echo "PASS: $label"
    else
        tests_failed=$((tests_failed + 1))
        echo "FAIL: $label (exit 0 attendu, obtenu non-0)"
    fi
}

assert_exits_nonzero() {
    local label="$1" tmp="$2"
    tests_run=$((tests_run + 1))
    if (cd "$tmp" && bash scripts/check-homologation-dossier.sh >/dev/null 2>&1); then
        tests_failed=$((tests_failed + 1))
        echo "FAIL: $label (exit non-0 attendu, obtenu 0)"
    else
        echo "PASS: $label"
    fi
}

cleanup() { rm -rf "$1"; }

# Construit un arbre synthétique minimal valide dans un répertoire temporaire.
#
# Invariants du arbre valide :
#   - Les 5 fichiers requis du dossier sont présents.
#   - Les 6 preuves obligatoires (PREUVE-05/13/14/16/17/18) apparaissent dans piece-list.md.
#   - PIECE-01 (PREUVE-17) est « Prête » et PREUVE-17 est « Existant » dans controles.md.
#   - Toutes les preuves référencées existent dans controles.md (pas d'orphelin).
#   - Aucun lien relatif brisé dans les fichiers du dossier.
#   - Aucune référence issue absente du backlog.
#   - Aucune affirmation d'homologation prématurée ni de déchiffrement serveur.
make_valid_tree() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/scripts" \
             "$tmp/docs/compliance/homologation-artci"
    cp "$CHECKER" "$tmp/scripts/check-homologation-dossier.sh"

    cat > "$tmp/BACKLOG.md" <<'EOF'
# Backlog — synthétique
EOF

    # controles.md : PREUVE-17 est Existant (supporte PIECE-01 « Prête »).
    # Les autres preuves obligatoires sont Partiel ou Planifié (non Existant).
    cat > "$tmp/docs/compliance/controles.md" <<'EOF'
# Contrôles & preuves
| **PREUVE-05** | Attestation localisation | Partiel |
| **PREUVE-13** | Récépissé ARTCI | Planifié |
| **PREUVE-14** | Rapport pentest | Planifié |
| **PREUVE-16** | Modèle de menace STRIDE | Planifié |
| **PREUVE-17** | Registre des traitements | Existant |
| **PREUVE-18** | Cartographie données/flux | Planifié |
EOF

    cat > "$tmp/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
Statut : PROJET DE SOUMISSION — l'homologation n'est pas acquise.
EOF

    # piece-list.md : 6 pièces couvrant les 6 preuves obligatoires.
    # PIECE-01 « Prête » adossée à PREUVE-17 (Existant). Les 5 autres non prêtes.
    cat > "$tmp/docs/compliance/homologation-artci/piece-list.md" <<'EOF'
# Index des pièces
| Pièce | Preuve source | Intitulé | Exigence(s) | Emplacement | Statut dossier | Propriétaire |
| --- | --- | --- | --- | --- | --- | --- |
| **PIECE-01** | [PREUVE-17](../controles.md) | Registre des traitements | REQ-LEX-21 | à produire | **Prête** | Agent |
| **PIECE-02** | [PREUVE-05](../controles.md) | Attestation localisation | REQ-LEX-19 | à produire | **Bloquante** | Infra |
| **PIECE-03** | [PREUVE-13](../controles.md) | Récépissé ARTCI | REQ-LEX-01 | à produire | **À produire** | Conseil juridique |
| **PIECE-04** | [PREUVE-14](../controles.md) | Rapport pentest | REQ-LEX-16 | à produire | **À produire** | Équipe pentest |
| **PIECE-05** | [PREUVE-16](../controles.md) | Modèle de menace | REQ-LEX-16 | à produire | **À produire** | Agent |
| **PIECE-06** | [PREUVE-18](../controles.md) | Cartographie données | REQ-LEX-07 | à produire | **À produire** | Agent |
EOF

    cat > "$tmp/docs/compliance/homologation-artci/readiness-dashboard.md" <<'EOF'
# Tableau de bord de préparation
Statut : PROJET — l'homologation n'est PAS acquise.
EOF

    cat > "$tmp/docs/compliance/homologation-artci/formalite-prealable.md" <<'EOF'
# Note de procédure — formalité préalable ARTCI
Nature de la formalité : [à confirmer — conseil juridique].
EOF

    cat > "$tmp/docs/compliance/homologation-artci/submission-checklist.md" <<'EOF'
# Checklist de complétude avant dépôt ARTCI
- [ ] Sign-off juridique complet.
- [ ] Attestation de localisation signée.
EOF

    echo "$tmp"
}

# ── CHECK 1 : structure du dossier ─────────────────────────────────────────────

echo "--- CHECK 1 : structure du dossier ---"

T=$(make_valid_tree)
assert_exits_zero "CHECK 1: arbre valide complet → succès" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/homologation-artci/README.md"
assert_exits_nonzero "CHECK 1: README.md manquant → échec" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/homologation-artci/piece-list.md"
assert_exits_nonzero "CHECK 1: piece-list.md manquant → échec" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/homologation-artci/readiness-dashboard.md"
assert_exits_nonzero "CHECK 1: readiness-dashboard.md manquant → échec" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/homologation-artci/formalite-prealable.md"
assert_exits_nonzero "CHECK 1: formalite-prealable.md manquant → échec" "$T"
cleanup "$T"

T=$(make_valid_tree)
rm "$T/docs/compliance/homologation-artci/submission-checklist.md"
assert_exits_nonzero "CHECK 1: submission-checklist.md manquant → échec" "$T"
cleanup "$T"

# ── CHECK 2 : pas de pièce orpheline ──────────────────────────────────────────

echo "--- CHECK 2 : pas de pièce orpheline ---"

# Pièce référençant une preuve absente de controles.md
T=$(make_valid_tree)
cat >> "$T/docs/compliance/homologation-artci/piece-list.md" <<'EOF'
| **PIECE-07** | [PREUVE-99](../controles.md) | Pièce fantôme | REQ-LEX-01 | à produire | **À produire** | Agent |
EOF
assert_exits_nonzero "CHECK 2: PIECE-07 référence PREUVE-99 absente de controles.md → échec" "$T"
cleanup "$T"

# Pièce dont la colonne « Preuve source » ne contient aucun PREUVE-NN
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/piece-list.md" <<'EOF'
# Index des pièces
| Pièce | Preuve source | Intitulé | Exigence(s) | Emplacement | Statut dossier | Propriétaire |
| --- | --- | --- | --- | --- | --- | --- |
| **PIECE-01** | (sans preuve source) | Pièce orpheline | REQ-LEX-01 | à produire | **À produire** | Agent |
| **PIECE-02** | [PREUVE-05](../controles.md) | Attestation localisation | REQ-LEX-19 | à produire | **Bloquante** | Infra |
| **PIECE-03** | [PREUVE-13](../controles.md) | Récépissé ARTCI | REQ-LEX-01 | à produire | **À produire** | Conseil |
| **PIECE-04** | [PREUVE-14](../controles.md) | Rapport pentest | REQ-LEX-16 | à produire | **À produire** | Pentest |
| **PIECE-05** | [PREUVE-16](../controles.md) | Modèle de menace | REQ-LEX-16 | à produire | **À produire** | Agent |
| **PIECE-06** | [PREUVE-17](../controles.md) | Registre | REQ-LEX-21 | à produire | **À produire** | Agent |
| **PIECE-07** | [PREUVE-18](../controles.md) | Cartographie | REQ-LEX-07 | à produire | **À produire** | Agent |
EOF
assert_exits_nonzero "CHECK 2: PIECE-01 sans PREUVE-NN → échec" "$T"
cleanup "$T"

# Aucune ligne PIECE-NN dans piece-list.md
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/piece-list.md" <<'EOF'
# Index des pièces
Aucune pièce définie pour l'instant.
EOF
assert_exits_nonzero "CHECK 2: aucune ligne PIECE-NN dans piece-list.md → échec" "$T"
cleanup "$T"

# ── CHECK 3 : preuves obligatoires présentes ───────────────────────────────────

echo "--- CHECK 3 : preuves obligatoires présentes ---"

# Chaque preuve obligatoire est testée séparément.
for MISSING in PREUVE-05 PREUVE-13 PREUVE-14 PREUVE-16 PREUVE-17 PREUVE-18; do
    T=$(make_valid_tree)
    # Réécrire piece-list.md sans la preuve manquante.
    grep -v "$MISSING" "$T/docs/compliance/homologation-artci/piece-list.md" \
        > "$T/docs/compliance/homologation-artci/piece-list.md.tmp"
    mv "$T/docs/compliance/homologation-artci/piece-list.md.tmp" \
       "$T/docs/compliance/homologation-artci/piece-list.md"
    assert_exits_nonzero "CHECK 3: $MISSING absente de piece-list.md → échec" "$T"
    cleanup "$T"
done

# Toutes les preuves obligatoires présentes → succès (couvert par le test valide du CHECK 1).

# ── CHECK 4 : honnêteté de statut ─────────────────────────────────────────────

echo "--- CHECK 4 : honnêteté de statut ---"

# Pièce « Prête » adossée à une preuve « Partiel » (non Existant) → violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/piece-list.md" <<'EOF'
# Index des pièces
| Pièce | Preuve source | Intitulé | Exigence(s) | Emplacement | Statut dossier | Propriétaire |
| --- | --- | --- | --- | --- | --- | --- |
| **PIECE-01** | [PREUVE-17](../controles.md) | Registre | REQ-LEX-21 | à produire | **Prête** | Agent |
| **PIECE-02** | [PREUVE-05](../controles.md) | Attestation | REQ-LEX-19 | à produire | **Prête** | Infra |
| **PIECE-03** | [PREUVE-13](../controles.md) | Récépissé | REQ-LEX-01 | à produire | **À produire** | Conseil |
| **PIECE-04** | [PREUVE-14](../controles.md) | Pentest | REQ-LEX-16 | à produire | **À produire** | Pentest |
| **PIECE-05** | [PREUVE-16](../controles.md) | Menace | REQ-LEX-16 | à produire | **À produire** | Agent |
| **PIECE-06** | [PREUVE-18](../controles.md) | Cartographie | REQ-LEX-07 | à produire | **À produire** | Agent |
EOF
# PREUVE-05 est Partiel (non Existant) → PIECE-02 « Prête » est malhonnête
assert_exits_nonzero "CHECK 4: PIECE-02 « Prête » avec PREUVE-05 (Partiel, non Existant) → échec" "$T"
cleanup "$T"

# Pièce « Prête » adossée à une preuve « Planifié » (non Existant) → violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/piece-list.md" <<'EOF'
# Index des pièces
| Pièce | Preuve source | Intitulé | Exigence(s) | Emplacement | Statut dossier | Propriétaire |
| --- | --- | --- | --- | --- | --- | --- |
| **PIECE-01** | [PREUVE-17](../controles.md) | Registre | REQ-LEX-21 | à produire | **Prête** | Agent |
| **PIECE-02** | [PREUVE-05](../controles.md) | Attestation | REQ-LEX-19 | à produire | **Bloquante** | Infra |
| **PIECE-03** | [PREUVE-13](../controles.md) | Récépissé | REQ-LEX-01 | à produire | **Prête** | Conseil |
| **PIECE-04** | [PREUVE-14](../controles.md) | Pentest | REQ-LEX-16 | à produire | **À produire** | Pentest |
| **PIECE-05** | [PREUVE-16](../controles.md) | Menace | REQ-LEX-16 | à produire | **À produire** | Agent |
| **PIECE-06** | [PREUVE-18](../controles.md) | Cartographie | REQ-LEX-07 | à produire | **À produire** | Agent |
EOF
# PREUVE-13 est Planifié (non Existant) → PIECE-03 « Prête » est malhonnête
assert_exits_nonzero "CHECK 4: PIECE-03 « Prête » avec PREUVE-13 (Planifié, non Existant) → échec" "$T"
cleanup "$T"

# Pièce « Bloquante » avec preuve non Existant → pas de violation (seul « Prête » est vérifié)
T=$(make_valid_tree)
assert_exits_zero "CHECK 4: pièces « Bloquante »/« À produire » avec preuves non Existant → pas de violation" "$T"
cleanup "$T"

# ── CHECK 5 : intégrité des liens relatifs ─────────────────────────────────────

echo "--- CHECK 5 : intégrité des liens relatifs ---"

# Lien vers un fichier inexistant dans README.md → échec
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
Voir [pièce inexistante](./fichier-qui-nexiste-pas.md).
Statut : PROJET DE SOUMISSION — l'homologation n'est pas acquise.
EOF
assert_exits_nonzero "CHECK 5: lien brisé (./fichier-qui-nexiste-pas.md) dans README.md → échec" "$T"
cleanup "$T"

# Lien vers un fichier inexistant dans piece-list.md → échec
T=$(make_valid_tree)
cat >> "$T/docs/compliance/homologation-artci/piece-list.md" <<'EOF'

Voir aussi : [pièce externe](../rapport-inexistant.md).
EOF
assert_exits_nonzero "CHECK 5: lien brisé (../rapport-inexistant.md) dans piece-list.md → échec" "$T"
cleanup "$T"

# Lien avec ancre de fragment #section : seul le chemin est vérifié (fichier existe) → succès
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
Voir [tableau de readiness](./readiness-dashboard.md#critere-de-soumission).
Statut : PROJET DE SOUMISSION — l'homologation n'est pas acquise.
EOF
assert_exits_zero "CHECK 5: lien avec ancre #fragment (fichier existant) → succès" "$T"
cleanup "$T"

# Lien vers controles.md parent depuis piece-list.md (déjà dans l'arbre valide) → succès
T=$(make_valid_tree)
assert_exits_zero "CHECK 5: liens ../controles.md dans piece-list.md (fichier présent) → succès" "$T"
cleanup "$T"

# ── CHECK 6 : traçabilité backlog ─────────────────────────────────────────────

echo "--- CHECK 6 : traçabilité backlog ---"

# Référence #99 absente du BACKLOG.md → échec
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/formalite-prealable.md" <<'EOF'
# Note de procédure — formalité préalable ARTCI
Voir issue #99 pour le suivi du dépôt ARTCI.
EOF
assert_exits_nonzero "CHECK 6: référence #99 absente de BACKLOG.md → échec" "$T"
cleanup "$T"

# Référence #30 présente dans BACKLOG.md → succès
T=$(make_valid_tree)
cat >> "$T/BACKLOG.md" <<'EOF'
- **#30** Dossier d'homologation ARTCI
EOF
cat > "$T/docs/compliance/homologation-artci/formalite-prealable.md" <<'EOF'
# Note de procédure — formalité préalable ARTCI
Voir issue #30 pour le suivi du dépôt ARTCI.
EOF
assert_exits_zero "CHECK 6: référence #30 présente dans BACKLOG.md → succès" "$T"
cleanup "$T"

# Plusieurs références, toutes présentes dans BACKLOG.md → succès
T=$(make_valid_tree)
cat >> "$T/BACKLOG.md" <<'EOF'
- **#5** Analyse de conformité
- **#8** Hébergement souverain
- **#25** Pentest externe
EOF
cat > "$T/docs/compliance/homologation-artci/readiness-dashboard.md" <<'EOF'
# Tableau de bord de préparation
Bloqueurs : sign-off juridique (#5), attestation de localisation (#8), pentest (#25).
Statut : PROJET — l'homologation n'est PAS acquise.
EOF
assert_exits_zero "CHECK 6: références #5, #8, #25 toutes présentes dans BACKLOG.md → succès" "$T"
cleanup "$T"

# Une référence présente + une absente → échec
T=$(make_valid_tree)
cat >> "$T/BACKLOG.md" <<'EOF'
- **#5** Analyse de conformité
EOF
cat > "$T/docs/compliance/homologation-artci/readiness-dashboard.md" <<'EOF'
# Tableau de bord de préparation
Bloqueurs : #5 (sign-off) et #42 (élément fictif non suivi dans le backlog).
Statut : PROJET — l'homologation n'est PAS acquise.
EOF
assert_exits_nonzero "CHECK 6: référence #42 absente de BACKLOG.md (avec #5 présent) → échec" "$T"
cleanup "$T"

# ── CHECK 7 : honnêteté globale ────────────────────────────────────────────────

echo "--- CHECK 7 : honnêteté globale ---"

# 7a — Affirmation positive que l'homologation est obtenue → violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI
L'homologation est obtenue après soumission du dossier complet.
EOF
assert_exits_nonzero "CHECK 7a: 'l'homologation est obtenue' (assertion positive) → échec" "$T"
cleanup "$T"

# 7a — Affirmation positive : homologation acquise → violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI
Suite à la revue du dossier, l'homologation est acquise.
EOF
assert_exits_nonzero "CHECK 7a: 'l'homologation est acquise' (assertion positive) → échec" "$T"
cleanup "$T"

# 7a — Formulation négative : « n'est pas acquise » → filtré par n' → pas de violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
L'homologation n'est pas acquise tant que l'ARTCI n'a pas délivré son acte.
EOF
assert_exits_zero "CHECK 7a: 'l'homologation n'est pas acquise' (formulation négative) → pas de violation" "$T"
cleanup "$T"

# 7a — « homologation est obtenue lorsque » → filtré par 'lorsque' → pas de violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
L'homologation est obtenue lorsque l'ARTCI délivre son acte favorable.
Statut : PROJET DE SOUMISSION — l'homologation n'est pas acquise.
EOF
assert_exits_zero "CHECK 7a: 'homologation est obtenue lorsque' (conditionnel filtré) → pas de violation" "$T"
cleanup "$T"

# 7b — « serveur déchiffre » dans un fichier du dossier → violation de l'invariant zero-knowledge
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/formalite-prealable.md" <<'EOF'
# Note de procédure — formalité préalable ARTCI
Le serveur déchiffre les données patient pour vérification de conformité.
EOF
assert_exits_nonzero "CHECK 7b: 'serveur déchiffre' dans dossier → VIOLATION invariant zero-knowledge → échec" "$T"
cleanup "$T"

# 7b — « serveur décrypte » → violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/formalite-prealable.md" <<'EOF'
# Note de procédure — formalité préalable ARTCI
Le serveur décrypte les blobs avant de les transmettre à l'ARTCI.
EOF
assert_exits_nonzero "CHECK 7b: 'serveur décrypte' dans dossier → VIOLATION invariant → échec" "$T"
cleanup "$T"

# 7b — « le serveur ne peut pas déchiffrer » (assertion négative, invariant zero-knowledge) → pas de violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
Architecture zero-knowledge : le serveur ne peut pas déchiffrer les blobs patients.
Statut : PROJET DE SOUMISSION — l'homologation n'est pas acquise.
EOF
assert_exits_zero "CHECK 7b: 'le serveur ne peut pas déchiffrer' (assertion négative ZK) → pas de violation" "$T"
cleanup "$T"

# ── CHECK 4 supplémentaire : cas limites d'honnêteté de statut ────────────────

echo "--- CHECK 4 supplémentaire : cas limites ---"

# « Prête » avec PREUVE-NN absent de controles.md → violation
# (différent de CHECK 2 : ici la pièce est « Prête », pas simplement orpheline)
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/piece-list.md" <<'EOF'
# Index des pièces
| Pièce | Preuve source | Intitulé | Exigence(s) | Emplacement | Statut dossier | Propriétaire |
| --- | --- | --- | --- | --- | --- | --- |
| **PIECE-01** | [PREUVE-17](../controles.md) | Registre | REQ-LEX-21 | à produire | **Prête** | Agent |
| **PIECE-02** | [PREUVE-05](../controles.md) | Attestation | REQ-LEX-19 | à produire | **Bloquante** | Infra |
| **PIECE-03** | [PREUVE-13](../controles.md) | Récépissé | REQ-LEX-01 | à produire | **À produire** | Conseil |
| **PIECE-04** | [PREUVE-14](../controles.md) | Pentest | REQ-LEX-16 | à produire | **À produire** | Pentest |
| **PIECE-05** | [PREUVE-16](../controles.md) | Menace | REQ-LEX-16 | à produire | **À produire** | Agent |
| **PIECE-06** | [PREUVE-18](../controles.md) | Cartographie | REQ-LEX-07 | à produire | **À produire** | Agent |
| **PIECE-07** | [PREUVE-99](../controles.md) | Pièce fantôme | REQ-LEX-01 | à produire | **Prête** | Agent |
EOF
# PREUVE-99 est absent de controles.md → PIECE-07 « Prête » est une violation d'honnêteté
assert_exits_nonzero "CHECK 4+: PIECE-07 « Prête » avec PREUVE-99 absente de controles.md → échec" "$T"
cleanup "$T"

# « Prête » avec aucun PREUVE-NN dans la ligne (préfixe null) → violation
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/piece-list.md" <<'EOF'
# Index des pièces
| Pièce | Preuve source | Intitulé | Exigence(s) | Emplacement | Statut dossier | Propriétaire |
| --- | --- | --- | --- | --- | --- | --- |
| **PIECE-01** | [PREUVE-17](../controles.md) | Registre | REQ-LEX-21 | à produire | **Prête** | Agent |
| **PIECE-02** | [PREUVE-05](../controles.md) | Attestation | REQ-LEX-19 | à produire | **Bloquante** | Infra |
| **PIECE-03** | [PREUVE-13](../controles.md) | Récépissé | REQ-LEX-01 | à produire | **À produire** | Conseil |
| **PIECE-04** | [PREUVE-14](../controles.md) | Pentest | REQ-LEX-16 | à produire | **À produire** | Pentest |
| **PIECE-05** | [PREUVE-16](../controles.md) | Menace | REQ-LEX-16 | à produire | **À produire** | Agent |
| **PIECE-06** | [PREUVE-18](../controles.md) | Cartographie | REQ-LEX-07 | à produire | **À produire** | Agent |
| **PIECE-07** | (aucune preuve source) | Pièce sans référence | REQ-LEX-01 | à produire | **Prête** | Agent |
EOF
# PIECE-07 est « Prête » mais sans PREUVE-NN → violation (preuve == vide)
assert_exits_nonzero "CHECK 4+: PIECE-07 « Prête » sans PREUVE-NN dans la ligne → échec" "$T"
cleanup "$T"

# « Prête » avec controles.md contenant « existant » minuscule (pas « Existant ») → violation
# Le vérificateur est case-sensitive ; « cadre existant » minuscule ne doit pas compter.
T=$(make_valid_tree)
# Remplacer la ligne PREUVE-17 pour qu'elle ait « existant » en minuscule uniquement.
sed 's/| Existant |/| existant (cadre) |/' "$T/docs/compliance/controles.md" \
    > "$T/docs/compliance/controles.md.tmp"
mv "$T/docs/compliance/controles.md.tmp" "$T/docs/compliance/controles.md"
# PIECE-01 est « Prête » et adossée à PREUVE-17 qui n'a plus « Existant » → violation
assert_exits_nonzero "CHECK 4+: « Prête » avec « existant » minuscule dans controles.md → échec (case-sensitive)" "$T"
cleanup "$T"

# ── CHECK 5 supplémentaire : liens brisés dans d'autres fichiers du dossier ───

echo "--- CHECK 5 supplémentaire : liens dans readiness-dashboard et submission-checklist ---"

# Lien brisé dans readiness-dashboard.md → échec
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/readiness-dashboard.md" <<'EOF'
# Tableau de bord de préparation
Voir [sources manquantes](./fichier-dashboard-inexistant.md).
Statut : PROJET — l'homologation n'est PAS acquise.
EOF
assert_exits_nonzero "CHECK 5+: lien brisé dans readiness-dashboard.md → échec" "$T"
cleanup "$T"

# Lien brisé dans submission-checklist.md → échec
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/submission-checklist.md" <<'EOF'
# Checklist avant dépôt ARTCI
Voir [annexe inexistante](./annexe-qui-nexiste-pas.md).
- [ ] Sign-off juridique complet.
EOF
assert_exits_nonzero "CHECK 5+: lien brisé dans submission-checklist.md → échec" "$T"
cleanup "$T"

# Lien brisé dans formalite-prealable.md → échec
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/formalite-prealable.md" <<'EOF'
# Note de procédure — formalité préalable ARTCI
Nature : [à confirmer — conseil juridique].
Voir [procédure ARTCI](./procedure-artci-inexistante.md).
EOF
assert_exits_nonzero "CHECK 5+: lien brisé dans formalite-prealable.md → échec" "$T"
cleanup "$T"

# ── CHECK 6 supplémentaire : références dans d'autres fichiers du dossier ─────

echo "--- CHECK 6 supplémentaire : références dans submission-checklist et README ---"

# Référence #77 absente du BACKLOG.md dans submission-checklist.md → échec
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/submission-checklist.md" <<'EOF'
# Checklist avant dépôt ARTCI
Référence bloquant : issue #77 (élément fictif hors backlog).
- [ ] Sign-off juridique complet.
- [ ] Attestation de localisation signée.
EOF
assert_exits_nonzero "CHECK 6+: référence #77 dans submission-checklist.md absente de BACKLOG.md → échec" "$T"
cleanup "$T"

# Référence #88 absente du BACKLOG.md dans README.md → échec
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
Prérequis : issue #88 (fictive, non présente dans le backlog).
Statut : PROJET DE SOUMISSION — l'homologation n'est pas acquise.
EOF
assert_exits_nonzero "CHECK 6+: référence #88 dans README.md absente de BACKLOG.md → échec" "$T"
cleanup "$T"

# Références présentes dans submission-checklist.md et dans BACKLOG.md → succès
T=$(make_valid_tree)
cat >> "$T/BACKLOG.md" <<'EOF'
- **#5** Analyse de conformité
- **#25** Pentest externe
- **#30** Dossier d'homologation
EOF
cat > "$T/docs/compliance/homologation-artci/submission-checklist.md" <<'EOF'
# Checklist avant dépôt ARTCI
- [ ] Sign-off juridique complet (bloc #5).
- [ ] Pentest livré et corrigé (#25).
- [ ] Dossier consolidé (#30).
EOF
assert_exits_zero "CHECK 6+: références #5, #25, #30 dans submission-checklist.md toutes présentes → succès" "$T"
cleanup "$T"

# ── CHECK 7b supplémentaire : insensibilité à la casse ────────────────────────

echo "--- CHECK 7b supplémentaire : insensibilité à la casse (flag -i) ---"

# « Serveur Déchiffre » (majuscule S, D) → violation capturée par grep -i
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/formalite-prealable.md" <<'EOF'
# Note de procédure — formalité préalable ARTCI
Nature de la formalité : [à confirmer — conseil juridique].
Architecture : le Serveur Déchiffre les données avant transmission.
EOF
assert_exits_nonzero "CHECK 7b+: 'Serveur Déchiffre' (casse mixte) → VIOLATION invariant ZK → échec" "$T"
cleanup "$T"

# « LE SERVEUR DÉCRYPTE » (tout majuscule) → violation capturée par grep -i
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
LE SERVEUR DÉCRYPTE les blobs avant stockage.
Statut : PROJET DE SOUMISSION — l'homologation n'est pas acquise.
EOF
assert_exits_nonzero "CHECK 7b+: 'LE SERVEUR DÉCRYPTE' (tout majuscules) → VIOLATION invariant ZK → échec" "$T"
cleanup "$T"

# « le serveur ne peut pas déchiffrer » en majuscules partielles → pas de violation
# « Le Serveur ne peut pas Déchiffrer » : le grep -i capturrait « serveur » et « déchiffrer »,
# mais l'invariant exige « serveur déchiffre » (actif, sans négation dans le même groupe de mots).
# Ce cas confirme que la formulation négative n'est pas bloquée même en casse mixte.
T=$(make_valid_tree)
cat > "$T/docs/compliance/homologation-artci/README.md" <<'EOF'
# Dossier d'homologation ARTCI — synthétique
Architecture zero-knowledge : Le Serveur ne peut pas Déchiffrer les blobs patients.
Statut : PROJET DE SOUMISSION — l'homologation n'est pas acquise.
EOF
assert_exits_zero "CHECK 7b+: 'Le Serveur ne peut pas Déchiffrer' (négation, casse mixte) → pas de violation" "$T"
cleanup "$T"

# ── SMOKE : le dossier livré passe le gate ────────────────────────────────────

echo "--- SMOKE : dossier livré docs/compliance/homologation-artci/ ---"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
tests_run=$((tests_run + 1))
if (cd "$REPO_ROOT" && bash scripts/check-homologation-dossier.sh >/dev/null 2>&1); then
    echo "PASS: SMOKE: le dossier d'homologation de la branche passe le gate sans modification"
else
    tests_failed=$((tests_failed + 1))
    echo "FAIL: SMOKE: le dossier d'homologation de la branche ÉCHOUE le gate"
    echo "  → relancer : bash scripts/check-homologation-dossier.sh"
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
echo "ok: tous les tests unitaires du vérificateur de dossier d'homologation ont réussi."
