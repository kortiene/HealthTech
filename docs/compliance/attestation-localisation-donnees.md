# Attestation de localisation des données — HealthTech

> **Pièce de conformité** (`PREUVE-05`) du critère d'acceptation **#8.2** (« attestation de localisation
> des données »). Démontre le contrôle **CTRL-08** (hébergement souverain in-country) et alimente
> l'exigence **REQ-LEX-19** (résidence des données). Référencée depuis
> [`loi-2013-450-artci-matrix.md`](./loi-2013-450-artci-matrix.md) et [`controles.md`](./controles.md),
> destinée au **dossier d'homologation ARTCI** ([#30](https://github.com/kortiene/HealthTech/issues/30)).
>
> ⚠️ **Statut : modèle prêt — signature en attente du bring-up.** Ce document fixe le **périmètre**, la
> **forme** et les **preuves exigées** de l'attestation. Les champs *[À COMPLÉTER]* sont renseignés à la
> **mise en service réelle** sur les hôtes de l'opérateur souverain retenu ([ADR 0009](../adr/0009-sovereign-operator-selection.md),
> décision de procurement #8 / P0 — **non encore tranchée**). Tant que le bring-up n'a pas eu lieu et que
> l'opérateur n'est pas contracté, **aucune attestation signée ne peut être affirmée** : la matrice de
> conformité garde donc CTRL-08 en `Planifié` et PREUVE-05 « À produire ».

## 1. Objet

La plateforme HealthTech est **local-first / zero-knowledge** : le dossier médical est chiffré côté
patient en **AES-256-GCM** avant tout transit ; le serveur ne stocke que des **blobs opaques indexés par
UUID anonymes** (aucune donnée nominative, aucune clé, aucun plaintext — [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md)).
Même illisible, cette donnée **doit résider physiquement en Côte d'Ivoire** (loi n°2013-450 ; exigences
ARTCI ; PRD §4/§5). La présente attestation établit que **l'intégralité du chemin de données** est
hébergée sur le territoire national, sans aucun cloud managé étranger.

## 2. Opérateur & datacenter (implantation)

| Élément | Valeur |
| --- | --- |
| Opérateur d'hébergement | *[À COMPLÉTER — opérateur retenu, ADR 0009]* |
| Datacenter / site | *[À COMPLÉTER — nom du datacenter]* |
| Adresse physique (Côte d'Ivoire) | *[À COMPLÉTER — adresse complète, commune]* |
| Licence / éligibilité ARTCI | *[À COMPLÉTER — n° de licence / référence d'autorisation]* |
| Référence contrat / DPA | *[À COMPLÉTER — clauses résidence, sécurité, sous-traitance — CTRL-26 / PREUVE-07]* |

## 3. Périmètre couvert (tout le chemin de données reste en Côte d'Ivoire)

| Composant | Rôle | Hébergement |
| --- | --- | --- |
| Backend Axum (×2, HA) | Service applicatif derrière le reverse-proxy | **Côte d'Ivoire** |
| MinIO | Stockage des blobs chiffrés + médias chiffrés (S3-compatible) | **Côte d'Ivoire** |
| PostgreSQL primaire | Métadonnées **non identifiantes** uniquement | **Côte d'Ivoire** |
| PostgreSQL réplica | Réplication / warm standby (HA in-country) | **Côte d'Ivoire** |
| Reverse-proxy TLS (Caddy/Nginx) + WAF | Terminaison TLS, filtrage | **Côte d'Ivoire** |
| Sauvegardes chiffrées (MinIO + Postgres) | Restauration | **Côte d'Ivoire** (aucune réplication étrangère) |
| **State backend Terraform** | État IaC (peut embarquer des secrets) | **Côte d'Ivoire**, chiffré (aucun backend managé étranger) |
| Coffre de secrets (SOPS + age) | Clés age in-country, secrets opérationnels | **Côte d'Ivoire** ([ADR 0007](../adr/0007-secrets-and-environments.md)) |

**Aucun** cloud managé étranger (AWS/GCP/Azure/…), **aucun** KMS ni service managé hors-CI n'intervient
dans le chemin de données, **y compris** pour les sauvegardes et l'état Terraform.

## 4. Preuves de localisation

| Preuve | Référence | Disponibilité |
| --- | --- | --- |
| Licence / attestation d'éligibilité ARTCI de l'opérateur | §2 | *[À joindre au bring-up]* |
| Contrat / DPA portant clause de résidence en Côte d'Ivoire | §2, CTRL-26 | *[À joindre au bring-up]* |
| Garde-fou IaC `country == "CI"` (non surchargeable) | `infra/terraform/main.tf`, `infra/ansible/playbook.yml` (PREUVE-06) | **Existant** |
| Garde-fou CI anti-régression résidence (fail-closed à chaque commit) | [`scripts/check-residency.sh`](../../scripts/check-residency.sh) + `.github/workflows/secrets.yml` | **Existant** |
| Inventaires Ansible ne listant que des hôtes in-country | `infra/ansible/inventories/{staging,prod}` | *[Renseignés au bring-up]* |
| State backend chiffré in-country (endpoint `.ci`/privé, jamais `amazonaws.com`) | `infra/terraform/main.tf` (TODO #8) | *[Configuré au bring-up]* |

> Les preuves marquées **Existant** sont des contrôles **techniques** déjà en place dans le dépôt et
> vérifiables sans credentials (`just infra-residency`, `just infra-validate`). Elles établissent que la
> chaîne IaC **interdit structurellement** un hébergement étranger ; l'attestation **signée** (preuves
> opérateur §2) requiert l'opérateur contracté et le bring-up.

## 5. Base légale

La formulation exacte de l'obligation de localisation stricte (obligation statutaire dure vs encadrement
des transferts transfrontaliers) est **en cours d'arbitrage juridique** — voir
[`ecarts.md`](./ecarts.md) **ECART-07** (impacte REQ-LEX-19/REQ-LEX-20). Le libellé final de la clause de
base légale ci-dessous est figé à la résolution d'ECART-07 :

> *[À COMPLÉTER après ECART-07 — base légale précise : article(s) de la loi n°2013-450 / exigence ARTCI.]*

## 6. Signature

| Champ | Valeur |
| --- | --- |
| Date d'établissement | *[À COMPLÉTER]* |
| Signataire (responsable de traitement / DPO) | *[À COMPLÉTER — cf. ECART-04 désignation DPO]* |
| Date de la mise en service in-country (bring-up #8.1) | *[À COMPLÉTER]* |
| Validation juridique | *Non — en attente* ([journal](./journal-validation-juridique.md)) |

## 7. Références

- [ADR 0005 — Storage & sovereign hosting](../adr/0005-storage-and-sovereign-hosting.md)
- [ADR 0007 — Secrets & environments](../adr/0007-secrets-and-environments.md)
- [ADR 0009 — Sovereign operator selection](../adr/0009-sovereign-operator-selection.md)
- [Matrice de conformité](./loi-2013-450-artci-matrix.md) (REQ-LEX-19/20/24) · [Contrôles & preuves](./controles.md) (CTRL-08/09/26, PREUVE-05/06/07)
- [Registre des écarts](./ecarts.md) (ECART-07) · Dossier ARTCI [#30](https://github.com/kortiene/HealthTech/issues/30)
