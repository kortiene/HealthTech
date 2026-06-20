#!/usr/bin/env bash
# Gate de qualité des artefacts de conformité — loi n°2013-450 & exigences ARTCI.
# Issue #5 (Épic E6 — Conformité, légal & gouvernance).
#
# Contrôles :
#   1. Structure documentaire — les 8 fichiers requis sous docs/compliance/ existent.
#   2. Schéma de la matrice  — chaque ligne REQ-LEX-NN a exactement 11 colonnes.
#   3. Gate de complétude    — chaque exigence Must a CTRL-NN, PREUVE-NN (sauf Écart),
#                              un responsable et un statut ; chaque Écart est tracé dans ecarts.md.
#   4. Intégrité des liens   — tous les liens relatifs (./*, ../*, ../../*) résolvent.
#   5. Traçabilité backlog   — chaque référence #NN dans docs/compliance/ existe dans BACKLOG.md.
#   6. Invariant anti-régression conformité — aucun contrôle ne décrit un déchiffrement
#                              actif côté serveur ni un stockage de clé/PII en clair.
#   7. Gate de validation juridique — le journal couvre tous les REQ-LEX-NN ;
#                              avertit si des exigences Must sont encore en attente.
#
# Style : aligné sur scripts/check-secrets.sh (POSIX, fail-closed, sections numérotées).
# Usage : bash scripts/check-compliance-matrix.sh   (ou : just compliance-check)
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { echo "erreur: $1" >&2; fail=1; }
ok()   { echo "ok: $1"; }

COMPLIANCE_DIR="docs/compliance"
MATRIX="$COMPLIANCE_DIR/loi-2013-450-artci-matrix.md"
EXIGENCES="$COMPLIANCE_DIR/exigences-legales.md"
CONTROLES="$COMPLIANCE_DIR/controles.md"
REGISTRE="$COMPLIANCE_DIR/registre-des-traitements.md"
CARTO="$COMPLIANCE_DIR/cartographie-donnees-et-flux.md"
JOURNAL="$COMPLIANCE_DIR/journal-validation-juridique.md"
ECARTS_FILE="$COMPLIANCE_DIR/ecarts.md"
README_FILE="$COMPLIANCE_DIR/README.md"
BACKLOG="BACKLOG.md"

# ============================================================
# CHECK 1 — Structure documentaire
# ============================================================
echo "--- [1/7] Structure documentaire ---"
for f in \
  "$README_FILE" \
  "$EXIGENCES" \
  "$CONTROLES" \
  "$MATRIX" \
  "$REGISTRE" \
  "$CARTO" \
  "$JOURNAL" \
  "$ECARTS_FILE"
do
  if [ -f "$f" ]; then
    ok "présent: $f"
  else
    note "fichier requis manquant: $f"
  fi
done

# ============================================================
# CHECK 2 — Schéma de la matrice (11 colonnes affichées par ligne de données)
# ============================================================
echo "--- [2/7] Schéma de la matrice ---"
schema_ok=0
schema_errors=0
while IFS= read -r line; do
  # awk avec -F'|' : NF = fields = colonnes+2 (champs vides en tête et en queue)
  cols=$(awk -F'|' '{print NF-2}' <<< "$line")
  req=$(echo "$line" | grep -oE 'REQ-LEX-[0-9]+' | head -1 || true)
  if [ "$cols" -ne 11 ]; then
    note "${req:-ligne}: schéma invalide — $cols colonne(s), 11 attendues"
    schema_errors=$((schema_errors + 1))
  else
    schema_ok=$((schema_ok + 1))
  fi
done < <(grep -E '^\| \*\*REQ-LEX-' "$MATRIX" 2>/dev/null || true)
if [ "$schema_errors" -eq 0 ]; then
  ok "toutes les lignes REQ-LEX ont 11 colonnes ($schema_ok lignes vérifiées)"
fi

# ============================================================
# CHECK 3 — Gate de complétude (exigences Must)
# ============================================================
echo "--- [3/7] Gate de complétude ---"
must_total=0
must_complete=0
while IFS= read -r line; do
  req=$(echo "$line" | grep -oE 'REQ-LEX-[0-9]+' | head -1 || true)
  # Colonnes awk (F='|') : $1=vide $2=REQ $3=Source $4=Exigence $5=Cat. $6=M/S
  #                        $7=CTRL $8=ADR/Issue $9=Preuve $10=Statut $11=Resp. $12=Valid.jur. $13=vide
  obligation=$(awk -F'|' '{print $6}' <<< "$line")
  if ! echo "$obligation" | grep -qi "Must"; then
    continue
  fi
  must_total=$((must_total + 1))
  row_ok=1

  ctrl=$(awk  -F'|' '{print $7}'  <<< "$line")
  preuve=$(awk -F'|' '{print $9}'  <<< "$line")
  statut_raw=$(awk -F'|' '{print $10}' <<< "$line")
  resp=$(awk  -F'|' '{print $11}' <<< "$line")

  # Normaliser : supprimer le gras Markdown (**) et les espaces entourant
  statut=$(printf '%s' "$statut_raw" | tr -d '*' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  resp_trim=$(printf '%s' "$resp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Au moins un CTRL-NN requis
  if ! echo "$ctrl" | grep -qE 'CTRL-[0-9]+'; then
    note "$req (Must): aucun contrôle CTRL-NN renseigné"
    row_ok=0
  fi

  # Au moins une PREUVE-NN requise sauf si Écart (l'écart documente l'absence de preuve)
  if ! echo "$statut" | grep -qi "Écart"; then
    if ! echo "$preuve" | grep -qE 'PREUVE-[0-9]+'; then
      note "$req (Must): aucune preuve PREUVE-NN et statut non-Écart ('$statut')"
      row_ok=0
    fi
  fi

  # Responsable non vide ni tiret seul
  if [ -z "$resp_trim" ] || [ "$resp_trim" = "—" ] || [ "$resp_trim" = "-" ]; then
    note "$req (Must): responsable non renseigné"
    row_ok=0
  fi

  # Statut non vide
  if [ -z "$statut" ]; then
    note "$req (Must): statut vide"
    row_ok=0
  fi

  # Si Écart → exigence doit être tracée dans ecarts.md
  if echo "$statut" | grep -qi "Écart"; then
    if ! grep -q "$req" "$ECARTS_FILE"; then
      note "$req: statut Écart dans la matrice mais REQ-ID absent de $ECARTS_FILE"
      row_ok=0
    fi
  fi

  [ "$row_ok" -eq 1 ] && must_complete=$((must_complete + 1))
done < <(grep -E '^\| \*\*REQ-LEX-' "$MATRIX" 2>/dev/null || true)
if [ "$must_total" -gt 0 ] && [ "$must_complete" -eq "$must_total" ]; then
  ok "$must_complete/$must_total exigences Must complètes"
elif [ "$must_total" -eq 0 ]; then
  note "aucune ligne REQ-LEX Must trouvée dans $MATRIX"
fi

# ============================================================
# CHECK 4 — Intégrité des liens internes relatifs
# ============================================================
echo "--- [4/7] Intégrité des liens internes ---"
link_ok=0
link_broken=0
while IFS= read -r raw_link; do
  # Extraire le chemin cible (contenu entre `](` et `)`)
  target=$(echo "$raw_link" | sed 's/^](\(.*\))/\1/')
  # Supprimer l'ancre de fragment éventuelle (#...)
  target=$(echo "$target" | sed 's/#.*//')
  [ -z "$target" ] && continue

  # Résoudre par rapport à la racine du dépôt
  case "$target" in
    ../../*) resolved="${target#../../}" ;;      # ../../BACKLOG.md → BACKLOG.md
    ../*)    resolved="docs/${target#../}" ;;    # ../adr/0005... → docs/adr/0005...
    ./*)     resolved="$COMPLIANCE_DIR/${target#./}" ;;  # ./ecarts.md → docs/compliance/ecarts.md
    *)       resolved="$COMPLIANCE_DIR/$target" ;;
  esac

  if [ -e "$resolved" ]; then
    link_ok=$((link_ok + 1))
  else
    note "lien brisé: $raw_link → chemin résolu '$resolved' inexistant"
    link_broken=$((link_broken + 1))
  fi
done < <(grep -hoE '\]\(\.[^)]+\)' "$COMPLIANCE_DIR"/*.md 2>/dev/null | sort -u || true)
if [ "$link_broken" -eq 0 ]; then
  ok "$link_ok lien(s) relatif(s) vérifié(s) — tous résolvent"
fi

# ============================================================
# CHECK 5 — Traçabilité backlog (chaque #NN cité doit exister)
# ============================================================
echo "--- [5/7] Traçabilité backlog ---"
backlog_ok=0
backlog_missing=0
while IFS= read -r issue_ref; do
  num="${issue_ref#\#}"
  # Recherche : l'issue #NN doit apparaître dans BACKLOG.md
  # La ligne `**#NN` ou `#NN[^0-9]` couvre les définitions et les références
  if grep -qE "#${num}[^0-9]|#${num}$" "$BACKLOG" 2>/dev/null; then
    backlog_ok=$((backlog_ok + 1))
  else
    note "référence $issue_ref présente dans docs/compliance/ mais absente de $BACKLOG"
    backlog_missing=$((backlog_missing + 1))
  fi
done < <(grep -hoE '#[0-9]+' "$COMPLIANCE_DIR"/*.md 2>/dev/null | sort -t'#' -k2 -n | uniq || true)
if [ "$backlog_missing" -eq 0 ]; then
  ok "$backlog_ok référence(s) issue vérifiée(s) dans $BACKLOG"
fi

# ============================================================
# CHECK 6 — Invariant anti-régression conformité
# ============================================================
# Échoue si la matrice ou le catalogue de contrôles décrit AFFIRMATIVEMENT
# un déchiffrement actif côté serveur, un stockage de clé côté serveur,
# ou un stockage de PII/données médicales en clair.
# Les assertions négatives légitimes ("le serveur ne peut pas déchiffrer")
# ne déclenchent PAS d'erreur.
echo "--- [6/7] Invariant anti-régression conformité ---"
antireg_ok=1
for f in "$MATRIX" "$CONTROLES"; do
  [ -f "$f" ] || continue

  # 1) Déchiffrement actif CÔTÉ SERVEUR (le serveur comme sujet actif qui déchiffre)
  #    Pattern : "serveur déchiffre" / "serveur décrypte" (sans "ne" / "pas" devant)
  #    NB : "serveur ne peut pas déchiffrer" ou "le serveur ne peut pas déchiffrer"
  #    ne matchent pas (le NF "ne" intervient avant "déchiffr-").
  if grep -qiE "\bserveur[[:space:]]+(déchiffre|décrypte)[^r]" "$f" 2>/dev/null; then
    note "$f: VIOLATION invariant — décrit un déchiffrement actif côté serveur"
    antireg_ok=0
  fi

  # 2) Clé stockée/enregistrée/persistée côté serveur (affirmation positive)
  if grep -qiE "(stocker|enregistrer|persister|déposer)[[:space:]]+la[[:space:]]+(clé|key)[[:space:]]+(côté[[:space:]]+)?serveur|(clé|key)[[:space:]]+(stockée?|enregistrée?|persistée?)[[:space:]]+(côté[[:space:]]+)?serveur" "$f" 2>/dev/null; then
    note "$f: VIOLATION invariant — décrit un stockage de clé côté serveur"
    antireg_ok=0
  fi

  # 3) PII / données médicales persistées EN CLAIR (affirmation positive)
  #    Exclusion de "ne jamais ... en clair" ou "jamais ... en clair" (négations).
  if grep -qiE "(stocker|enregistrer|persister)[[:space:]].{0,50}(PII|données[[:space:]]personnelles|dossier[[:space:]]médical|données[[:space:]]de[[:space:]]santé).{0,50}en[[:space:]]clair" "$f" 2>/dev/null; then
    note "$f: VIOLATION invariant — décrit un stockage de PII/données médicales en clair"
    antireg_ok=0
  fi
done
[ "$antireg_ok" -eq 1 ] && ok "invariant anti-régression respecté (aucun déchiffrement/stockage interdit détecté)"

# ============================================================
# CHECK 7 — Gate de validation juridique
# ============================================================
echo "--- [7/7] Gate de validation juridique ---"
# Compter les exigences Must dans le registre
# `|| true` absorbe le code de sortie 1 de grep quand le compte est 0 (évite la duplication)
must_in_register=$(grep -c '| Must' "$EXIGENCES" 2>/dev/null || true)
must_in_register="${must_in_register:-0}"
# Compter celles signées sans réserve bloquante dans le journal
# Format attendu : "| REQ-LEX-NN | Must | Validé |" (sans "avec réserves")
must_signed=$(grep -cE '\| Must \| Validé \|' "$JOURNAL" 2>/dev/null || true)
must_signed="${must_signed:-0}"

# Vérifier que chaque REQ-LEX-NN du registre a une entrée dans le journal
journal_missing=0
while IFS= read -r req; do
  if ! grep -q "$req" "$JOURNAL" 2>/dev/null; then
    note "exigence $req présente dans $EXIGENCES mais absente du journal de validation"
    journal_missing=$((journal_missing + 1))
  fi
done < <(grep -oE 'REQ-LEX-[0-9]+' "$EXIGENCES" | sort -u || true)
[ "$journal_missing" -eq 0 ] && ok "toutes les exigences du registre ont une entrée dans le journal"

echo "  Exigences Must dans le registre : $must_in_register"
echo "  Exigences Must signées (Validé)  : $must_signed"

if [ "$must_in_register" -gt 0 ] && [ "$must_signed" -ge "$must_in_register" ]; then
  echo "  → Critère d'acceptation de #5 ATTEINT : matrice validée par le conseil juridique."
else
  echo "  → Matrice NON encore validée ($must_signed/$must_in_register Must signés) — en attente du conseil juridique."
fi

# Détection d'incohérence : le journal prétend « Oui » alors que des Must sont en attente
validated_claim=$(grep -c 'Matrice validée.*\*\*Oui\*\*' "$JOURNAL" 2>/dev/null || true)
validated_claim="${validated_claim:-0}"
if [ "$validated_claim" -gt 0 ] && [ "$must_signed" -lt "$must_in_register" ]; then
  note "$JOURNAL: prétend 'Matrice validée = Oui' alors que $must_signed/$must_in_register Must sont signés — incohérence"
fi

# ============================================================
# Résultat final
# ============================================================
echo ""
if [ "$fail" -ne 0 ]; then
  echo "ECHEC: violations détectées dans les artefacts de conformité (voir ci-dessus)." >&2
  exit 1
fi
echo "ok: tous les contrôles de qualité des artefacts de conformité sont passés."
