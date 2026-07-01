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
| **CTRL-03** | **Clé maîtresse** générée sur l'appareil, scellée dans l'**Android Keystore** (StrongBox→repli TEE, **sans repli logiciel**), non exportée en clair | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [#11](https://github.com/kortiene/HealthTech/issues/11) | **Partiel** (génération en cœur Rust `MasterKeyHandle` + shim Keystore Kotlin `KeystoreSealer.kt` (chiffrement par enveloppe KEK matérielle) + service Dart sans repli logiciel livrés ; validation matérielle StrongBox/TEE en device lab [#29]) |
| **CTRL-04** | **Récupération de clé PBKDF2** (phrase de passe / questions culturelles), paramètres anti-brute-force | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [#12](https://github.com/kortiene/HealthTech/issues/12) | Planifié |
| **CTRL-05** | **QR d'accès éphémère ~120 s**, à usage unique ; clé jamais persistée hors du QR | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [#16](https://github.com/kortiene/HealthTech/issues/16) | Planifié |
| **CTRL-06** | **Déchiffrement RAM-only** côté professionnel (jamais sur disque) | Technique | [ADR 0002](../adr/0002-doctor-interface-pwa.md), [#17](https://github.com/kortiene/HealthTech/issues/17) | Planifié |
| **CTRL-07** | **Wipe de fin de session** (clic « Terminer » / 15 min d'inactivité / fermeture d'onglet) | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [#19](https://github.com/kortiene/HealthTech/issues/19) | Planifié |
| **CTRL-08** | **Hébergement souverain** in-country (datacenter national ARTCI-éligible), aucun cloud étranger dans le chemin de données | Organisationnel / Infra | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [ADR 0009](../adr/0009-sovereign-operator-selection.md), [#8](https://github.com/kortiene/HealthTech/issues/8) | **Planifié** (critères de sélection opérateur fixés [ADR 0009] ; pick & bring-up = procurement long-lead) |
| **CTRL-09** | **Garde-fou IaC résidence** `country == "CI"` (non surchargeable par environnement) **+ tripwire CI anti-régression** (rejet de tout provider/backend/endpoint étranger à chaque commit) | Technique | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [ADR 0007](../adr/0007-secrets-and-environments.md), [#8](https://github.com/kortiene/HealthTech/issues/8) | **Partiel** (garde-fou Terraform/Ansible + [`scripts/check-residency.sh`](../../scripts/check-residency.sh) en CI ; bring-up à venir) |
| **CTRL-10** | **Aucun KMS / service managé étranger** dans le chemin (secrets in-country : SOPS + age) | Organisationnel / Infra | [ADR 0007](../adr/0007-secrets-and-environments.md) | **Partiel** (décision + scaffolding secrets ; mise en service réelle dépend de #8) |
| **CTRL-11** | **Médias lourds hors du téléphone** + **URL éphémères presigned** révocables servies in-country | Technique | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [#23](https://github.com/kortiene/HealthTech/issues/23) | Planifié |
| **CTRL-12** | **Budget 500 Ko** du dossier texte (garde-fou bloquant/avertissant) | Technique | [#15](https://github.com/kortiene/HealthTech/issues/15) | Planifié |
| **CTRL-13** | **Métadonnées non identifiantes uniquement** en base (UUID, version/taille du chiffré, horodatages, paramètres KDF publics) | Technique | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md) | Planifié |
| **CTRL-14** | **Redaction des logs** : config backend fail-fast qui **redige** tout secret ; pas de PII/clé/clair journalisée | Technique | [ADR 0007](../adr/0007-secrets-and-environments.md) | **Partiel** (contrat de config redacting décidé ; backend à implémenter) |
| **CTRL-15** | **Écrans de consentement + CGU + politique de confidentialité** dans l'onboarding | Organisationnel | [#7](https://github.com/kortiene/HealthTech/issues/7), [#13](https://github.com/kortiene/HealthTech/issues/13) | **Partiel** (textes draft v1.0 livrés [`docs/legal/consent-v1.md`](../../docs/legal/consent-v1.md) + modèle `ConsentRecord` ; validation juridique + intégration UX onboarding = [#13](https://github.com/kortiene/HealthTech/issues/13)) |
| **CTRL-16** | **Horodatage de capture du consentement** (preuve de recueil) | Technique | [#13](https://github.com/kortiene/HealthTech/issues/13) | Planifié |
| **CTRL-17** | **Modèle local-first** : le patient **détient et lit** son dossier sur son appareil | Technique | [#14](https://github.com/kortiene/HealthTech/issues/14), [#15](https://github.com/kortiene/HealthTech/issues/15) | Planifié |
| **CTRL-18** | **Édition du dossier + rechiffrement** (note/ordonnance fusionnée puis re-chiffrée) | Technique | [#18](https://github.com/kortiene/HealthTech/issues/18), [#15](https://github.com/kortiene/HealthTech/issues/15) | **Partiel** (fusion append-only + rechiffrement RAM avec la clé de session, aucun plaintext sur disque ni journalisé — `app-patient/lib/src/doctor/consultation_merge.dart`, `consultation_edit_service.dart` ; renvoi cloud + wipe fin de session = [#19](https://github.com/kortiene/HealthTech/issues/19)) |
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
| **CTRL-31** | **Information / transparence** (politique de confidentialité accessible, mentions à la collecte) | Organisationnel | [#7](https://github.com/kortiene/HealthTech/issues/7) | **Partiel** (texte draft v1.0 dans [`docs/legal/consent-v1.md`](../../docs/legal/consent-v1.md) ; validation juridique + affichage UX = [#13](https://github.com/kortiene/HealthTech/issues/13)) |
| **CTRL-32** | **Résilience hors-ligne sans perte de données** (US-2.4, KPI « 100 % des consultations sans perte même en coupure totale ») : l'ordonnance chiffrée est enfilée dans une **file locale chiffrée (SQLCipher)** au lieu d'être perdue quand l'envoi échoue ; **rien en clair** sur l'appareil (ciphertext AES-256-GCM dans une base SQLCipher AES-256, clé scellée Keystore) ; le wipe RAM de la clé de session reste préservé ; **au retour réseau, la file remonte vers l'hébergement souverain sans perte ni doublon** | Technique | [ADR 0006](../adr/0006-offline-storage-and-keys.md), [ADR 0010](../adr/0010-offline-sync-conflict-resolution.md), [#21](https://github.com/kortiene/HealthTech/issues/21), [#22](https://github.com/kortiene/HealthTech/issues/22) | **Partiel** (file `OfflineUploadQueue` + impl. SQLCipher `SqlCipherUploadQueue` + enqueue-on-failure dans `SessionEndService` (#21) **et drain `SyncService` au retour réseau** (#22, `put`→`remove`, livraison *at-least-once* + PUT idempotent au niveau UUID = aucune perte ni doublon ; backoff borné, échec persistant signalé jamais purgé) livrés — `app-patient/lib/src/doctor/{offline_upload_queue,sqlcipher_upload_queue,session_end_service,sync_service,sync_trigger}.dart` ; logique couverte host-only par l'impl. in-memory, liaison SQLCipher réelle + migration v1→v2 = e2e device-backed [#29] ; option B versionnage conditionnée à [#9](https://github.com/kortiene/HealthTech/issues/9)) |

## 2. Catalogue des preuves (`PREUVE-NN`)

> **Disponibilité :** `Existant` (artefact présent dans le dépôt) · `Planifié` (sera produit par l'issue
> citée) · `À produire` (artefact externe / organisationnel attendu).
>
> 🔗 **Renvoi dossier d'homologation (#30) :** ces preuves sont indexées comme **pièces** (`PIECE-NN`) du
> dossier ARTCI dans [`homologation-artci/piece-list.md`](./homologation-artci/piece-list.md). Le **statut
> dossier** y est dérivé de la **disponibilité** ci-dessous (une preuve non `Existant` n'est jamais « Prête »).

| ID | Preuve attendue | Démontre (CTRL) | Source (issue / fichier) | Disponibilité |
| --- | --- | --- | --- | --- |
| **PREUVE-01** | **Vecteurs de test NIST AES-GCM** passants (gating CI) + revue de sécurité du module | CTRL-01 | [#10](https://github.com/kortiene/HealthTech/issues/10) ; [`crypto-core/tests/aes_gcm_nist_vectors.rs`](../../crypto-core/tests/aes_gcm_nist_vectors.rs), [`crypto-core/tests/vectors/PROVENANCE.md`](../../crypto-core/tests/vectors/PROVENANCE.md), [`docs/security/crypto-core-review.md`](../security/crypto-core-review.md) | **Existant** (vecteurs en gating ; revue interne livrée — revue indépendante = PREUVE-15/#26) |
| **PREUVE-02** | Test **« le serveur ne peut pas déchiffrer »** | CTRL-02 | [#9](https://github.com/kortiene/HealthTech/issues/9) | Planifié |
| **PREUVE-03** | **Capture réseau** « pas de PII en clair » à l'onboarding | CTRL-01, CTRL-02, CTRL-13 | [#13](https://github.com/kortiene/HealthTech/issues/13) | Planifié |
| **PREUVE-04** | **Schéma de base de données** (métadonnées non identifiantes uniquement) | CTRL-13 | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [#9](https://github.com/kortiene/HealthTech/issues/9) | Planifié |
| **PREUVE-05** | **Attestation de localisation** des données ([`attestation-localisation-donnees.md`](./attestation-localisation-donnees.md) — modèle prêt ; signature en attente du bring-up & de l'opérateur) | CTRL-08 | [#8](https://github.com/kortiene/HealthTech/issues/8), [#30](https://github.com/kortiene/HealthTech/issues/30) | **Partiel** (cadre existant ; preuves opérateur à joindre au bring-up) |
| **PREUVE-06** | **Garde-fou IaC** `country == "CI"` (validation Terraform/Ansible) **+ tripwire résidence CI** ([`scripts/check-residency.sh`](../../scripts/check-residency.sh), `just infra-residency`) | CTRL-09 | `infra/terraform/`, `infra/ansible/`, `scripts/check-residency.sh` | **Existant** (garde-fou + tripwire fail-closed en CI) |
| **PREUVE-07** | **Contrat / clauses hébergeur** (DPA) | CTRL-26 | [#8](https://github.com/kortiene/HealthTech/issues/8) | À produire |
| **PREUVE-08** | **Test d'expiration QR** (refus après 120 s) | CTRL-05 | [#16](https://github.com/kortiene/HealthTech/issues/16) | Planifié |
| **PREUVE-09** | **Analyse mémoire/disque** (aucune écriture en clair ; RAM-only + wipe) | CTRL-06, CTRL-07 | [#17](https://github.com/kortiene/HealthTech/issues/17), [#19](https://github.com/kortiene/HealthTech/issues/19) | Planifié |
| **PREUVE-10** | **Garde-fou budget 500 Ko** (test bloquant/avertissant) | CTRL-12 | [#15](https://github.com/kortiene/HealthTech/issues/15) | Planifié |
| **PREUVE-11** | **Texte de consentement validé** juridiquement | CTRL-15 | [#7](https://github.com/kortiene/HealthTech/issues/7) | **Draft** ([`docs/legal/consent-v1.md`](../../docs/legal/consent-v1.md) — validation juridique à obtenir avant production) |
| **PREUVE-12** | **Horodatage de capture du consentement** | CTRL-16 | [#13](https://github.com/kortiene/HealthTech/issues/13) | Planifié |
| **PREUVE-13** | **Récépissé / décision d'autorisation ARTCI** | CTRL-02 *(formalité)*, CTRL-30 | [#30](https://github.com/kortiene/HealthTech/issues/30) | À produire |
| **PREUVE-14** | **Rapport de pentest** | CTRL-21 | [#25](https://github.com/kortiene/HealthTech/issues/25) | Planifié |
| **PREUVE-15** | **Avis de revue cryptographique** indépendante | CTRL-22 | [#26](https://github.com/kortiene/HealthTech/issues/26) | Planifié |
| **PREUVE-16** | **Document de threat model** (STRIDE) | CTRL-20 | [#6](https://github.com/kortiene/HealthTech/issues/6) | **Existant** ([`docs/threat-model/stride-threat-model.md`](../threat-model/stride-threat-model.md)) |
| **PREUVE-17** | **Registre des traitements** | CTRL-24 | [`registre-des-traitements.md`](./registre-des-traitements.md) | **Existant** (ce livrable) |
| **PREUVE-18** | **Cartographie données & flux** | CTRL-25 | [`cartographie-donnees-et-flux.md`](./cartographie-donnees-et-flux.md) | **Existant** (ce livrable) |
| **PREUVE-19** | **Démo app patient** affichant le dossier complet | CTRL-17 | [#15](https://github.com/kortiene/HealthTech/issues/15), [#14](https://github.com/kortiene/HealthTech/issues/14) | Planifié |
| **PREUVE-20** | **Parcours d'édition → rechiffrement** | CTRL-18 | [#18](https://github.com/kortiene/HealthTech/issues/18) | **Partiel** (merge + re-chiffrement RAM couverts par les tests unitaires #18 ; parcours e2e complet = [#20](https://github.com/kortiene/HealthTech/issues/20)) |
| **PREUVE-21** | **Flux/endpoint de suppression** + **preuve d'irréversibilité** (crypto-effacement) | CTRL-19 | [ECART-02](./ecarts.md) | À produire (**écart**) |
| **PREUVE-22** | **Audit des logs** + configuration de redaction | CTRL-14 | [ADR 0007](../adr/0007-secrets-and-environments.md) | Planifié |
| **PREUVE-23** | **Audit d'architecture / dépendances** (aucun service étranger ; revue réseau) | CTRL-08, CTRL-10 | [#25](https://github.com/kortiene/HealthTech/issues/25), SCA CI [#3](https://github.com/kortiene/HealthTech/issues/3) | Planifié |
| **PREUVE-24** | **Runbook d'incident** + **modèle de notification** de violation | CTRL-27 | [ECART-03](./ecarts.md) | À produire (**écart**) |
| **PREUVE-25** | **Politique de rétention** documentée | CTRL-28 | [ECART-01](./ecarts.md) | À produire (**écart**) |
| **PREUVE-26** | **Acte de désignation** correspondant / DPO | CTRL-29 | [ECART-04](./ecarts.md) | À produire (**écart**) |
| **PREUVE-27** | **Test « consultation validée hors-ligne sans perte »** (échec d'envoi → blob chiffré enfilé, RAM wipée, ciphertext opaque ≠ clair) + **test « drain au retour réseau sans perte ni doublon »** (file rejouée FIFO, `put`→`remove`, re-PUT idempotent après crash, backoff/plafond, ré-entrance) + **stratégie de conflits documentée** + **durabilité/illisibilité SQLCipher** | CTRL-32 | [#21](https://github.com/kortiene/HealthTech/issues/21), [#22](https://github.com/kortiene/HealthTech/issues/22) ; [ADR 0010](../adr/0010-offline-sync-conflict-resolution.md) ; `app-patient/test/doctor/{session_end_service,sync_service}_test.dart`, `app-patient/test/e2e/consultation_loop_e2e_test.dart` | **Partiel** (chemin hors-ligne + drain + opacité couverts host-only ; stratégie de conflits documentée en ADR 0010 ; durabilité WAL + illisibilité sans clé + migration v1→v2 = e2e device-backed, suivi [#29]) |
| **PREUVE-27** | **Textes d'information / transparence** (politique de confidentialité, mentions) | CTRL-31, CTRL-15 | [#7](https://github.com/kortiene/HealthTech/issues/7) | **Draft** ([`docs/legal/consent-v1.md`](../../docs/legal/consent-v1.md) § 3 — validation juridique à obtenir avant production) |
| **PREUVE-28** | **Démo TLS** (transit chiffré ; configuration reverse proxy) | CTRL-23 | [#8](https://github.com/kortiene/HealthTech/issues/8) | Planifié |
| **PREUVE-29** | **Clé maîtresse scellée matériellement, jamais en clair persistant** (US-1.1) : génération en cœur Rust (`MasterKeyHandle`/`export_sealable`, copie en clair `wipe`-ée), scellement par KEK matérielle non-exportable (`KeystoreSealer.kt`), persistance du **seul blob scellé**, **aucun repli logiciel** ; tests unitaires (Rust génération/`wipe`, Dart mock-channel/no-fallback) + tests instrumentés StrongBox/TEE en device lab | CTRL-03 | [#11](https://github.com/kortiene/HealthTech/issues/11), device lab [#29](https://github.com/kortiene/HealthTech/issues/29) | **Partiel** (code livré ; preuve matérielle au device lab) |

---

## 3. Note importante sur les contrôles « best-effort »

- **RAM-only navigateur (CTRL-06) — réserve connue** ([ADR 0000](../adr/0000-index.md) risque #1) : en
  navigateur, le garbage collector JS peut copier/pager du plaintext ; le RAM-only y est **best-effort, non
  prouvable** à un auditeur. À **signaler honnêtement** dans la matrice et au pentest ([#25](https://github.com/kortiene/HealthTech/issues/25)).
  Mitigations décidées : reload-pour-vider-le-heap en fin de session, durée de vie minimale du plaintext,
  zeroize des buffers WASM ; un shell médecin natif reste un repli haute-assurance.
- **Crypto-effacement (CTRL-19)** : son acceptabilité juridique comme « effacement » au sens de la loi
  **reste à valider** par le conseil juridique ([ECART-02](./ecarts.md)).
