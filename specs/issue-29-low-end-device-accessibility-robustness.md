# Accessibilité & robustesse sur smartphones d'entrée de gamme

> **Issue :** #29 — Accessibilité & robustesse sur smartphones d'entrée de gamme · **Épic :** E4 — Performance & UX · **Jalon :** M4 — Durcissement & lancement · **Effort :** M · **Priorité :** Should · **Étiquettes :** `ux` `tech-debt`
> **Implémente :** Personas PRD §2 (Awa, smartphone Infinix 32 Go souvent saturé ; Dr. Koné, micro-coupures de courant) + KPI de fiabilité PRD §1 (« 100 % des consultations sans perte de données, même en coupure réseau totale ») + contrainte d'infrastructure locale PRD §4 (stockage des smartphones d'entrée de gamme).
> **Ordre recommandé :** 28 (vague 6 — durcissement & lancement), après #27 (perf < 3 s) et #28 (UX médecin < 5 min), et après la boucle de consultation (#17→#19) et la résilience hors-ligne (#21/#22) dont il valide la robustesse terrain.

## Problem Statement

Le produit vise explicitement des utilisateurs sur **matériel contraint** : le persona Awa possède un **Infinix 32 Go « souvent saturé »**, et le persona Dr. Koné travaille dans un environnement à **micro-coupures de courant**. Le KPI de fiabilité impose « **100 % des consultations sans perte de données** ». Or, jusqu'à présent, chaque brique a été construite et testée dans des conditions favorables (runner CI, machine de dev), sans jamais être **validée sur un appareil de référence bas de gamme** ni **stressée** par les deux contraintes terrain qui définissent le marché :

1. **Stockage quasi saturé.** Sur un téléphone 32 Go presque plein, les écritures locales peuvent échouer (« disque plein »). Les chemins qui écrivent sur disque — la **file hors-ligne SQLCipher** (#21) et son journal WAL, le keystore, les caches applicatifs — doivent **échouer proprement, alerter fort, et ne jamais perdre silencieusement** une consultation ni écrire de plaintext. Aujourd'hui, un seul chemin de perte résiduelle est identifié et géré (`OfflineQueueUnavailable` dans `session_end_service.dart`), mais il n'existe **aucune validation** que l'app reste utilisable, ni que le budget de stockage local est borné, sous pression disque.

2. **Micro-coupures de courant.** Une coupure peut **tuer le processus à n'importe quel instant** — y compris entre le chiffrement, le PUT réseau, l'enqueue hors-ligne et le wipe RAM. La logique de fin de session (#19/#21) et la synchronisation au retour réseau (#22) affirment des invariants de **non-perte / non-doublon** (*at-least-once* + PUT idempotent, `put` **puis** `remove`, WAL SQLCipher), mais ces invariants n'ont **jamais été éprouvés contre une interruption brutale** (process kill / kill -9 mid-write), ni sur un appareil réel à I/O lente et saturée.

3. **Accessibilité bas de gamme.** #28 pose les invariants d'ergonomie clinique (cibles tactiles ≥ 48 dp, contraste AA, lisibilité plein jour, usage à une main) au niveau de la **norme UX** ; #29 doit les **valider sur appareil de référence** et couvrir l'accessibilité fine restante : **mise à l'échelle du texte** (gros caractères système), **lecteurs d'écran** (TalkBack), **faible RAM** (déchiffrement RAM-only qui ne doit pas provoquer d'OOM), **écran de petite taille / basse densité**.

Le critère d'acceptation — « **parcours patient et médecin validés sur appareil de référence bas de gamme** » — est, comme le pentest (#25), l'homologation (#30) et la campagne d'utilisabilité (#28/#31), en partie une **activité humaine sur matériel réel** non closable par du seul code. Cette issue livre donc : (a) le **profil d'appareil de référence** documenté, (b) un **protocole de validation** reproductible (accessibilité + robustesse), (c) des **garde-fous anti-régression automatisés** exécutables dans la CI existante (pression disque, atomicité crash/coupure, budget de stockage local, invariants d'accessibilité), et (d) cadre explicitement ce qui reste une **validation terrain humaine**.

## Goals

- **G1 — Profil d'appareil de référence figé.** Un document normatif définissant l'« appareil de référence bas de gamme » (type Infinix 32 Go quasi saturé) : RAM, version Android/API minimale, densité/taille d'écran, espace libre résiduel cible, réglages d'accessibilité testés — source de vérité partagée par #28 (protocole d'utilisabilité), #29 et #31 (pilote Abidjan).
- **G2 — Protocole de validation accessibilité + robustesse.** Un document reproductible (activité humaine/terrain) : scénarios patient **et** médecin, procédure de saturation du stockage, procédure d'injection de coupures (process kill mid-flow, coupure réseau + coupure d'alimentation simulée), grille d'accessibilité (échelle texte, TalkBack, contraste, cibles tactiles, une main), critères de réussite, gabarit de compte-rendu « à produire ».
- **G3 — Garde-fou robustesse « pression disque » (CI).** Des tests host-only prouvant que les chemins d'écriture disque (file hors-ligne, wipe) **dégradent proprement** quand l'écriture échoue (« disque plein ») : alerte forte, **aucune perte silencieuse**, **aucun plaintext / clé écrit**, invariant `OfflineQueueUnavailable` respecté.
- **G4 — Garde-fou robustesse « coupure / atomicité » (CI).** Des tests host-only prouvant que, quel que soit l'instant d'interruption du parcours de fin de session et de synchronisation (avant/pendant/après PUT, enqueue, remove, wipe), on conserve **non-perte + non-doublon** et le **wipe RAM** ; qu'un redémarrage relit une file cohérente et draine sans doublon (idempotence UUID de #22).
- **G5 — Budget de stockage local borné.** Une constante/source de vérité (analogue à `PerfBudget` #27 et `UxBudget` #28) bornant l'empreinte disque locale attendue (taille de la file hors-ligne, absence d'images lourdes sur l'appareil — rappel #23), et un garde-fou signalant une dérive.
- **G6 — Invariants d'accessibilité automatisables.** Étendre le garde-fou UX (#28) avec des assertions vérifiables en CI : cibles tactiles ≥ 48 dp / 44 px, présence de libellés sémantiques (accessibilité lecteur d'écran) sur les actions clés, robustesse au **facteur d'échelle de texte** (pas de troncature/overflow des libellés d'action et de l'information vitale à grande taille).
- **G7 — Traçabilité.** Rattacher la validation aux personas PRD §2, au KPI de fiabilité §1 et à la contrainte de stockage §4 ; sans prétendre que la validation matérielle est réalisée tant qu'elle ne l'est pas.

## Non-Goals

- **Réaliser** la validation terrain sur l'appareil Infinix physique (activité humaine/matérielle — cette issue livre le profil, le protocole et les garde-fous, pas les mesures terrain ; celles-ci sont collectées lors de #31 / d'une campagne dédiée, potentiellement mutualisée avec #28).
- **Réimplémenter** la boucle de consultation, la file hors-ligne (#21), la synchronisation (#22) ou la fin de session (#19) : #29 **valide et durcit** leur robustesse, il ne réécrit pas leur logique. De petits correctifs de robustesse ciblés (ex. message d'erreur, garde de budget) sont acceptables ; toute refonte est hors périmètre.
- **Modifier la cryptographie, le format de blob, le protocole réseau, la surface QR/token ou le modèle de menace.** #29 est purement validation / robustesse / accessibilité.
- **Porter la boucle dans la PWA `app-medecin`** (câblage WASM crypto #17, Service Worker #21, file IndexedDB #22) : hors périmètre ; #29 fournit le profil et les invariants d'accessibilité que ce portage devra respecter, et note que le garde-fou PWA correspondant s'activera à l'arrivée du flux.
- **Optimisation perf < 3 s** (#27) et **budget d'étapes UX < 5 min** (#28) : déjà couverts ; #29 les *rejoue sur appareil contraint* mais ne redéfinit pas leurs cibles.
- **Internationalisation** : l'UI reste en **français** (marché ivoirien).
- **Compression du blob de session QR** : suivi identifié hors #27/#29 (cf. *Avancement* #27) — non traité ici.

## Relevant Repository Context

**Architecture (rappel).** Local-first / zero-knowledge : dossier chiffré côté patient en **AES-256-GCM** (crypto-core Rust, #10) avant tout transit ; le serveur ne stocke que des **blobs opaques indexés par UUID anonyme** (#9) ; le médecin déchiffre **en RAM uniquement** après scan d'un **QR éphémère (~120 s)**, et la session est **effacée (wipe)** à « Terminer » ou après 15 min d'inactivité (#17–#19). Résilience hors-ligne via **file chiffrée SQLCipher** (#21) drainée à la reconnexion (#22, *at-least-once* + PUT idempotent). Données hébergées en **Côte d'Ivoire** (ARTCI / loi n°2013-450). Budget dossier **≤ 500 Ko** de texte brut ; **images lourdes jamais sur le téléphone** (URL éphémère uniquement, #23).

**Surfaces concernées.**

- **Implémentation Flutter de référence `app-patient/`** (host-testable, Material, français) — surface porteuse des parcours patient **et** médecin de référence, et donc la cible exécutable de #29 :
  - **Robustesse / disque :** `app-patient/lib/src/doctor/session_end_service.dart` gère déjà le seul chemin de perte résiduelle : `SessionEndService.terminate` fait `PUT` puis, sur `BackendUnavailable`, **enqueue** au lieu de perdre, wipe en `finally`, et propage `OfflineQueueUnavailable` (après wipe) si l'enqueue échoue aussi (« disque plein ») pour **alerter fort**. `app-patient/lib/src/doctor/offline_upload_queue.dart` (interface + `InMemoryUploadQueue`) et `sqlcipher_upload_queue.dart` (impl. SQLCipher, WAL, table versionnée, clé scellée Keystore via #11) portent la persistance disque. `sync_service.dart` (#22) draine en FIFO — `put` **puis** `remove`, mutex anti-réentrance, `RetryPolicy` bornée, `SyncSummary` — garantissant no-loss/no-duplicate au niveau UUID. `sync_trigger.dart` déclenche resume/opportuniste.
  - **UI :** `app-patient/lib/src/ui/record_view_screen.dart` (cartes de sections, FAB, « Terminer », minuteur 15 min, badge « N en attente » + « Synchroniser », snackbars hors-ligne rassurantes), `scan_screen.dart` (erreurs orientées action), `consultation_edit_screen.dart`, `onboarding_screen.dart`, `qr_screen.dart`.
  - **UX/mesure (base à étendre, #28) :** `app-patient/lib/src/doctor/ux_budget.dart` (`UxBudget` — `canonicalSteps`, `maxConsultationSteps/Screens`, `criticalSectionOrder`, `taskTimeProxyBudgetMs`, `humanTrainingBudgetMs`), `task_timing.dart` (instrumentation temps-tâche respectueuse de la vie privée, désactivée par défaut). Tests garde-fous existants : `app-patient/test/ux/consultation_walkthrough_budget_test.dart`, `ux_budget_test.dart`, `task_timing_test.dart`.
  - **Perf (base, #27) :** `app-patient/lib/src/record/perf_budget.dart` (`PerfBudget`, `MAX_BLOB_BYTES = 128 Kio`), `test/record/blob_size_budget_test.dart`, `test/perf/decrypt_pipeline_perf_test.dart`. `record_size_guard.dart` borne le dossier à ≤ 500 Kio.
  - **Sécurité (base, #25) :** `app-patient/test/security/security_regression_test.dart` (14 tests nommés, dont `OFFLINE-OPAQUE`, `SESSION-WIPE×3`) — modèle pour de nouveaux tests de régression robustesse.
- **PWA `app-medecin/`** (Preact + TS + Vite, vitest) — **scaffold** : `app.tsx` (TODO(#17/#21/#22)), `session.ts` (`IDLE_TIMEOUT_MS`), `walkthrough.test.ts` (fumée). Le flux de consultation n'y est **pas** implémenté ; #29 y ajoute au plus des invariants d'accessibilité de fumée et documente l'activation future.
- **Documentation existante à étendre :** `docs/ux/` (`medecin-ux-guidelines.md`, `usability-test-protocol.md`, `README.md` — #28), `docs/perf/` (`decryption-budget.md`, `measurement-protocol.md` — #27), `docs/adr/` (0001 Flutter patient, 0002 PWA médecin, 0006 offline storage & keys, 0010 conflict resolution).

**Conventions observées.**
- Specs nommées `specs/issue-NN-<slug>.md` ; docs thématiques sous `docs/<thème>/` ; ADR sous `docs/adr/`.
- Recettes via `justfile` (`just perf`, `just ux-check`, `just lint`, `just homologation-check`) ; les gates roulent dans la CI existante (`flutter test`, `cargo test --workspace`, `npm test` PWA). Garde-fous de cohérence doc↔code en scripts `scripts/check-*.sh` fail-closed.
- **Microcopie 100 % française**, ton orienté action ; source-de-vérité numérique en constantes (`PerfBudget`, `UxBudget`).
- Discipline d'**honnêteté** : ce qui est une démarche humaine (terrain, juridique) est marqué « à produire / restant », jamais présenté comme fait (cf. #25/#28/#30).

**Statut stack (caveat backlog #1).** Les ADR 0001 (patient Flutter), 0002 (médecin PWA Preact), 0003 (crypto-core Rust/WASM), 0004 (backend Rust/axum) sont **Acceptés** — le socle est tranché *au niveau ADR*. **Restent ouverts** et à confirmer pour #29 : le **choix de l'appareil de référence exact** (modèle Infinix précis, API Android min), l'**outillage de simulation** (émulateur bas de gamme vs device farm vs appareil physique ; méthode de saturation disque ; méthode d'injection de coupure/kill), l'**outil d'audit d'accessibilité** (Accessibility Scanner Android, axe-core côté PWA), et la **stratégie de test crash-safe** (test host-only par injection de faute vs test instrumenté device-backed).

## Proposed Implementation

L'issue #29 se décompose en **cinq livrables**, du plus normatif au plus opérationnel, tous **sans toucher à la crypto ni au protocole**. Ils réutilisent les patterns de #27 (budget + gate CI) et #28 (norme + protocole + garde-fou + instrumentation).

### Livrable A — Profil d'appareil de référence (normatif) → `docs/ux/low-end-device-profile.md`

Document opposable, source de vérité partagée par #28/#29/#31 :

- **Définition de l'appareil de référence** : gamme (type Infinix), **RAM** cible (ex. 2–3 Go), **stockage** (32 Go) et **espace libre résiduel** de test (« quasi saturé » : cible d'espace libre en dessous de laquelle valider, ex. < 500 Mo), **version Android / API minimale** supportée, **densité / taille d'écran** (mdpi/hdpi, petit écran), **débit réseau** (réutiliser le profil `3G-STABLE` de #27).
- **Réglages d'accessibilité à tester** : facteur d'échelle de texte maximal supporté, TalkBack activé, contraste élevé, taille d'affichage.
- **Contraintes dérivées** pour l'implémentation : budget mémoire du déchiffrement RAM-only (le ≤ 500 Ko + l'absence d'images lourdes #23 doivent suffire), budget de stockage local (Livrable D), pas de dépendance à des API récentes indisponibles sur l'API min.
- **Traçabilité** vers PRD §2 (personas), §1 (KPI fiabilité), §4 (stockage) et les issues liées.

### Livrable B — Protocole de validation accessibilité & robustesse (opérationnel) → `docs/ux/low-end-validation-protocol.md`

Document reproductible (exécuté par des humains sur matériel réel ; sortie = preuve du critère d'acceptation). Symétrique du protocole d'utilisabilité #28, mais orienté **robustesse + accessibilité** et couvrant **les deux parcours** (patient : onboarding → génération QR → sauvegarde ; médecin : scan → lecture → note → terminer) :

- **Objectif & critère mesurable** : les deux parcours se complètent **sans perte de données** et restent **utilisables** sur l'appareil de référence saturé, sous coupures.
- **Environnement** : appareil de référence (Livrable A), stockage saturé selon le profil, lien 3G/Edge simulé (`3G-STABLE`, #27), données **synthétiques** (aucune PII/donnée médicale réelle).
- **Scénario « stockage saturé »** : procédure pour amener l'appareil à l'espace libre cible, puis exécuter les parcours ; vérifier que l'enqueue hors-ligne échoue **proprement** (alerte, pas de perte silencieuse), que rien de sensible n'est écrit, et que l'app reste réactive.
- **Scénario « micro-coupure »** : interruption brutale (retrait batterie/kill process) injectée à des points critiques (pendant chiffrement, pendant PUT, entre `put` et `remove`, pendant wipe) ; au redémarrage, vérifier **non-perte + non-doublon** et l'absence de plaintext/clé résiduel.
- **Grille d'accessibilité** : échelle de texte max (pas d'overflow de l'info vitale ni des actions), TalkBack (chaque action a un libellé), contraste AA, cibles tactiles ≥ 48 dp, usage à une main.
- **Perf sous contrainte** : rejouer la cible < 3 s (#27) et le proxy < 5 min (#28) sur l'appareil saturé ; consigner les écarts.
- **Instruments** : Accessibility Scanner (Android) / axe-core (PWA), l'instrumentation temps-tâche existante (`task_timing.dart`, #28), captures d'espace disque avant/après.
- **Critères de réussite** & **gabarit de compte-rendu** (statut « à produire » tant que la campagne n'a pas eu lieu — même discipline d'honnêteté que #25/#28/#30).
- **Éthique & confidentialité** : données synthétiques uniquement, alignement politique de consentement (#7), résidence des artefacts (#5).

### Livrable C — Garde-fous robustesse (automatisés, CI, host-only)

Des tests d'**injection de faute** réutilisant le harnais existant (`app-patient/test/support/consultation_loop_harness.dart`, fakes de `BackendClient`/`OfflineUploadQueue`), sans matériel :

- **C1 — Pression disque / « disque plein » :** file (fake) configurée pour faire échouer `enqueue` → prouver que `SessionEndService.terminate` **propage `OfflineQueueUnavailable` après le wipe**, que la session est **wipée quand même** (`finally`), et que **rien de sensible** (plaintext, clé de session) n'a été exposé ou persisté. Étendre `session_end_service_test.dart`.
- **C2 — Atomicité coupure / interruption :** simuler une interruption à chaque frontière du parcours de fin de session et de drain (#22) — avant PUT, après PUT avant `remove`, après enqueue avant wipe — et asserter les invariants **non-perte + non-doublon** (livraison *at-least-once* + PUT idempotent UUID) et **wipe RAM inconditionnel**. Réutiliser la logique in-memory de `sync_service_test.dart` / `offline_upload_queue_test.dart`, en ajoutant des points d'interruption injectés.
- **C3 — Redémarrage / reprise de file :** après une interruption simulée avec un blob enfilé, prouver qu'un `drain` ultérieur (#22) livre sans doublon et vide la file (idempotence). La **durabilité WAL réelle** de SQLCipher (survie à un vrai kill process) reste un test **device-backed** non exécutable en CI host-only — documenté comme restant.
- **C4 — Régression sécurité :** ajouter des cas nommés à `app-patient/test/security/security_regression_test.dart` (ex. `LOWEND-DISKFULL-NO-PLAINTEXT`, `LOWEND-CRASH-NO-KEY`, `LOWEND-CRASH-NO-LOSS`) sur le modèle des tests #25.

### Livrable D — Budget de stockage local (source de vérité + garde-fou) → `app-patient/lib/src/doctor/storage_budget.dart`

Analogue à `PerfBudget` (#27) et `UxBudget` (#28) :

- Constantes bornant l'**empreinte disque locale attendue** : rappel `MAX_BLOB_BYTES` (128 Kio, #27) par entrée de file, plafond raisonnable du **nombre d'entrées en file** avant alerte, invariant **« aucune image lourde sur l'appareil »** (#23 — seule une URL éphémère).
- Garde-fou host-only asserttant qu'une entrée de file respecte le plafond de taille et que le modèle de dossier n'embarque pas d'image binaire lourde (uniquement des URL éphémères).
- Documenté dans le profil (Livrable A) et référencé par le protocole (Livrable B).

### Livrable E — Invariants d'accessibilité automatisables (CI) — extension du garde-fou UX #28

Étendre les tests UX host-only (`app-patient/test/ux/`) et, a minima, la fumée PWA :

- **Cibles tactiles** : asserter que les actions clés (FAB « Ajouter », « Terminer », boutons d'onboarding, « Synchroniser ») exposent une cible ≥ 48 dp (widget tests Flutter).
- **Libellés sémantiques** : asserter la présence de `Semantics`/labels d'accessibilité (support lecteur d'écran) sur les actions clés et sur l'information vitale (allergies).
- **Robustesse à l'échelle de texte** : rendre les écrans clés avec un `textScaleFactor` élevé et asserter l'absence d'overflow/troncature de l'info vitale et des libellés d'action (widget tests).
- **PWA** : test de fumée vitest documentant l'invariant cible et son activation future à l'arrivée du flux (ne pas simuler un parcours inexistant).
- **Recette** : intégrer à `just ux-check` (ou nouvelle recette `just lowend-check`) et à `just lint` ; ajouter un `scripts/check-lowend-docs.sh` fail-closed (cohérence profil/protocole ↔ constantes existantes) sur le modèle de `check-ux-docs.sh` / `check-homologation-dossier.sh`.

### Séquencement de mise en œuvre par un agent

1. Rédiger le profil d'appareil de référence (A) — normatif, sans code.
2. Rédiger le protocole de validation (B) — normatif, sans code.
3. Introduire `storage_budget.dart` (D) + garde-fou de budget de stockage.
4. Ajouter les garde-fous robustesse host-only (C1–C4) en réutilisant le harnais et les fakes existants.
5. Ajouter les invariants d'accessibilité (E) aux widget tests + fumée PWA ; câbler la recette et le script de cohérence doc↔code.
6. Appliquer les **petits** correctifs de robustesse/accessibilité découverts (microcopie d'alerte, `Semantics`, tailles de cible) sans changer le comportement crypto/réseau.
7. Mettre à jour la documentation transverse (PRD, BACKLOG *Avancement* honnête, éventuel ADR, README) et marquer la **validation terrain** comme démarche humaine restante.

## Affected Files / Packages / Modules

**À créer**
- `docs/ux/low-end-device-profile.md` — profil d'appareil de référence (Livrable A).
- `docs/ux/low-end-validation-protocol.md` — protocole de validation accessibilité + robustesse (Livrable B).
- `app-patient/lib/src/doctor/storage_budget.dart` — source de vérité budget de stockage local (Livrable D).
- `app-patient/test/doctor/storage_budget_test.dart` — garde-fou de budget (Livrable D).
- Tests robustesse host-only (Livrable C) : extensions de `app-patient/test/doctor/session_end_service_test.dart`, `sync_service_test.dart`, `offline_upload_queue_test.dart` (points d'interruption injectés) ; cas nommés dans `app-patient/test/security/security_regression_test.dart`.
- Tests d'accessibilité (Livrable E) : `app-patient/test/ux/accessibility_invariants_test.dart` (cibles tactiles, `Semantics`, échelle de texte) ; extension de `app-medecin/src/walkthrough.test.ts` (fumée).
- `scripts/check-lowend-docs.sh` — garde-fou de cohérence doc↔code (fail-closed).
- Éventuel `docs/adr/0011-low-end-device-support.md` (ou numéro libre suivant) si le profil doit être figé en ADR — **à décider** (peut aussi vivre comme simple doc `docs/ux/`).

**À lire / potentiellement ajuster (sans changer le comportement crypto/réseau)**
- `app-patient/lib/src/doctor/session_end_service.dart`, `offline_upload_queue.dart`, `sqlcipher_upload_queue.dart`, `sync_service.dart`, `sync_trigger.dart` — points d'injection de faute ; robustesse « disque plein » et coupure.
- `app-patient/lib/src/ui/record_view_screen.dart`, `scan_screen.dart`, `consultation_edit_screen.dart`, `onboarding_screen.dart`, `qr_screen.dart` — cibles tactiles, `Semantics`, robustesse échelle texte, microcopie d'alerte robustesse.
- `app-patient/lib/src/doctor/ux_budget.dart`, `task_timing.dart` — base UX/mesure à réutiliser (#28).
- `app-patient/lib/src/record/perf_budget.dart`, `record_size_guard.dart`, `media_cipher.dart` — rappel des bornes (500 Ko, 128 Kio, images déportées #23).
- `app-patient/test/support/consultation_loop_harness.dart` — harnais et fakes réutilisés.
- `justfile` — recette `lowend-check` (ou extension `ux-check`) intégrée à `lint`.
- `PRD_HealthTech.md` (§2/§4), `BACKLOG.md` (#29), `README.md` racine, `docs/ux/README.md` — traçabilité.

## API / Interface Changes

- **Aucune** modification d'API réseau, d'endpoint backend, de surface QR/token, ni de CLI patient/médecin.
- **Nouvelles API publiques internes** (à documenter dans le README du paquet concerné) :
  - Constantes de **budget de stockage local** (`storage_budget.dart`, Livrable D) — surface de configuration du garde-fou.
- Nouvelle recette développeur/CI `just lowend-check` (ou extension de `just ux-check`).
- Nouveau script de cohérence `scripts/check-lowend-docs.sh` (interface CI).

## Data Model / Protocol Changes

- **Aucune.** Pas de changement de schéma de dossier, de format de blob chiffré, de schéma de la file SQLCipher, de persistance ou de sérialisation.
- Le budget de stockage (D) n'introduit que des **constantes** et un garde-fou ; aucun nouveau champ, aucun nouveau stockage. Les tests de robustesse (C) exercent les chemins existants sans modifier leurs contrats.

## Security & Compliance Considerations

- **Ne jamais affaiblir la crypto.** #29 est validation/robustesse/accessibilité ; aucune touche à AES-256-GCM, PBKDF2, gestion des nonces/clés, ni au format de blob. La saturation disque et les coupures ne doivent **jamais** conduire à contourner le chiffrement ou à écrire du plaintext en secours.
- **Zero-knowledge préservé** : le serveur (et la file locale) ne reçoivent que des **blobs opaques indexés par UUID anonyme** ; aucun nouveau flux de données ; les garde-fous d'injection de faute doivent **prouver** qu'un échec disque/coupure ne fait fuir ni plaintext, ni clé de session, ni payload QR (cas nommés Livrable C4).
- **Déchiffrement RAM-only + wipe (#17/#19)** : le wipe de fin de session doit rester **inconditionnel** même sous échec/interruption (`finally`) ; C1/C2 le prouvent. Une coupure d'alimentation vide la RAM *de facto* — l'invariant à garantir est qu'**aucun plaintext/clé n'a été écrit sur disque** avant la coupure. Sur PWA, le reload-to-drop-heap (ADR 0002) reste la stratégie.
- **QR éphémère (~120 s)** : inchangé ; l'accessibilité (échelle texte, TalkBack) ne doit pas exposer la clé ni prolonger la fenêtre.
- **Non-perte de données (KPI fiabilité)** : les garde-fous C2/C3 protègent l'invariant *at-least-once* + PUT idempotent UUID (#22) ; le seul chemin de perte résiduelle (`OfflineQueueUnavailable`) doit **alerter fort** (C1) — jamais échouer en silence.
- **Journalisation / redaction — invariant dur** : les alertes de robustesse ajoutées et l'instrumentation ne doivent **jamais** contenir de donnée médicale en clair, de clé, de payload QR, ni de PII — uniquement des libellés d'étape, des durées, des codes d'erreur techniques (réutiliser le contrat de `task_timing.dart`). À vérifier par les tests de redaction et la revue sécurité.
- **Budget ≤ 500 Ko & images lourdes (#23)** : réaffirmé par le budget de stockage (D) — **aucune image lourde stockée sur l'appareil**, seulement une **URL éphémère** ; c'est aussi la principale garde-fou mémoire pour les appareils faible RAM.
- **Résidence des données (ARTCI / loi n°2013-450)** : la validation terrain n'utilise que des **données synthétiques** ; artefacts de campagne conformes au registre des traitements (#5) ; consentement participants (#7).

## Testing Plan

- **Robustesse « disque plein » (host-only, CI, C1)** : `SessionEndService.terminate` avec une file qui échoue → `OfflineQueueUnavailable` propagé **après** wipe ; session wipée ; aucun plaintext/clé exposé.
- **Atomicité coupure (host-only, CI, C2)** : interruptions injectées avant/pendant/après PUT, enqueue, remove, wipe → invariants **non-perte + non-doublon** + wipe inconditionnel.
- **Reprise de file au redémarrage (host-only, CI, C3)** : drain post-interruption livre sans doublon et vide la file (idempotence UUID #22).
- **Budget de stockage (host-only, CI, D)** : entrée de file ≤ `MAX_BLOB_BYTES` ; modèle de dossier sans image binaire lourde (URL éphémère uniquement).
- **Accessibilité (widget tests Flutter, CI, E)** : cibles tactiles ≥ 48 dp sur les actions clés ; présence de `Semantics`/labels ; rendu à `textScaleFactor` élevé sans overflow de l'info vitale ni des libellés d'action.
- **Régression sécurité (host-only, CI, C4)** : cas nommés `LOWEND-DISKFULL-NO-PLAINTEXT`, `LOWEND-CRASH-NO-KEY`, `LOWEND-CRASH-NO-LOSS` ajoutés à `security_regression_test.dart`.
- **Fumée PWA (vitest)** : invariant d'accessibilité documenté + marqueur d'activation future (ne pas simuler un flux inexistant).
- **Cohérence doc↔code (script, CI)** : `scripts/check-lowend-docs.sh` vérifie que le profil/protocole référencent des chemins et constantes existants.
- **Non-régression des gates existants** : `flutter test`, `npm test`, `cargo test --workspace`, `just perf`, `just ux-check` restent verts.
- **Device-backed (restant, hors CI host-only)** : durabilité WAL SQLCipher sous vrai kill process ; illisibilité de la file sans clé Keystore ; déchiffrement RAM-only sous faible RAM réelle ; audit Accessibility Scanner / axe-core sur appareil. Documentés comme non exécutables en CI host-only.
- **Manuel / terrain (hors CI, humain)** : la validation des deux parcours sur l'appareil Infinix réel selon le protocole (B) — produit la **preuve du critère d'acceptation** ; résultats consignés au gabarit.

## Documentation Updates

- **PRD** (`PRD_HealthTech.md` §2/§4) : lier les personas et la contrainte de stockage bas de gamme au profil (`docs/ux/low-end-device-profile.md`) et au protocole, comme la NFR UX/perf pointent vers leurs docs.
- **BACKLOG** (`BACKLOG.md` #29) : ajouter un bloc *Avancement* honnête (profil + protocole + garde-fous CI livrés ; **validation matérielle terrain restante**, dépendante de l'appareil réel et potentiellement mutualisée avec #28/#31 ; tests device-backed WAL restants).
- **ADR** : décider si un ADR fige le **profil d'appareil de référence / support bas de gamme** (recommandé pour opposabilité ; sinon doc `docs/ux/`).
- **README** : `docs/ux/README.md` (ajouter les nouveaux docs à l'index), `app-medecin/README.md` si un invariant d'accessibilité PWA est noté, README racine si nécessaire.
- **justfile** : documenter `just lowend-check` (ou l'extension de `ux-check`).
- **Revue** : ajouter les invariants d'accessibilité/robustesse à la checklist de revue UX (Livrable A de #28) pour les PR touchant l'UI ou les chemins d'écriture disque.

## Risks and Open Questions

1. **Le critère d'acceptation est matériel/humain.** « Parcours validés sur appareil de référence bas de gamme » exige un **appareil réel** (ou device farm) ; les garde-fous CI sont des **proxies anti-régression**, pas la preuve. À assumer explicitement, comme #25/#28/#30.
2. **Choix de l'appareil de référence exact** (modèle Infinix précis, RAM, API Android min, espace libre cible « quasi saturé ») — décision d'équipe/produit à figer dans le profil (A).
3. **Méthode de test crash-safe.** L'injection de faute host-only (fakes) couvre la **logique** ; la **durabilité réelle** (WAL SQLCipher sous kill process, batterie retirée) n'est prouvable que **device-backed** — non exécutable dans la CI host-only actuelle. Où et comment exécuter ces tests device-backed reste ouvert (émulateur throttlé ? appareil physique dans un pipeline dédié ?).
4. **Surface médecin cible.** La PWA `app-medecin` (surface de production, ADR 0002) n'a pas encore le flux (#17/#21/#22) ; la validation terrain médecin portera-t-elle sur la PWA (nécessite le portage d'abord) ou sur l'implémentation Flutter de référence ? Cela conditionne où vivent les invariants d'accessibilité device-backed. *Recommandation : figer profil + garde-fous sur la surface Flutter exécutable, miroiter dans la PWA à l'arrivée du flux (cohérent avec #28).*
5. **Outillage ouvert (caveat #1)** : méthode de saturation disque, injection de coupure, outil d'audit d'accessibilité (Accessibility Scanner vs axe-core), format d'export des mesures — décisions à confirmer.
6. **Valeur du budget de stockage local** (`storage_budget.dart`) : combien d'entrées en file avant alerte ? À dériver du profil (32 Go quasi saturé) et d'un premier passage terrain ; risque de garde-fou trop laxiste ou trop rigide (même prudence que `MAX_CONSULTATION_STEPS`, #28).
7. **Recouvrement avec #28 (utilisabilité) et #31 (pilote).** Les campagnes terrain peuvent être **mutualisées** (même appareil de référence, mêmes participants) ; à arbitrer pour éviter la duplication d'effort.
8. **Faible RAM & déchiffrement RAM-only** : sur 2–3 Go de RAM, le déchiffrement en mémoire du dossier (borné à 500 Ko) + WASM crypto (PWA) doit tenir ; à valider — le budget 500 Ko et le déport des images (#23) sont les principales protections, mais l'empreinte réelle reste à mesurer.

## Implementation Checklist

1. [ ] **Confirmer le profil d'appareil de référence** (modèle Infinix, RAM, API min, espace libre cible) — décision produit/équipe (Risk #2), via doc ou ADR.
2. [ ] Rédiger `docs/ux/low-end-device-profile.md` (Livrable A) : appareil, RAM/stockage/espace libre, API Android min, densité/écran, réglages d'accessibilité, budgets dérivés, traçabilité PRD §2/§4 et KPI §1.
3. [ ] Rédiger `docs/ux/low-end-validation-protocol.md` (Livrable B) : parcours patient **et** médecin, scénario « stockage saturé », scénario « micro-coupure », grille d'accessibilité, perf sous contrainte (#27/#28), instruments, critères de réussite, gabarit de compte-rendu « à produire », éthique/consentement (#7), données synthétiques.
4. [ ] Introduire `app-patient/lib/src/doctor/storage_budget.dart` (Livrable D) : constantes de budget de stockage local (rappel `MAX_BLOB_BYTES`, plafond d'entrées, invariant « pas d'image lourde sur l'appareil ») + `storage_budget_test.dart`.
5. [ ] Ajouter les **garde-fous robustesse** host-only (Livrable C) en réutilisant `consultation_loop_harness.dart` et les fakes : C1 (disque plein → `OfflineQueueUnavailable` après wipe), C2 (atomicité coupure : non-perte + non-doublon + wipe inconditionnel), C3 (reprise de file au redémarrage, idempotence).
6. [ ] Ajouter les cas nommés de **régression sécurité** (Livrable C4) à `security_regression_test.dart` : `LOWEND-DISKFULL-NO-PLAINTEXT`, `LOWEND-CRASH-NO-KEY`, `LOWEND-CRASH-NO-LOSS`.
7. [ ] Ajouter les **invariants d'accessibilité** (Livrable E) : widget tests cibles tactiles ≥ 48 dp, `Semantics`/labels, robustesse `textScaleFactor` (pas d'overflow info vitale/actions) ; fumée PWA + marqueur d'activation future.
8. [ ] Appliquer les **petits** correctifs de robustesse/accessibilité découverts (microcopie d'alerte « disque plein/hors-ligne », `Semantics` manquants, tailles de cible) **sans** changer le comportement crypto/réseau.
9. [ ] Ajouter `scripts/check-lowend-docs.sh` (fail-closed) et la recette `just lowend-check` (ou extension `ux-check`), intégrées à `just lint`.
10. [ ] Vérifier que **rien** ne journalise/persiste de plaintext, clé, payload QR ou PII sous échec/coupure ; passer la revue sécurité.
11. [ ] Mettre à jour la doc transverse : PRD §2/§4 (liens), BACKLOG #29 (*Avancement* honnête), `docs/ux/README.md`, README(s), éventuel ADR profil bas de gamme.
12. [ ] Confirmer que tous les gates existants restent verts (`flutter test`, `npm test`, `cargo test --workspace`, `just perf`, `just ux-check`) et que `just lowend-check` passe.
13. [ ] Documenter explicitement les tests **device-backed** restants (durabilité WAL sous kill, faible RAM, audit accessibilité appareil) comme non exécutables en CI host-only.
14. [ ] Marquer explicitement la **validation terrain sur appareil Infinix réel** (deux parcours) comme démarche humaine restante, non close par cette issue (mutualisable avec #28/#31).
