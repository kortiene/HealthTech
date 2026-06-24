# Catalogue des contrôles & des preuves

> **Contrôles** (`CTRL-NN`) techniques/organisationnels et **preuves** (`PREUVE-NN`) qui les démontrent.
> Chaque contrôle est rattaché à sa **source de vérité** (ADR et/ou issue). Mapping exigence ↔ contrôle ↔
> preuve : [`loi-2013-450-artci-matrix.md`](./loi-2013-450-artci-matrix.md).
>
> ⚠️ **Honnêteté de statut.** Le projet est *greenfield* (squelette de monorepo, aucune logique de sécurité
> implémentée). La plupart des contrôles sont donc **`Planifié`** (décidés par ADR/backlog) et **non
> `Conforme`**. Aucun contrôle ne doit **jamais** impliquer un déchiffrement côté serveur ni un stockage de
> clé / PII en clair.

## 1. Catalogue des contrôles (`CTRL-NN`)

| ID | Contrôle | Type | Source de vérité (ADR / issue) | État de livraison |
| --- | --- | --- | --- | --- |
| **CTRL-01** | Chiffrement **AES-256-GCM côté patient** avant tout transit (chiffrement authentifié) | Technique | [ADR 0003](../adr/0003-shared-crypto-core-rust.md), [#10](https://github.com/kortiene/HealthTech/issues/10) | Planifié |
| **CTRL-02** | Architecture **zero-knowledge** : serveur ne stocke que des **blobs opaques** indexés par **UUID anonymes** ; aucune voie de déchiffrement serveur | Technique | [ADR 0004](../adr/0004-backend-rust-axum.md), [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [#9](https://github.com/kortiene/HealthTech/issues/9) | Planifié |
| **CTRL-03** | **Clé maîtresse** générée sur l'appareil, scellée dans l'**Android Keystore**, non exportée en clair | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [#11](https://github.com/kortiene/HealthTech/issues/11) | Planifié |
| **CTRL-04** | **Récupération de clé PBKDF2** (phrase de passe / questions culturelles), paramètres anti-brute-force | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [#12](https://github.com/kortiene/HealthTech/issues/12) | Planifié |
| **CTRL-05** | **QR d'accès éphémère ~120 s**, à usage unique ; clé jamais persistée hors du QR | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [#16](https://github.com/kortiene/HealthTech/issues/16) | Planifié |
| **CTRL-06** | **Déchiffrement RAM-only** côté professionnel (jamais sur disque) | Technique | [ADR 0002](../adr/0002-doctor-interface-pwa.md), [#17](https://github.com/kortiene/HealthTech/issues/17) | Planifié |
| **CTRL-07** | **Wipe de fin de session** (clic « Terminer » / 15 min d'inactivité / fermeture d'onglet) | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [#19](https://github.com/kortiene/HealthTech/issues/19) | Planifié |
| **CTRL-08** | **Hébergement souverain** in-country (datacenter national ARTCI-éligible), aucun cloud étranger dans le chemin de données | Organisationnel / Infra | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [#8](https://github.com/kortiene/HealthTech/issues/8) | Planifié |
| **CTRL-09** | **Garde-fou IaC résidence** `country == "CI"` (non surchargeable par environnement) | Technique | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [ADR 0007](../adr/0007-secrets-and-environments.md), [#8](https://github.com/kortiene/HealthTech/issues/8) | **Partiel** (garde-fou présent dans le squelette `infra/terraform/`) |
| **CTRL-10** | **Aucun KMS / service managé étranger** dans le chemin (secrets in-country : SOPS + age) | Organisationnel / Infra | [ADR 0007](../adr/0007-secrets-and-environments.md) | **Partiel** (décision + scaffolding secrets ; mise en service réelle dépend de #8) |
| **CTRL-11** | **Médias lourds hors du téléphone** + **URL éphémères presigned** révocables servies in-country | Technique | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [#23](https://github.com/kortiene/HealthTech/issues/23) | Planifié |
| **CTRL-12** | **Budget 500 Ko** du dossier texte (garde-fou bloquant/avertissant) | Technique | [#15](https://github.com/kortiene/HealthTech/issues/15) | Planifié |
| **CTRL-13** | **Métadonnées non identifiantes uniquement** en base (UUID, version/taille du chiffré, horodatages, paramètres KDF publics) | Technique | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md) | Planifié |
| **CTRL-14** | **Redaction des logs** : config backend fail-fast qui **redige** tout secret ; pas de PII/clé/clair journalisée | Technique | [ADR 0007](../adr/0007-secrets-and-environments.md) | **Partiel** (contrat de config redacting décidé ; backend à implémenter) |
| **CTRL-15** | **Écrans de consentement + CGU + politique de confidentialité** dans l'onboarding | Organisationnel | [#7](https://github.com/kortiene/HealthTech/issues/7), [#13](https://github.com/kortiene/HealthTech/issues/13) | Planifié |
| **CTRL-16** | **Horodatage de capture du consentement** (preuve de recueil) | Technique | [#13](https://github.com/kortiene/HealthTech/issues/13) | Planifié |
| **CTRL-17** | **Modèle local-first** : le patient **détient et lit** son dossier sur son appareil | Technique | [#14](https://github.com/kortiene/HealthTech/issues/14), [#15](https://github.com/kortiene/HealthTech/issues/15) | Planifié |
| **CTRL-18** | **Édition du dossier + rechiffrement** (note/ordonnance fusionnée puis re-chiffrée) | Technique | [#18](https://github.com/kortiene/HealthTech/issues/18), [#15](https://github.com/kortiene/HealthTech/issues/15) | Planifié |
| **CTRL-19** | **Crypto-effacement** (destruction de la clé rend le blob irrécupérable) + suppression du blob par UUID | Technique | [#9](https://github.com/kortiene/HealthTech/issues/9) ; **flux de suppression à concevoir** ([ECART-02](./ecarts.md)) | **Écart** (à instruire) |
| **CTRL-20** | **Modèle de menace STRIDE** & politique de sécurité | Organisationnel | [#6](https://github.com/kortiene/HealthTech/issues/6) | **Livré** ([`docs/threat-model/stride-threat-model.md`](../threat-model/stride-threat-model.md) + [`SECURITY.md`](../../SECURITY.md)) |
| **CTRL-21** | **Pentest externe** (crypto, ZK, QR, récupération, wipe) | Organisationnel | [#25](https://github.com/kortiene/HealthTech/issues/25) | Planifié |
| **CTRL-22** | **Revue cryptographique indépendante** (AES-GCM, PBKDF2, nonces/clés) | Organisationnel | [#26](https://github.com/kortiene/HealthTech/issues/26) | Planifié |
| **CTRL-23** | **TLS** en transit (reverse proxy in-country) | Technique | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md) | Planifié |
| **CTRL-24** | **Registre des activités de traitement** | Organisationnel | [#5](https://github.com/kortiene/HealthTech/issues/5) (ce livrable) | **Partiel** ([`registre-des-traitements.md`](./registre-des-traitements.md) produit ; validation en attente) |
| **CTRL-25** | **Cartographie des données & flux** (frontière zero-knowledge) | Organisationnel | [#5](https://github.com/kortiene/HealthTech/issues/5) (ce livrable) | **Partiel** ([`cartographie-donnees-et-flux.md`](./cartographie-donnees-et-flux.md) produit ; validation en attente) |
| **CTRL-26** | **Clauses contractuelles hébergeur** (DPA : sécurité, confidentialité, sous-traitance, localisation) | Organisationnel | [#8](https://github.com/kortiene/HealthTech/issues/8) | Planifié |
| **CTRL-27** | **Procédure d'incident / notification de violation** (ARTCI & personnes) | Organisationnel | **à définir** ([ECART-03](./ecarts.md)) | **Écart** (à instruire) |
| **CTRL-28** | **Politique de rétention** documentée (durées + purge) | Organisationnel | **à définir** ([ECART-01](./ecarts.md)) | **Écart** (à instruire) |
| **CTRL-29** | **Désignation d'un correspondant / DPO** (le cas échéant) | Organisationnel / Gouvernance | **décision de gouvernance** ([ECART-04](./ecarts.md)) | **Écart** (à confirmer) |
| **CTRL-30** | **Dépôt de la formalité préalable ARTCI** (déclaration / autorisation) | Organisationnel | [#30](https://github.com/kortiene/HealthTech/issues/30) | Planifié |
| **CTRL-31** | **Information / transparence** (politique de confidentialité accessible, mentions à la collecte) | Organisationnel | [#7](https://github.com/kortiene/HealthTech/issues/7) | Planifié |

## 2. Catalogue des preuves (`PREUVE-NN`)

> **Disponibilité :** `Existant` (artefact présent dans le dépôt) · `Planifié` (sera produit par l'issue
> citée) · `À produire` (artefact externe / organisationnel attendu).

| ID | Preuve attendue | Démontre (CTRL) | Source (issue / fichier) | Disponibilité |
| --- | --- | --- | --- | --- |
| **PREUVE-01** | **Vecteurs de test NIST AES-GCM** passants | CTRL-01 | [#10](https://github.com/kortiene/HealthTech/issues/10) | Planifié |
| **PREUVE-02** | Test **« le serveur ne peut pas déchiffrer »** | CTRL-02 | [#9](https://github.com/kortiene/HealthTech/issues/9) | Planifié |
| **PREUVE-03** | **Capture réseau** « pas de PII en clair » à l'onboarding | CTRL-01, CTRL-02, CTRL-13 | [#13](https://github.com/kortiene/HealthTech/issues/13) | Planifié |
| **PREUVE-04** | **Schéma de base de données** (métadonnées non identifiantes uniquement) | CTRL-13 | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [#9](https://github.com/kortiene/HealthTech/issues/9) | Planifié |
| **PREUVE-05** | **Attestation de localisation** des données | CTRL-08 | [#8](https://github.com/kortiene/HealthTech/issues/8), [#30](https://github.com/kortiene/HealthTech/issues/30) | À produire |
| **PREUVE-06** | **Garde-fou IaC** `country == "CI"` (test/validation Terraform) | CTRL-09 | `infra/terraform/` | **Existant** (squelette + garde-fou) |
| **PREUVE-07** | **Contrat / clauses hébergeur** (DPA) | CTRL-26 | [#8](https://github.com/kortiene/HealthTech/issues/8) | À produire |
| **PREUVE-08** | **Test d'expiration QR** (refus après 120 s) | CTRL-05 | [#16](https://github.com/kortiene/HealthTech/issues/16) | Planifié |
| **PREUVE-09** | **Analyse mémoire/disque** (aucune écriture en clair ; RAM-only + wipe) | CTRL-06, CTRL-07 | [#17](https://github.com/kortiene/HealthTech/issues/17), [#19](https://github.com/kortiene/HealthTech/issues/19) | Planifié |
| **PREUVE-10** | **Garde-fou budget 500 Ko** (test bloquant/avertissant) | CTRL-12 | [#15](https://github.com/kortiene/HealthTech/issues/15) | Planifié |
| **PREUVE-11** | **Texte de consentement validé** juridiquement | CTRL-15 | [#7](https://github.com/kortiene/HealthTech/issues/7) | À produire |
| **PREUVE-12** | **Horodatage de capture du consentement** | CTRL-16 | [#13](https://github.com/kortiene/HealthTech/issues/13) | Planifié |
| **PREUVE-13** | **Récépissé / décision d'autorisation ARTCI** | CTRL-02 *(formalité)*, CTRL-30 | [#30](https://github.com/kortiene/HealthTech/issues/30) | À produire |
| **PREUVE-14** | **Rapport de pentest** | CTRL-21 | [#25](https://github.com/kortiene/HealthTech/issues/25) | Planifié |
| **PREUVE-15** | **Avis de revue cryptographique** indépendante | CTRL-22 | [#26](https://github.com/kortiene/HealthTech/issues/26) | Planifié |
| **PREUVE-16** | **Document de threat model** (STRIDE) | CTRL-20 | [#6](https://github.com/kortiene/HealthTech/issues/6) | **Existant** ([`docs/threat-model/stride-threat-model.md`](../threat-model/stride-threat-model.md)) |
| **PREUVE-17** | **Registre des traitements** | CTRL-24 | [`registre-des-traitements.md`](./registre-des-traitements.md) | **Existant** (ce livrable) |
| **PREUVE-18** | **Cartographie données & flux** | CTRL-25 | [`cartographie-donnees-et-flux.md`](./cartographie-donnees-et-flux.md) | **Existant** (ce livrable) |
| **PREUVE-19** | **Démo app patient** affichant le dossier complet | CTRL-17 | [#15](https://github.com/kortiene/HealthTech/issues/15), [#14](https://github.com/kortiene/HealthTech/issues/14) | Planifié |
| **PREUVE-20** | **Parcours d'édition → rechiffrement** | CTRL-18 | [#18](https://github.com/kortiene/HealthTech/issues/18) | Planifié |
| **PREUVE-21** | **Flux/endpoint de suppression** + **preuve d'irréversibilité** (crypto-effacement) | CTRL-19 | [ECART-02](./ecarts.md) | À produire (**écart**) |
| **PREUVE-22** | **Audit des logs** + configuration de redaction | CTRL-14 | [ADR 0007](../adr/0007-secrets-and-environments.md) | Planifié |
| **PREUVE-23** | **Audit d'architecture / dépendances** (aucun service étranger ; revue réseau) | CTRL-08, CTRL-10 | [#25](https://github.com/kortiene/HealthTech/issues/25), SCA CI [#3](https://github.com/kortiene/HealthTech/issues/3) | Planifié |
| **PREUVE-24** | **Runbook d'incident** + **modèle de notification** de violation | CTRL-27 | [ECART-03](./ecarts.md) | À produire (**écart**) |
| **PREUVE-25** | **Politique de rétention** documentée | CTRL-28 | [ECART-01](./ecarts.md) | À produire (**écart**) |
| **PREUVE-26** | **Acte de désignation** correspondant / DPO | CTRL-29 | [ECART-04](./ecarts.md) | À produire (**écart**) |
| **PREUVE-27** | **Textes d'information / transparence** (politique de confidentialité, mentions) | CTRL-31, CTRL-15 | [#7](https://github.com/kortiene/HealthTech/issues/7) | À produire |
| **PREUVE-28** | **Démo TLS** (transit chiffré ; configuration reverse proxy) | CTRL-23 | [#8](https://github.com/kortiene/HealthTech/issues/8) | Planifié |

---

## 3. Note importante sur les contrôles « best-effort »

- **RAM-only navigateur (CTRL-06) — réserve connue** ([ADR 0000](../adr/0000-index.md) risque #1) : en
  navigateur, le garbage collector JS peut copier/pager du plaintext ; le RAM-only y est **best-effort, non
  prouvable** à un auditeur. À **signaler honnêtement** dans la matrice et au pentest ([#25](https://github.com/kortiene/HealthTech/issues/25)).
  Mitigations décidées : reload-pour-vider-le-heap en fin de session, durée de vie minimale du plaintext,
  zeroize des buffers WASM ; un shell médecin natif reste un repli haute-assurance.
- **Crypto-effacement (CTRL-19)** : son acceptabilité juridique comme « effacement » au sens de la loi
  **reste à valider** par le conseil juridique ([ECART-02](./ecarts.md)).
