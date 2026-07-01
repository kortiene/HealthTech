# Tableau de bord de préparation (readiness) — homologation ARTCI

> Dérivé de [`piece-list.md`](./piece-list.md) (statuts de pièces) et du
> [journal de validation juridique](../journal-validation-juridique.md) (sign-off `Must`).
> **Aucune valeur n'est inventée** : chaque compteur se réfère à un artefact source et est **recalculable**.

> ⚠️ **L'homologation n'est PAS acquise.** Ce tableau existe précisément pour empêcher de croire l'inverse.

## 1. Synthèse chiffrée des pièces

Compté sur les 18 pièces de [`piece-list.md`](./piece-list.md) :

| Statut dossier | Pièces | Détail |
| --- | --- | --- |
| **Prête** | **5** | PIECE-01, PIECE-02, PIECE-03, PIECE-04, PIECE-08 |
| **Partielle** | **2** | PIECE-10, PIECE-11 (consentement / transparence — draft, validation juridique requise) |
| **À produire** | **6** | PIECE-05, PIECE-06, PIECE-09, PIECE-12, PIECE-17, PIECE-18 |
| **Bloquante** | **5** | PIECE-07 (attestation non signée), PIECE-13, PIECE-14, PIECE-15, PIECE-16 (écarts) |
| **Total** | **18** | — |

## 2. Validation juridique (critère d'acceptation de #5, prérequis de #30)

| Indicateur | Valeur | Source |
| --- | --- | --- |
| Exigences `Must` totales | 22 (+ REQ-LEX-23 `Must [à confirmer]`) | [journal](../journal-validation-juridique.md) |
| Exigences `Must` **validées sans réserve bloquante** | **0 / 22** | [journal](../journal-validation-juridique.md) |
| Matrice validée ? | **Non** | [journal](../journal-validation-juridique.md) |
| Attestation de localisation signée ? | **Non** (modèle prêt, opérateur souverain #8 non contracté) | [attestation](../attestation-localisation-donnees.md) |
| Rapport de pentest livré ? | **Non** (périmètre prêt, exécution #25 en attente) | [périmètre](../../security/pentest-scope.md) |
| Récépissé / décision ARTCI obtenu ? | **Non** (`PREUVE-13` — à produire) | [`piece-list.md`](./piece-list.md) |

## 3. Critère de soumission (défini, **non atteint**)

Le dossier devient **soumissible** lorsque **toutes** les conditions suivantes sont réunies :

1. **(a)** Toutes les exigences `Must` sont **signées sans réserve bloquante** au
   [journal de validation juridique](../journal-validation-juridique.md) — *aujourd'hui 0/22.*
2. **(b)** L'**attestation de localisation** (`PREUVE-05`) est **signée** après contrat opérateur souverain
   et bring-up in-country (#8) — *aujourd'hui non signée.*
3. **(c)** Le **rapport de pentest** (`PREUVE-14`, #25) est **livré** avec toutes les vulnérabilités
   `Critical`/`High` **corrigées et re-testées** — *aujourd'hui non produit.*
4. **(d)** **Aucune pièce obligatoire** n'est au statut **Bloquante** (écarts ECART-01…04 résolus, pièces
   « À produire » produites) — *aujourd'hui 5 pièces Bloquantes.*

> Tant que (a)–(d) ne sont pas tous vrais, ce dossier reste un **projet** ; l'homologation reste une
> **décision externe de l'ARTCI** non anticipable.

## 4. Bloqueurs (prérequis externes sur le chemin critique `… → #25 → #30 → #31`)

| # | Bloqueur | Pièce / preuve | Tracé vers | Responsable (externe) |
| --- | --- | --- | --- | --- |
| B1 | **Sign-off juridique incomplet** — 0/22 `Must` validées | matrice / journal | [journal](../journal-validation-juridique.md), #5 | Conseil juridique |
| B2 | **Attestation de localisation non signée** — dépend du choix + contrat opérateur souverain et du bring-up | PIECE-07 / `PREUVE-05` | [attestation](../attestation-localisation-donnees.md), #8 | Procurement / infra |
| B3 | **Rapport de pentest non produit** — Critical/High à corriger + re-tester | PIECE-06 / `PREUVE-14` | [périmètre](../../security/pentest-scope.md), #25 | Équipe pentest externe |
| B4 | **Récépissé / décision ARTCI** non obtenu — dépend de la soumission humaine | PIECE-18 / `PREUVE-13` | [`formalite-prealable.md`](./formalite-prealable.md), #30 | Conseil juridique (dépôt) |

## 5. Écarts à résoudre (issues distinctes suivies par le dossier)

| Écart | Objet | Pièce impactée |
| --- | --- | --- |
| [ECART-01](../ecarts.md) | Politique de rétention & purge | PIECE-13 (`PREUVE-25`) |
| [ECART-02](../ecarts.md) | Flux d'effacement + crypto-effacement | PIECE-14 (`PREUVE-21`) |
| [ECART-03](../ecarts.md) | Notification de violation | PIECE-15 (`PREUVE-24`) |
| [ECART-04](../ecarts.md) | Désignation DPO / correspondant | PIECE-16 (`PREUVE-26`) |
| [ECART-05](../ecarts.md) | Régime données de santé / mineurs (nature de la formalité) | [`formalite-prealable.md`](./formalite-prealable.md), PIECE-18 |
| [ECART-06](../ecarts.md) | Rôles RT / sous-traitant | PIECE-01, PIECE-09 |
| [ECART-07](../ecarts.md) | Base légale de la localisation stricte | PIECE-07 |
| [ECART-08](../ecarts.md) | Accès d'urgence / break-glass | *(transverse — ne pas introduire de porte dérobée serveur)* |

## 6. Recalcul

Les compteurs de la §1 se recomptent directement depuis la colonne « Statut dossier » de
[`piece-list.md`](./piece-list.md) ; ceux de la §2 depuis la synthèse du
[journal](../journal-validation-juridique.md). Le gate de cohérence
([`../../../scripts/check-homologation-dossier.sh`](../../../scripts/check-homologation-dossier.sh)) vérifie
notamment qu'aucune pièce « Prête » ne s'adosse à une preuve non `Existant`.
