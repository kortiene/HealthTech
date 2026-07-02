# Profil d'appareil de référence — smartphone bas de gamme

> **Issue porteuse :** [#29 — Accessibilité & robustesse sur smartphones d'entrée de gamme](../../BACKLOG.md) · Épic **E4 — Performance & UX** · Jalon **M4 — Durcissement & lancement** · labels `ux` `tech-debt`.
> **Implémente :** personas [`PRD_HealthTech.md`](../../PRD_HealthTech.md) §2 (Awa — Infinix 32 Go « souvent saturé » ; Dr. Koné — micro-coupures de courant), KPI de fiabilité §1 (« 100 % des consultations sans perte de données, même en coupure réseau totale ») et contrainte de stockage §4 (smartphones d'entrée de gamme).
> **Source de vérité partagée** par #28 (protocole d'utilisabilité), #29 (ce document) et #31 (pilote Abidjan).
> **Statut :** **document normatif opposable**, prêt à l'emploi. Le **choix du modèle Infinix exact** (Risk #2) et la **validation terrain** (deux parcours sur l'appareil réel) restent des **démarches humaines** non closes par du code — même discipline d'honnêteté que le pentest (#25), l'homologation (#30) et la campagne d'utilisabilité (#28).

Ce document **fige** ce qu'est l'« appareil de référence bas de gamme » sur lequel HealthTech doit
être **utilisable** et **robuste**. Il ne modifie ni la cryptographie, ni le format de blob, ni le
protocole réseau, ni le modèle de menace. Il sert de base commune au **protocole de validation**
([`low-end-validation-protocol.md`](./low-end-validation-protocol.md)) et aux **garde-fous
anti-régression** automatisés.

---

## 1. Définition de l'appareil de référence

| Caractéristique | Cible de référence | Justification |
|-----------------|--------------------|---------------|
| **Gamme** | Type **Infinix** (entrée de gamme, marché ivoirien) | Persona Awa (PRD §2). Modèle exact à figer par l'équipe produit (Risk #2). |
| **RAM** | **2–3 Go** | Contraint le déchiffrement RAM-only ; borne mémoire = dossier ≤ 500 Ko + images déportées (#23). |
| **Stockage** | **32 Go** | Persona Awa (PRD §2). |
| **Espace libre résiduel de test** | **< 500 Mo** (« quasi saturé ») | Cible réaliste sous laquelle valider ; les écritures locales (file SQLCipher #21, WAL, keystore) peuvent échouer. |
| **Version Android / API min** | **Android 8.0 / API 26** (à confirmer, Risk #2) | Plancher raisonnable pour l'entrée de gamme encore en service ; interdit toute dépendance à une API plus récente. |
| **Densité / taille d'écran** | Petit écran, **mdpi/hdpi** | Vérifier l'absence de troncature et le respect des cibles tactiles à basse densité. |
| **Débit réseau** | Profil **`3G-STABLE`** (#27) : ~750 kbit/s, ~150 ms RTT | Réutilise le profil de perf ([`docs/perf/decryption-budget.md`](../perf/decryption-budget.md)) pour rejouer le « < 3 s » sur appareil contraint. |

---

## 2. Réglages d'accessibilité à tester

Sur l'appareil de référence, valider les parcours sous chacun des réglages suivants :

- **Mise à l'échelle du texte** — facteur d'échelle système **élevé** (gros caractères) : aucune
  **troncature / overflow** de l'**information vitale** (allergies) ni des **libellés d'action**
  (`Ajouter une note / ordonnance`, `Terminer`, `Synchroniser`, boutons d'onboarding).
- **Lecteur d'écran (TalkBack)** — chaque action clé et l'information vitale exposent un **libellé
  sémantique** ; les titres de section sont des **en-têtes** navigables.
- **Contraste élevé** — lisibilité plein jour, contraste **AA** (repris de la norme UX #28).
- **Taille d'affichage** — densité augmentée : la mise en page reste utilisable **à une main**.

Les invariants automatisables correspondants (cibles tactiles ≥ 48 dp, présence de `Semantics`,
robustesse au `textScaleFactor`) sont des **garde-fous anti-régression** (widget tests `test/ux/`,
phase tests) ; ils ne remplacent pas l'audit sur appareil (Accessibility Scanner) — cf. §5.

---

## 3. Contraintes dérivées pour l'implémentation

- **Budget mémoire (RAM-only).** Le déchiffrement en mémoire du dossier (borné à **500 Ko** de
  texte brut, [`RecordSizeGuard`](../../app-patient/lib/src/record/record_size_guard.dart)) et le
  **déport des images lourdes** (#23 — seul un [`MediaDescriptor`](../../app-patient/lib/src/record/medical_record.dart)
  off-device est embarqué, jamais les octets) sont les principales protections mémoire pour les
  appareils à faible RAM.
- **Budget de stockage local.** Borné par la source de vérité
  [`app-patient/lib/src/doctor/storage_budget.dart`](../../app-patient/lib/src/doctor/storage_budget.dart)
  (`StorageBudget`) :
  - `maxQueueEntryBytes = 131072` (128 Kio) par entrée de file — **égal** à
    `PerfBudget.maxCompressedBlobBytes` (#27) ;
  - `maxPendingQueueEntries = 64` entrées en attente avant alerte UI (garde conservateur, **jamais**
    une purge silencieuse — KPI non-perte #22) ;
  - `maxQueueFootprintBytes ≈ 8 Mio` (empreinte disque bornée de la file, négligeable devant les
    500 Mo résiduels) ;
  - invariant **« aucune image lourde sur l'appareil »** (`recordCarriesNoHeavyMedia` : aucun
    `data:` URI inline ; uniquement des pointeurs off-device).
- **Pas d'API récente indisponible** sur l'API min (§1) : toute dépendance plateforme doit être
  disponible sur le plancher API.
- **Dégradation propre sous pression disque.** Un échec d'écriture locale (« disque plein ») doit
  **alerter fort** et ne **jamais** perdre silencieusement une consultation ni écrire de plaintext
  (invariant `OfflineQueueUnavailable`, [`session_end_service.dart`](../../app-patient/lib/src/doctor/session_end_service.dart)).

---

## 4. Décision d'opposabilité (doc vs ADR)

Le profil est figé **au niveau documentaire** sous `docs/ux/` — cohérent avec la **norme UX
opposable** (#28) qui vit également sous `docs/ux/` plutôt que dans un ADR. Les décisions
d'architecture socle (Flutter #ADR-0001, PWA #ADR-0002, crypto-core #ADR-0003) restent les ADR
pertinents ; ce profil **paramètre** leur validation terrain, il ne tranche pas une nouvelle
architecture. Un ADR dédié pourra être ouvert si le choix du modèle exact (Risk #2) doit être
gravé plus formellement.

---

## 5. Traçabilité

- **PRD §2** (personas Awa / Dr. Koné) → ce profil (RAM, stockage, micro-coupures).
- **PRD §1** (KPI fiabilité « sans perte de données ») → garde-fous robustesse (pression disque,
  atomicité coupure) définis par le protocole [`low-end-validation-protocol.md`](./low-end-validation-protocol.md).
- **PRD §4** (stockage bas de gamme, images déportées #23) → `StorageBudget` + invariant sans image
  lourde.
- **#27** (perf < 3 s / profil `3G-STABLE`) et **#28** (UX < 5 min / appareil de référence) →
  rejoués sur appareil contraint par le protocole.
- **#31** (pilote Abidjan) → réutilise ce profil (mutualisation possible avec #28).
- Le **critère d'acceptation** (« parcours patient et médecin validés sur appareil de référence
  bas de gamme ») reste une **preuve terrain humaine** : ce document livre le **profil**, pas les
  **mesures**. Voir le gabarit de compte-rendu « à produire » du protocole (§8).
