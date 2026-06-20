# Matrice de conformité — loi n°2013-450 & exigences ARTCI

> **Pièce maîtresse** du volet conformité ([#5](https://github.com/kortiene/HealthTech/issues/5)).
> Lie **exigence → contrôle(s) → preuve(s) → statut → responsable → validation juridique**.
>
> - Exigences : [`exigences-legales.md`](./exigences-legales.md) (`REQ-LEX-NN`).
> - Contrôles & preuves : [`controles.md`](./controles.md) (`CTRL-NN`, `PREUVE-NN`).
> - Écarts : [`ecarts.md`](./ecarts.md) (`ECART-NN`).
> - Validation : [`journal-validation-juridique.md`](./journal-validation-juridique.md).
>
> ⚠️ **Statuts honnêtes (projet greenfield).** La majorité des contrôles techniques sont **`Planifié`**
> (décidés par ADR/backlog, **non encore implémentés**) : **aucun « Conforme » n'est affirmé pour un
> contrôle non livré**. Les **citations d'articles** sont **`[à confirmer]`** par le conseil juridique
> (cf. [`exigences-legales.md`](./exigences-legales.md)). La colonne **Validation juridique** est partout
> **« Non — en attente »** : **aucun sign-off n'a encore eu lieu** ([journal](./journal-validation-juridique.md)).

## Légende des colonnes

`REQ` = identifiant exigence · `Cat.` = catégorie · `M/S` = Must/Should · `CTRL` = contrôle(s) ·
`ADR/Issue` = source de vérité · `Preuve` = artefact(s) attendu(s) · `Statut` ∈ {Conforme, Partiel,
Planifié, Écart} · `Resp.` = responsable · `Valid. jur.` = validation du conseil juridique.

---

## Matrice

| REQ | Source légale | Exigence (résumé) | Cat. | M/S | CTRL | ADR / Issue | Preuve | Statut | Resp. | Valid. jur. |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **REQ-LEX-01** | L.2013-450 `[art. à confirmer]` ; ARTCI | Formalité préalable ARTCI avant mise en œuvre | Formalités | Must | CTRL-30 | #30 | PREUVE-13 | **Planifié** | Gouvernance + Conseil jur. | Non — en attente |
| **REQ-LEX-02** | L.2013-450 `[art. sensibles à confirmer]` | Données de santé sensibles → régime renforcé / **autorisation préalable** | Formalités / Sensibles | Must | CTRL-30, CTRL-15, CTRL-02 | #30, #7, #9 | PREUVE-13, PREUVE-11 | **Écart** (régime à instruire) | Conseil jur. | Non — en attente |
| **REQ-LEX-03** | L.2013-450 `[art. à confirmer]` | Base légale = **consentement** | Consentement | Must | CTRL-15, CTRL-16 | #7, #13 | PREUVE-11, PREUVE-12 | **Planifié** | Product/UX + Conseil jur. | Non — en attente |
| **REQ-LEX-04** | L.2013-450 `[art. à confirmer]` | Consentement **libre, spécifique, éclairé**, prouvé | Consentement | Must | CTRL-15, CTRL-16 | #7, #13 | PREUVE-11, PREUVE-12 | **Planifié** | Product/UX | Non — en attente |
| **REQ-LEX-05** | L.2013-450 `[art. à confirmer]` | Consentement **mineurs / personnes protégées** | Consentement | Should `[à conf.]` | CTRL-15 | #7 | PREUVE-11 | **Écart** (régime à confirmer) | Conseil jur. | Non — en attente |
| **REQ-LEX-06** | L.2013-450 `[art. à confirmer]` | **Finalité** déterminée, légitime, explicite | Principes | Must | CTRL-24, CTRL-25 | #5 | PREUVE-17, PREUVE-18 | **Partiel** | Conseil jur. + Product | Non — en attente |
| **REQ-LEX-07** | L.2013-450 `[art. à confirmer]` | **Minimisation** des données | Principes | Must | CTRL-02, CTRL-13, CTRL-12, CTRL-11 | #9, #15, #23 ; ADR 0005 | PREUVE-02, PREUVE-04, PREUVE-10 | **Planifié** | Backend + Crypto | Non — en attente |
| **REQ-LEX-08** | L.2013-450 `[art. à confirmer]` | **Exactitude** & mise à jour | Principes | Must | CTRL-18, CTRL-17 | #18, #15, #14 | PREUVE-20, PREUVE-19 | **Planifié** | App patient + App médecin | Non — en attente |
| **REQ-LEX-09** | L.2013-450 `[art. à confirmer]` | **Loyauté & licéité** de la collecte | Principes | Must | CTRL-15, CTRL-31, CTRL-24 | #7, #5 | PREUVE-11, PREUVE-27, PREUVE-17 | **Partiel** | Conseil jur. | Non — en attente |
| **REQ-LEX-10** | L.2013-450 `[art. à confirmer]` ; règles santé `[à conf.]` | **Durée de conservation** limitée (vs rétention médicale minimale) | Conservation | Must | CTRL-28, CTRL-11, CTRL-05, CTRL-07 | ECART-01 ; #23, #16, #19 | PREUVE-25, PREUVE-08, PREUVE-09 | **Écart** (à instruire) | Gouvernance + Conseil jur. | Non — en attente |
| **REQ-LEX-11** | L.2013-450 `[art. à confirmer]` | **Droit à l'information** (transparence à la collecte) | Droits | Must | CTRL-31, CTRL-15 | #7 | PREUVE-27, PREUVE-11 | **Planifié** | Product/UX + Conseil jur. | Non — en attente |
| **REQ-LEX-12** | L.2013-450 `[art. à confirmer]` | **Droit d'accès** | Droits | Must | CTRL-17 | #14, #15 | PREUVE-19 | **Planifié** | App patient | Non — en attente |
| **REQ-LEX-13** | L.2013-450 `[art. à confirmer]` | **Droit de rectification** | Droits | Must | CTRL-18 | #18, #15 | PREUVE-20 | **Planifié** | App médecin/patient | Non — en attente |
| **REQ-LEX-14** | L.2013-450 `[art. à confirmer]` | **Droit d'opposition** | Droits | Must | CTRL-15, CTRL-19 | #7 ; ECART-02 | PREUVE-11, PREUVE-21 | **Écart** (mécanisme à concevoir) | Conseil jur. | Non — en attente |
| **REQ-LEX-15** | L.2013-450 `[art. à confirmer]` | **Droit à la suppression / effacement** | Droits | Must | CTRL-19 | #9 ; ECART-02 | PREUVE-21 | **Écart** (à instruire) | Backend + Conseil jur. | Non — en attente |
| **REQ-LEX-16** | L.2013-450 `[art. à confirmer]` | **Mesures techniques de sécurité** (confidentialité, intégrité) | Sécurité | Must | CTRL-01, CTRL-02, CTRL-03, CTRL-04, CTRL-23, CTRL-20, CTRL-21, CTRL-22 | #10, #9, #11, #12, #6, #25, #26 ; ADR 0003 | PREUVE-01, PREUVE-02, PREUVE-14, PREUVE-15, PREUVE-16 | **Planifié** | Crypto + Sécurité | Non — en attente |
| **REQ-LEX-17** | L.2013-450 `[art. à confirmer]` ; secret médical `[à conf.]` | **Confidentialité / secret** des données de santé | Sécurité / Sensibles | Must | CTRL-01, CTRL-02, CTRL-05, CTRL-06, CTRL-07 | #10, #9, #16, #17, #19 | PREUVE-02, PREUVE-08, PREUVE-09 | **Planifié** | Crypto + App médecin | Non — en attente |
| **REQ-LEX-18** | L.2013-450 `[art. à confirmer]` | **Contrôle des accès** (accès éphémère contrôlé par le patient) | Sécurité | Must | CTRL-05, CTRL-06, CTRL-07 | #16, #17, #19 | PREUVE-08, PREUVE-09 | **Planifié** | App patient + App médecin | Non — en attente |
| **REQ-LEX-19** | L.2013-450 `[art. à confirmer]` ; PRD §5 ; ARTCI | **Résidence des données** sur le territoire national | Résidence | Must | CTRL-08, CTRL-09, CTRL-10 | ADR 0005, ADR 0007, #8 | PREUVE-05, PREUVE-06, PREUVE-07 | **Partiel** | Infra/DevOps + Conseil jur. | Non — en attente |
| **REQ-LEX-20** | L.2013-450 `[art. à confirmer]` | **Encadrement des transferts** transfrontaliers | Transferts | Must | CTRL-08, CTRL-10, CTRL-11 | ADR 0005, #23 | PREUVE-23, PREUVE-05 | **Planifié** | Infra/DevOps | Non — en attente |
| **REQ-LEX-21** | L.2013-450 `[art. à confirmer]` | **Registre des activités de traitement** | Accountability | Must | CTRL-24 | #5 | PREUVE-17 | **Partiel** | Conseil jur. + Product | Non — en attente |
| **REQ-LEX-22** | L.2013-450 `[art. à confirmer]` | **Correspondant / DPO** (si requis) | Accountability | Should `[à conf.]` | CTRL-29 | ECART-04 | PREUVE-26 | **Écart** (à confirmer) | Gouvernance | Non — en attente |
| **REQ-LEX-23** | L.2013-450 `[art. à confirmer]` | **Notification des violations** (ARTCI / personnes) | Violations | Must `[à confirmer]` | CTRL-27 | ECART-03 | PREUVE-24 | **Écart** (à instruire) | Sécurité + Gouvernance | Non — en attente |
| **REQ-LEX-24** | L.2013-450 `[art. à confirmer]` | **Encadrement de la sous-traitance** (hébergeur) | Sous-traitance | Must | CTRL-26, CTRL-08 | #8 | PREUVE-07, PREUVE-05 | **Planifié** | Infra/DevOps + Conseil jur. | Non — en attente |
| **REQ-LEX-25** | Dérivé REQ-LEX-16/17 ; ADR 0007 ; PRD §4 | **Journalisation sans** PII / clés / clair | Sécurité | Must | CTRL-14, CTRL-13 | ADR 0007 | PREUVE-22 | **Partiel** | Backend/DevOps | Non — en attente |

---

## Tableau de bord (synthèse des statuts)

| Statut | Nombre | Exigences |
| --- | --- | --- |
| **Conforme** | 0 | *(aucun — projet greenfield, aucun contrôle livré+prouvé)* |
| **Partiel** | 5 | REQ-LEX-06, 09, 19, 21, 25 |
| **Planifié** | 13 | REQ-LEX-01, 03, 04, 07, 08, 11, 12, 13, 16, 17, 18, 20, 24 |
| **Écart** | 7 | REQ-LEX-02, 05, 10, 14, 15, 22, 23 |
| **Total** | **25** | |

**Validation juridique :** **0 / 25** exigences signées. La matrice **n'est donc pas encore « validée »**
(critère d'acceptation de [#5](https://github.com/kortiene/HealthTech/issues/5) **non atteint** tant que
toutes les exigences `Must` ne sont pas signées sans réserve bloquante — voir
[`journal-validation-juridique.md`](./journal-validation-juridique.md)).

## Garde-fou anti-régression conformité

Aucune ligne de cette matrice ne décrit un contrôle impliquant :

- un **déchiffrement côté serveur** (le serveur ne détient que des blobs opaques — CTRL-02), ou
- un **stockage de clé / PII en clair** (clés client-side only ; logs redigés — CTRL-03, CTRL-14, CTRL-25).

Si une future exigence semblait l'imposer, **créer un écart** ([`ecarts.md`](./ecarts.md)) plutôt
qu'affaiblir la cryptographie ou le modèle zero-knowledge. Cet invariant est destiné à être **vérifié
automatiquement** (cf. [`README.md` §8](./README.md) et la *Testing Plan* de la spec).
