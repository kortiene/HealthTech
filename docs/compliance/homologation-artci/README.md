# Dossier d'homologation ARTCI — HealthTech (loi n°2013-450)

> **Issue porteuse :** [#30 — Dossier d'homologation ARTCI](https://github.com/kortiene/HealthTech/issues/30)
> (Épic **E6 — Homologation & lancement** · Jalon **M4** · Effort **L** · Priorité **Must** · labels `compliance` `docs`).
> **Spec source :** [`specs/issue-30-artci-homologation-dossier.md`](../../../specs/issue-30-artci-homologation-dossier.md).
> **Dépend de :** [#5](https://github.com/kortiene/HealthTech/issues/5) (analyse de conformité) et [#25](https://github.com/kortiene/HealthTech/issues/25) (audit / pentest externe).
> **Langue faisant foi :** **français** (droit ivoirien francophone ; le conseil juridique et l'ARTCI travaillent sur le texte français) — cohérent avec [`docs/compliance/README.md`](../README.md).

> ⚠️ **Statut du dossier : PROJET DE SOUMISSION — NON SOUMISSIBLE EN L'ÉTAT.**
> L'homologation **n'est pas acquise** du seul fait de l'existence des pièces. À ce jour **0/22**
> exigences `Must` sont validées sans réserve par le conseil juridique, l'**attestation de localisation
> n'est pas signée**, et le **rapport de pentest n'est pas produit**. Voir
> [`readiness-dashboard.md`](./readiness-dashboard.md) pour les bloqueurs tracés.

---

## 1. Objet & destinataire

Ce répertoire consolide le **dossier d'homologation ARTCI** de la plateforme **HealthTech**, en application
de la **loi ivoirienne n°2013-450 du 19 juin 2013** relative à la protection des données à caractère
personnel et des exigences de l'**ARTCI** (Autorité de Régulation des Télécommunications/TIC de Côte
d'Ivoire).

- **Destinataire :** ARTCI (autorité de contrôle) + conseil juridique du projet (pré-dépôt).
- **Nature de la formalité :** **déclaration** ou **autorisation préalable** pour données de santé (données
  sensibles) — **`[à confirmer — conseil juridique]`**, voir [`formalite-prealable.md`](./formalite-prealable.md)
  et [ECART-05](../ecarts.md). **Aucun numéro d'article ni délai ARTCI n'est inventé dans ce dossier.**
- **Rôle du présent dossier :** point d'entrée unique et transmissible qui **indexe** chaque pièce probante,
  sa version, son statut et l'exigence couverte. Il **référence** les artefacts sources (liens relatifs) et
  **ne recopie pas** leur contenu.

Ce dossier est un **travail d'assemblage documentaire** au-dessus du corpus conformité/sécurité déjà en
dépôt ([#5](https://github.com/kortiene/HealthTech/issues/5), [#6](https://github.com/kortiene/HealthTech/issues/6),
[#25](https://github.com/kortiene/HealthTech/issues/25), [#26](https://github.com/kortiene/HealthTech/issues/26),
[#7](https://github.com/kortiene/HealthTech/issues/7), [#8](https://github.com/kortiene/HealthTech/issues/8)).

## 2. Résumé exécutif de l'architecture opposable

L'architecture de HealthTech est conçue pour la **minimisation** et le **contrôle par la personne
concernée** — invariants produit non négociables ([PRD §4](../README.md#7-invariants-produit-non-négociables-rappel-prd-4)) :

- **Local-first / zero-knowledge.** Le dossier médical est chiffré **côté patient en AES-256-GCM** (chiffrement
  authentifié) **avant tout transit**. Le serveur ne stocke que des **blobs opaques indexés par UUID
  anonymes** et **ne peut pas déchiffrer** le dossier (aucune clé, aucun chemin de déchiffrement serveur).
- **Accès éphémère patient-contrôlé.** Un **QR d'accès ~120 s** à usage unique porte la clé de session ; le
  professionnel **déchiffre en RAM uniquement** ; la session est **effacée (wipe)** en fin de consultation
  ou après inactivité.
- **Résidence stricte en Côte d'Ivoire.** Hébergement souverain in-country ; **aucun cloud étranger** dans
  le chemin de données ; garde-fou IaC `country == "CI"` + tripwire CI anti-régression.
- **Budget ≤ 500 Ko** du dossier texte ; **images lourdes jamais stockées sur l'appareil** (URL éphémère
  révocable servie in-country uniquement).

> **Garde-fou anti « coche-la-case-au-prix-de-la-crypto ».** Si une exigence ARTCI semblait imposer un
> déchiffrement serveur ou un stockage de clé/PII en clair, on **ouvre un écart** ([`ecarts.md`](../ecarts.md)),
> on **ne cède pas**. Aucune pièce de ce dossier ne décrit ni ne justifie un tel affaiblissement.

## 3. Sommaire du dossier

| # | Fichier | Rôle |
| --- | --- | --- |
| 1 | [`README.md`](./README.md) | Ce point d'entrée : objet, destinataire, résumé opposable, avertissements. |
| 2 | [`piece-list.md`](./piece-list.md) | **Index probatoire** : une ligne `PIECE-NN` par pièce, avec preuve source `PREUVE-NN`, exigence(s) couverte(s), emplacement, statut dossier, propriétaire. |
| 3 | [`readiness-dashboard.md`](./readiness-dashboard.md) | **Tableau de bord de préparation** : synthèse chiffrée, critère de soumission, bloqueurs tracés. |
| 4 | [`formalite-prealable.md`](./formalite-prealable.md) | **Procédure de formalité** ARTCI : nature `[à confirmer]`, destinataire, format, suivi du récépissé. |
| 5 | [`submission-checklist.md`](./submission-checklist.md) | **Checklist de complétude** (gate humain) avant tout dépôt réel. |

**Pièces maîtresses référencées** (sources de vérité, non recopiées ici) : la
[matrice de conformité](../loi-2013-450-artci-matrix.md), le [catalogue contrôles & preuves](../controles.md),
le [registre des traitements](../registre-des-traitements.md), la
[cartographie données & flux](../cartographie-donnees-et-flux.md), l'
[attestation de localisation](../attestation-localisation-donnees.md), le
[journal de validation juridique](../journal-validation-juridique.md) et le
[registre des écarts](../ecarts.md).

## 4. Conventions

- **`PIECE-NN`** — numéro de pièce du dossier (ordre de soumission logique), défini dans
  [`piece-list.md`](./piece-list.md). Chaque `PIECE-NN` est adossée à une **preuve source `PREUVE-NN`** du
  [catalogue](../controles.md).
- **Statut dossier** (dérivé honnêtement du statut de la preuve source) : `Prête` (livrée **et** vérifiée) ·
  `Partielle` · `À produire` · `Bloquante`. **Règle d'or : aucune pièce n'est « Prête » tant que sa preuve
  source n'est pas `Existant` (livrée et vérifiée).**
- Les autres conventions d'identifiants (`REQ-LEX-NN`, `CTRL-NN`, `PREUVE-NN`, `ECART-NN`, `ADR NNNN`, `#NN`)
  sont celles du volet #5 — voir [`docs/compliance/README.md` §4](../README.md#4-conventions-didentifiants).

## 5. Avertissement de statut

Ce dossier est un **projet de soumission** tant que les **bloqueurs** listés dans
[`readiness-dashboard.md`](./readiness-dashboard.md) ne sont pas levés. **L'existence d'une pièce ne vaut
pas conformité** : une pièce n'est « Prête » que **livrée et vérifiée**, et l'homologation n'est atteinte
que par la **décision effective de l'ARTCI** (`PREUVE-13`, aujourd'hui « À produire »). Rien dans ce dossier
n'affirme que l'homologation est obtenue ou que la soumission est complète.

## 6. Avertissement juridique

L'agent de code **structure et pré-remplit** ce dossier. **L'interprétation et la validation du droit
ivoirien relèvent du conseil juridique** : l'exactitude des citations légales, la nature de la formalité, la
couverture des obligations et le **sign-off** final sont de sa responsabilité
([journal de validation](../journal-validation-juridique.md)). Les références non confirmées portent la
mention **`[à confirmer — conseil juridique]`**. Le **dépôt effectif** auprès de l'ARTCI et l'obtention du
récépissé/décision sont une **démarche humaine/juridique externe**, hors périmètre d'un agent de code.
