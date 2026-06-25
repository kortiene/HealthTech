# Provisionnement de l'hébergement souverain en Côte d'Ivoire (#8)

> **Issue :** #8 — Provisionnement de l'hébergement en Côte d'Ivoire · **Épic :** E7 — Hébergement souverain & backend zero-knowledge · **Jalon :** M0 — Fondations & Conformité · **Effort :** L · **Priorité :** Must · **Étiquettes :** `infra` `compliance`
>
> **Type :** spec de planification — **ne pas implémenter** dans cette phase.
>
> **Critères d'acceptation (BACKLOG / issue) :** (1) infrastructure opérationnelle sur le territoire national ; (2) attestation de localisation des données.

## Problem Statement

La plateforme HealthTech est **local-first / zero-knowledge** : le dossier médical est chiffré côté patient en AES-256-GCM avant tout transit, et le serveur ne stocke que des blobs opaques indexés par UUID anonymes. Même illisible, cette donnée **doit résider physiquement en Côte d'Ivoire** pour satisfaire l'**ARTCI** et la **loi n°2013-450** relative à la protection des données à caractère personnel (PRD §4, §5). Aucun cloud managé étranger n'est admis dans le chemin de données (compute, base de métadonnées, stockage de blobs/médias, sauvegardes, ni backend d'état Terraform).

Aujourd'hui le dépôt contient un **scaffold structure-only** explicitement marqué `TODO(#8)` :
- `infra/terraform/main.tf` — aucun provider réel, aucune ressource déclarée, garde-fou de résidence (`country == "CI"`) déjà en place ;
- `infra/ansible/playbook.yml` — aucun rôle de service réel, garde-fous env/résidence en place ;
- ADR 0005 (stockage & hébergement souverain) et ADR 0007 (secrets & environnements, SOPS+age) acceptés ;
- bundles de secrets chiffrés `secrets/{staging,prod}/`.

Le gap : (a) **sélectionner** un opérateur/datacenter national éligible ARTCI ; (b) **provisionner réellement** le footprint in-country via l'IaC existante (remplacer les placeholders par des ressources, un provider, un state backend chiffré in-country, et des rôles Ansible) ; (c) produire l'**attestation de localisation des données** versée au dossier d'homologation ARTCI (#30). Le point (a) est une **décision de procurement** (long-lead, hors-code) ; cette spec cadre ce qu'un agent de code peut exécuter une fois l'opérateur choisi, et isole ce qui reste une décision humaine à confirmer.

## Goals

- **G1.** Documenter le critère de sélection et la décision d'opérateur/datacenter national éligible ARTCI (via un ADR de suivi ou un addendum à ADR 0005), avec preuve d'implantation physique en Côte d'Ivoire.
- **G2.** Compléter `infra/terraform/` : provider de l'opérateur local choisi, définitions VM/bare-metal du footprint ADR 0005 (Axum ×2, MinIO, Postgres primaire+réplica, reverse-proxy TLS Caddy/Nginx, WAF), réseau privé, security groups, volumes de sauvegarde chiffrés in-country, et **state backend chiffré in-country**.
- **G3.** Compléter `infra/ansible/` : rôles par service (`axum_backend`, `minio`, `postgres_primary`, `postgres_replica`, `caddy_tls`, `waf`, `backups`) + injection des secrets opérationnels depuis le vault SOPS/age vers un `EnvironmentFile` systemd `0600` (jamais world-readable, jamais en argv).
- **G4.** Préserver et **renforcer** les garde-fous de résidence : `country` reste épinglé à `CI`, et la CI échoue si une ressource/host/backend étranger est introduit dans le chemin de données.
- **G5.** Rendre le `staging` in-country **reproductible depuis l'IaC** (critère d'acceptation de #4), puis amener un environnement opérationnel sur le territoire national (critère #8.1).
- **G6.** Produire l'**attestation de localisation des données** (document de conformité) — critère #8.2 — et la lier à la matrice de conformité (#5) et au dossier ARTCI (#30).
- **G7.** Définir/documenter la HA in-country et le runbook d'unseal après coupure courant/réseau (risque ADR 0005), sans aucun failover étranger.

## Non-Goals

- **Implémentation de l'API zero-knowledge de stockage de blobs (`PUT/GET /blob/{uuid}`)** — c'est #9, qui *consomme* cette infrastructure ; cette spec ne l'implémente pas.
- **Déport des images médicales lourdes + URL éphémère** — c'est #23 ; on provisionne le store objet (MinIO) qui le supportera, mais pas la logique applicative.
- **File offline SQLCipher / synchronisation** (#21, #22), **optimisation réseau dégradé** (#24) — côté client/applicatif.
- **Constitution complète du dossier d'homologation ARTCI** (#30) — on fournit *une pièce* (l'attestation de localisation), pas le dossier entier.
- **Choix de la stack applicative** (#1) — déjà tranché par les ADR 0001-0008 ; cette spec s'aligne dessus sans le rouvrir.
- **Gestion des secrets / SOPS+age** (#4, ADR 0007) — déjà livré ; on le *consomme* et on complète seulement le state backend chiffré qui en dépend.
- **Toute opération git/GitHub** (branches, commits, PR, issues d'écart) — hors périmètre de cette phase ADW.
- **Signature de contrat réelle, paiement, ou commande matérielle** — décision business/procurement humaine ; la spec la cadre mais ne l'exécute pas.

## Relevant Repository Context

**État du dépôt.** Contrairement à la note « greenfield » du BACKLOG (rédigée au démarrage), le socle M0 est en grande partie posé. Pour ce domaine précis :

| Élément | Chemin | État actuel |
| --- | --- | --- |
| ADR hébergement/stockage | `docs/adr/0005-storage-and-sovereign-hosting.md` | **Accepté.** MinIO (blobs+médias), Postgres 16 (métadonnées non-identifiantes), hébergement in-country only, IaC Terraform+Ansible, SPOF de dispo accepté + HA in-country. |
| ADR secrets & environnements | `docs/adr/0007-secrets-and-environments.md` | **Accepté.** SOPS+age, recipients par-env, in-country pour staging/prod. *Dépend de #8 pour la mise en service réelle.* |
| Index ADR | `docs/adr/0000-index.md` | À mettre à jour si un ADR de suivi est ajouté. |
| IaC — Terraform | `infra/terraform/main.tf`, `environments/{dev,staging,prod}.tfvars`, `README.md` | **Placeholder.** Garde-fou résidence `country == "CI"` (non surchargeable), sélection d'env, variables de sizing non-secrètes, secrets injectés `TF_VAR_*` (`default=null`, `sensitive`), outputs (`residency_note`, `injected_secrets_present`). **Aucune ressource ni provider.** |
| IaC — Ansible | `infra/ansible/playbook.yml`, `inventories/{dev,staging,prod}`, `group_vars/*.yml`, `README.md` | **Placeholder.** Garde-fous env+résidence, sketch d'injection secrets `0600` commenté. **Aucun rôle de service.** |
| Dev local | `infra/dev/compose.yaml` | Postgres + MinIO local, creds throwaway (hors résidence, env `dev`). |
| Secrets | `secrets/{staging,prod}/services.sops.yaml(.example)`, `/.sops.yaml` | Bundles chiffrés au repos + recipients age publics par-env. |
| Validation IaC | `justfile` cible `infra-validate` | `terraform fmt -check` + `init -backend=false` + `validate` + `ansible-playbook --syntax-check` par env. Credential-free. |
| Hygiène secrets | `justfile` cible `secrets-lint`, `.github/workflows/secrets.yml`, `.gitleaks.toml`, `scripts/check-secrets.sh` | gitleaks + tripwire, fail-closed, en CI. |
| Conformité | `docs/compliance/` (matrice loi 2013-450/ARTCI, exigences, contrôles, écarts) | Matrice exigence→contrôle→preuve. **ECART-07** (base légale exacte de la localisation stricte) **ouvert** — à trancher juridiquement ; impacte la formulation de l'attestation. |
| Backend (consommateur) | `backend/` (Rust/Axum), `backend/src/config.rs` | Redaction des secrets en `Debug`/`Display` ; consomme `APP_ENV`, `DATABASE_URL`, `MINIO_*`. |

**Conventions à respecter.** IaC paramétrée par environnement via un **sélecteur unique** (`-var-file=environments/<env>.tfvars` / `-i inventories/<env>` / `APP_ENV`) ; **aucun secret en clair** committé (seulement `*.sops.yaml` chiffrés + recipients publics + `*.example`) ; garde-fou de résidence non surchargeable ; placeholders portant des `TODO(#8)` explicites + une section « Status » honnête (« ne stand up live infrastructure »).

**Décisions encore ouvertes (à confirmer, ne pas présumer) :**
- **Opérateur/datacenter national précis** (VITIB-Grand-Bassam ou autre opérateur licencié) — non tranché ; conditionne le provider Terraform et le state backend.
- **Provider Terraform disponible** chez l'opérateur (provider natif vs SSH/`null_resource`/bare-metal piloté par Ansible si l'opérateur n'a pas de provider) — à confirmer après G1.
- **Reverse-proxy : Caddy vs Nginx** (ADR 0005 dit « Caddy/Nginx ») — à figer.
- **Stratégie TLS/CA** : ACME (si une AC publique accessible in-country) vs AC interne in-country ; durée de vie des certs — flaggé pour #8 dans `infra/README.md`.
- **WAF** : produit/implémentation (ModSecurity/Coraza devant Caddy, ou WAF de l'opérateur) — à choisir.
- **Mécanisme d'unseal après coupure** : age private key présente sur l'hôte vs OpenBao in-country (unseal manuel/HSM) — ADR 0007 le laisse ouvert.
- **Base légale exacte de la localisation** (ECART-07) — décision juridique qui cadre le libellé de l'attestation.

## Proposed Implementation

Découpage en **phases** ; les phases « décision » (P0, P6) requièrent une confirmation humaine, les phases « code » (P1–P5, P7) sont exécutables par un agent une fois la décision prise.

### P0 — Sélection de l'opérateur souverain (décision, hors-code)
1. Établir une grille de sélection : éligibilité/licence ARTCI, implantation physique CI vérifiable, capacité bare-metal/VM, réseau privé, sauvegarde in-country, SLA/disponibilité, existence d'un provider Terraform (ou accès SSH pour pilotage Ansible), durée d'approvisionnement.
2. Documenter la décision dans un **ADR de suivi** (`docs/adr/0009-sovereign-operator-selection.md`) ou un addendum à ADR 0005, avec la preuve d'implantation (licence/attestation opérateur). Mettre à jour `docs/adr/0000-index.md`.

### P1 — Terraform : provider, état chiffré, ressources
3. Renseigner `required_providers` avec le provider de l'opérateur (P0). **Aucun** `aws`/`google`/`azurerm` dans le chemin de données.
4. Configurer un **state backend chiffré et in-country** (l'état peut embarquer des secrets) — pas de backend managé étranger. Lever le `TODO(#8)` correspondant dans `main.tf` et `infra/terraform/README.md`.
5. Déclarer les ressources du footprint ADR 0005, dimensionnées par les variables existantes (`backend_instance_count`, `postgres_replica_count`) : VMs/bare-metal Axum ×2, MinIO, Postgres primaire + réplica, reverse-proxy TLS, WAF, réseau privé, security groups (least-privilege, n'exposer que le proxy), volumes de **sauvegarde chiffrés in-country**.
6. **Conserver** le garde-fou `country == "CI"` et l'output `residency_note` ; ajouter, si le provider l'expose, une validation/`precondition` que la **région/zone de chaque ressource est en CI**.
7. Garder les secrets en `TF_VAR_*` injectés via `sops exec-env` ; ne jamais introduire de valeur en clair dans les tfvars.

### P2 — Ansible : rôles de service + injection secrets
8. Éclater le playbook en rôles : `axum_backend` (×2), `minio`, `postgres_primary`, `postgres_replica` (réplication streaming/warm standby), `caddy_tls`, `waf`, `backups`.
9. Implémenter l'injection : `lookup('community.sops.sops', …)` (clé age privée in-country) → `EnvironmentFile` systemd `0600` root-only, avec `no_log: true`. Remplacer le sketch commenté. Variables non-secrètes depuis `group_vars/<env>.yml` (déjà présents : `secrets_env_file`, `sops_secrets_path`).
10. **Conserver** les garde-fous `assert` env∈{dev,staging,prod} et `country == 'CI'`.

### P3 — HA, sauvegardes & unseal in-country
11. Réplication Postgres primaire→réplica + warm standby ; sauvegardes chiffrées MinIO+Postgres sur volume in-country ; **aucun failover étranger** (SPOF assumé, ADR 0005).
12. Documenter/automatiser le **runbook d'unseal après coupure** (clé age in-country présente au boot, ou OpenBao in-country selon décision ADR 0007) — un nœud staging/prod doit redémarrer sans ressaisie de secrets au-delà de l'unseal documenté.

### P4 — Garde-fous de résidence en CI (anti-régression)
13. Ajouter à la CI un **contrôle de résidence** échouant si une ressource/provider/host/backend étranger apparaît (ex. script qui grep les providers `aws|google|azurerm` et les inventaires/backends pour des endpoints hors-CI, branché à côté de `infra-validate`/`secrets-lint`). `log()` explicite de tout ce qui est volontairement hors-périmètre.
14. Étendre `just infra-validate` pour couvrir les nouveaux fichiers (rester credential-free : `validate`/`--syntax-check` sans toucher au réseau ni aux creds).

### P5 — Reproductibilité staging puis bring-up
15. Vérifier le chemin reproductible (`infra/README.md`) : `sops -d … > 0600 env`, `terraform apply -var-file=environments/staging.tfvars`, `ansible-playbook -i inventories/staging … -e env=staging`.
16. **Bring-up réel in-country** (sur hôtes de l'opérateur P0) — atteint le critère #8.1 « infrastructure opérationnelle sur le territoire national ».

### P6 — Attestation de localisation des données (critère #8.2)
17. Rédiger `docs/compliance/attestation-localisation-donnees.md` : opérateur, datacenter, adresse/implantation CI, périmètre (compute, métadonnées, blobs, médias, sauvegardes, state backend), preuve (licence ARTCI opérateur, contrat/engagement de résidence), date, signataire, et lien vers la base légale (ECART-07). Référencer ce document depuis la matrice de conformité (#5) et le préparer pour le dossier ARTCI (#30).

### P7 — Mise à jour de la documentation
18. Aligner `infra/README.md`, `infra/terraform/README.md`, `infra/ansible/README.md` (retirer/qualifier « structure-only scaffold » devenu opérationnel, lever les `TODO(#8)`), ADR 0005/0007, BACKLOG (#8 → fait), et docs de conformité.

## Affected Files / Packages / Modules

**À modifier**
- `infra/terraform/main.tf` — provider, state backend chiffré in-country, ressources du footprint, conserver le garde-fou résidence.
- `infra/terraform/environments/{dev,staging,prod}.tfvars` — sizing par env (ne jamais y mettre `country` ni de secret).
- `infra/terraform/README.md` — lever les `TODO(#8)`, documenter provider + state backend.
- `infra/ansible/playbook.yml` — passer aux rôles, implémenter l'injection secrets `0600`.
- `infra/ansible/group_vars/{dev,staging,prod}.yml` — variables non-secrètes par service.
- `infra/ansible/inventories/{dev,staging,prod}` — hôtes réels in-country (staging/prod).
- `infra/ansible/README.md`, `infra/README.md` — statut opérationnel, runbooks HA/unseal/sauvegarde.
- `justfile` — étendre `infra-validate` ; ajouter une cible de contrôle de résidence si pertinent.
- `docs/adr/0000-index.md`, `docs/adr/0005-storage-and-sovereign-hosting.md`, `docs/adr/0007-secrets-and-environments.md` — addendum/références.
- `BACKLOG.md` — statut #8 ; `docs/compliance/` (matrice, contrôles) — lien vers l'attestation.

**À créer**
- `infra/ansible/roles/{axum_backend,minio,postgres_primary,postgres_replica,caddy_tls,waf,backups}/` — rôles.
- `docs/adr/0009-sovereign-operator-selection.md` (ou addendum ADR 0005) — décision d'opérateur.
- `docs/compliance/attestation-localisation-donnees.md` — attestation (critère #8.2).
- Éventuel `scripts/check-residency.sh` + workflow CI associé (`.github/workflows/`).

**À lire (référence, ne pas modifier sans raison)**
- `PRD_HealthTech.md` (§4 résidence, contraintes), `secrets/README.md`, `/.sops.yaml`, `backend/src/config.rs` (clés consommées), `docs/compliance/ecarts.md` (ECART-07), `docs/threat-model/stride-threat-model.md`.

## API / Interface Changes

**Aucune API applicative publique** (réseau, CLI app, QR/access-token) n'est introduite par #8. Les surfaces touchées sont **opérationnelles** :
- **Variables Terraform** (déjà définies) : `environment`, `backend_instance_count`, `postgres_replica_count` ; secrets `TF_VAR_*` (`postgres_app_password`, `minio_root_secret`, `presigned_url_signing_key`).
- **Outputs Terraform** : `residency_note`, `environment`, `name_prefix`, `injected_secrets_present` (à conserver ; ajouts possibles : endpoints internes — **jamais** de secret en valeur).
- **Sélecteurs CLI ops** : `-var-file=environments/<env>.tfvars`, `-i inventories/<env>`, `-e env=<env>`.
- Les endpoints réseau réels (`PUT/GET /blob/{uuid}`) appartiennent à **#9**, pas à #8.

## Data Model / Protocol Changes

**Aucune** modification du schéma de dossier, du format de blob chiffré, du protocole QR, ou de la sérialisation applicative. #8 provisionne le substrat. Côté persistance opérationnelle : la base de métadonnées Postgres ne contient que des données **non-identifiantes** (UUID anonyme de blob, version/taille du ciphertext, timestamps, params KDF publics, bookkeeping de sync) — **jamais** de PII, de clé, ni de plaintext (ADR 0005). Le store objet MinIO ne contient que des blobs déjà chiffrés client-side + médias chiffrés ; le chiffrement-at-rest serveur est une **défense en profondeur** sous le chiffrement client (la confidentialité n'en dépend jamais).

## Security & Compliance Considerations

- **Zero-knowledge préservé.** L'infra ne voit jamais de plaintext : le dossier est chiffré client-side **AES-256-GCM** avant transit ; le serveur stocke des **blobs opaques indexés par UUID anonymes**. #8 ne doit introduire aucun composant capable de déchiffrer.
- **Résidence des données (non-négociable).** Tout le chemin de données — compute, métadonnées, blobs, médias, sauvegardes, **et le state backend Terraform** — reste physiquement en Côte d'Ivoire (ARTCI / loi n°2013-450). **Aucun cloud managé étranger.** Garde-fou `country == "CI"` non surchargeable + contrôle CI anti-régression.
- **Secrets.** Jamais de secret en clair committé ; injection SOPS/age (clé privée in-country) vers `EnvironmentFile` `0600` root-only, `no_log: true`, jamais en argv. Le state Terraform (qui peut embarquer des secrets) doit être chiffré et in-country.
- **Pas de fuite via logs.** Ne jamais logguer de plaintext médical, de clé, ni de PII ; le backend redige déjà ses secrets (`config.rs`) ; les tâches Ansible manipulant des secrets portent `no_log: true` ; les outputs Terraform sensibles restent `sensitive`/booléens de présence.
- **URL éphémères médias.** MinIO émet des presigned/ephemeral URLs court-TTL, scoppées par objet et révocables (support de #23) ; la **clé de signature presigned-URL** gate l'accès média — rotation délibérée (ADR 0005/0007).
- **Budget ≤ 500 Ko / médias hors device.** L'infra respecte le modèle PRD : dossier texte ≤ 500 Ko, images lourdes **jamais** sur le device patient (seulement une URL éphémère) — MinIO héberge les médias chiffrés in-country.
- **QR éphémère (~120 s) & déchiffrement RAM-only + wipe.** Non implémenté par #8 (client/#16-#19) ; à **ne pas** contredire ni affaiblir.
- **Disponibilité.** SPOF de datacenter unique **assumé** (aucun failover étranger permis) ; mitigé par HA in-country (Postgres primaire+réplica, warm standby) et clients offline-first. Runbook d'unseal in-country après coupure.
- **Pas de back-door.** Aucun accès serveur de déchiffrement, même pour le break-glass (ECART-08).

## Testing Plan

> La stack de test n'est pas un sujet ici (IaC) ; les vérifications sont **credential-free** et statiques par défaut.

- **Validation IaC (statique, CI).** `just infra-validate` étendu : `terraform fmt -check`, `init -backend=false`, `validate`, et `ansible-playbook --syntax-check` pour chaque env (dev/staging/prod) — sans creds ni réseau.
- **Contrôle de résidence (CI, nouveau).** Test échouant si un provider/host/backend/endpoint étranger apparaît dans `infra/` (grep `aws|google|azurerm`, inventaires hors-CI, state backend managé étranger). Doit aussi vérifier que `country` n'est pas surchargé dans un tfvars.
- **Hygiène secrets (CI, existant).** `just secrets-lint` (gitleaks + tripwire) reste vert ; aucun secret en clair introduit.
- **Tests de garde-fou (négatifs).** `terraform plan` avec `country` forcé ≠ `CI` **doit échouer** ; `ansible-playbook` avec `-e country=XX` **doit échouer** (assert).
- **Reproductibilité staging.** Rejouer le chemin `infra/README.md` sur un hôte in-country : provisionnement idempotent (un second `apply`/`playbook` ne change rien).
- **Résilience (manuel/runbook, post bring-up).** Simulation de coupure courant/réseau d'un nœud : unseal documenté, redémarrage des services, réplica Postgres rattrape ; les consultations offline-first survivent (côté client, déjà couvert ailleurs).
- **Sauvegarde/restauration.** Test de restauration d'une sauvegarde chiffrée MinIO+Postgres in-country.
- **Documentation.** Vérifier que l'attestation et les ADR sont liés depuis la matrice de conformité et le dossier ARTCI (#30).

## Documentation Updates

- **ADR :** ajouter `0009-sovereign-operator-selection.md` (ou addendum ADR 0005) + mise à jour de `0000-index.md` ; lever les `TODO(#8)` dans ADR 0005/0007.
- **infra/** : `README.md`, `terraform/README.md`, `ansible/README.md` — passer de « structure-only scaffold » à statut opérationnel, documenter provider, state backend, rôles, runbooks HA/unseal/sauvegarde.
- **Conformité :** créer `docs/compliance/attestation-localisation-donnees.md` (critère #8.2) ; la référencer depuis `docs/compliance/loi-2013-450-artci-matrix.md` et `controles.md` ; noter l'incidence d'ECART-07 (base légale de la localisation).
- **BACKLOG.md :** marquer #8 réalisé ; retirer #8 du risque « long-lead » une fois provisionné.
- **PRD :** §4/§5 déjà alignés — confirmer la traçabilité vers l'attestation, pas de réécriture nécessaire.

## Risks and Open Questions

1. **Long-lead procurement (chemin critique).** Le choix/contrat opérateur (P0) peut prendre des semaines et bloque P1–P6 ; risque BACKLOG explicite (#8). *À lancer immédiatement.*
2. **Provider Terraform de l'opérateur.** Si l'opérateur national n'expose pas de provider Terraform, le provisionnement bascule vers du bare-metal piloté par Ansible/SSH (`null_resource`/`remote-exec` ou inventaire manuel) — **décision à confirmer** après P0.
3. **State backend chiffré in-country.** Aucun backend managé étranger admis ; nécessite une solution in-country (ex. backend chiffré sur stockage objet MinIO local, ou état chiffré au repos sur volume in-country) — **à concevoir**.
4. **Unseal après coupure.** Clé age in-country au boot vs OpenBao in-country (unseal manuel/HSM) — laissé ouvert par ADR 0007 ; impacte le runbook et l'automatisation.
5. **SPOF de disponibilité.** Datacenter unique sans failover étranger ; la HA in-country et l'offline-first sont la seule mitigation — à valider face au KPI « 100 % des consultations sans perte ».
6. **ECART-07 (base légale).** La formulation exacte de la localisation stricte (obligation statutaire vs mitigation de transfert) est ouverte côté juridique ; conditionne le libellé de l'attestation (#8.2) et des exigences résidence.
7. **TLS/CA & WAF.** ACME vs AC interne in-country, et le produit WAF, restent à figer (flaggés dans `infra/README.md`).
8. **Validité du bring-up en environnement automatisé.** Le bring-up réel exige des creds/hosts in-country indisponibles en CI ; la CI reste credential-free (validate/syntax-check) — ne pas laisser croire qu'un cluster live tourne tant qu'il n'est pas provisionné.

## Implementation Checklist

> Étapes pour un agent ultérieur. Les étapes ⚠️ requièrent une **décision/confirmation humaine** avant exécution.

- [ ] **⚠️ P0.1** Établir la grille de sélection opérateur (éligibilité ARTCI, implantation CI, capacité, provider, SLA, délai) et trancher l'opérateur/datacenter.
- [ ] **⚠️ P0.2** Rédiger `docs/adr/0009-sovereign-operator-selection.md` (ou addendum ADR 0005) avec preuve d'implantation ; mettre à jour `docs/adr/0000-index.md`.
- [ ] **P1.1** Renseigner `required_providers` (provider de l'opérateur ; aucun aws/google/azurerm) dans `infra/terraform/main.tf`.
- [ ] **P1.2** Configurer le state backend **chiffré et in-country** ; lever le `TODO(#8)` correspondant.
- [ ] **P1.3** Déclarer les ressources du footprint ADR 0005 (Axum ×2, MinIO, Postgres primaire+réplica, reverse-proxy TLS, WAF, réseau privé, security groups least-privilege, volumes de sauvegarde chiffrés), dimensionnées par les variables existantes.
- [ ] **P1.4** Conserver le garde-fou `country == "CI"` + `residency_note` ; ajouter une `precondition` région/zone-CI si le provider l'expose. Garder les secrets en `TF_VAR_*`.
- [ ] **P2.1** Éclater `playbook.yml` en rôles (`axum_backend`, `minio`, `postgres_primary`, `postgres_replica`, `caddy_tls`, `waf`, `backups`).
- [ ] **P2.2** Implémenter l'injection SOPS/age → `EnvironmentFile` systemd `0600` root-only, `no_log: true` ; conserver les asserts env/résidence.
- [ ] **P3.1** Configurer la réplication Postgres + warm standby ; sauvegardes chiffrées MinIO+Postgres in-country ; aucun failover étranger.
- [ ] **P3.2** Documenter/automatiser le runbook d'unseal après coupure (in-country).
- [ ] **P4.1** Ajouter le contrôle de résidence CI (script + workflow) ; étendre `just infra-validate` aux nouveaux fichiers (rester credential-free).
- [ ] **P4.2** Ajouter les tests négatifs de garde-fou (`country` ≠ CI → échec en terraform et ansible).
- [ ] **P5.1** Vérifier le chemin reproductible staging (sops-d 0600 → terraform apply → ansible playbook) ; confirmer l'idempotence.
- [ ] **⚠️ P5.2** Réaliser le bring-up in-country sur les hôtes de l'opérateur (critère #8.1).
- [ ] **⚠️ P6.1** Rédiger `docs/compliance/attestation-localisation-donnees.md` (opérateur, datacenter, périmètre, preuve, base légale ECART-07) — critère #8.2.
- [ ] **P6.2** Lier l'attestation depuis la matrice de conformité (#5) et préparer pour le dossier ARTCI (#30).
- [ ] **P7.1** Mettre à jour `infra/*/README.md`, ADR 0005/0007, `BACKLOG.md` (#8 fait) ; retirer #8 des risques long-lead.
- [ ] **P7.2** Vérifier qu'aucun secret/PII/plaintext n'a été introduit (relancer `just secrets-lint` + contrôle de résidence).
