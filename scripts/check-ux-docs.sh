#!/usr/bin/env bash
# Gate de cohérence de la norme UX médecin (issue #28, Épic E4 — NFR UX).
#
# La norme UX vit sous docs/ux/ (guide normatif + protocole de test utilisateur)
# et s'adosse à une source de vérité code (app-patient/lib/src/doctor/ux_budget.dart,
# task_timing.dart). Ce gate protège contre la DÉRIVE doc↔code et contre toute
# affirmation malhonnête que la preuve terrain « < 5 min » est acquise.
#
# Contrôles :
#   1. Structure       — docs UX + artefacts code requis existent.
#   2. Cohérence budget — les valeurs du guide (max étapes/écrans) == ux_budget.dart.
#   3. Labels canoniques — scan/read/edit/terminate présents dans le code ET le guide.
#   4. Contrat sécurité — instrumentation désactivée par défaut ; aucun log de
#                        plaintext/clé/PII ; aucun déchiffrement serveur décrit.
#   5. Honnêteté statut — protocole marqué « à produire » ; proxy machine != preuve
#                        humaine ; aucune affirmation que le test terrain est réalisé.
#   6. Traçabilité backlog — les #NN cités par les docs UX existent dans BACKLOG.md.
#
# Style : aligné sur scripts/check-homologation-dossier.sh (bash, fail-closed,
# sections numérotées). Usage : bash scripts/check-ux-docs.sh (ou : just ux-check).
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { echo "erreur: $1" >&2; fail=1; }
ok()   { echo "ok: $1"; }

UX_DIR="docs/ux"
GUIDE="$UX_DIR/medecin-ux-guidelines.md"
PROTOCOL="$UX_DIR/usability-test-protocol.md"
UX_README="$UX_DIR/README.md"
BUDGET="app-patient/lib/src/doctor/ux_budget.dart"
TIMING="app-patient/lib/src/doctor/task_timing.dart"
BACKLOG="BACKLOG.md"

CANONICAL_STEPS="scan read edit terminate"

# ============================================================
# CHECK 1 — Structure (docs + artefacts code)
# ============================================================
echo "--- [1/6] Structure ---"
for f in "$GUIDE" "$PROTOCOL" "$UX_README" "$BUDGET" "$TIMING"; do
  if [ -f "$f" ]; then ok "présent: $f"; else note "fichier requis manquant: $f"; fi
done

# Extraction d'une constante int Dart : `static const int NAME = 42;` -> 42
dart_int() { grep -oE "$1[[:space:]]*=[[:space:]]*[0-9]+" "$BUDGET" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true; }

# ============================================================
# CHECK 2 — Cohérence du budget (guide == code)
# ============================================================
echo "--- [2/6] Cohérence du budget doc↔code ---"
steps_code=$(dart_int 'maxConsultationSteps')
screens_code=$(dart_int 'maxConsultationScreens')
if [ -z "$steps_code" ] || [ -z "$screens_code" ]; then
  note "maxConsultationSteps / maxConsultationScreens introuvable(s) dans $BUDGET"
else
  ok "budget code: maxConsultationSteps=$steps_code, maxConsultationScreens=$screens_code"
  # Le guide doit énoncer explicitement les mêmes valeurs (protège contre la dérive).
  if ! grep -qE "maxConsultationSteps.*=[[:space:]]*$steps_code" "$GUIDE"; then
    note "le guide ($GUIDE) ne cite pas maxConsultationSteps = $steps_code (dérive doc↔code)"
  fi
  if ! grep -qE "maxConsultationScreens.*=[[:space:]]*$screens_code" "$GUIDE"; then
    note "le guide ($GUIDE) ne cite pas maxConsultationScreens = $screens_code (dérive doc↔code)"
  fi
  # Cohérence interne : 4 étapes, 3 écrans (terminate ne rouvre pas d'écran).
  steps_count=$(echo "$CANONICAL_STEPS" | wc -w | tr -d ' ')
  if [ "$steps_code" != "$steps_count" ]; then
    note "maxConsultationSteps ($steps_code) != nombre d'étapes canoniques ($steps_count)"
  fi
fi

# ============================================================
# CHECK 3 — Labels canoniques présents (code + guide)
# ============================================================
echo "--- [3/6] Labels canoniques ---"
missing_labels=0
for s in $CANONICAL_STEPS; do
  grep -qE "'$s'" "$BUDGET"    || { note "label canonique '$s' absent de $BUDGET"; missing_labels=$((missing_labels+1)); }
  grep -qE "\b$s\b" "$GUIDE"   || { note "label canonique '$s' absent du guide $GUIDE"; missing_labels=$((missing_labels+1)); }
done
[ "$missing_labels" -eq 0 ] && ok "labels canoniques cohérents ($CANONICAL_STEPS) — code + guide"

# ============================================================
# CHECK 4 — Contrat de sécurité de l'instrumentation
# ============================================================
echo "--- [4/6] Contrat de sécurité ---"
sec=1
# 4a. Désactivée par défaut (production-safe).
if ! grep -qE 'enabled[[:space:]]*=[[:space:]]*false' "$TIMING"; then
  note "$TIMING: l'instrumentation n'est pas désactivée par défaut (enabled = false attendu)"; sec=0
fi
# 4b. Le contrat « labels + durées uniquement » est documenté dans le guide.
if ! grep -qiE 'jamais.*(donnée médicale|PII|clé)' "$GUIDE"; then
  note "$GUIDE: le contrat de non-journalisation (donnée médicale/clé/PII) n'est pas énoncé"; sec=0
fi
# 4c. Invariant anti-régression : aucun déchiffrement serveur décrit dans la norme UX.
if grep -rhiE '\bserveur[[:space:]]+(déchiffre|décrypte)' "$UX_DIR"/*.md 2>/dev/null >/dev/null; then
  note "VIOLATION invariant — un doc UX décrit un déchiffrement actif côté serveur"; sec=0
fi
[ "$sec" -eq 1 ] && ok "contrat de sécurité respecté (instrument off par défaut, non-journalisation documentée, zero-knowledge préservé)"

# ============================================================
# CHECK 5 — Honnêteté du statut (preuve humaine != proxy machine)
# ============================================================
echo "--- [5/6] Honnêteté du statut ---"
honnete=1
# 5a. Le protocole marque le compte-rendu comme « à produire ».
grep -qi 'à produire' "$PROTOCOL" || { note "$PROTOCOL: statut « à produire » absent (le gabarit doit rester honnête)"; honnete=0; }
# 5b. Le proxy machine est explicitement distingué de la preuve humaine : le guide
#     qualifie le garde-fou de « signal de régression » ET parle de « preuve »
#     humaine, et le code source de vérité porte la même mise en garde.
if ! grep -qi 'signal de régression' "$GUIDE" || ! grep -qi 'preuve' "$GUIDE"; then
  note "distinction proxy machine / preuve humaine « < 5 min » non explicite dans $GUIDE"; honnete=0
fi
if ! grep -qiE 'signal|proof|preuve' "$BUDGET"; then
  note "$BUDGET: la mise en garde proxy-machine-!=-preuve-humaine est absente"; honnete=0
fi
# 5c. Aucune affirmation que la campagne terrain est réalisée/réussie.
if grep -rhniE "(test|campagne)[[:space:]]+(utilisateur|terrain|d'utilisabilité)[[:space:]]+(réalisé|effectué|mené|conduit|passé|réussi)e?s?\b" "$UX_DIR"/*.md 2>/dev/null \
   | grep -vE "n'|ne |pas |sera|à |restent?|non " >/dev/null; then
  note "affirmation possible que le test terrain est réalisé — le critère reste une démarche humaine"; honnete=0
fi
[ "$honnete" -eq 1 ] && ok "honnêteté respectée (campagne « à produire », proxy machine != preuve humaine)"

# ============================================================
# CHECK 6 — Traçabilité backlog (#NN cités présents dans BACKLOG.md)
# ============================================================
echo "--- [6/6] Traçabilité backlog ---"
backlog_ok=0
backlog_missing=0
while IFS= read -r ref; do
  num="${ref#\#}"
  if grep -qE "#${num}([^0-9]|$)" "$BACKLOG" 2>/dev/null; then
    backlog_ok=$((backlog_ok + 1))
  else
    note "référence $ref citée dans docs/ux/ mais absente de $BACKLOG"
    backlog_missing=$((backlog_missing + 1))
  fi
done < <(grep -hoE '#[0-9]+' "$UX_DIR"/*.md 2>/dev/null | sort -t'#' -k2 -n | uniq || true)
[ "$backlog_missing" -eq 0 ] && ok "$backlog_ok référence(s) issue vérifiée(s) dans $BACKLOG"

# ============================================================
# Résultat final
# ============================================================
echo ""
if [ "$fail" -ne 0 ]; then
  echo "ECHEC: incohérences détectées dans la norme UX (voir ci-dessus)." >&2
  exit 1
fi
echo "ok: tous les contrôles de cohérence de la norme UX médecin sont passés."
