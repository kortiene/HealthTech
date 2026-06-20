# Registre des exigences légales — loi n°2013-450 & ARTCI

> Registre **atomisé** des obligations : **1 obligation = 1 ligne `REQ-LEX-NN`**.
> Source de mapping : [`loi-2013-450-artci-matrix.md`](./loi-2013-450-artci-matrix.md) · contrôles :
> [`controles.md`](./controles.md) · écarts : [`ecarts.md`](./ecarts.md).
>
> ⚠️ **Citations d'articles à confirmer.** Conformément à la spec, **aucun numéro d'article n'est inventé**.
> Les références précises portent la mention **`[art. à confirmer — conseil juridique]`** tant qu'elles ne
> sont pas vérifiées sur le texte officiel de la **loi n°2013-450 du 19 juin 2013** et les textes / lignes
> directrices de l'**ARTCI**. Le **thème** de chaque exigence, lui, reflète des obligations standard du
> régime ivoirien de protection des données.

## Légende

- **Obligation :** `Must` (obligation légale dure) / `Should` (recommandé ou conditionnel).
- **Catégorie :** voir regroupement ci-dessous.
- Une exigence sans contrôle, sans preuve ou sans issue porteuse est reportée dans [`ecarts.md`](./ecarts.md).

---

## A. Formalités préalables (déclaration / autorisation)

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-01** | Loi n°2013-450 `[art. à confirmer]` ; pratique ARTCI | Accomplir la **formalité préalable** auprès de l'ARTCI (déclaration ou autorisation selon la nature du traitement) **avant** la mise en œuvre. | Formalités préalables | Must |
| **REQ-LEX-02** | Loi n°2013-450 `[art. données sensibles à confirmer]` | Les **données de santé** étant des **données sensibles**, le traitement relève d'un **régime renforcé** (vraisemblablement **autorisation préalable** ARTCI, et non simple déclaration). | Formalités préalables / Données sensibles | Must |

## B. Base légale & consentement

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-03** | Loi n°2013-450 `[art. à confirmer]` | Le traitement doit reposer sur une **base légale** valable (ici : **consentement** de la personne concernée). | Base légale & consentement | Must |
| **REQ-LEX-04** | Loi n°2013-450 `[art. à confirmer]` | Le consentement doit être **libre, spécifique, éclairé** (et univoque), avec preuve de recueil. | Base légale & consentement | Must |
| **REQ-LEX-05** | Loi n°2013-450 `[art. à confirmer]` | **Mineurs / personnes protégées** : régime de consentement spécifique (représentant légal). | Base légale & consentement | Should `[à confirmer]` |

## C. Principes relatifs au traitement

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-06** | Loi n°2013-450 `[art. à confirmer]` | **Finalité** déterminée, légitime et explicite ; pas de traitement ultérieur incompatible. | Principes (finalité) | Must |
| **REQ-LEX-07** | Loi n°2013-450 `[art. à confirmer]` | **Minimisation** : données adéquates, pertinentes et limitées à ce qui est nécessaire. | Principes (minimisation) | Must |
| **REQ-LEX-08** | Loi n°2013-450 `[art. à confirmer]` | **Exactitude** : données exactes et tenues à jour. | Principes (exactitude) | Must |
| **REQ-LEX-09** | Loi n°2013-450 `[art. à confirmer]` | **Loyauté & licéité** de la collecte et du traitement. | Principes (loyauté) | Must |

## D. Durée de conservation

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-10** | Loi n°2013-450 `[art. à confirmer]` ; règles sectorielles santé `[à confirmer]` | **Conservation limitée** à la durée nécessaire aux finalités, puis suppression/anonymisation — **à arbitrer** avec les durées **minimales** de conservation des dossiers médicaux. | Durée de conservation | Must |

## E. Droits de la personne concernée

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-11** | Loi n°2013-450 `[art. à confirmer]` | **Droit à l'information** : informer la personne (finalité, destinataires, droits, etc.) au moment de la collecte. | Droits — information | Must |
| **REQ-LEX-12** | Loi n°2013-450 `[art. à confirmer]` | **Droit d'accès** : la personne peut obtenir communication de ses données. | Droits — accès | Must |
| **REQ-LEX-13** | Loi n°2013-450 `[art. à confirmer]` | **Droit de rectification** : correction des données inexactes. | Droits — rectification | Must |
| **REQ-LEX-14** | Loi n°2013-450 `[art. à confirmer]` | **Droit d'opposition** (pour motifs légitimes). | Droits — opposition | Must |
| **REQ-LEX-15** | Loi n°2013-450 `[art. à confirmer]` | **Droit à la suppression / effacement** des données. | Droits — suppression | Must |

## F. Sécurité & confidentialité

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-16** | Loi n°2013-450 `[art. à confirmer]` | **Mesures techniques et organisationnelles** assurant confidentialité, intégrité et sécurité des données. | Sécurité | Must |
| **REQ-LEX-17** | Loi n°2013-450 `[art. à confirmer]` ; règles santé `[à confirmer]` | **Confidentialité / secret** des données de santé (secret professionnel). | Sécurité / Données sensibles | Must |
| **REQ-LEX-18** | Loi n°2013-450 `[art. à confirmer]` | **Contrôle des accès** aux données ; accès limité aux personnes autorisées (ici : **contrôlé par le patient**). | Sécurité | Must |

## G. Résidence & transferts transfrontaliers

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-19** | Loi n°2013-450 `[art. à confirmer]` ; PRD §5 ; ARTCI | **Résidence des données** sur le **territoire national** (hébergement en Côte d'Ivoire). *(Base exacte — obligation statutaire dure ou mitigation des restrictions de transfert — à préciser : voir [ECART](./ecarts.md).)* | Résidence | Must |
| **REQ-LEX-20** | Loi n°2013-450 `[art. à confirmer]` | **Encadrement des transferts transfrontaliers** : pas de transfert hors du pays sans garanties adéquates / autorisation. | Transferts | Must |

## H. Accountability (responsabilité)

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-21** | Loi n°2013-450 `[art. à confirmer]` | Tenir un **registre des activités de traitement** (accountability). | Accountability | Must |
| **REQ-LEX-22** | Loi n°2013-450 `[art. à confirmer]` | **Désignation d'un correspondant / DPO** (si requis ou recommandé). | Accountability | Should `[à confirmer]` |

## I. Violations de données

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-23** | Loi n°2013-450 `[art. à confirmer]` | **Notification des violations** de données (à l'ARTCI et/ou aux personnes concernées) dans les délais prescrits. | Violations | Must `[à confirmer]` |

## J. Sous-traitance

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-24** | Loi n°2013-450 `[art. à confirmer]` | **Encadrement contractuel de la sous-traitance** (hébergeur) : obligations de sécurité et de confidentialité opposables. | Sous-traitance | Must |

## K. Journalisation / redaction (corollaire sécurité)

| ID | Source légale | Exigence (langage clair) | Catégorie | Obligation |
| --- | --- | --- | --- | --- |
| **REQ-LEX-25** | Dérivé de REQ-LEX-16/17 ; PRD §4 ; [ADR 0007](../adr/0007-secrets-and-environments.md) | **Aucune donnée médicale en clair, clé, ou PII** dans les journaux / logs applicatifs et d'infrastructure. | Sécurité | Must |

---

## Synthèse par caractère obligatoire

| Obligation | Exigences |
| --- | --- |
| **Must** | REQ-LEX-01, 02, 03, 04, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 24, 25 (+ 23 `[à confirmer]`) |
| **Should / conditionnel** | REQ-LEX-05, 22 |

> **Note de complétude.** Ce registre est un **projet structuré** : la liste des exigences et leur
> qualification `Must/Should` doivent être **revues et complétées** par le conseil juridique sur le texte
> officiel (cf. [risques & questions ouvertes](../../specs/loi-2013-450-artci-compliance-matrix.md#risks-and-open-questions)).
