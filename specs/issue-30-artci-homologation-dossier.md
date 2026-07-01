# Dossier d'homologation ARTCI (issue #30)

> **Épic :** E6 — Homologation & lancement · **Jalon :** M4 — Durcissement & lancement
> **Effort :** L · **Priorité :** Must · **Étiquettes :** `compliance` `docs`
> **Dépend de :** #5 (analyse de conformité loi n°2013-450 / ARTCI) et #25 (audit de sécurité & pentest externe).
> **Langue faisant foi :** **français** (droit ivoirien francophone ; le conseil juridique et l'ARTCI travaillent sur le texte français) — cohérent avec [`docs/compliance/README.md`](../docs/compliance/README.md).

Ceci est un **document de planification**. Il ne modifie aucun code applicatif et n'affaiblit aucun contrôle. Il décrit **comment constituer, vérifier et soumettre** le dossier d'homologation ARTCI à partir des preuves déjà produites, et **ce qui reste bloquant** avant qu'une soumission — et *a fortiori* l'homologation — soit honnêtement possible.

---

## Problem Statement

Le PRD (§1, §5) fait de l'**homologation ARTCI à 100 % avant le lancement commercial** un KPI de conformité non négociable (loi ivoirienne n°2013-450 du 19 juin 2013 relative à la protection des données à caractère personnel). Le projet a déjà produit, de façon dispersée, une grande partie des **pièces probantes** requises :

- une **matrice de conformité** `exigence → contrôle → preuve` et ses artefacts d'appui ([`docs/compliance/`](../docs/compliance/README.md), issue #5) ;
- un **registre des traitements**, une **cartographie données/flux**, un **modèle d'attestation de localisation** ;
- un **modèle de menace STRIDE**, une **revue crypto interne**, un **périmètre de pentest externe** et une **suite de tests de régression sécurité** (issues #6, #10, #25, #26).

Il manque aujourd'hui **trois choses** :

1. Un **dossier de soumission consolidé** — un point d'entrée unique qui indexe chaque pièce, sa version, son statut, son propriétaire, et l'exigence ARTCI qu'elle couvre — sous une forme directement transmissible à l'ARTCI et au conseil juridique.
2. Une **procédure de formalité préalable** documentée (déclaration vs autorisation préalable pour données de santé — encore à trancher juridiquement, [ECART-05](../docs/compliance/ecarts.md)), avec la **checklist de complétude** conditionnant la soumission.
3. Un **tableau de bord de préparation (readiness)** honnête, qui trace ce qui est *prêt*, *partiel*, *planifié* ou *bloquant*, de sorte que personne ne puisse croire l'homologation acquise alors que **0/22 exigences `Must` sont juridiquement validées** et que l'**attestation de localisation n'est pas signée** (opérateur souverain #8 non contracté).

Sans ce dossier consolidé, les preuves existent mais ne forment pas un livrable soumissible, et le chemin critique de lancement (`… → #25 → #30 → #31`) reste bloqué de façon opaque.

---

## Goals

1. **Créer le dossier d'homologation consolidé** sous [`docs/compliance/homologation-artci/`](../docs/compliance/) : un `README.md` maître (sommaire du dossier), une **liste des pièces** (`piece-list`) indexant chaque preuve, une **checklist de soumission**, et une **note de procédure de formalité préalable**.
2. **Réutiliser sans les dupliquer** les artefacts existants de #5, #6, #25, #26, #8 : le dossier **référence** (liens relatifs) et **statue** (prêt / partiel / à produire / bloquant), il ne recopie pas leur contenu.
3. **Établir un tableau de bord de readiness** dérivé du catalogue de preuves (`PREUVE-01 … PREUVE-29`) et du journal de validation juridique, avec une **règle d'honnêteté** : aucune pièce n'est marquée « prête » tant qu'elle n'est pas livrée **et** vérifiée.
4. **Documenter la procédure de soumission ARTCI** : nature de la formalité (à confirmer juridiquement), destinataire, format attendu, pièces obligatoires, et suivi du **récépissé / décision d'autorisation** (`PREUVE-13`, aujourd'hui « À produire »).
5. **Rendre les bloqueurs explicites** : lister, tracés vers leur issue/écart, tous les prérequis non satisfaits (sign-off juridique, attestation signée, pentest exécuté, écarts ECART-01…08) qui empêchent une soumission complète.
6. **Ajouter une vérification anti-régression** légère (gate de complétude/traçabilité du dossier) cohérente avec l'outillage de #5, **sans figer la stack** (#3).

---

## Non-Goals

- **Ne pas** exécuter la formalité elle-même auprès de l'ARTCI (dépôt, échanges, obtention du récépissé) : c'est une démarche **humaine/juridique externe** hors du périmètre d'un agent de code.
- **Ne pas** produire l'**avis juridique** ni interpréter le droit ivoirien : le conseil juridique reste responsable de l'exactitude des citations et du sign-off ([journal de validation](../docs/compliance/journal-validation-juridique.md)).
- **Ne pas** réaliser le **pentest externe** (#25) ni la **revue crypto indépendante** (#26) ; le dossier ne fait qu'indexer leurs livrables une fois produits.
- **Ne pas** signer l'**attestation de localisation** (#8.2) ni choisir l'opérateur souverain (#8/P0) : hors périmètre, décision de procurement.
- **Ne pas** résoudre les écarts ECART-01…08 (rétention, effacement, notification de violation, DPO, rôles RT/sous-traitant, base légale de localisation, break-glass) : ce sont des issues distinctes ; le dossier les **suit**.
- **Ne pas** modifier la cryptographie, le modèle zero-knowledge, ou tout code applicatif.
- **Ne pas** créer/committer/ouvrir d'issues GitHub (orchestration hors de cette phase).

---

## Relevant Repository Context

**Statut global.** Le projet est *greenfield côté fonctionnel* mais le corpus **conformité/sécurité est mûr et déjà en dépôt**. Le dossier #30 est essentiellement un **travail d'assemblage documentaire** au-dessus de pièces existantes.

**Décisions de stack encore ouvertes (#1).** Le langage, le framework et l'outillage de build/test/CI ne sont pas figés. **Aucun choix de ce spec ne doit présumer une stack.** Le dossier est du Markdown pur ; toute vérification automatisée (lint liens, gate de complétude) est décrite de façon **agnostique** et son outillage concret reste à confirmer avec #3 (maquette house-style : script POSIX dans [`scripts/`](../scripts/) câblé via une recette `just`, cf. `just secrets-lint`, `just infra-residency`).

**Artefacts sources déjà présents (à référencer, pas à dupliquer) :**

| Source | Chemin | Rôle pour #30 |
| --- | --- | --- |
| Volet conformité (#5) | [`docs/compliance/README.md`](../docs/compliance/README.md) | Méthodologie, conventions d'ID (`REQ-LEX`, `CTRL`, `PREUVE`, `ECART`), statuts honnêtes. |
| Exigences légales | [`docs/compliance/exigences-legales.md`](../docs/compliance/exigences-legales.md) | 22 `Must` (+1 `Must [à confirmer]`), 2 `Should` : couverture à démontrer. |
| Contrôles & preuves | [`docs/compliance/controles.md`](../docs/compliance/controles.md) | Catalogue `CTRL-NN` + `PREUVE-01…29` : **socle du tableau de readiness**. |
| Matrice de conformité | [`docs/compliance/loi-2013-450-artci-matrix.md`](../docs/compliance/loi-2013-450-artci-matrix.md) | Pièce maîtresse `exigence → contrôle → preuve → statut → responsable → validation`. |
| Registre des traitements | [`docs/compliance/registre-des-traitements.md`](../docs/compliance/registre-des-traitements.md) | `PREUVE-17`, pièce obligatoire du dossier. |
| Cartographie données/flux | [`docs/compliance/cartographie-donnees-et-flux.md`](../docs/compliance/cartographie-donnees-et-flux.md) | `PREUVE-18`, frontière zero-knowledge. |
| Attestation de localisation | [`docs/compliance/attestation-localisation-donnees.md`](../docs/compliance/attestation-localisation-donnees.md) | `PREUVE-05` — **modèle prêt, non signé** (dépend de #8). |
| Journal de validation juridique | [`docs/compliance/journal-validation-juridique.md`](../docs/compliance/journal-validation-juridique.md) | **Critère bloquant** : 0/22 `Must` validées à ce jour. |
| Registre des écarts | [`docs/compliance/ecarts.md`](../docs/compliance/ecarts.md) | ECART-01…08 à suivre dans le dossier. |
| Modèle de menace STRIDE (#6) | [`docs/threat-model/stride-threat-model.md`](../docs/threat-model/stride-threat-model.md) | `PREUVE-16`. |
| Revue crypto interne (#10) | [`docs/security/crypto-core-review.md`](../docs/security/crypto-core-review.md) | Appui `PREUVE-01`. |
| Brief revue crypto indépendante (#26) | [`docs/security/independent-crypto-review-brief.md`](../docs/security/independent-crypto-review-brief.md) | `PREUVE-15` (avis à produire). |
| Périmètre pentest (#25) | [`docs/security/pentest-scope.md`](../docs/security/pentest-scope.md) | Cadre de `PREUVE-14` (rapport à produire par l'équipe externe). |
| Consentement / transparence (#7) | [`docs/legal/consent-v1.md`](../docs/legal/consent-v1.md) | `PREUVE-11`/`PREUVE-27` (**draft**, validation juridique à obtenir). |
| ADR | [`docs/adr/`](../docs/adr/0000-index.md) | Décisions justifiant les contrôles (0005 stockage/hébergement, 0007 secrets, 0009 opérateur, 0010 sync). |
| Specs sœurs | [`specs/loi-2013-450-artci-compliance-matrix.md`](./loi-2013-450-artci-compliance-matrix.md), [`specs/issue-25-security-audit-pentest.md`](./issue-25-security-audit-pentest.md), [`specs/issue-26-independent-crypto-review.md`](./issue-26-independent-crypto-review.md) | Modèles de style/format à suivre. |

**Convention de statuts (héritée de #5, à réemployer telle quelle) :** `Conforme` (livré + preuve vérifiée), `Partiel`, `Planifié`, `Écart`. La **validation juridique** est une colonne **distincte** du statut technique. Règle d'or : on n'affirme jamais « Conforme »/« prêt » pour une pièce non livrée et non prouvée, et **aucun contrôle n'implique un déchiffrement serveur ni un stockage de clé/PII en clair**.

---

## Proposed Implementation

Créer un sous-répertoire **`docs/compliance/homologation-artci/`** rassemblant le dossier de soumission. Chaque fichier est du Markdown, référence les pièces sources par **liens relatifs**, et statue sans dupliquer le contenu.

### 1. `README.md` — sommaire maître du dossier

Point d'entrée unique et transmissible. Contient :

- **Objet & destinataire** : dossier d'homologation ARTCI pour la plateforme HealthTech (loi n°2013-450), sous quelle **formalité** (déclaration / autorisation préalable — *à confirmer juridiquement*, voir §note-formalité et [ECART-05](../docs/compliance/ecarts.md)).
- **Résumé exécutif (1 page)** de l'architecture opposable : local-first / zero-knowledge, AES-256-GCM client, QR éphémère ~120 s, RAM-only + wipe, résidence CI stricte, budget ≤ 500 Ko, images lourdes hors device.
- **Sommaire du dossier** : table de toutes les pièces (renvoi à `piece-list.md`).
- **Avertissement de statut** : le dossier est un **projet de soumission** tant que les bloqueurs (§readiness) ne sont pas levés ; l'homologation n'est **pas** acquise du seul fait de l'existence des pièces.
- **Avertissement juridique** identique à celui du volet #5 (interprétation et sign-off = conseil juridique).

### 2. `piece-list.md` — liste des pièces (index probatoire)

Table dérivée du catalogue `PREUVE-NN` de [`controles.md`](../docs/compliance/controles.md), une ligne par pièce du dossier :

| Colonne | Contenu |
| --- | --- |
| `PIECE-NN` | Numéro de pièce du dossier (ordre de soumission). |
| Preuve source | `PREUVE-NN` correspondant (lien vers `controles.md`). |
| Intitulé | Nom de la pièce (ex. « Registre des traitements »). |
| Exigence(s) couverte(s) | `REQ-LEX-NN` (lien matrice). |
| Emplacement | Lien relatif vers l'artefact (ou « à produire »). |
| Statut dossier | `Prête` / `Partielle` / `À produire` / `Bloquante`. |
| Propriétaire | Rôle responsable (agent / conseil juridique / infra / équipe pentest externe). |

**Règle de dérivation honnête :** le *statut dossier* est calculé du statut de la preuve source — une preuve `Planifié`/`À produire`/`Partiel` ne peut **jamais** être « Prête ». Exemples issus du catalogue actuel : `PREUVE-16` (threat model) → **Prête** ; `PREUVE-17`/`PREUVE-18` (registre, cartographie) → **Prêtes** ; `PREUVE-05` (attestation localisation) → **Partielle/Bloquante** (non signée) ; `PREUVE-13` (récépissé ARTCI) → **À produire** ; `PREUVE-14` (rapport pentest) → **À produire** (#25) ; `PREUVE-11`/`PREUVE-27` (consentement) → **Partielles** (draft, validation juridique requise) ; `PREUVE-21`/`PREUVE-24`/`PREUVE-25`/`PREUVE-26` (effacement, notification, rétention, DPO) → **Bloquantes** (écarts).

### 3. `readiness-dashboard.md` — tableau de bord de préparation

- **Synthèse chiffrée** : nombre de pièces `Prête` / `Partielle` / `À produire` / `Bloquante` ; nombre d'exigences `Must` **juridiquement validées** (aujourd'hui **0/22**, source [journal](../docs/compliance/journal-validation-juridique.md)).
- **Critère de soumission** (défini, non atteint) : « le dossier est soumissible lorsque (a) toutes les exigences `Must` sont signées sans réserve bloquante, (b) l'attestation de localisation est signée, (c) le rapport de pentest est livré avec Critical/High corrigés et re-testés, et (d) aucune pièce obligatoire n'est `Bloquante` ».
- **Liste des bloqueurs** tracés → issue/écart (voir §Risks).
- **Aucune valeur n'est inventée** : les compteurs se réfèrent aux artefacts sources et sont recalculables.

### 4. `formalite-prealable.md` — note de procédure

- Nature de la formalité applicable aux **données de santé** (données sensibles) : **déclaration** vs **autorisation préalable** — porte la mention **`[à confirmer — conseil juridique]`** (ECART-05) ; **aucun numéro d'article ni délai ARTCI n'est inventé**.
- Destinataire, format de dépôt attendu, pièces obligatoires (renvoi `piece-list`), et **suivi du récépissé/décision** (`PREUVE-13`) : où sera consigné le numéro de récépissé une fois obtenu.
- Étapes humaines/juridiques explicitement marquées « hors périmètre agent de code ».

### 5. `submission-checklist.md` — checklist de complétude avant dépôt

Liste à cocher, ordonnée par bloqueur, alignée sur le critère de soumission : sign-off juridique complet, attestation signée, pentest livré+corrigé, écarts obligatoires résolus, pièces `À produire` produites. Sert de **gate humain** avant toute soumission réelle.

### 6. Croisement inverse dans la matrice (léger)

Ajouter dans [`docs/compliance/README.md`](../docs/compliance/README.md) (§arborescence) et, si pertinent, en tête de [`controles.md`](../docs/compliance/controles.md), un renvoi vers le nouveau dossier `homologation-artci/`, afin que la chaîne `preuve → pièce de dossier` soit navigable dans les deux sens. Mettre à jour les statuts `PREUVE-13`/`PREUVE-05` **uniquement si** leur emplacement de suivi change (sinon, laisser tel quel).

---

## Affected Files / Packages / Modules

**À créer :**

- `docs/compliance/homologation-artci/README.md` — sommaire maître.
- `docs/compliance/homologation-artci/piece-list.md` — index probatoire (`PIECE-NN` ↔ `PREUVE-NN`).
- `docs/compliance/homologation-artci/readiness-dashboard.md` — readiness + bloqueurs.
- `docs/compliance/homologation-artci/formalite-prealable.md` — procédure de formalité.
- `docs/compliance/homologation-artci/submission-checklist.md` — checklist avant dépôt.
- `specs/issue-30-artci-homologation-dossier.md` — **ce fichier**.

**À lire / mettre à jour a minima (renvois croisés, sans réécriture) :**

- [`docs/compliance/README.md`](../docs/compliance/README.md) — ajouter le dossier à l'arborescence des livrables + méthodo étape 8.
- [`docs/compliance/controles.md`](../docs/compliance/controles.md) — renvoi éventuel vers `piece-list`.
- [`BACKLOG.md`](../BACKLOG.md) — annoter l'avancement de #30 (comme fait pour #18/#21/#22).
- Optionnel : [`justfile`](../justfile) + [`scripts/`](../scripts/) si un gate de complétude POSIX est ajouté (à confirmer #3).

**À lire seulement (sources de vérité) :** tous les fichiers listés dans *Relevant Repository Context*.

---

## API / Interface Changes

**None.** Le dossier est purement documentaire : aucune commande CLI publique, aucun endpoint réseau, aucune surface QR/token modifiée. Une éventuelle recette `just homologation-lint` (gate de complétude/liens) serait un **outil interne de dépôt**, non une API publique ; son ajout est conditionné à #3 et documenté si livré.

---

## Data Model / Protocol Changes

**None.** Aucun schéma d'enregistrement, format de blob chiffré, persistance ou sérialisation n'est touché. Le dossier ne manipule **aucune donnée patient** : uniquement des catégories, des schémas, des flux, des statuts et des liens — conformément à la règle « aucune donnée réelle dans les artefacts de conformité ».

---

## Security & Compliance Considerations

- **Zero-knowledge & crypto intactes.** Le dossier **décrit et oppose** les invariants — chiffrement client **AES-256-GCM** avant transit, serveur ne stockant que des **blobs opaques indexés par UUID anonymes**, incapable de déchiffrer — mais ne les modifie ni ne les affaiblit. Garde-fou anti « coche-la-case-au-prix-de-la-crypto » : si une exigence ARTCI semblait imposer un déchiffrement serveur ou un stockage de clé/PII en clair, on **ouvre un écart**, on ne cède pas.
- **Accès éphémère patient-contrôlé.** Le résumé opposable rappelle le **QR ~120 s**, le **déchiffrement RAM-only** côté professionnel et le **wipe** de fin de session / inactivité (US-1.2, US-2.1, US-2.3) comme preuves de minimisation et de contrôle par la personne concernée.
- **Résidence des données (loi n°2013-450 / ARTCI).** Pièce centrale du dossier : l'**attestation de localisation** (`PREUVE-05`) + le garde-fou IaC `country == "CI"` (`PREUVE-06`). Statut **honnête** : attestation **non signée** tant que l'opérateur souverain (#8/P0) n'est pas contracté et le bring-up réalisé — donc **pièce bloquante**, jamais présentée comme acquise.
- **Budget ≤ 500 Ko & médias hors device.** Le dossier référence les contrôles associés (`CTRL-12`/`PREUVE-10` ; déport images + URL éphémère #23) comme mesures de minimisation/robustesse, sans les redéfinir.
- **Aucune donnée sensible dans le dossier.** Interdiction absolue de journaliser ou d'inclure des **données médicales en clair, des clés, ou de la PII** — y compris dans les exemples, captures ou modèles. Les « captures réseau » citées comme preuves (`PREUVE-03`) sont des **artefacts d'autres issues** ; le dossier ne les recopie pas.
- **Traçabilité probante.** Chaque pièce du dossier pointe vers sa source vérifiable ; aucune preuve fabriquée. Les références légales non confirmées portent `[à confirmer — conseil juridique]` — **aucun numéro d'article ni délai inventé**.

---

## Testing Plan

La stack et l'outillage CI ne sont pas figés (#1/#3) : les vérifications sont décrites de façon **agnostique**, maquette house-style = script POSIX + recette `just`.

- **Documentation / lint liens (Must).** Vérifier que tous les liens relatifs du dossier résolvent (aucune pièce fantôme) — cohérent avec le lint de #5.
- **Gate de complétude du dossier (Must).** Vérifier que chaque `PREUVE-NN` obligatoire du catalogue apparaît dans `piece-list.md`, et que chaque `PIECE-NN` référence une preuve existante (pas d'orphelin dans les deux sens).
- **Gate de cohérence de statut (Must).** Vérifier qu'aucune pièce marquée « Prête » ne pointe vers une preuve source `Planifié`/`À produire`/`Partiel` (invariant d'honnêteté) ; vérifier que le compteur « `Must` juridiquement validées » du dashboard concorde avec le [journal](../docs/compliance/journal-validation-juridique.md).
- **Gate de traçabilité backlog (Should).** Vérifier que les issues citées (#5, #6, #8, #25, #26, #7, écarts) existent dans `BACKLOG.md`.
- **Invariant anti-régression conformité (Must).** Aucune pièce n'introduit un contrôle impliquant un déchiffrement serveur ou un stockage clé/PII en clair (grep de garde, comme suggéré dans #5 §8).
- **Aucun test crypto/e2e/résilience nouveau** : hors périmètre (pièces produites par #10, #25, #21/#22). Le dossier ne fait que les indexer.

---

## Documentation Updates

- **`docs/compliance/README.md`** : ajouter `homologation-artci/` à l'arborescence des livrables (§3) et à la méthodologie (§2, étape 8 « alimenter #30 »).
- **`docs/compliance/controles.md`** : renvoi optionnel `PREUVE → PIECE` vers `piece-list.md` ; ne changer les statuts `PREUVE-05`/`PREUVE-13` que si leur suivi migre dans le dossier.
- **`BACKLOG.md`** : annoter l'avancement de #30 (dossier constitué / soumission bloquée par sign-off + attestation + pentest) dans le style des notes *Avancement* existantes.
- **PRD** : le §5 référence déjà #30 ; **aucune modification requise** sauf si le lien du dossier doit y figurer (à confirmer, changement mineur).
- **ADR** : aucun nouvel ADR nécessaire pour le dossier lui-même ; les décisions de gouvernance issues des écarts (DPO, rétention, base légale) feront l'objet d'ADR **dans leurs issues respectives**, pas ici.

---

## Risks and Open Questions

**Bloqueurs (prérequis externes, sur le chemin critique de lancement) :**

1. **Sign-off juridique incomplet** — **0/22** exigences `Must` validées sans réserve ([journal](../docs/compliance/journal-validation-juridique.md)). Tant que ce n'est pas complet, la matrice reste un *projet* et le dossier n'est pas soumissible. *Externe : conseil juridique.*
2. **Attestation de localisation non signée** (`PREUVE-05`) — dépend du choix + contrat de l'opérateur souverain (#8/P0) et du bring-up (#8.1/#8.2). *Externe : procurement/infra.*
3. **Rapport de pentest non produit** (`PREUVE-14`, #25) — l'exécution du pentest et la correction des Critical/High sont un préalable ; le périmètre est prêt, le rapport non. *Externe : équipe pentest.*
4. **Récépissé/décision ARTCI** (`PREUVE-13`) — « À produire » ; dépend de la soumission humaine effective.

**Écarts à résoudre (issues distinctes, suivies par le dossier) :** rétention (ECART-01), flux d'effacement + crypto-effacement (ECART-02), notification de violation (ECART-03), désignation DPO (ECART-04), régime données de santé / mineurs (ECART-05), rôles RT/sous-traitant (ECART-06), base légale de la localisation (ECART-07), accès d'urgence/break-glass (ECART-08).

**Questions ouvertes (décisions à confirmer) :**

- **Nature de la formalité** ARTCI pour données de santé : déclaration ou **autorisation préalable** ? (ECART-05) — conditionne la procédure et les pièces obligatoires. *`[à confirmer — conseil juridique]`.*
- **Format de dépôt** exigé par l'ARTCI (portail, dossier papier, modèle imposé ?) — non documenté ici faute de source vérifiée ; ne rien inventer.
- **Outillage du gate de complétude** — langage du script / action CI non tranchés (#1/#3).
- **Numérotation `PIECE-NN`** — figer un ordre de soumission stable (proposition : suivre l'ordre logique du dossier, pas l'ordre `PREUVE`).
- **Langue des pièces techniques** — le dossier est en français ; certaines pièces techniques (specs, tests) sont bilingues — confirmer si l'ARTCI exige une version FR de chaque pièce.

**Compatibilité :** aucune dépendance de code ; risque principal = **dérive** entre le dossier et les artefacts sources si ces derniers évoluent → le gate de complétude/cohérence limite ce risque.

---

## Implementation Checklist

- [ ] Créer le répertoire `docs/compliance/homologation-artci/`.
- [ ] Rédiger `README.md` maître : objet, destinataire, résumé exécutif opposable (ZK/crypto/QR/résidence/500 Ko), sommaire, avertissements de statut et juridique.
- [ ] Rédiger `piece-list.md` : une ligne `PIECE-NN` par `PREUVE-NN` obligatoire, avec exigence(s) couverte(s), emplacement, **statut dérivé honnêtement**, propriétaire.
- [ ] Rédiger `readiness-dashboard.md` : synthèse chiffrée (dont **0/22 `Must` validées**), critère de soumission défini, liste des bloqueurs tracés vers issue/écart.
- [ ] Rédiger `formalite-prealable.md` : nature de formalité `[à confirmer]`, destinataire, pièces obligatoires, suivi du récépissé (`PREUVE-13`) ; marquer les étapes humaines « hors périmètre agent ».
- [ ] Rédiger `submission-checklist.md` : gate humain avant dépôt, aligné sur le critère de soumission.
- [ ] Ajouter les renvois croisés dans `docs/compliance/README.md` (arborescence + méthodo étape 8) et, si utile, en tête de `controles.md`.
- [ ] Annoter l'avancement de #30 dans `BACKLOG.md` (dossier constitué ; soumission bloquée par sign-off + attestation + pentest).
- [ ] (Optionnel, si #3 le permet) Ajouter un gate de complétude/cohérence POSIX dans `scripts/` + recette `just` ; sinon documenter la vérification manuelle.
- [ ] Vérifier : tous les liens relatifs résolvent ; aucune pièce « Prête » adossée à une preuve non livrée ; aucune donnée patient/clé/PII dans le dossier ; aucune référence légale inventée (mentions `[à confirmer]` présentes).
- [ ] Relire pour honnêteté : le dossier n'affirme **nulle part** que l'homologation est obtenue ou la soumission complète.
