#!/usr/bin/env bash
# Gate de complétude & cohérence du dossier d'homologation ARTCI (issue #30, Épic E6).
#
# Le dossier vit sous docs/compliance/homologation-artci/. Il INDEXE des preuves
# existantes (docs/compliance/controles.md) sans les dupliquer. Ce gate protège
# contre la dérive et contre toute affirmation malhonnête de préparation.
#
# Contrôles :
#   1. Structure       — les 5 fichiers requis du dossier existent.
#   2. Pas d'orphelin  — chaque PIECE-NN de piece-list.md référence un PREUVE-NN
#                        présent dans controles.md.
#   3. Preuves obligatoires — un socle stable de PREUVE-NN apparaît dans piece-list.md.
#   4. Honnêteté statut — aucune pièce « Prête » ne s'adosse à une preuve source
#                        dont la disponibilité (controles.md) n'est pas « Existant ».
#   5. Intégrité liens — tous les liens relatifs du dossier résolvent.
#   6. Traçabilité backlog — chaque #NN cité dans le dossier existe dans BACKLOG.md.
#   7. Honnêteté globale — aucune affirmation « homologation obtenue/acquise » ;
#                        aucun contrôle décrivant un déchiffrement serveur / clé / PII en clair.
#
# Style : aligné sur scripts/check-compliance-matrix.sh (POSIX, fail-closed, sections numérotées).
# Usage : bash scripts/check-homologation-dossier.sh   (ou : just homologation-check)
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { echo "erreur: $1" >&2; fail=1; }
ok()   { echo "ok: $1"; }

DOSSIER="docs/compliance/homologation-artci"
CONTROLES="docs/compliance/controles.md"
BACKLOG="BACKLOG.md"

README_FILE="$DOSSIER/README.md"
PIECE_LIST="$DOSSIER/piece-list.md"
DASHBOARD="$DOSSIER/readiness-dashboard.md"
FORMALITE="$DOSSIER/formalite-prealable.md"
CHECKLIST="$DOSSIER/submission-checklist.md"

# Preuves-socle attendues comme pièces transmissibles du dossier.
MANDATORY_PREUVES="PREUVE-05 PREUVE-13 PREUVE-14 PREUVE-16 PREUVE-17 PREUVE-18"

# ============================================================
# CHECK 1 — Structure du dossier
# ============================================================
echo "--- [1/7] Structure du dossier ---"
for f in "$README_FILE" "$PIECE_LIST" "$DASHBOARD" "$FORMALITE" "$CHECKLIST"; do
  if [ -f "$f" ]; then ok "présent: $f"; else note "fichier requis manquant: $f"; fi
done

# ============================================================
# CHECK 2 — Pas de pièce orpheline (PIECE-NN → PREUVE-NN existant dans controles.md)
# ============================================================
echo "--- [2/7] Pas de pièce orpheline ---"
piece_rows=0
piece_orphans=0
while IFS= read -r line; do
  piece=$(echo "$line" | grep -oE 'PIECE-[0-9]+' | head -1 || true)
  [ -z "$piece" ] && continue
  piece_rows=$((piece_rows + 1))
  preuve=$(echo "$line" | grep -oE 'PREUVE-[0-9]+' | head -1 || true)
  if [ -z "$preuve" ]; then
    note "$piece: aucune preuve source PREUVE-NN"
    piece_orphans=$((piece_orphans + 1))
    continue
  fi
  if ! grep -qE "\*\*$preuve\*\*|\| $preuve " "$CONTROLES" 2>/dev/null; then
    note "$piece: preuve source $preuve absente de $CONTROLES"
    piece_orphans=$((piece_orphans + 1))
  fi
done < <(grep -E '^\| \*\*PIECE-' "$PIECE_LIST" 2>/dev/null || true)
if [ "$piece_orphans" -eq 0 ] && [ "$piece_rows" -gt 0 ]; then
  ok "$piece_rows pièce(s) — toutes adossées à une preuve existante"
elif [ "$piece_rows" -eq 0 ]; then
  note "aucune ligne PIECE-NN trouvée dans $PIECE_LIST"
fi

# ============================================================
# CHECK 3 — Preuves obligatoires présentes dans piece-list.md
# ============================================================
echo "--- [3/7] Preuves obligatoires présentes ---"
missing_mandatory=0
for p in $MANDATORY_PREUVES; do
  if ! grep -q "$p" "$PIECE_LIST" 2>/dev/null; then
    note "preuve obligatoire $p absente de $PIECE_LIST"
    missing_mandatory=$((missing_mandatory + 1))
  fi
done
[ "$missing_mandatory" -eq 0 ] && ok "socle de preuves obligatoires présent ($MANDATORY_PREUVES)"

# ============================================================
# CHECK 4 — Honnêteté de statut (« Prête » ⇒ preuve source « Existant »)
# ============================================================
echo "--- [4/7] Honnêteté de statut ---"
# Une preuve est « Existant » si sa ligne dans controles.md contient le token
# capitalisé « Existant » (case-sensitive : « cadre existant » minuscule ne compte pas).
preuve_is_existant() {
  local p="$1"
  grep -E "\| \*\*$p\*\* \|" "$CONTROLES" 2>/dev/null | grep -q 'Existant'
}
honesty_violations=0
while IFS= read -r line; do
  # Ligne de pièce marquée « Prête » (hors en-tête de règle de dérivation).
  echo "$line" | grep -qE '^\| \*\*PIECE-' || continue
  echo "$line" | grep -q 'Prête' || continue
  piece=$(echo "$line" | grep -oE 'PIECE-[0-9]+' | head -1)
  preuve=$(echo "$line" | grep -oE 'PREUVE-[0-9]+' | head -1 || true)
  if [ -z "$preuve" ] || ! preuve_is_existant "$preuve"; then
    note "$piece marquée « Prête » mais sa preuve source ${preuve:-?} n'est pas « Existant » dans $CONTROLES"
    honesty_violations=$((honesty_violations + 1))
  fi
done < <(grep -E '^\| \*\*PIECE-' "$PIECE_LIST" 2>/dev/null || true)
[ "$honesty_violations" -eq 0 ] && ok "aucune pièce « Prête » adossée à une preuve non « Existant »"

# ============================================================
# CHECK 5 — Intégrité des liens relatifs du dossier
# ============================================================
echo "--- [5/7] Intégrité des liens relatifs ---"
link_ok=0
link_broken=0
for f in "$DOSSIER"/*.md; do
  [ -f "$f" ] || continue
  dir=$(dirname "$f")
  while IFS= read -r target; do
    target="${target%%#*}"   # retirer l'ancre de fragment
    [ -z "$target" ] && continue
    if (cd "$dir" && [ -e "$target" ]); then
      link_ok=$((link_ok + 1))
    else
      note "lien brisé dans $f: '$target'"
      link_broken=$((link_broken + 1))
    fi
  done < <(grep -oE '\]\(\.[^)]+\)' "$f" | sed 's/^](\(.*\))$/\1/' | sort -u || true)
done
[ "$link_broken" -eq 0 ] && ok "$link_ok lien(s) relatif(s) vérifié(s) — tous résolvent"

# ============================================================
# CHECK 6 — Traçabilité backlog (#NN cités présents dans BACKLOG.md)
# ============================================================
echo "--- [6/7] Traçabilité backlog ---"
backlog_ok=0
backlog_missing=0
while IFS= read -r ref; do
  num="${ref#\#}"
  if grep -qE "#${num}[^0-9]|#${num}$" "$BACKLOG" 2>/dev/null; then
    backlog_ok=$((backlog_ok + 1))
  else
    note "référence $ref citée dans le dossier mais absente de $BACKLOG"
    backlog_missing=$((backlog_missing + 1))
  fi
done < <(grep -hoE '#[0-9]+' "$DOSSIER"/*.md 2>/dev/null | sort -t'#' -k2 -n | uniq || true)
[ "$backlog_missing" -eq 0 ] && ok "$backlog_ok référence(s) issue vérifiée(s) dans $BACKLOG"

# ============================================================
# CHECK 7 — Honnêteté globale (pas d'homologation « obtenue » ; invariant crypto)
# ============================================================
echo "--- [7/7] Honnêteté globale & invariant conformité ---"
honnete=1
# 7a. Aucune affirmation positive que l'homologation est obtenue/acquise.
#     Les tournures négatives ("n'est pas acquise", "non acquise") ne matchent pas.
if grep -rhnE "homologation[[:space:]]+(est[[:space:]]+)?(obtenue|acquise)" "$DOSSIER"/*.md 2>/dev/null \
   | grep -vE "n'|ne |non |pas (acquise|obtenue)|lorsque|que lorsque|uniquement|prérequis" >/dev/null; then
  note "affirmation possible que l'homologation est obtenue/acquise — à vérifier (le dossier est un PROJET)"
  honnete=0
fi
# 7b. Invariant anti-régression : aucun déchiffrement serveur actif décrit dans le dossier.
if grep -rhiE "\bserveur[[:space:]]+(déchiffre|décrypte)[^r]" "$DOSSIER"/*.md 2>/dev/null >/dev/null; then
  note "VIOLATION invariant — le dossier décrit un déchiffrement actif côté serveur"
  honnete=0
fi
[ "$honnete" -eq 1 ] && ok "honnêteté globale respectée (aucune homologation prématurée, aucun déchiffrement serveur)"

# ============================================================
# Résultat final
# ============================================================
echo ""
if [ "$fail" -ne 0 ]; then
  echo "ECHEC: violations détectées dans le dossier d'homologation (voir ci-dessus)." >&2
  exit 1
fi
echo "ok: tous les contrôles de complétude/cohérence du dossier d'homologation sont passés."
