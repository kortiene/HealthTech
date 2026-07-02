# Backlog — Plateforme de Santé Numérique Décentralisée (Côte d'Ivoire)

> **Source :** dérivé de [`PRD_HealthTech.md`](./PRD_HealthTech.md)
> **État du dépôt au moment de la rédaction :** projet *greenfield* — aucun code, uniquement le PRD.
> **Architecture cible :** Local-First / Zero-Knowledge Cloud, chiffrement AES-256-GCM côté patient, hébergement obligatoire en Côte d'Ivoire (ARTCI / loi n°2013-450).

## Légende

- **Effort :** `S` (≤ 2 j), `M` (3–5 j), `L` (1–2+ semaines)
- **Priorité :** `Must` / `Should` / `Could` (MoSCoW, alignée sur le PRD)
- **Étiquettes :** `feature`, `bug`, `tech-debt`, `docs`, `security`, `infra`, `compliance`, `ux`, `crypto`

---

## Vue d'ensemble des jalons (milestones)

| Jalon | Objectif (1 ligne) | Épics couverts |
| ----- | ------------------ | -------------- |
| **M0 — Fondations & Conformité** | Mettre en place le socle technique, cryptographique, légal et l'hébergement souverain avant d'écrire la moindre fonctionnalité. | E0, E6, E7 |
| **M1 — Cœur cryptographique & onboarding patient** | Le patient crée un compte chiffré localement, ses données sont sauvegardées en zero-knowledge, et il peut les restaurer. | E1, E5, E7 |
| **M2 — Boucle de consultation** | Le cycle complet QR → scan → consultation → effacement fonctionne de bout en bout. C'est le cœur de valeur du produit. | E1, E2 |
| **M3 — Résilience hors-ligne & médias** | La consultation survit aux coupures réseau/courant et gère les images médicales lourdes hors du téléphone. | E2, E5 |
| **M4 — Durcissement & lancement** | Audit de sécurité, homologation ARTCI, validation des performances et pilote terrain à Abidjan. | E3, E4, E6 |

**Chemin critique :** M0 → M1 → M2 → M3 → M4 (chaque jalon dépend du précédent ; M2 ne peut commencer tant que le module crypto de M1 n'est pas figé).

---

## M0 — Fondations & Conformité

> **Objectif :** Aucune fonctionnalité avant un socle sûr. On fige ici l'architecture, le modèle de menace et le cadre légal.

### E0 — Socle projet & DevOps `infra`

- **#1 — Choix de la stack technique & ADR** · `Must` · `M` · `docs` `infra`
  Trancher : framework app patient (Kotlin natif vs Flutter — cible Android entrée de gamme), interface médecin (PWA React vs mobile partagé), backend (Go/Rust/Node), stockage objet pour les blobs. Documenter via des ADR (Architecture Decision Records).
  *Acceptation :* un ADR par décision majeure committé dans `/docs/adr/` ; justification du compromis taille/perf sur smartphones d'entrée de gamme.

- **#2 — Initialisation du monorepo & structure** · `Must` · `S` · `infra`
  Créer l'arborescence (`/app-patient`, `/app-medecin`, `/backend`, `/crypto-core`, `/infra`, `/docs`), licences, `README`, `.gitignore`, conventions de commits.
  *Acceptation :* `git init`, structure en place, README décrivant le projet et la commande de build de chaque paquet.

- **#3 — Pipeline CI/CD** · `Must` · `M` · `infra`
  Lint, tests unitaires, build des apps et du backend, scan de dépendances (SCA), à chaque PR.
  *Acceptation :* CI verte obligatoire avant merge ; build APK et image backend produits en artefacts.

- **#4 — Environnements & secrets** · `Should` · `M` · `infra` `security`
  Gestion des secrets (pas de clé en clair dans le repo), environnements dev/staging/prod, IaC pour l'hébergement local.
  *Acceptation :* secrets injectés via coffre-fort ; `staging` reproductible depuis l'IaC.
  *Décision :* [ADR 0007](./docs/adr/0007-secrets-and-environments.md) (SOPS + age, in-country ; par-env dev/staging/prod). *Fournit* le coffre-fort et le scan de secrets consommés par #3 (CI) ; dépend de #8 pour la mise en service réelle.

### E6 — Conformité, légal & gouvernance `compliance`

- **#5 — Analyse de conformité loi n°2013-450 & exigences ARTCI** · `Must` · `L` · `compliance` `docs`
  Cartographier chaque exigence légale (résidence des données, consentement, droits du patient) vers une exigence technique.
  *Acceptation :* matrice de conformité exigence → contrôle technique → preuve, validée par le conseil juridique.
  *Spec :* [`specs/loi-2013-450-artci-compliance-matrix.md`](./specs/loi-2013-450-artci-compliance-matrix.md).
  *Livrables :* [`docs/compliance/`](./docs/compliance/README.md) — [matrice](./docs/compliance/loi-2013-450-artci-matrix.md), [exigences](./docs/compliance/exigences-legales.md), [contrôles & preuves](./docs/compliance/controles.md), [registre des traitements](./docs/compliance/registre-des-traitements.md), [cartographie données/flux](./docs/compliance/cartographie-donnees-et-flux.md), [journal de validation juridique](./docs/compliance/journal-validation-juridique.md), [écarts](./docs/compliance/ecarts.md). *Matrice = **projet** tant que le sign-off juridique de toutes les exigences `Must` n'est pas acquis.*
  *Écarts découverts (issues à créer) :* politique de rétention (`ECART-01`), flux de suppression/crypto-effacement (`ECART-02`), procédure de notification de violation (`ECART-03`), désignation correspondant/DPO (`ECART-04`), régime données de santé/mineurs (`ECART-05`), qualification des rôles RT/sous-traitant (`ECART-06`), base légale de la localisation (`ECART-07`), accès d'urgence/break-glass (`ECART-08`). Détail : [`docs/compliance/ecarts.md`](./docs/compliance/ecarts.md).

- **#6 — Modèle de menace & politique de sécurité** · `Must` · `L` · `security` `docs`
  Threat model (STRIDE) couvrant : vol de téléphone, serveur compromis, MITM réseau, QR code intercepté, attaque sur la phrase de passe de récupération.
  *Acceptation :* document de threat model revu ; chaque menace `Must` a une contre-mesure tracée vers une issue.

- **#7 — Politique de consentement & parcours juridique patient** · `Should` · `M` · `compliance` `ux`
  Écrans de consentement, CGU, politique de confidentialité conformes à la loi ivoirienne.
  *Acceptation :* textes validés juridiquement, intégrés au parcours d'onboarding (#13).

### E7 — Hébergement souverain & backend zero-knowledge `infra`

- **#8 — Provisionnement de l'hébergement en Côte d'Ivoire** · `Must` · `L` · `infra` `compliance` · *En cours (procurement long-lead)*
  Sélectionner et provisionner l'hébergement local (datacenter national) garantissant la résidence des données.
  *Acceptation :* infrastructure opérationnelle sur le territoire national, attestation de localisation.
  *Avancement :* critères de sélection opérateur fixés ([ADR 0009](./docs/adr/0009-sovereign-operator-selection.md)) ; garde-fou de résidence anti-régression livré (`scripts/check-residency.sh`, en CI + `just infra-residency`/`infra-validate`) ; modèle d'attestation de localisation produit ([`attestation-localisation-donnees.md`](./docs/compliance/attestation-localisation-donnees.md), PREUVE-05). **Restant (décision humaine + bring-up) :** choix/contrat de l'opérateur (P0), provider + ressources + state backend chiffré in-country Terraform, rôles Ansible, mise en service réelle (#8.1) et signature de l'attestation (#8.2).

- **#9 — Service de stockage de blobs zero-knowledge** · `Must` · `L` · `feature` `backend` `security`
  API minimale : stocker / récupérer un blob chiffré indexé par UUID anonyme. Le serveur ne voit jamais de donnée nominative ni de clé.
  *Acceptation :* endpoints `PUT/GET /blob/{uuid}` ; aucune donnée en clair persistée ; tests prouvant que le serveur ne peut pas déchiffrer.

---

## M1 — Cœur cryptographique & onboarding patient

> **Objectif :** Le patient possède réellement ses données : clé générée localement, sauvegarde illisible par le serveur, restauration possible.

### E5 — Cœur cryptographique (bibliothèque partagée) `crypto`

- **#10 — Module AES-256-GCM (chiffrement/déchiffrement de blob)** · `Must` · `M` · `crypto` `security`
  Bibliothèque partagée patient/médecin : chiffrement authentifié AES-256-GCM, gestion des nonces, vecteurs de test.
  *Acceptation :* vecteurs de test officiels passants ; revue de sécurité du module ; API stable réutilisée par les apps.
  *Dépend de :* #6.

- **#11 — Génération & gestion de la clé maîtresse locale** · `Must` · `M` · `crypto` `security`
  Génération de la clé maîtresse sur l'appareil, stockage dans le keystore matériel (Android Keystore), jamais exportée en clair.
  *Acceptation :* clé générée et scellée dans le keystore ; aucune fuite en mémoire persistante.
  *Implémente :* US-1.1.

- **#12 — Dérivation & récupération de clé (PBKDF2 + questions culturelles)** · `Must` · `M` · `crypto` `security` `ux`
  Dérivation PBKDF2 depuis une phrase de passe ou des questions de sécurité adaptées au contexte ivoirien ; paramètres de coût calibrés pour les téléphones d'entrée de gamme.
  *Acceptation :* restauration réussie sur un nouvel appareil à partir de la phrase/des réponses ; paramètres résistants au brute-force documentés.
  *Implémente :* US-1.4 · *Dépend de :* #6, #11.

### E1 — Application Patient (onboarding) `feature`

- **#13 — Création de compte chiffré (n° CMU / téléphone)** · `Must` · `M` · `feature` `ux`
  Parcours d'onboarding : saisie n° CMU/téléphone, génération locale de la clé (#11), aucune donnée nominative envoyée en clair.
  *Acceptation :* compte créé hors-ligne ; capture réseau prouvant l'absence de PII en clair.
  *Implémente :* US-1.1 · *Dépend de :* #11, #7.

- **#14 — Sauvegarde cloud zero-knowledge du dossier** · `Must` · `M` · `feature` `security`
  Chiffrement local du dossier complet (blob) puis téléversement automatique vers le serveur ivoirien (#9).
  *Acceptation :* le blob téléversé est indéchiffrable côté serveur ; téléversement automatique après modification.
  *Implémente :* US-1.3 · *Dépend de :* #9, #10.

- **#15 — Structure & schéma du dossier médical (≤ 500 Ko)** · `Must` · `M` · `feature` `tech-debt`
  Définir le schéma du dossier texte, valider la contrainte de 500 Ko de texte brut, stratégie de compression/troncature.
  *Acceptation :* schéma versionné ; garde-fou bloquant/avertissant au-delà de 500 Ko.
  *Dépend de :* contrainte PRD §4.

---

## M2 — Boucle de consultation

> **Objectif :** Le parcours QR → scan → édition → effacement fonctionne de bout en bout. C'est le cœur de valeur démontrable.

### E1 — Application Patient (partage) `feature`

- **#16 — Génération du QR code d'accès temporaire** · `Must` · `M` · `feature` `crypto`
  QR dynamique contenant l'URL serveur + la clé symétrique de déchiffrement ; expiration à 120 s ; affichage UX clair du compte à rebours.
  *Acceptation :* QR expiré refusé côté médecin après 120 s ; clé jamais persistée hors du QR.
  *Implémente :* US-1.2 · *Dépend de :* #10, #14.

### E2 — Interface Professionnel de Santé `feature`

- **#17 — Scan du QR & déchiffrement en RAM uniquement** · `Must` · `L` · `feature` `security`
  Scan → téléchargement du blob (#9) → déchiffrement avec la clé du QR **uniquement en mémoire vive**, jamais sur disque.
  *Acceptation :* analyse mémoire/disque prouvant l'absence d'écriture en clair ; dossier affiché après scan.
  *Implémente :* US-2.1 · *Dépend de :* #16, #9, #10.

- **#18 — Ajout de note / ordonnance & fusion en mémoire** · `Must` · `M` · `feature` `ux`
  Formulaire d'édition rapide ; fusion des ajouts avec le dossier existant en RAM ; modèle d'ordonnance.
  *Acceptation :* note/ordonnance fusionnée sans écraser l'historique ; rechiffrement du dossier mis à jour.
  *Implémente :* US-2.2 · *Dépend de :* #17.
  *Avancement :* fusion append-only (`doctor/consultation_merge.dart`), modèle d'ordonnance (`record/prescription.dart`), rechiffrement RAM avec la clé de session + garde 500 Kio préservant la nouvelle note (`doctor/consultation_edit_service.dart`), formulaire d'édition rapide (`ui/consultation_edit_screen.dart`) et porteur de session RAM (`doctor/consultation_session.dart`). **Restant :** renvoi cloud + wipe RAM de fin de session (#19), identité praticien (placeholder `practitioner-unverified`).

- **#19 — Fin de session : rechiffrement, renvoi cloud & wipe RAM** · `Must` · `M` · `feature` `security`
  Au clic « Terminer » ou après 15 min d'inactivité : chiffrer le nouveau dossier, l'envoyer au cloud, vider la RAM du médecin.
  *Acceptation :* après fin de session, aucune donnée patient résiduelle en mémoire ; blob mis à jour côté serveur.
  *Implémente :* US-2.3 · *Dépend de :* #17, #18, #14.

- **#20 — Démo end-to-end de la boucle de consultation** · `Should` · `S` · `docs` `feature`
  Scénario de bout en bout (patient génère QR → médecin scanne, édite, termine → patient voit la mise à jour) automatisé en test d'intégration.
  *Acceptation :* test e2e vert couvrant le cycle complet.
  *Dépend de :* #16–#19.
  *Avancement :* test d'intégration « à fakes » livré (`app-patient/test/e2e/consultation_loop_e2e_test.dart`) enchaînant les services **réels** #16→#19 — premier *end-to-end* M2 atteint. Asserte le câblage (clé de session round-trip QR, fusion append-only survivant au renvoi cloud, mise à jour observable), les invariants transverses (opacité serveur, wipe clé + blob) et les variantes (QR expiré, 5xx en fin de session). Fakes partagés extraits dans `app-patient/test/support/consultation_loop_harness.dart`. **Restant :** e2e *device-backed* (crypto-core natif via FRB, scan réel) et sync patient post-consultation (ré-import master-key) — suivis hors #20.

---

## M3 — Résilience hors-ligne & médias

> **Objectif :** Garantir 100 % des consultations sans perte de données même hors réseau, et sortir les images lourdes du téléphone.

### E2 — Résilience médecin `feature`

- **#21 — File d'attente hors-ligne sécurisée (SQLCipher)** · `Must` · `L` · `feature` `security`
  En cas de coupure réseau, l'ordonnance chiffrée est placée dans une file locale chiffrée (SQLCipher).
  *Acceptation :* consultation validée hors-ligne ; donnée stockée chiffrée localement ; rien en clair.
  *Implémente :* US-2.4 · *Dépend de :* #10, #19.
  *Avancement :* file `OfflineUploadQueue` (`doctor/offline_upload_queue.dart`) — interface `enqueue/pending/remove/count` + modèle `PendingUpload` + `InMemoryUploadQueue` (FIFO, idempotence, copie défensive) ; impl. prod drift + SQLCipher (`doctor/sqlcipher_upload_queue.dart`, clé de base scellée Keystore via enveloppe #11, ouverture `PRAGMA key` + WAL, table versionnée `pending_uploads`). `SessionEndService.terminate` retourne désormais `SessionEndOutcome` (`uploaded`/`queued`/`nothingToUpload`) et **enfile au lieu de perdre** `pendingBlob` sur `BackendUnavailable`, en préservant le wipe RAM en `finally` ; double-échec → `OfflineQueueUnavailable`. Câblé dans `ui/record_view_screen.dart` (snackbar « enregistrée hors-ligne »). Tests host-only : logique in-memory + chemin hors-ligne de `terminate` + variante e2e hors-ligne. **Restant :** drain réseau au retour de connexion (#22) ; e2e *device-backed* de la liaison SQLCipher (durabilité WAL + illisibilité sans clé, non exécutable en CI host-only) ; sync patient post-consultation (ré-import master-key, hors issue).

- **#22 — Synchronisation au retour du réseau** · `Must` · `M` · `feature` `tech-debt`
  Dès le retour réseau, la file se synchronise vers le cloud ; gestion des conflits et des renvois.
  *Acceptation :* aucune perte ni doublon après reconnexion ; stratégie de résolution de conflits documentée.
  *Implémente :* US-2.4 · *Dépend de :* #21.
  *Avancement :* `SyncService.drain()` (`doctor/sync_service.dart`) draine `OfflineUploadQueue.pending()` en FIFO — `put` **puis** `remove` (jamais de retrait avant un 2xx), mutex anti-réentrance (pas de double-PUT concurrent), arrêt propre sur `BackendUnavailable` ; `RetryPolicy` (backoff exponentiel borné + `maxAttempts`, échec persistant **signalé jamais purgé**) ; `SyncSummary { synced, failed, conflicts, skipped, persistentFailures, remaining }`. File étendue (`offline_upload_queue.dart` + `sqlcipher_upload_queue.dart` schemaVersion **2** + migration v1→v2 : `last_attempt_at`/`last_error`/`state`) avec `markAttempt`/`markConflict` et champs lecture-seule sur `PendingUpload` ; `*.g.dart` régénéré. Déclencheur découplé `SyncTrigger` (`doctor/sync_trigger.dart` : resume/start/manuel/opportuniste, sans paquet de connectivité). UI (`ui/record_view_screen.dart`) : badge « N en attente », bouton « Synchroniser », drain opportuniste après PUT réussi, alerte conflit/échec persistant. **No-loss/no-duplicate** = livraison *at-least-once* + PUT idempotent au niveau UUID. Stratégie de conflits documentée : **[ADR 0010](docs/adr/0010-offline-sync-conflict-resolution.md)** (A dernier-gagne aveugle par défaut, crochets B câblés-mais-inactifs jusqu'à versionnage #9, C réconciliation patient en suivi). Tests host-only : logique de drain in-memory (succès, no-loss, reconnexion, idempotence, FIFO, backoff/plafond, ré-entrance) — phase tests. **Restant :** option B conditionnée à un versionnage serveur (#9) ; e2e *device-backed* de la migration drift v1→v2 + durabilité WAL (non exécutable en CI host-only) ; sync patient post-consultation (ré-import master-key, hors issue) ; option drain en arrière-plan (WorkManager).

### E5 — Gestion des médias lourds `feature`

- **#23 — Déport des images médicales sur serveur chiffré + URL éphémère** · `Must` · `L` · `feature` `security` `infra`
  Interdire le stockage des radiographies/scans sur le téléphone ; les stocker sur serveur distant chiffré ; n'intégrer qu'un lien d'accès éphémère au dossier texte.
  *Acceptation :* aucune image lourde sur le téléphone patient ; URL éphémère révoquée après expiration.
  *Implémente :* PRD §4 (contrainte stockage).

- **#24 — Optimisation réseau dégradé (Edge/3G)** · `Should` · `M` · `tech-debt` `infra`
  Téléchargement/déchiffrement instantanés sous Edge/3G : compression, reprise de téléchargement, budget de taille.
  *Acceptation :* dossier de 500 Ko téléchargé+déchiffré dans la cible perf sur lien simulé 3G instable.
  *Dépend de :* #15, #14.

---

## M4 — Durcissement & lancement

> **Objectif :** Prouver la sécurité, obtenir l'homologation, valider les performances et piloter à Abidjan.

### E3 — Sécurité & audit `security`

- **#25 — Audit de sécurité & test d'intrusion externe** · `Must` · `L` · `security`
  Pentest par un tiers ciblant crypto, zero-knowledge, QR, récupération de clé, wipe RAM.
  *Acceptation :* rapport d'audit ; toutes les vulnérabilités `Critical`/`High` corrigées et re-testées.
  *Dépend de :* M1–M3 complets.

- **#26 — Revue cryptographique indépendante** · `Should` · `M` · `security` `crypto`
  Revue par un expert crypto des choix AES-GCM, PBKDF2, gestion des nonces/clés.
  *Acceptation :* avis d'expert favorable ou correctifs appliqués.

### E4 — Performance & UX `ux`

- **#27 — Validation des performances (déchiffrement < 3 s en 3G)** · `Must` · `M` · `tech-debt` `ux`
  Banc de mesure : scan → affichage du dossier ≤ 3 s sous 3G stable.
  *Acceptation :* mesures reproductibles confirmant la cible ; régression bloquée en CI.
  *Implémente :* NFR Performance.
  *Avancement :* **modèle de budget + gate CI livrés.** Le cap 3 s est décomposé
  (doc source [`docs/perf/decryption-budget.md`](./docs/perf/decryption-budget.md))
  autour d'un profil `3G-STABLE` documenté (750 kbit/s, 150 ms) : terme réseau
  modélisé analytiquement et **borné de façon déterministe** par un plafond de
  taille de blob (`MAX_BLOB_BYTES = 128 Kio`), termes CPU bornés par des seuils
  généreux (ordre de grandeur). **Artefacts :** constantes uniques `PerfBudget`
  (`app-patient/lib/src/record/perf_budget.dart`) ; garde de taille déterministe
  `test/record/blob_size_budget_test.dart` (worst-case ~500 Kio → ~48 Kio
  on-wire, ≤ plafond) ; timing chaîne CPU in-process
  `test/perf/decrypt_pipeline_perf_test.dart` (median-of-N, réseau exclu) ;
  régression décryptage Rust `crypto-core/tests/decrypt_perf_regression.rs`
  (+ bench reporting `benches/decrypt_record.rs`, sans criterion) ; recette
  `just perf`. Les assertions **roulent dans la CI existante** (`cargo test
  --workspace` / `flutter test`) → *régression bloquée en CI*. Protocole terrain
  hors-CI documenté ([`docs/perf/measurement-protocol.md`](./docs/perf/measurement-protocol.md)).
  **Reste :** mesures terrain réelles (lien throttlé/appareil) avant #31 ;
  benchmark décryptage **PWA** après l'arrivée du WASM #17 ; suivi (hors #27) —
  **le blob de session QR n'est pas compressé aujourd'hui** (`access_token.dart`),
  donc le téléchargement médecin n'est pas encore borné par `MAX_BLOB_BYTES`
  (optimisation, hors périmètre mesure+gate).

- **#28 — Affûtage UX médecin (prise en main < 5 min)** · `Must` · `M` · `ux`
  Interface ultra-épurée, sans menus complexes ; tests d'utilisabilité avec des médecins.
  *Acceptation :* un médecin non formé réalise une consultation complète en < 5 min lors d'un test utilisateur.
  *Implémente :* NFR UX.
  *Avancement :* **norme + outillage + protocole livrés.** Guide UX opposable ([`docs/ux/medecin-ux-guidelines.md`](./docs/ux/medecin-ux-guidelines.md) — mono-flux « zéro menu », parcours canonique 4 étapes / 3 écrans, hiérarchie de l'info critique, ergonomie clinique, microcopie FR, feedback d'état, anti-patterns, checklist de revue UX) et protocole de test utilisateur ([`docs/ux/usability-test-protocol.md`](./docs/ux/usability-test-protocol.md) — panel, environnement bas de gamme + 3G-STABLE, scénario scripté, SUS FR, seuils, éthique, gabarit de compte-rendu « à produire »). Source de vérité code : budget d'étapes ([`app-patient/lib/src/doctor/ux_budget.dart`](./app-patient/lib/src/doctor/ux_budget.dart) — `maxConsultationSteps`, `maxConsultationScreens`, `canonicalSteps`, `criticalSectionOrder`, proxy temps-tâche machine) et instrumentation temps-tâche respectueuse de la vie privée ([`app-patient/lib/src/doctor/task_timing.dart`](./app-patient/lib/src/doctor/task_timing.dart) — labels + durées seulement, désactivée par défaut). Gate de cohérence doc↔code [`scripts/check-ux-docs.sh`](./scripts/check-ux-docs.sh) câblé (`just ux-check`, dans `just lint`). Le garde-fou de parcours host-only (`app-patient/test/ux/`) et le test de fumée PWA (`app-medecin/src/walkthrough.test.ts`) arrivent en phase tests. **Restant (démarche humaine + séquencement) :** la **campagne d'utilisabilité terrain** avec de vrais médecins (preuve du critère < 5 min — non closable par du code, mêmes limites que #25/#30), collectée via #31 ; portage du flux de consultation dans la PWA `app-medecin` (#17/#21/#22) avant tout test terrain sur cette surface ; valeur définitive de `MAX_CONSULTATION_STEPS` à confirmer par un premier passage terrain.

- **#29 — Accessibilité & robustesse sur smartphones d'entrée de gamme** · `Should` · `M` · `ux` `tech-debt`
  Tester sur appareils type Infinix 32 Go quasi saturés ; gérer micro-coupures de courant.
  *Acceptation :* parcours patient et médecin validés sur appareil de référence bas de gamme.

### E6 — Homologation & lancement `compliance`

- **#30 — Dossier d'homologation ARTCI** · `Must` · `L` · `compliance` `docs`
  Constituer et soumettre le dossier d'homologation ; preuves de conformité (#5, #25).
  *Acceptation :* homologation ARTCI obtenue à 100 % avant lancement commercial (Objectif KPI).
  *Dépend de :* #5, #25.
  *Avancement :* **dossier consolidé constitué** sous [`docs/compliance/homologation-artci/`](./docs/compliance/homologation-artci/README.md) — README maître (résumé opposable ZK/crypto/QR/résidence/500 Ko), index probatoire `PIECE-01…18 ↔ PREUVE-NN` avec statut dérivé honnêtement ([`piece-list.md`](./docs/compliance/homologation-artci/piece-list.md)), tableau de readiness (5 Prêtes / 2 Partielles / 6 À produire / 5 Bloquantes ; **0/22 `Must` juridiquement validées**), note de formalité `[à confirmer — conseil juridique]` et checklist de dépôt (gate humain). Gate de complétude/cohérence [`scripts/check-homologation-dossier.sh`](./scripts/check-homologation-dossier.sh) câblé (`just homologation-check`, dans `just lint`). **Soumission bloquée** (chemin critique) par : sign-off juridique 0/22 (#5), attestation de localisation non signée (#8), rapport de pentest non produit (#25), écarts ECART-01…04. Le **dépôt ARTCI et l'obtention du récépissé** (`PREUVE-13`) restent une **démarche humaine/juridique** hors périmètre agent.

- **#31 — Pilote terrain à Abidjan (beta)** · `Should` · `L` · `feature` `ux`
  Déploiement pilote (Cocody/Yopougon) avec un panel de patients et médecins ; collecte de retours.
  *Acceptation :* pilote mené ; métriques d'adoption et de fiabilité collectées vers les KPIs (50 000 patients / 500 médecins).
  *Dépend de :* #30.

---

## Récapitulatif des dépendances clés

- **#10 (AES-256-GCM)** est la pierre angulaire : bloque #14, #16, #17, #21.
- **#9 (serveur zero-knowledge)** bloque toute sauvegarde/lecture cloud (#14, #17, #19).
- **#25 (pentest)** et **#5 (conformité)** conditionnent **#30 (homologation ARTCI)**, elle-même prérequis du lancement.
- La boucle de consultation (M2) n'a de valeur démontrable qu'une fois #16→#19 enchaînés ; viser un premier *end-to-end* (#20) le plus tôt possible.

## Risques à surveiller

1. **Récupération de clé** (#12) : compromis sécurité ↔ ergonomie ; un mauvais choix bloque les patients hors de leurs données.
2. **Contrainte 500 Ko** (#15, #24) : impose une discipline de schéma dès M1, difficile à rétro-fitter.
3. **Hébergement souverain** (#8) : délai d'approvisionnement potentiellement long, à lancer dès M0.
4. **Homologation ARTCI** (#30) : dépendance externe sur le chemin critique du lancement.

---

## Ordre d'implémentation recommandé

> Séquence dérivée des dépendances de chaque issue. Reflétée dans le champ **`Ordre`** du [GitHub Project « HealthTech — Roadmap »](https://github.com/users/kortiene/projects/2) (tri ascendant pour la dérouler à l'écran).

### Chemin critique (enchaînement bloquant le plus long)

> **#1 → #2 → #6 → #10 → #9 → #14 → #16 → #17 → #19 → #21 → #25 → #30 → #31**

Tout retard sur cette chaîne décale le lancement. Deux dépendances **externes** y pèsent lourd : **#8** (hébergement, à lancer immédiatement) et **#5 + #30** (conformité / homologation ARTCI) — d'où leur démarrage anticipé malgré l'absence de code.

### Vagues (ce qui peut avancer en parallèle)

- **Vague 0 — fondations & longs délais (J0, en parallèle) :** #1, #6, #5, #8
- **Vague 1 — socle technique :** #2, #3, #4, #7, #15
- **Vague 2 — cœur crypto & backend :** #10, #9, #11
- **Vague 3 — onboarding patient (M1) :** #12, #14, #13
- **Vague 4 — boucle de consultation (M2, quasi séquentielle) :** #16 → #17 → #18 → #19 → #20
- **Vague 5 — résilience hors-ligne & médias (M3) :** #21, #23, #24, #22
- **Vague 6 — durcissement & lancement (M4) :** #26, #28, #27, #29, #25, #30, #31

### Séquence stricte (1 seul flux, ordre topologique)

| Ordre | Issue | | Ordre | Issue |
| ----: | ----- | --- | ----: | ----- |
| 1  | #1 — Stack & ADR              | | 17 | #17 — Scan QR + déchiffrement RAM |
| 2  | #6 — Modèle de menace         | | 18 | #18 — Note / ordonnance |
| 3  | #5 — Conformité ARTCI         | | 19 | #19 — Fin de session + wipe |
| 4  | #8 — Hébergement souverain    | | 20 | #20 — Démo end-to-end |
| 5  | #2 — Monorepo                 | | 21 | #23 — Déport images + URL éphémère |
| 6  | #3 — CI/CD                    | | 22 | #24 — Optimisation réseau dégradé |
| 7  | #4 — Environnements & secrets | | 23 | #21 — File offline (SQLCipher) |
| 8  | #15 — Schéma dossier ≤ 500 Ko | | 24 | #22 — Synchronisation réseau |
| 9  | #10 — Module AES-256-GCM      | | 25 | #26 — Revue crypto indépendante |
| 10 | #9 — Service blob zero-knowledge | | 26 | #28 — Affûtage UX médecin |
| 11 | #11 — Clé maîtresse locale    | | 27 | #27 — Validation perf < 3 s |
| 12 | #12 — Dérivation/récupération PBKDF2 | | 28 | #29 — Accessibilité bas de gamme |
| 13 | #7 — Consentement & juridique | | 29 | #25 — Audit sécurité / pentest |
| 14 | #13 — Création de compte chiffré | | 30 | #30 — Homologation ARTCI |
| 15 | #14 — Sauvegarde cloud ZK     | | 31 | #31 — Pilote terrain Abidjan |
| 16 | #16 — Génération QR temporaire | | | |
