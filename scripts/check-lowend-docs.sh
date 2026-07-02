#!/usr/bin/env bash
# Gate de cohérence bas de gamme (issue #29, Épic E4 — robustesse & accessibilité).
#
# Le profil d'appareil de référence + le protocole de validation vivent sous
# docs/ux/ et s'adossent à une source de vérité code
# (app-patient/lib/src/doctor/storage_budget.dart, elle-même alignée sur
# PerfBudget #27). Ce gate protège contre la DÉRIVE doc↔code et contre toute
# affirmation malhonnête que la validation terrain (deux parcours sur appareil
# Infinix réel) est acquise.
#
# Contrôles :
#   1. Structure        — docs #29 + source de vérité code requis existent.
#   2. Cohérence budget — le profil cite les constantes de storage_budget.dart ;
#                         maxQueueEntryBytes == PerfBudget.maxCompressedBlobBytes.
#   3. Références croisées — profil ↔ protocole ↔ storage_budget ; profil cite le
#                         profil réseau 3G-STABLE (#27) et l'invariant images (#23).
#   4. Contrat sécurité — aucun contournement crypto ; aucun plaintext/clé écrit ;
#                         aucun déchiffrement serveur décrit.
#   5. Honnêteté statut — « à produire » + « démarche humaine » présents ; aucune
#                         affirmation que la validation terrain est réalisée.
#   6. Traçabilité backlog — les #NN cités par les docs #29 existent dans BACKLOG.md.
#
# Style : aligné sur scripts/check-ux-docs.sh (bash, fail-closed, sections
# numérotées). Usage : bash scripts/check-lowend-docs.sh (ou : just lowend-check).
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { echo "erreur: $1" >&2; fail=1; }
ok()   { echo "ok: $1"; }

UX_DIR="docs/ux"
PROFILE="$UX_DIR/low-end-device-profile.md"
PROTOCOL="$UX_DIR/low-end-validation-protocol.md"
STORAGE="app-patient/lib/src/doctor/storage_budget.dart"
PERF="app-patient/lib/src/record/perf_budget.dart"
BACKLOG="BACKLOG.md"

# ============================================================
# CHECK 1 — Structure (docs + artefacts code)
# ============================================================
echo "--- [1/6] Structure ---"
for f in "$PROFILE" "$PROTOCOL" "$STORAGE" "$PERF"; do
  if [ -f "$f" ]; then ok "présent: $f"; else note "fichier requis manquant: $f"; fi
done

# Extraction d'une constante int Dart : `... NAME = 42;` -> 42 (depuis $1 = fichier).
dart_int() { grep -oE "$2[[:space:]]*=[[:space:]]*[0-9]+" "$1" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true; }

# ============================================================
# CHECK 2 — Cohérence du budget (profil == code == PerfBudget)
# ============================================================
echo "--- [2/6] Cohérence du budget doc↔code ---"
entry_code=$(dart_int "$STORAGE" 'maxQueueEntryBytes')
entries_code=$(dart_int "$STORAGE" 'maxPendingQueueEntries')
perf_code=$(dart_int "$PERF" 'maxCompressedBlobBytes')
if [ -z "$entry_code" ] || [ -z "$entries_code" ]; then
  note "maxQueueEntryBytes / maxPendingQueueEntries introuvable(s) dans $STORAGE"
else
  ok "budget code: maxQueueEntryBytes=$entry_code, maxPendingQueueEntries=$entries_code"
  # 2a. Le profil doit citer explicitement les mêmes valeurs (anti-dérive).
  if ! grep -qE "maxQueueEntryBytes[^0-9]*=[[:space:]]*$entry_code" "$PROFILE"; then
    note "le profil ($PROFILE) ne cite pas maxQueueEntryBytes = $entry_code (dérive doc↔code)"
  fi
  if ! grep -qE "maxPendingQueueEntries[^0-9]*=[[:space:]]*$entries_code" "$PROFILE"; then
    note "le profil ($PROFILE) ne cite pas maxPendingQueueEntries = $entries_code (dérive doc↔code)"
  fi
  # 2b. Invariant dur : la taille d'entrée == plafond de blob compressé (#27).
  if [ -z "$perf_code" ]; then
    note "maxCompressedBlobBytes introuvable dans $PERF"
  elif [ "$entry_code" != "$perf_code" ]; then
    note "maxQueueEntryBytes ($entry_code) != PerfBudget.maxCompressedBlobBytes ($perf_code) — les deux doivent rester égaux (#27)"
  else
    ok "invariant taille: maxQueueEntryBytes == PerfBudget.maxCompressedBlobBytes == $perf_code"
  fi
fi

# ============================================================
# CHECK 3 — Références croisées
# ============================================================
echo "--- [3/6] Références croisées ---"
xref=1
# 3a. Profil ↔ protocole ↔ source de vérité code.
grep -q 'low-end-validation-protocol.md' "$PROFILE" || { note "$PROFILE ne référence pas le protocole"; xref=0; }
grep -q 'low-end-device-profile.md'      "$PROTOCOL" || { note "$PROTOCOL ne référence pas le profil"; xref=0; }
grep -q 'storage_budget.dart'            "$PROFILE" || { note "$PROFILE ne référence pas storage_budget.dart"; xref=0; }
# 3b. Profil ancré sur le profil réseau perf (#27) et l'invariant images déportées (#23).
grep -q '3G-STABLE'                      "$PROFILE" || { note "$PROFILE ne cite pas le profil réseau 3G-STABLE (#27)"; xref=0; }
grep -qE 'recordCarriesNoHeavyMedia|image lourde' "$PROFILE" || { note "$PROFILE n'énonce pas l'invariant « aucune image lourde » (#23)"; xref=0; }
[ "$xref" -eq 1 ] && ok "références croisées cohérentes (profil ↔ protocole ↔ storage_budget, 3G-STABLE, #23)"

# ============================================================
# CHECK 4 — Contrat de sécurité
# ============================================================
echo "--- [4/6] Contrat de sécurité ---"
sec=1
# 4a. La source de vérité affirme n'introduire aucun changement crypto/protocole.
if ! grep -qiE 'no crypto|aucun.*crypto|NO crypto, protocol' "$STORAGE"; then
  note "$STORAGE: l'invariant « aucun changement crypto/protocole » n'est pas énoncé"; sec=0
fi
# 4b. Le protocole exige qu'aucun plaintext/clé/payload QR ne soit écrit sur disque.
if ! grep -qiE 'plaintext' "$PROTOCOL" || ! grep -qiE 'payload QR|clé' "$PROTOCOL"; then
  note "$PROTOCOL: l'invariant « aucun plaintext/clé/payload QR écrit » n'est pas énoncé"; sec=0
fi
# 4c. Invariant anti-régression : aucun doc #29 ne décrit un déchiffrement serveur.
if grep -rhiE '\bserveur[[:space:]]+(déchiffre|décrypte)' "$PROFILE" "$PROTOCOL" 2>/dev/null >/dev/null; then
  note "VIOLATION invariant — un doc #29 décrit un déchiffrement actif côté serveur"; sec=0
fi
[ "$sec" -eq 1 ] && ok "contrat de sécurité respecté (aucun changement crypto, non-persistance plaintext/clé, zero-knowledge préservé)"

# ============================================================
# CHECK 5 — Honnêteté du statut
# ============================================================
echo "--- [5/6] Honnêteté du statut ---"
honnete=1
# 5a. Les deux docs marquent le gabarit / statut « à produire ».
grep -qi 'à produire' "$PROTOCOL" || { note "$PROTOCOL: statut « à produire » absent (gabarit honnête requis)"; honnete=0; }
grep -qi 'à produire' "$PROFILE"  || { note "$PROFILE: statut « à produire » absent"; honnete=0; }
# 5b. La validation terrain est explicitement une démarche humaine restante.
grep -qiE 'démarche humaine|humaine' "$PROFILE"  || { note "$PROFILE: la validation terrain n'est pas marquée « démarche humaine »"; honnete=0; }
grep -qiE 'démarche humaine|humains?|restant'   "$PROTOCOL" || { note "$PROTOCOL: la validation terrain n'est pas marquée restante/humaine"; honnete=0; }
# 5c. Aucune affirmation que la validation terrain est réalisée/réussie.
if grep -rhniE "(parcours|validation|campagne)[[:space:]]+(patient|médecin|terrain)?[[:space:]]*(réalisé|effectué|mené|conduit|validé sur appareil réel|réussi)e?s?\b" "$PROFILE" "$PROTOCOL" 2>/dev/null \
   | grep -vE "n'|ne |pas |sera|à |restent?|non |reste|<" >/dev/null; then
  note "affirmation possible que la validation terrain est réalisée — le critère reste une démarche humaine"; honnete=0
fi
[ "$honnete" -eq 1 ] && ok "honnêteté respectée (« à produire », validation terrain = démarche humaine restante)"

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
    note "référence $ref citée dans les docs #29 mais absente de $BACKLOG"
    backlog_missing=$((backlog_missing + 1))
  fi
done < <(grep -hoE '#[0-9]+' "$PROFILE" "$PROTOCOL" 2>/dev/null | sort -t'#' -k2 -n | uniq || true)
[ "$backlog_missing" -eq 0 ] && ok "$backlog_ok référence(s) issue vérifiée(s) dans $BACKLOG"

# ============================================================
# Résultat final
# ============================================================
echo ""
if [ "$fail" -ne 0 ]; then
  echo "ECHEC: incohérences détectées dans les artefacts bas de gamme (voir ci-dessus)." >&2
  exit 1
fi
echo "ok: tous les contrôles de cohérence bas de gamme (#29) sont passés."
