#!/usr/bin/env bash
# Gate de qualité du modèle de menace STRIDE — issue #6.
#
# Contrôles :
#   1. Structure documentaire   — les 2 fichiers requis existent.
#   2. Couverture des 5 menaces — THR-01..05 (nommées dans l'issue) présentes.
#   3. Traçabilité Must         — chaque menace Must a une référence d'issue (#NN).
#   4. Invariant zero-knowledge — aucune contre-mesure ne décrit de backdoor serveur.
#   5. Intégrité des liens      — les liens relatifs résolvent.
#   6. Traçabilité backlog      — chaque #NN cité existe dans BACKLOG.md.
#
# Usage : bash scripts/check-threat-model.sh   (ou intégré dans just compliance-check)
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { echo "erreur: $1" >&2; fail=1; }
ok()   { echo "ok: $1"; }

THREAT_MODEL="docs/threat-model/stride-threat-model.md"
SECURITY_MD="SECURITY.md"
BACKLOG="BACKLOG.md"

# ============================================================
# CHECK 1 — Structure documentaire
# ============================================================
echo "--- [1/6] Structure documentaire ---"
for f in "$THREAT_MODEL" "$SECURITY_MD"; do
  if [ -f "$f" ]; then
    ok "présent: $f"
  else
    note "fichier requis manquant: $f"
  fi
done

# ============================================================
# CHECK 2 — Couverture des 5 menaces nommées dans l'issue #6
# ============================================================
echo "--- [2/6] Couverture des menaces nommées (issue #6) ---"
declare -A REQUIRED_THREATS=(
  ["THR-01"]="Vol de téléphone"
  ["THR-02"]="Serveur compromis"
  ["THR-03"]="MITM réseau"
  ["THR-04"]="QR code intercepté"
  ["THR-05"]="Attaque sur la phrase de passe"
)

[ -f "$THREAT_MODEL" ] || { note "modèle manquant — skip check 2"; }

if [ -f "$THREAT_MODEL" ]; then
  for id in "${!REQUIRED_THREATS[@]}"; do
    label="${REQUIRED_THREATS[$id]}"
    if grep -q "$id" "$THREAT_MODEL"; then
      ok "menace $id présente (${label})"
    else
      note "menace $id absente du threat model (${label})"
    fi
  done
fi

# ============================================================
# CHECK 3 — Traçabilité Must : chaque THR marqué Must a au moins un #NN
# ============================================================
echo "--- [3/6] Traçabilité Must → issue ---"
if [ -f "$THREAT_MODEL" ]; then
  # Extraire les lignes de la table de synthèse (section 5) avec **Must**
  must_traced=0
  must_missing=0
  while IFS= read -r line; do
    # Cherche une colonne Must dans la table de synthèse
    if ! echo "$line" | grep -q "\*\*Must\*\*"; then
      continue
    fi
    # Vérifie qu'un #NN est présent sur la même ligne
    if echo "$line" | grep -qE '#[0-9]+'; then
      must_traced=$((must_traced + 1))
    else
      thr=$(echo "$line" | grep -oE 'THR-[0-9]+' | head -1 || true)
      note "${thr:-ligne Must}: aucun #NN de backlog tracé pour cette menace Must"
      must_missing=$((must_missing + 1))
    fi
  done < <(grep -E '\*\*Must\*\*' "$THREAT_MODEL" 2>/dev/null || true)

  if [ "$must_missing" -eq 0 ] && [ "$must_traced" -gt 0 ]; then
    ok "$must_traced menace(s) Must tracée(s) vers des issues backlog"
  elif [ "$must_traced" -eq 0 ] && [ "$must_missing" -eq 0 ]; then
    note "aucune ligne **Must** trouvée dans le tableau de synthèse de $THREAT_MODEL"
  fi
fi

# ============================================================
# CHECK 4 — Invariant zero-knowledge / no-backdoor
# ============================================================
echo "--- [4/6] Invariant zero-knowledge & no-backdoor ---"
inv_ok=1
for f in "$THREAT_MODEL" "$SECURITY_MD"; do
  [ -f "$f" ] || continue

  # Pas de déchiffrement actif côté serveur décrit positivement
  if grep -qiE "\bserveur[[:space:]]+(déchiffre|décrypte)[^r]" "$f" 2>/dev/null; then
    note "$f: VIOLATION — décrit un déchiffrement actif côté serveur"
    inv_ok=0
  fi

  # Pas de backdoor introduite : flag uniquement si une ligne mentionne backdoor/porte dérobée
  # SANS négation sur la même ligne (aucune, jamais, pas de, ne pas, interdit, refus, never).
  # Les rejets explicites ("aucune backdoor", "jamais de porte dérobée") ne déclenchent pas d'erreur.
  if grep -iE "backdoor|porte[[:space:]]+dérobée" "$f" 2>/dev/null \
     | grep -qivE "aucune|jamais|pas[[:space:]]+de|ne[[:space:]]+pas|interdit|refus|never|ne[[:space:]]+sera[[:space:]]+pas|n'est[[:space:]]+introduite|potentielle|composants[[:space:]]+exposés|risque"; then
    note "$f: VIOLATION — décrit l'introduction affirmative d'une backdoor serveur"
    inv_ok=0
  fi
done
[ "$inv_ok" -eq 1 ] && ok "invariant zero-knowledge/no-backdoor respecté"

# ============================================================
# CHECK 5 — Intégrité des liens relatifs
# ============================================================
echo "--- [5/6] Intégrité des liens relatifs ---"
link_ok=0
link_broken=0
for f in "$THREAT_MODEL" "$SECURITY_MD"; do
  [ -f "$f" ] || continue
  dir=$(dirname "$f")
  while IFS= read -r raw_link; do
    target=$(echo "$raw_link" | sed 's/^](\(.*\))/\1/')
    target=$(echo "$target" | sed 's/#.*//')
    [ -z "$target" ] && continue
    # Résoudre relativement au fichier source
    case "$target" in
      /*) resolved="${target#/}" ;;
      *)  resolved="$dir/$target" ;;
    esac
    # Nettoyer les ./ et ../
    resolved=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$resolved" 2>/dev/null || echo "$resolved")
    if [ -e "$resolved" ]; then
      link_ok=$((link_ok + 1))
    else
      note "lien brisé dans $f : $raw_link → '$resolved' inexistant"
      link_broken=$((link_broken + 1))
    fi
  done < <(grep -oE '\]\(\.[^)]+\)' "$f" 2>/dev/null | sort -u || true)
done
[ "$link_broken" -eq 0 ] && ok "$link_ok lien(s) relatif(s) vérifié(s) — tous résolvent"

# ============================================================
# CHECK 6 — Traçabilité backlog (#NN dans le threat model)
# ============================================================
echo "--- [6/6] Traçabilité backlog ---"
backlog_ok=0
backlog_missing=0
for f in "$THREAT_MODEL" "$SECURITY_MD"; do
  [ -f "$f" ] || continue
  while IFS= read -r issue_ref; do
    num="${issue_ref#\#}"
    if grep -qE "#${num}[^0-9]|#${num}$" "$BACKLOG" 2>/dev/null; then
      backlog_ok=$((backlog_ok + 1))
    else
      note "référence $issue_ref dans $f absente de $BACKLOG"
      backlog_missing=$((backlog_missing + 1))
    fi
  done < <(grep -oE '#[0-9]+' "$f" 2>/dev/null | sort -t'#' -k2 -n | uniq || true)
done
if [ "$backlog_missing" -eq 0 ]; then
  ok "$backlog_ok référence(s) issue vérifiée(s) dans $BACKLOG"
fi

# ============================================================
# Résultat final
# ============================================================
echo ""
if [ "$fail" -ne 0 ]; then
  echo "ECHEC: violations détectées dans le modèle de menace (voir ci-dessus)." >&2
  exit 1
fi
echo "ok: tous les contrôles de qualité du modèle de menace sont passés."
