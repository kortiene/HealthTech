# Affûtage UX médecin — prise en main d'une consultation en < 5 min

> **Issue :** #28 — Affûtage UX médecin (prise en main < 5 min) · **Épic :** E4 — Performance & UX · **Jalon :** M4 · **Effort :** M · **Priorité :** Must · **Étiquette :** `ux`
> **Implémente :** NFR UX (PRD §5 — « L'application du médecin doit pouvoir être prise en main avec moins de 5 minutes de formation »).
> **Ordre recommandé :** 26 (vague 6 — durcissement & lancement), après la boucle de consultation (#17→#19) et la résilience hors-ligne (#21/#22).

## Problem Statement

Le PRD (§5) et l'ADR 0002 posent une exigence non-fonctionnelle mesurable : un médecin **non formé** doit pouvoir réaliser une **consultation complète** (scanner le QR patient → lire le dossier → ajouter une note/ordonnance → terminer la session) en **moins de 5 minutes**, avec une interface « ultra-épurée, sans menus complexes ». Le persona Dr. Koné voit 30 patients/jour : chaque seconde et chaque friction cognitive comptent, et l'outil doit s'insérer dans sa routine sans l'obliger à apprendre une nouvelle logique.

Aujourd'hui, il manque deux choses :

1. **Une norme UX opposable.** Les écrans médecin existants (voir *Relevant Repository Context*) ont été construits fonctionnalité par fonctionnalité (#17–#22) sans spécification UX transverse : pas de principes d'interaction figés, pas de règles de microcopie française, pas de contraintes d'ergonomie clinique (cibles tactiles, hiérarchie de l'information critique comme les allergies, lisibilité en plein jour, gestuelle à une main). Rien ne garantit aujourd'hui que le parcours reste « sans menus complexes » quand de nouvelles fonctions s'ajoutent.
2. **Une preuve du < 5 min.** Le critère d'acceptation est un résultat de **test d'utilisabilité avec de vrais médecins** — activité humaine/terrain non automatisable, comme le pentest (#25) et l'homologation (#30). Il n'existe ni protocole de test, ni instrument de mesure du temps-tâche, ni garde-fou automatisé empêchant une régression du parcours (ajout d'une étape, d'un écran, d'un menu) entre deux tests terrain coûteux.

Cette issue livre la **norme UX** + l'**outillage de mesure/anti-régression** + le **protocole de test utilisateur**, et cadre ce qui reste une **démarche humaine** (le test terrain lui-même).

## Goals

- **G1 — Principes UX figés.** Un document normatif de conception de l'interface médecin : parcours mono-flux, « zéro menu », hiérarchie de l'information (allergies/pathologies avant le reste), microcopie française, cibles tactiles et lisibilité pour usage clinique, feedback d'état (compte à rebours QR, « en attente »/hors-ligne, wipe de fin de session), gestion des erreurs orientée action.
- **G2 — Parcours de référence documenté et compté.** Décrire le parcours canonique en N étapes explicites (scan → lecture → note/ordonnance → terminer) et le nombre d'interactions/écrans requis, pour qu'un ajout futur soit évalué contre cette ligne de base.
- **G3 — Garde-fou anti-régression automatisé.** Un test (host-only, exécutable en CI existante) qui traverse le parcours de référence et **échoue si le nombre d'étapes/écrans dépasse le budget** défini, et qui mesure un **temps-tâche machine** (proxy déterministe, réseau exclu) comme signal de régression — pas comme substitut au test humain.
- **G4 — Instrumentation temps-tâche respectueuse de la vie privée.** Un mécanisme optionnel de mesure de durée de tâche pour les sessions de test utilisateur (horodatage d'étapes, agrégats de durée) **sans jamais journaliser de donnée médicale, de clé, ni de PII**.
- **G5 — Protocole de test utilisateur.** Un document reproductible : recrutement (médecins non formés, profil Dr. Koné), scénario scripté, environnement (appareil de référence bas de gamme, lien 3G simulé), grille de scores (SUS + succès/échec par tâche + temps), seuil de réussite (< 5 min), et modèle de compte-rendu — livrable exploitable pour #29 (bas de gamme) et #31 (pilote Abidjan).
- **G6 — Traçabilité.** Rattacher la preuve produite à la NFR UX du PRD et à l'issue #31 (pilote), sans prétendre que le test terrain est réalisé tant qu'il ne l'est pas.

## Non-Goals

- **Réaliser** le test d'utilisabilité terrain avec de vrais médecins (activité humaine — cette issue livre le protocole, l'instrument et le garde-fou, pas les mesures terrain ; celles-ci sont collectées lors de #31 / d'une campagne dédiée).
- **Construire ou finir la boucle de consultation** elle-même : le scan (#17), la note/ordonnance (#18), la fin de session/wipe (#19), la file hors-ligne (#21) et la resync (#22) sont hors périmètre — #28 **affine** leur UX, il ne les implémente pas.
- **Porter la boucle de consultation dans la PWA** (`app-medecin`) : le câblage WASM crypto-core (#17), le flux de scan PWA + Service Worker (#21) et la file IndexedDB (#22) restent des issues distinctes. #28 fournit la norme UX que ce portage devra respecter, mais ne l'exécute pas.
- Toute modification de la cryptographie, du format de blob, du protocole réseau ou du modèle de menace.
- Accessibilité fine et robustesse bas de gamme approfondies : cadrées par **#29** (`ux` `tech-debt`). #28 pose les invariants d'ergonomie ; #29 valide sur appareil de référence.
- Internationalisation multi-langues : l'UI est en **français** (marché ivoirien) ; pas de i18n framework ici.

## Relevant Repository Context

**Architecture (rappel).** Local-first / zero-knowledge : le dossier est chiffré côté patient en AES-256-GCM (crypto-core Rust, #10) avant tout transit ; le serveur ne stocke que des blobs opaques indexés par UUID anonyme (#9) ; le médecin déchiffre **en RAM uniquement** après scan d'un QR éphémère (~120 s), et la session est **effacée** (wipe) à « Terminer » ou après 15 min d'inactivité (#17–#19). Résilience hors-ligne via file chiffrée (#21) drainée à la reconnexion (#22). Données hébergées en Côte d'Ivoire (ARTCI / loi n°2013-450). Budget dossier ≤ 500 Ko de texte brut ; images lourdes jamais sur le téléphone (URL éphémère uniquement).

**Deux surfaces « médecin » coexistent — point à clarifier (voir Risks) :**

1. **PWA `app-medecin/` (surface de production selon l'ADR 0002).** Preact + TypeScript + Vite, testée avec **vitest**. C'est *aujourd'hui un scaffold qui compile* :
   - `app-medecin/src/app.tsx` — app-shell stub ; commentaire explicite « consultation flow à venir (TODO(#21)) », WASM crypto TODO(#17), file IndexedDB TODO(#22).
   - `app-medecin/src/session.ts` — helpers purs : `sessionTitle()`, `IDLE_TIMEOUT_MS = 15 min` (aligné #19).
   - `app-medecin/src/app.test.ts` — tests vitest existants.
   - `app-medecin/README.md` — décrit le parcours cible mono-flux (scan → RAM-only → éditer → re-chiffrer → upload → wipe + reload). **Le parcours n'est pas encore implémenté dans la PWA.**
   - **ADR 0002** cite explicitement le « learnable in < 5 minutes » et « ultra-simple single-flow UI » comme motivation du choix Preact — #28 en est la matérialisation.

2. **Implémentation Flutter de référence dans `app-patient/` (host-testable, pour la démo e2e #20).** Écrans médecin réels, en français, Material, déjà mono-flux :
   - `app-patient/lib/src/ui/scan_screen.dart` — viseur caméra, décodage QR, gestion d'erreurs orientée action (`'QR expiré — demandez un nouveau code au patient'`, etc.).
   - `app-patient/lib/src/ui/record_view_screen.dart` — dossier en cartes de sections (Informations, Allergies, Pathologies, Médicaments, Consultations), FAB « Ajouter une note / ordonnance », action AppBar « Terminer », minuteur d'inactivité 15 min, badge « N en attente » + « Synchroniser », snackbars hors-ligne rassurantes.
   - `app-patient/lib/src/ui/consultation_edit_screen.dart` — formulaire d'édition rapide.
   - `app-patient/lib/src/doctor/*` — services (scan, merge, edit, session end, offline queue SQLCipher, sync). Voir aussi `app-patient/test/e2e/consultation_loop_e2e_test.dart` et `app-patient/test/support/consultation_loop_harness.dart`.

   Ces écrans sont la **meilleure référence UX existante** et constituent un premier terrain d'application de la norme (et du garde-fou host-only).

**Conventions observées.**
- **Microcopie 100 % française**, ton orienté action (ex. les messages d'erreur du `scan_screen`).
- Specs récentes nommées `specs/issue-NN-<slug>.md` (ex. `issue-27-decryption-performance-validation.md`) ; docs thématiques sous `docs/<thème>/` (ex. `docs/perf/`, `docs/compliance/`).
- Recettes via `justfile` (ex. `just perf`, `just lint`, `just homologation-check`) — les gates roulent dans la CI existante (`flutter test`, `cargo test --workspace`, `npm test` côté PWA).
- ADR pour toute décision structurante, sous `docs/adr/`.

**Statut stack (caveat #1).** L'ADR 0001 (patient Flutter), 0002 (médecin PWA Preact), 0003 (crypto-core Rust WASM) et 0004 (backend Rust/axum) sont **Acceptés** — le socle technique est donc largement tranché *au niveau ADR*. **Ne pas confondre** avec les choix d'outillage UX propres à #28 qui, eux, **restent ouverts** : bibliothèque de design-tokens/thème, éventuel harnais de mesure temps-tâche, framework de test de parcours côté PWA (Playwright vs Testing-Library/vitest). Ces choix sont flaggés comme décisions à confirmer.

## Proposed Implementation

L'issue #28 se décompose en **quatre livrables**, du plus normatif au plus opérationnel. Aucun ne modifie la crypto ni le protocole.

### Livrable A — Guide UX de l'interface médecin (normatif) → `docs/ux/medecin-ux-guidelines.md`

Document opposable qui fige les principes et sert de critère de revue pour toute future contribution touchant l'UI médecin :

- **Principe mono-flux « zéro menu ».** Un seul parcours linéaire ; interdiction de menus imbriqués/hamburger/onglets pour le cœur de consultation. Toute action secondaire (synchro, hors-ligne) reste périphérique et non bloquante.
- **Parcours canonique de référence** (base du budget d'étapes, cf. Livrable C) :
  1. **Scanner** le QR patient (une action : viser).
  2. **Lire** le dossier — l'information vitale (allergies, pathologies chroniques, médicaments) est visible **sans défilement** ou en tête de liste.
  3. **Ajouter** une note / ordonnance (une action d'entrée : le FAB) → formulaire rapide → valider.
  4. **Terminer** (une action) → re-chiffrement + envoi/enqueue + wipe → confirmation.
- **Hiérarchie de l'information critique** : ordre et proéminence des sections ; les allergies ne doivent jamais être « sous le pli » sans indicateur.
- **Ergonomie clinique** : cibles tactiles ≥ 48 dp / 44 px, contraste AA minimum, typographie lisible en plein jour, utilisabilité à une main, pas de dépendance au survol.
- **Microcopie française** : registre, ton orienté action, vocabulaire médical local ; catalogue des chaînes clés (titres d'écran, libellés d'action, erreurs) avec la règle « message = cause + action à faire » (repris du `scan_screen`).
- **Feedback d'état obligatoire** : compte à rebours QR côté patient (référence #16), indicateur de déchiffrement (< 3 s, cf. #27), état « N en attente »/hors-ligne rassurant (jamais un rouge d'erreur pour un simple hors-ligne — cf. logique existante), confirmation visible du wipe/fin de session.
- **Gestion des erreurs** : chaque erreur mappe une action de récupération (modèle déjà présent dans `scan_screen._errorMessage`).
- **Anti-patterns explicitement bannis** : boîtes de dialogue en cascade, confirmations superflues, réglages avancés dans le flux, jargon technique visible.
- **Checklist de revue UX** (à intégrer dans la revue de PR / `review_phase`) que toute PR modifiant l'UI médecin doit passer.

### Livrable B — Protocole de test d'utilisabilité (opérationnel) → `docs/ux/usability-test-protocol.md`

Document reproductible pour la campagne terrain (exécutée par des humains ; sortie = preuve du critère d'acceptation) :

- **Objectif & hypothèse mesurable** : un médecin non formé complète une consultation en < 5 min ; définition précise de « complète » (les 4 étapes du parcours canonique, dossier mis à jour observable).
- **Panel** : médecins généralistes non formés au produit, profil Dr. Koné ; taille d'échantillon recommandée (p. ex. 5–8 pour du qualitatif, justifiée).
- **Environnement de test** : appareil de référence bas de gamme (type Infinix, cf. #29), lien réseau 3G/Edge simulé (cf. profil `3G-STABLE` de #27), données de test **synthétiques** (aucune donnée patient réelle).
- **Scénario scripté** : tâches à réaliser, consignes au facilitateur, ce qui est chronométré (début = scan, fin = confirmation de fin de session).
- **Instruments** : chronométrage des tâches (voir Livrable D), échelle **SUS** (System Usability Scale, traduite FR), taux de succès/échec par tâche, comptage d'erreurs et d'hésitations, verbatims.
- **Critères de réussite** : seuil temps < 5 min (médiane et % de participants sous le seuil), score SUS cible, zéro échec sur les étapes vitales.
- **Éthique & confidentialité** : consentement des participants, aucune captation de PII/donnée médicale réelle, données de session anonymisées, alignement avec la politique de consentement (#7).
- **Modèle de compte-rendu** : gabarit de résultats (statut « à produire » tant que la campagne n'a pas eu lieu — même discipline d'honnêteté que le dossier d'homologation #30).

### Livrable C — Garde-fou anti-régression du parcours (automatisé, CI)

Un test de parcours de référence qui **matérialise le budget d'étapes** du Livrable A et signale toute dérive :

- **Cible primaire** : côté implémentation médecin **réellement exécutable en CI**. Aujourd'hui, c'est l'implémentation Flutter de référence (`app-patient`), qui possède déjà un e2e host-only (`consultation_loop_e2e_test.dart`). Ajouter un test de type « parcours minimal » qui :
  - traverse scan → lecture → ajout note → terminer via les écrans/services existants ;
  - **asserte le nombre d'écrans/interactions** requis contre une constante de budget partagée (p. ex. `MAX_CONSULTATION_STEPS`) ; échoue si un écran/menu est ajouté sans mise à jour explicite du budget (donc revue consciente).
  - mesure un **temps-tâche machine déterministe** (somme des durées de traitement in-process, réseau exclu) comme **proxy de régression**, avec un seuil généreux — explicitement documenté comme **signal machine, pas preuve humaine du < 5 min**.
- **Constante de budget unique** (source de vérité) exposée dans le code médecin (analogue à `PerfBudget` de #27) et référencée par le guide UX (Livrable A) et le test.
- **Côté PWA** (`app-medecin`) : tant que la boucle n'y est pas implémentée (#17/#21/#22), fournir a minima un **test vitest de fumée du parcours** vérifiant les invariants déjà présents (mono-flux, `IDLE_TIMEOUT_MS`, absence de menu dans le shell) et documenter que le garde-fou « nombre d'étapes » PWA sera activé à l'arrivée du flux. Ne pas simuler un parcours qui n'existe pas.
- **Recette** : `just ux-check` (ou intégration dans `just lint`) enchaînant les assertions host-only.

### Livrable D — Instrumentation temps-tâche (respect vie privée, optionnelle)

Un utilitaire léger pour chronométrer les étapes pendant les sessions de test utilisateur, **sans surface de risque** :

- API minimale : marquer le début/fin des étapes canoniques (`scan`, `read`, `edit`, `terminate`) et produire des **durées agrégées** ; aucune capture du contenu du dossier.
- **Invariant de sécurité strict** : ne journalise **jamais** de donnée médicale, de clé, de payload QR, ni de PII — uniquement des libellés d'étape et des durées (millisecondes). Désactivée par défaut en production ; activable en mode test.
- Sortie exploitable par le compte-rendu du Livrable B (export CSV/JSON de durées anonymes).
- **Emplacement** : côté surface instrumentable (Flutter de référence pour la campagne host/appareil ; miroir PWA lorsque le flux y existe). Choix de l'emplacement à confirmer selon la surface retenue pour le test terrain (voir Risks).

### Séquencement de mise en œuvre par un agent

1. Écrire le guide UX (A) — normatif, sans code.
2. Écrire le protocole de test (B) — normatif, sans code.
3. Introduire la constante de budget d'étapes + le garde-fou (C) sur la surface Flutter existante ; ajouter le test de fumée PWA.
4. Ajouter l'instrumentation temps-tâche (D) et la recette `just ux-check`.
5. Mettre à jour la documentation transverse (PRD note, BACKLOG avancement, éventuel ADR UX, README des apps).

## Affected Files / Packages / Modules

**À créer**
- `docs/ux/medecin-ux-guidelines.md` — guide UX normatif (Livrable A).
- `docs/ux/usability-test-protocol.md` — protocole de test utilisateur (Livrable B).
- `docs/ux/README.md` — index du dossier UX (convention `docs/<thème>/`).
- Test de parcours minimal / budget (Livrable C), p. ex. `app-patient/test/ux/consultation_walkthrough_budget_test.dart`.
- Constante de budget d'étapes (Livrable C), p. ex. `app-patient/lib/src/doctor/ux_budget.dart`.
- Utilitaire d'instrumentation temps-tâche (Livrable D), p. ex. `app-patient/lib/src/doctor/task_timing.dart` (+ miroir PWA `app-medecin/src/taskTiming.ts` si retenu).
- Test de fumée parcours PWA, p. ex. `app-medecin/src/walkthrough.test.ts`.
- Éventuel `docs/adr/0011-doctor-ux-single-flow.md` si les principes doivent être figés en ADR (à décider).

**À lire / potentiellement ajuster (sans changer le comportement crypto/réseau)**
- `app-patient/lib/src/ui/scan_screen.dart`, `record_view_screen.dart`, `consultation_edit_screen.dart` — alignement microcopie/hiérarchie/cibles tactiles sur le guide.
- `app-medecin/src/app.tsx`, `session.ts`, `README.md` — refléter la norme UX cible ; ne pas prétendre que le flux existe.
- `app-patient/test/e2e/consultation_loop_e2e_test.dart`, `app-patient/test/support/consultation_loop_harness.dart` — réutiliser le harnais existant pour le garde-fou.
- `justfile` — ajouter `ux-check` (et l'intégrer à `lint`).
- `PRD_HealthTech.md` (§5), `BACKLOG.md` (#28), `README.md` racine — traçabilité.

## API / Interface Changes

- **Aucune** modification d'API réseau, d'endpoint backend, de surface QR/token, ou de CLI.
- **Nouvelles API publiques internes** (à documenter dans le README du paquet concerné) :
  - Constante de budget d'étapes (Livrable C) — surface de configuration du garde-fou.
  - Utilitaire d'instrumentation temps-tâche (Livrable D) — API publique décrite dans le guide/README ; contrat de sécurité (aucune PII/donnée médicale/clé) documenté explicitement.
- Nouvelle recette `just ux-check` (interface développeur/CI).

## Data Model / Protocol Changes

- **Aucune.** Pas de changement de schéma de dossier, de format de blob chiffré, de persistance, ni de sérialisation.
- L'instrumentation temps-tâche (D) ne produit que des **durées et libellés d'étape** en mémoire/export volontaire ; elle n'introduit aucun nouveau champ dans le dossier médical ni aucun stockage persistant de session par défaut.

## Security & Compliance Considerations

- **Ne jamais affaiblir la crypto.** #28 est purement UX/outillage ; aucune touche à AES-256-GCM, PBKDF2, gestion des nonces/clés, ni au format de blob.
- **Zero-knowledge préservé** : le serveur ne voit toujours que des blobs opaques indexés par UUID anonyme ; aucun nouveau flux de données vers le serveur.
- **Déchiffrement RAM-only + wipe de fin de session** : l'UX doit *rendre visible* et *ne pas contourner* le wipe (#19) ni le déchiffrement en mémoire (#17) ; l'instrumentation temps-tâche ne doit pas maintenir de référence au dossier déchiffré au-delà de la session, ni empêcher la GC/le reload-to-drop-heap de la PWA (ADR 0002).
- **QR éphémère (~120 s)** : l'UX doit afficher clairement l'état d'expiration et guider vers un nouveau code (comportement déjà présent) ; aucune persistance de la clé de session hors du QR.
- **Journalisation / redaction — invariant dur** : l'instrumentation (D) et tout log ajouté **ne doivent jamais** contenir de donnée médicale en clair, de clé, de payload QR, ni de PII — uniquement des libellés d'étape et des durées. À vérifier par un test de redaction et par la revue sécurité.
- **Résidence des données (ARTCI / loi n°2013-450)** : aucune donnée de test utilisateur contenant de la PII réelle ; données synthétiques uniquement ; tout artefact de campagne reste sur le territoire et conforme au registre des traitements (#5).
- **Budget ≤ 500 Ko & images lourdes** : inchangé ; l'UX de lecture doit présenter les médias comme des **liens éphémères** (jamais stockés sur l'appareil, cf. #23), sans introduire de mise en cache locale d'image.
- **Consentement** : le test utilisateur suit la politique de consentement participants (#7) ; distinct du consentement patient produit.

## Testing Plan

- **Garde-fou de parcours (host-only, CI)** : test qui traverse scan → lecture → note → terminer et **asserte le nombre d'écrans/étapes ≤ budget** ; échec si dépassement non justifié. (Flutter `app-patient` d'abord ; PWA quand le flux existe.)
- **Proxy temps-tâche machine (host-only, CI)** : mesure déterministe (réseau exclu) de la somme des traitements du parcours, seuil généreux, documenté comme signal de régression — **pas** comme preuve du < 5 min humain.
- **Test d'invariants UX** : vérifie l'ordre des sections critiques (allergies/pathologies avant le reste), la présence des libellés d'action clés en français, et l'absence de menu/onglet dans le shell médecin.
- **Test de redaction (sécurité)** : prouve que l'instrumentation temps-tâche n'émet aucune donnée médicale/clé/PII (assertions sur la sortie).
- **Test de fumée PWA (vitest)** : `IDLE_TIMEOUT_MS`, `sessionTitle`, mono-flux du shell ; marqueur documenté pour l'activation future du garde-fou d'étapes PWA.
- **Résilience/état** : l'UX hors-ligne (« N en attente », snackbar rassurante) reste couverte par les tests existants #21/#22 ; #28 ne les régresse pas.
- **Tests documentaires** : le garde-fou de cohérence (analogue à `just homologation-check`) vérifie que le guide UX et le protocole référencent des chemins/constantes existants.
- **Manuel / terrain (hors CI, humain)** : la campagne d'utilisabilité selon le protocole (B) — produit la preuve du critère d'acceptation ; résultats consignés au gabarit de compte-rendu.

## Documentation Updates

- **PRD** (`PRD_HealthTech.md` §5) : lier la NFR UX à la norme (`docs/ux/medecin-ux-guidelines.md`) et au protocole de test, comme la NFR conformité pointe vers la matrice.
- **BACKLOG** (`BACKLOG.md` #28) : ajouter un bloc *Avancement* honnête (norme + garde-fou + protocole livrés ; **mesures terrain restantes**, dépendantes d'une campagne humaine et de la présence du flux PWA).
- **ADR** : décider si un `docs/adr/0011-doctor-ux-single-flow.md` fige les principes mono-flux/zéro-menu (recommandé pour opposabilité).
- **README** : `app-medecin/README.md` (refléter la norme cible), `docs/ux/README.md` (nouvel index), README racine si nécessaire.
- **justfile** : documenter `just ux-check`.
- **Revue** : intégrer la checklist UX (Livrable A) au flux `review_phase`.

## Risks and Open Questions

1. **Quelle surface médecin est la cible du critère d'acceptation ?** L'ADR 0002 désigne la **PWA** `app-medecin` comme interface de production, mais son flux de consultation est encore un scaffold (`TODO(#17/#21/#22)`), tandis qu'une implémentation **Flutter de référence** complète existe dans `app-patient`. **À confirmer** : le test terrain < 5 min portera-t-il sur la PWA (nécessite d'avoir d'abord porté le flux, #17/#21/#22) ou sur l'implémentation Flutter de référence ? Cela détermine où vivent le garde-fou (C) et l'instrumentation (D). *Recommandation : figer la norme et le garde-fou maintenant sur la surface exécutable (Flutter), et miroiter dans la PWA à l'arrivée du flux.*
2. **Dépendance de séquencement** : une campagne d'utilisabilité crédible exige une boucle de consultation fonctionnelle de bout en bout sur la surface testée. Sur la PWA, cela dépend de #17/#21/#22 ; risque de blocage si #28 est lancé avant.
3. **Le critère d'acceptation est humain** : « un médecin non formé … lors d'un test utilisateur » ne peut être clos par du code. Le garde-fou automatisé est un **proxy anti-régression**, pas une preuve. Assumer explicitement, comme pour #25/#30.
4. **Budget d'étapes** : quelle valeur exacte pour `MAX_CONSULTATION_STEPS` ? À dériver du parcours canonique et à valider par un premier passage terrain ; risque de garde-fou trop laxiste ou trop rigide.
5. **Outillage UX ouvert (caveat #1)** : bibliothèque de thème/design-tokens, framework de test de parcours PWA (Playwright vs vitest/Testing-Library), format d'export de l'instrumentation — décisions à confirmer.
6. **Cohérence PWA ↔ Flutter** : deux implémentations de la même norme risquent de diverger ; prévoir que le guide UX est la source unique et que les deux surfaces s'y réfèrent.
7. **Recouvrement avec #29 (bas de gamme) et #31 (pilote)** : la campagne d'utilisabilité peut être mutualisée avec le pilote Abidjan (#31) ; à arbitrer pour éviter la duplication d'effort terrain.

## Implementation Checklist

1. [ ] **Confirmer la surface cible** (PWA vs Flutter de référence) pour le garde-fou et le test terrain (Risk #1) — via ADR ou décision d'équipe.
2. [ ] Créer `docs/ux/` + `docs/ux/README.md` (index).
3. [ ] Rédiger `docs/ux/medecin-ux-guidelines.md` : principes mono-flux/zéro-menu, parcours canonique en 4 étapes, hiérarchie info critique, ergonomie clinique (cibles/contraste/une-main), catalogue microcopie FR, feedback d'état, gestion d'erreurs, anti-patterns, checklist de revue UX.
4. [ ] Rédiger `docs/ux/usability-test-protocol.md` : objectif mesurable, panel, environnement (bas de gamme + 3G simulé), scénario scripté, instruments (SUS FR + temps + succès/échec), seuils de réussite, éthique/consentement (#7), gabarit de compte-rendu (statut « à produire »).
5. [ ] Introduire la constante de budget d'étapes (source de vérité, ex. `ux_budget.dart`) et la référencer depuis le guide.
6. [ ] Ajouter le **garde-fou de parcours** host-only (Flutter) réutilisant `consultation_loop_harness.dart` : assertion nombre d'écrans ≤ budget + proxy temps-tâche machine (réseau exclu, seuil généreux, documenté comme signal).
7. [ ] Ajouter le **test d'invariants UX** : ordre sections critiques, libellés d'action FR, absence de menu.
8. [ ] Ajouter l'**instrumentation temps-tâche** (Livrable D) avec contrat de sécurité (aucune PII/clé/donnée médicale) + **test de redaction**.
9. [ ] Ajouter le **test de fumée PWA** (vitest) et documenter l'activation future du garde-fou d'étapes PWA (ne pas simuler un flux inexistant).
10. [ ] Ajouter la recette `just ux-check` et l'intégrer à `just lint` (assertions en CI existante).
11. [ ] Aligner (sans changer le comportement crypto/réseau) la microcopie et la hiérarchie des écrans Flutter existants sur le guide ; refléter la norme cible dans `app-medecin` (README + shell).
12. [ ] Mettre à jour la doc transverse : PRD §5 (lien), BACKLOG #28 (*Avancement* honnête), README(s), éventuel ADR 0011, intégration checklist UX au `review_phase`.
13. [ ] Vérifier que **rien** ne journalise/persiste de plaintext, clé ou PII ; passer la revue sécurité.
14. [ ] Confirmer que tous les gates existants restent verts (`flutter test`, `npm test`, `cargo test --workspace`) et que `just ux-check` passe.
15. [ ] Marquer explicitement la partie **campagne terrain** comme démarche humaine restante (non close par cette issue).
