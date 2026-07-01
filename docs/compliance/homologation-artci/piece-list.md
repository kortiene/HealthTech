# Liste des pièces du dossier (index probatoire)

> **Point d'entrée :** [`README.md`](./README.md). **Preuves sources :** [`../controles.md`](../controles.md)
> (catalogue `PREUVE-NN`). **Exigences :** [`../loi-2013-450-artci-matrix.md`](../loi-2013-450-artci-matrix.md).
>
> Chaque ligne est **une pièce du dossier** (`PIECE-NN`, dans l'ordre de soumission logique) adossée à une
> **preuve source** `PREUVE-NN`. Le **statut dossier** est **dérivé** du statut de la preuve source dans le
> catalogue — **il n'est jamais recalculé à la hausse**.

## Règle de dérivation (honnêteté de statut)

| Statut dossier | Condition sur la preuve source (`../controles.md`) |
| --- | --- |
| **Prête** | Preuve source **`Existant`** (artefact livré **et** vérifié dans le dépôt). |
| **Partielle** | Preuve source `Partiel` ou `Draft` (cadre présent, validation/complétude en cours). |
| **À produire** | Preuve source `Planifié` ou `À produire` (artefact non encore livré). |
| **Bloquante** | Preuve **`À produire (écart)`** ou dépendance externe non levée (attestation non signée, pentest non exécuté). Bloque la soumission. |

> ⚠️ Une preuve `Planifié` / `À produire` / `Partiel` / `Draft` ne peut **jamais** être présentée « Prête ».
> La colonne **Emplacement** pointe la source vérifiable ; « à produire » = artefact externe/organisationnel attendu.

## Index des pièces

| Pièce | Preuve source | Intitulé | Exigence(s) couverte(s) | Emplacement | Statut dossier | Propriétaire |
| --- | --- | --- | --- | --- | --- | --- |
| **PIECE-01** | [PREUVE-17](../controles.md) | Registre des activités de traitement | REQ-LEX-21, REQ-LEX-06 | [`../registre-des-traitements.md`](../registre-des-traitements.md) | **Prête** | Agent / conseil juridique (validation) |
| **PIECE-02** | [PREUVE-18](../controles.md) | Cartographie des données & flux (frontière zero-knowledge) | REQ-LEX-07, REQ-LEX-16 | [`../cartographie-donnees-et-flux.md`](../cartographie-donnees-et-flux.md) | **Prête** | Agent / conseil juridique (validation) |
| **PIECE-03** | [PREUVE-16](../controles.md) | Modèle de menace STRIDE & politique de sécurité | REQ-LEX-16, REQ-LEX-17 | [`../../threat-model/stride-threat-model.md`](../../threat-model/stride-threat-model.md) | **Prête** | Agent (sécurité) |
| **PIECE-04** | [PREUVE-01](../controles.md) | Revue crypto interne + vecteurs NIST AES-GCM (gating CI) | REQ-LEX-16 | [`../../security/crypto-core-review.md`](../../security/crypto-core-review.md) | **Prête** | Agent (crypto) |
| **PIECE-05** | [PREUVE-15](../controles.md) | Avis de revue cryptographique **indépendante** | REQ-LEX-16 | à produire (brief : [`../../security/independent-crypto-review-brief.md`](../../security/independent-crypto-review-brief.md), #26) | **À produire** | Expert crypto externe |
| **PIECE-06** | [PREUVE-14](../controles.md) | Rapport de **pentest externe** (Critical/High corrigés + re-testés) | REQ-LEX-16 | à produire (périmètre : [`../../security/pentest-scope.md`](../../security/pentest-scope.md), #25) | **À produire** | Équipe pentest externe |
| **PIECE-07** | [PREUVE-05](../controles.md) | **Attestation de localisation des données** (résidence CI) | REQ-LEX-19, REQ-LEX-20 | [`../attestation-localisation-donnees.md`](../attestation-localisation-donnees.md) — **modèle prêt, non signé** | **Bloquante** | Infra / procurement (#8) |
| **PIECE-08** | [PREUVE-06](../controles.md) | Garde-fou IaC résidence `country == "CI"` + tripwire CI | REQ-LEX-19 | [`../../../scripts/check-residency.sh`](../../../scripts/check-residency.sh) | **Prête** | Agent (infra) |
| **PIECE-09** | [PREUVE-07](../controles.md) | Contrat / clauses hébergeur (DPA : sécurité, sous-traitance, localisation) | REQ-LEX-24, REQ-LEX-20 | à produire (#8) | **À produire** | Procurement / conseil juridique |
| **PIECE-10** | [PREUVE-11](../controles.md) | Texte de consentement **validé juridiquement** | REQ-LEX-03, REQ-LEX-04 | [`../../legal/consent-v1.md`](../../legal/consent-v1.md) — **draft** | **Partielle** | Conseil juridique (#7) |
| **PIECE-11** | [PREUVE-27](../controles.md) | Textes d'information / transparence (politique de confidentialité, mentions) | REQ-LEX-11, REQ-LEX-04 | [`../../legal/consent-v1.md`](../../legal/consent-v1.md) §3 — **draft** | **Partielle** | Conseil juridique (#7) |
| **PIECE-12** | [PREUVE-12](../controles.md) | Preuve d'horodatage de capture du consentement | REQ-LEX-04 | à produire (#13) | **À produire** | Équipe produit |
| **PIECE-13** | [PREUVE-25](../controles.md) | Politique de rétention documentée (durées + purge) | REQ-LEX-10 | à produire — **[ECART-01](../ecarts.md)** | **Bloquante** | Gouvernance / conseil juridique |
| **PIECE-14** | [PREUVE-21](../controles.md) | Flux d'effacement (suppression par UUID + crypto-effacement) | REQ-LEX-15, REQ-LEX-14 | à produire — **[ECART-02](../ecarts.md)** | **Bloquante** | Conception / conseil juridique |
| **PIECE-15** | [PREUVE-24](../controles.md) | Runbook d'incident + modèle de notification de violation | REQ-LEX-23 | à produire — **[ECART-03](../ecarts.md)** | **Bloquante** | Gouvernance / conseil juridique |
| **PIECE-16** | [PREUVE-26](../controles.md) | Acte de désignation correspondant / DPO | REQ-LEX-22 | à produire — **[ECART-04](../ecarts.md)** | **Bloquante** | Gouvernance |
| **PIECE-17** | [PREUVE-02](../controles.md) | Test « le serveur ne peut pas déchiffrer » (preuve zero-knowledge) | REQ-LEX-07, REQ-LEX-16 | à produire (#9) | **À produire** | Agent (backend) |
| **PIECE-18** | [PREUVE-13](../controles.md) | **Récépissé / décision d'autorisation ARTCI** | REQ-LEX-01, REQ-LEX-02 | à produire (démarche ARTCI — voir [`formalite-prealable.md`](./formalite-prealable.md)) | **À produire** | Conseil juridique (dépôt humain) |

> **Note de couverture.** Cet index sélectionne les pièces **transmissibles à l'ARTCI**. Les preuves
> techniques internes (`PREUVE-03/04/08/09/10/19/20/22/23/28/29`) restent des artefacts d'appui des issues
> qui les produisent ; elles n'apparaissent pas comme pièces autonomes du dossier mais soutiennent les
> contrôles couverts par les pièces ci-dessus. Aucune n'est recopiée ici.

> **Aucune donnée patient / clé / PII** ne figure dans ce dossier — uniquement des intitulés, statuts et
> liens vers des artefacts eux-mêmes exempts de données réelles.
