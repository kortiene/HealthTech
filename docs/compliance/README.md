# Conformité — loi n°2013-450 & exigences ARTCI

> **Issue porteuse :** [#5 — Analyse de conformité loi n°2013-450 & exigences ARTCI](https://github.com/kortiene/HealthTech/issues/5)
> (Épic **E6 — Conformité, légal & gouvernance** · Effort **L** · Priorité **Must** · labels `compliance` `docs`).
> **Spec source :** [`specs/loi-2013-450-artci-compliance-matrix.md`](../../specs/loi-2013-450-artci-compliance-matrix.md).
> **Langue faisant foi :** **français** (droit ivoirien francophone ; le conseil juridique travaille sur le texte français).

Ce répertoire matérialise la **traçabilité formelle** entre les obligations de la **loi ivoirienne
n°2013-450 du 19 juin 2013** relative à la protection des données à caractère personnel (et les exigences
de l'**ARTCI**) et l'architecture technique/organisationnelle de la plateforme HealthTech. Il constitue la
**base probante** du dossier d'homologation ARTCI ([#30](https://github.com/kortiene/HealthTech/issues/30)).

## 1. Objet

« Avoir de bons contrôles » ne suffit pas : l'ARTCI et le conseil juridique attendent, **pour chaque
obligation légale**, (1) quelle exigence technique/organisationnelle la satisfait, (2) où vit la **preuve**,
et (3) qui en est **responsable**. Ce volet produit donc une **matrice de conformité**
`exigence → contrôle(s) → preuve(s)` et ses artefacts d'appui.

## 2. Méthodologie

Approche en couches (chaque couche est un fichier de ce répertoire) :

1. **Sourcer le droit applicable** (avec le conseil juridique) : texte officiel de la loi n°2013-450,
   textes / décisions / lignes directrices de l'ARTCI, et toute règle sectorielle santé applicable.
   ⚠️ **Aucun numéro d'article n'est inventé** : les références non vérifiées portent la mention
   **`[à confirmer — conseil juridique]`** plutôt qu'une citation fausse.
2. **Atomiser les exigences** → [`exigences-legales.md`](./exigences-legales.md) (`REQ-LEX-NN`).
3. **Cataloguer les contrôles** → [`controles.md`](./controles.md) (`CTRL-NN`), chacun rattaché à son ADR /
   issue de vérité.
4. **Cataloguer les preuves** → recensées dans [`controles.md`](./controles.md) (`PREUVE-NN`) et reliées
   dans la matrice.
5. **Mapper et statuer** → [`loi-2013-450-artci-matrix.md`](./loi-2013-450-artci-matrix.md)
   (`exigence → contrôle(s) → preuve(s) → statut → responsable → validation juridique`).
6. **Identifier les écarts** → [`ecarts.md`](./ecarts.md) (toute exigence `Must` non couverte → issue
   porteuse, existante ou à créer).
7. **Faire valider** ligne à ligne par le conseil juridique → [`journal-validation-juridique.md`](./journal-validation-juridique.md).
8. **Alimenter [#30](https://github.com/kortiene/HealthTech/issues/30)** : la matrice validée + le registre
   + l'attestation de localisation deviennent des pièces du dossier d'homologation.

## 3. Arborescence des livrables

| Fichier | Rôle |
| --- | --- |
| [`README.md`](./README.md) | Ce point d'entrée : objet, méthodologie, conventions, glossaire. |
| [`exigences-legales.md`](./exigences-legales.md) | **Registre des exigences** atomisées (`REQ-LEX-NN`). |
| [`controles.md`](./controles.md) | **Catalogue des contrôles** (`CTRL-NN`) + **catalogue des preuves** (`PREUVE-NN`). |
| [`loi-2013-450-artci-matrix.md`](./loi-2013-450-artci-matrix.md) | **La matrice de conformité** (pièce maîtresse). |
| [`registre-des-traitements.md`](./registre-des-traitements.md) | Registre des activités de traitement. |
| [`cartographie-donnees-et-flux.md`](./cartographie-donnees-et-flux.md) | Inventaire des données + flux (frontière zero-knowledge). |
| [`journal-validation-juridique.md`](./journal-validation-juridique.md) | Journal de **sign-off** du conseil juridique. |
| [`ecarts.md`](./ecarts.md) | Registre des **écarts** → issue porteuse. |

## 4. Conventions d'identifiants

| Préfixe | Désigne | Exemple | Catalogue |
| --- | --- | --- | --- |
| `REQ-LEX-NN` | Une **exigence légale** atomisée (1 obligation = 1 ligne) | `REQ-LEX-19` (résidence) | [`exigences-legales.md`](./exigences-legales.md) |
| `CTRL-NN` | Un **contrôle** technique ou organisationnel | `CTRL-01` (AES-256-GCM client) | [`controles.md`](./controles.md) |
| `PREUVE-NN` | Un **artefact de preuve** démontrant un contrôle | `PREUVE-02` (« le serveur ne peut pas déchiffrer ») | [`controles.md`](./controles.md) |
| `#NN` | Une **issue GitHub** (`kortiene/HealthTech`) | [`#9`](https://github.com/kortiene/HealthTech/issues/9) | [`BACKLOG.md`](../../BACKLOG.md) |
| `ADR NNNN` | Une **décision d'architecture** | [`ADR 0005`](../adr/0005-storage-and-sovereign-hosting.md) | [`docs/adr/`](../adr/0000-index.md) |
| `ECART-NN` | Un **écart** de conformité tracé | `ECART-01` | [`ecarts.md`](./ecarts.md) |

## 5. Statuts de conformité (sémantique honnête)

Le projet est **greenfield côté fonctionnel** : aucune logique métier de sécurité n'est encore implémentée
(seul un squelette de monorepo existe). En conséquence, **la majorité des contrôles techniques sont au
statut `Planifié`** (décidés par ADR / backlog) et **non `Conforme`**. On n'affirme **jamais** « Conforme »
pour un contrôle non encore livré et prouvé.

| Statut | Signification |
| --- | --- |
| **Conforme** | Contrôle **livré** et **preuve disponible et vérifiée**. |
| **Partiel** | Contrôle décidé/partiellement livré, ou preuve incomplète/en cours. |
| **Planifié** | Contrôle **décidé** (ADR/issue) mais **pas encore implémenté** ; preuve **attendue**. |
| **Écart** | Exigence **sans** contrôle, **sans** preuve, ou **sans** issue porteuse → tracée dans [`ecarts.md`](./ecarts.md). |

La colonne **Validation juridique** est distincte du statut technique : une ligne peut être techniquement
`Planifié` tout en étant juridiquement « à valider ». **La matrice n'est « validée » que lorsque toutes les
exigences `Must` sont signées sans réserve bloquante** dans le journal de validation — c'est le **critère
d'acceptation** de l'issue #5.

## 6. Glossaire

| Terme | Définition (au sens de la loi n°2013-450 / pratique ARTCI) |
| --- | --- |
| **Donnée à caractère personnel** | Toute information relative à une personne physique identifiée ou identifiable. |
| **Donnée sensible** | Catégorie particulière (dont **données de santé**) bénéficiant d'une protection renforcée et, le cas échéant, d'un régime d'**autorisation préalable**. |
| **Responsable de traitement (RT)** | Personne/entité qui détermine les **finalités et moyens** du traitement. *(Répartition RT ↔ sous-traitant entre patient / médecin / plateforme : voir [ECART-06](./ecarts.md).)* |
| **Sous-traitant** | Entité traitant les données **pour le compte** du RT (ici, typiquement l'**hébergeur** souverain, [#8](https://github.com/kortiene/HealthTech/issues/8)). |
| **Personne concernée** | La personne physique à laquelle se rapportent les données (ici, le **patient**). |
| **Formalité préalable** | Démarche auprès de l'ARTCI avant mise en œuvre : **déclaration** ou **autorisation** selon la nature du traitement. |
| **Zero-knowledge** | Propriété d'architecture : le serveur ne détient que des **blobs chiffrés opaques** indexés par **UUID anonymes**, et **ne peut pas** déchiffrer le dossier. |
| **Crypto-effacement** | Rendre une donnée chiffrée **irrécupérable** en détruisant sa clé (mécanisme proposé pour le droit à l'effacement — **à valider juridiquement**, [ECART-02](./ecarts.md)). |
| **Blob** | Le dossier médical chiffré côté patient (AES-256-GCM), ≤ 500 Ko de texte brut, stocké opaque côté serveur. |
| **DPO / correspondant** | Personne chargée de la protection des données (désignation requise ou recommandée — **à confirmer**, [ECART-04](./ecarts.md)). |

## 7. Invariants produit non négociables (rappel, PRD §4)

La matrice doit **refléter et renforcer** ces invariants — jamais les diluer :

- Chiffrement client **AES-256-GCM** avant tout transit.
- Serveur **zero-knowledge** : blobs opaques + UUID anonymes ; **le serveur ne peut pas déchiffrer**.
- QR d'accès **éphémère ~120 s** ; déchiffrement **RAM-only** + **wipe** de fin de session / inactivité.
- **Résidence** des données en Côte d'Ivoire ; aucun cloud étranger dans le chemin de données.
- Dossier texte **≤ 500 Ko** ; **aucune image lourde** sur le téléphone (URL éphémère seulement).
- **Ne jamais** journaliser de données médicales en clair, de clés, ou de PII — **y compris dans ces
  artefacts de conformité**, qui ne contiennent **aucune donnée patient réelle** (uniquement catégories,
  schémas, flux).

> ⚠️ **Garde-fou anti « coche-la-case-au-prix-de-la-crypto » :** aucun contrôle de cette matrice ne doit
> jamais impliquer un **déchiffrement côté serveur** ni un **stockage de clé / PII en clair**. Si une
> exigence semble l'imposer, on crée un **écart** et on instruit une issue — on n'affaiblit jamais la
> cryptographie ni le modèle zero-knowledge.

## 8. Vérification (maintenabilité)

Le format tabulaire est **stable et automatiquement vérifiable**. Les contrôles de qualité recommandés
(lint Markdown + intégrité des liens, validation de schéma de la matrice, **gate de complétude**, gate de
**traçabilité backlog**, **invariant anti-régression conformité**, **gate de validation juridique**) sont
décrits dans la *Testing Plan* de la spec. **L'outillage concret (langage du script, action CI) reste à
confirmer avec [#3](https://github.com/kortiene/HealthTech/issues/3)** et n'est volontairement **pas**
figé ici (agnostique de la stack). La maquette house-style serait un script POSIX dans
[`scripts/`](../../scripts/) câblé via une recette `just` (cf. `just secrets-lint`).

## 9. Avertissement juridique

L'agent de code **structure et pré-remplit** ces artefacts. **L'interprétation et la validation du droit
ivoirien relèvent du conseil juridique** : l'exactitude des citations, la couverture des obligations et le
sign-off final sont de sa responsabilité ([journal de validation](./journal-validation-juridique.md)).
Tant que ce sign-off n'est pas acquis pour toutes les exigences `Must`, **la matrice est un projet, pas une
attestation de conformité**.
