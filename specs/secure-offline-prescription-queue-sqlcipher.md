# File d'attente hors-ligne sécurisée (SQLCipher) (#21)

> **Issue :** #21 — File d'attente hors-ligne sécurisée (SQLCipher) · `feature` `security`
> **Épic :** E2 — Résilience médecin · **Effort :** L · **Priorité :** Must · **Implémente :** US-2.4
> **Dépend de :** #10 (module AES-256-GCM, mergé PR #63), #19 (fin de session : PUT blob + wipe RAM, mergé PR #75).
> **Bloque / précède :** #22 (synchronisation au retour du réseau — *drain* de cette file).
> **Jalon :** M3 — Résilience hors-ligne & médias.
> **Décision d'architecture cadrante :** [ADR 0006 — Offline storage & key management](../docs/adr/0006-offline-storage-and-keys.md).

## Problem Statement

La boucle de consultation (M2, #16→#20) suppose un réseau disponible en fin de session. Aujourd'hui,
`SessionEndService.terminate` (`app-patient/lib/src/doctor/session_end_service.dart`, #19) fait :

1. `PUT /blob/{uuid}` de `session.pendingBlob` (le dossier ré-chiffré pendant la consultation) ;
2. `session.wipe()` dans un bloc `finally` — **toujours**, même si le PUT échoue.

Conséquence directe : si le médecin valide une consultation **hors réseau** (micro-coupure de courant,
zone Edge/3G instable — le quotidien du Dr. Koné décrit dans le PRD §2), le PUT lève `BackendUnavailable`,
puis `finally` **zéroïse `pendingBlob`**. **L'ordonnance chiffrée est perdue.** C'est précisément ce que
US-2.4 et le KPI « 100 % des consultations sans perte de données, même en cas de coupure réseau totale »
(PRD §1) interdisent.

Le code anticipe déjà le correctif : `medical_record_store.dart` et `main.dart` portent des TODO
explicites renvoyant à « the offline-sync queue (#21) », et `pubspec.yaml` déclare déjà `drift` +
`sqlcipher_flutter_libs`. **#21 doit livrer cette file locale chiffrée** : en cas d'échec d'envoi, le
blob chiffré (déjà AES-256-GCM) est **persisté dans une file SQLCipher** au lieu d'être perdu, et la
consultation est validée hors-ligne. Le *drain* effectif au retour du réseau est l'objet de **#22** ;
#21 s'arrête à *enqueue + persistance sûre + exposition de la file pour #22*.

### Critères d'acceptation (issue #21)

- Consultation **validée hors-ligne** (l'échec d'envoi ne fait pas perdre l'ordonnance).
- Donnée **stockée chiffrée localement ; rien en clair**.

## Goals

- **Aucune perte de données hors-ligne :** quand l'envoi de fin de session échoue (`BackendUnavailable`,
  ou pas de réseau), le blob chiffré + l'UUID anonyme sont **persistés de façon durable** dans une file
  locale, et la consultation est considérée « validée (en attente de synchronisation) » côté médecin.
- **Persistance chiffrée, jamais de clair :** la file est une base **SQLCipher** (chiffrement AES-256
  de toute la base, ADR 0006), dont la clé est scellée par le Keystore matériel ; et le contenu stocké
  est lui-même **déjà un ciphertext AES-256-GCM** (double rideau : même une base SQLCipher déverrouillée
  ne révèle que du ciphertext opaque).
- **Invariant du wipe RAM préservé :** la clé de session éphémère (120 s) reste **wipée** en fin de
  session, exactement comme aujourd'hui. La file ne stocke **que** le ciphertext opaque + l'UUID — jamais
  la clé de session, jamais le dossier en clair.
- **Durabilité face aux coupures de courant :** un enqueue est atomique (transaction) et survit à un kill
  brutal du process / coupure d'alimentation (WAL ou équivalent ; pas d'entrée à moitié écrite).
- **Surface de file consommable par #22 :** une interface claire `enqueue / peek(list) / markSynced /
  remove` (sans logique réseau) que la synchronisation #22 viendra *drainer*, avec un schéma de
  ligne suffisant pour gérer l'ordre, les renvois et la résolution de conflits côté #22.
- **Idempotence à l'enqueue :** ré-enfiler la même fin de session (re-tap « Terminer », relance d'app)
  ne crée pas de doublon non maîtrisé (clé d'unicité documentée — voir « Data Model »).
- **Observabilité sans fuite :** journaux limités à UUID + état + compteur de tentatives ; **jamais** de
  ciphertext, de clé, ni de PII.

## Non-Goals

- **Pas la synchronisation réseau (#22).** #21 ne contient **aucune** logique de détection de retour
  réseau, de retry programmé, ni de résolution de conflit serveur. Il expose la file ; #22 la draine.
  (À garder strictement séparé pour ne pas empiéter sur #22.)
- **Pas de nouvelle cryptographie.** Le blob est déjà chiffré (clé de session, #16/#18) ; #21 ne
  (re)chiffre rien au niveau applicatif. Le seul « chiffrement » ajouté est le chiffrement **de base**
  par SQLCipher (config de la lib), pas une primitive maison.
- **Pas de ré-import master-key côté patient.** Le blob en attente est chiffré avec la **clé de session**,
  pas la clé maître. La question « comment le patient ré-intègre l'update post-consultation dans sa
  sauvegarde master-key (#14) » reste **non couverte** par une issue (déjà signalée en #20) — #21 ne doit
  pas prétendre la résoudre.
- **Pas le portage de la boucle médecin vers `app-medecin/` (PWA).** Voir « Relevant Repository Context » :
  la logique médecin vit dans `app-patient/` (Flutter). La variante **IndexedDB** du PWA (ADR 0006) est
  documentée mais **hors périmètre de livraison** ici, tant que la boucle n'est pas portée.
- **Pas les images lourdes (#23)** ni l'optimisation réseau dégradé (#24).
- **Pas de file pour la sauvegarde patient (#14).** Le TODO #21 dans `medical_record_store.dart` suggère
  une réutilisation possible, mais le critère d'acceptation de #21 cible la **consultation médecin**
  (US-2.4). Réutiliser le même composant de file pour le patient est une **option** à signaler, pas un
  livrable obligatoire (voir « Open Questions »).

## Relevant Repository Context

### Où vit la logique « médecin » (observation d'architecture)

Bien que l'Épic 2 vise « l'interface professionnel de santé » et qu'un projet `app-medecin/` (PWA
Preact/TS, ADR 0002) existe en squelette, **toute la boucle de consultation #16→#20 a été implémentée en
Dart dans `app-patient/lib/src/doctor/**`**. Par cohérence avec #17–#20 (et avec ADR 0006 qui fixe la file
SQLCipher côté Flutter/Android), **#21 doit être livré dans `app-patient/`** et exécutable via
`flutter test`. C'est une observation à conserver, pas l'objet de #21 de la corriger.

### Composants existants à brancher

| Élément | Fichier | Rôle pour #21 |
| --- | --- | --- |
| Fin de session (#19) | `app-patient/lib/src/doctor/session_end_service.dart` | `terminate(session)` : PUT puis `wipe()` en `finally`. **Point d'insertion** : enfiler au lieu de perdre `pendingBlob` quand le PUT échoue. |
| Porteur de session RAM (#18) | `app-patient/lib/src/doctor/consultation_session.dart` | `pendingBlob` (`nonce(12)\|\|ct\|\|tag(16)`), `payload.uuid`, `wipe()`. La file copie les octets **avant** `wipe()`. |
| Transport ZK (#14) | `app-patient/lib/src/cloud/backend_client.dart` | `BackendClient.put/get` ; `BackendUnavailable` (échec réseau / non-2xx), `BlobNotFound`. C'est l'exception qui déclenche l'enqueue. |
| Persistance scellée existante (#11) | `app-patient/lib/src/secure/sealed_blob_store.dart` | Modèle d'**interface + impl. fichier + impl. in-memory pour tests** à imiter pour la file (testabilité host-only sans `path_provider`/natif). |
| Clé maître / Keystore (#11) | `app-patient/lib/src/secure/{master_key_service,keystore_channel}.dart` | Le shim Keystore qui scellera la **clé de base SQLCipher** (KEK matérielle, ADR 0006). `KeystoreUnavailable` → échec **bruyant**. |
| Bornes 500 Kio (#15) | `app-patient/lib/src/record/record_size_guard.dart` | Déjà appliquées **avant** chiffrement (#18) ; le blob enfilé respecte donc le budget. #21 n'y touche pas. |
| Dépendances déjà déclarées | `app-patient/pubspec.yaml` | `drift: ^2.21.0`, `sqlcipher_flutter_libs: ^0.6.4`, `drift_dev`, `build_runner`, `path_provider`. **NB** documenté dans le pubspec : ne PAS ajouter `sqlite3_flutter_libs` en plus (duplication de classe au dex merge). |

### Conventions établies (à réutiliser)

- Code sous `app-patient/lib/src/<domaine>/`, tests miroir sous `app-patient/test/<domaine>/`.
- En-tête de commentaire de fichier listant le rôle + les invariants de sécurité (cf. `session_end_service.dart`).
- **Interface + impl. de prod + impl. in-memory pour tests** (cf. `SealedBlobStore` / `InMemorySealedBlobStore`),
  pour rester testable en host-only quand le natif (`path_provider`, SQLCipher) n'est pas disponible.
- Injection de dépendances par constructeur (services prennent leurs collaborateurs en paramètre).
- `dart format` + `flutter analyze` **stricts** (Flutter 3.41.5 traite les `info` comme bloquants ;
  voir mémoire `project-backlog-state` : `prefer_const_constructors`, indentation old-style, imports minimaux).
- Le harnais e2e partagé (#20) `app-patient/test/support/consultation_loop_harness.dart` fournit
  `FakeCryptoCore`, `FakeBlobBackend` (avec `failPut: true` → 503) et `referenceRecord()` — **directement
  réutilisables** pour tester le chemin hors-ligne.

### Décisions déjà prises (ADR 0006) vs. encore ouvertes (#1)

**Tranché par ADR 0006 :**
- **Patient/Android (Flutter) :** file = **SQLCipher** (AES-256 full-DB) via `drift` +
  `sqlcipher_flutter_libs` ; clé de base scellée par le Keystore (jamais en clair).
- **PWA médecin (web) :** SQLCipher impossible en navigateur → file = **ciphertext AES-256-GCM dans
  IndexedDB** (déviation **explicitement loguée** par rapport au mot « SQLCipher » de #21 ; frontière de
  confiance équivalente-ou-supérieure). → **variante web**, hors périmètre de livraison #21 (cf. Non-Goals).

**Encore ouvert (à confirmer, #1 non clos) :**
- **`drift` vs `sqflite_sqlcipher`** : ADR 0006 dit « `drift` + `sqlcipher_flutter_libs` (ou
  `sqflite_sqlcipher`) ». Le `pubspec.yaml` penche **drift** (+ `drift_dev`/`build_runner`). **Recommandation :
  drift**, mais c'est une décision toolchain à entériner.
- **Exécution en CI :** le natif SQLCipher n'est **pas** disponible en test host-only (comme
  `path_provider`/FRB). La **logique de file** doit donc être testée via une **impl. in-memory**, et la
  liaison drift/SQLCipher réelle validée en test d'intégration *device-backed* (suivi, dépend de #1 +
  émulateur en CI). Voir « Testing Plan ».

## Proposed Implementation

### Vue d'ensemble

Introduire une **file d'attente d'envois** (« pending-upload queue ») dans `app-patient/lib/src/doctor/`,
derrière une **interface abstraite** (`OfflineUploadQueue`) avec deux implémentations : une **drift +
SQLCipher** pour la prod (Android), une **in-memory** pour les tests host-only. Brancher
`SessionEndService` pour **enfiler au lieu de perdre** `pendingBlob` quand le PUT échoue.

### 1. Interface de file (`OfflineUploadQueue`)

`app-patient/lib/src/doctor/offline_upload_queue.dart` — pure logique, **aucune** dépendance réseau :

```dart
/// Un envoi chiffré en attente : opaque ciphertext (déjà AES-256-GCM) + UUID.
class PendingUpload {
  final String id;            // identifiant local de file (UUID v4 généré localement)
  final String blobUuid;      // UUID anonyme du dossier (clé /blob/{uuid})
  final Uint8List ciphertext; // nonce(12)||ct||tag(16) — JAMAIS de clair
  final int attempts;         // tentatives de sync (incrémenté par #22)
  final String enqueuedAtIso; // horodatage d'enfilement (ordre FIFO / debug)
}

abstract class OfflineUploadQueue {
  /// Persiste un envoi en attente. Atomique et durable (survit à un crash).
  /// Idempotent sur (blobUuid, ciphertext) — voir clé d'unicité (Data Model).
  Future<void> enqueue(String blobUuid, Uint8List ciphertext);

  /// Liste les envois en attente (FIFO), pour #22. Ne supprime rien.
  Future<List<PendingUpload>> pending();

  /// Supprime un envoi (appelé par #22 après un PUT réussi).
  Future<void> remove(String id);

  /// Nombre d'envois en attente (badge UI « N en attente de synchro »).
  Future<int> count();
}
```

> **Frontière #21/#22 :** #21 livre `enqueue` + le stockage + `pending/remove/count`. #22 ajoutera la
> détection réseau, le retry et l'incrément de `attempts` / la résolution de conflit. **Ne pas** implémenter
> de boucle de retry dans #21.

### 2. Implémentation prod : drift + SQLCipher

`app-patient/lib/src/doctor/sqlcipher_upload_queue.dart` (+ table drift générée) :

- Une base **SQLCipher** dédiée (ou une table dans la base patient existante quand #14 l'introduit ;
  **décision à confirmer** — voir Open Questions). Table `pending_uploads(id TEXT PK, blob_uuid TEXT,
  ciphertext BLOB, attempts INTEGER DEFAULT 0, enqueued_at TEXT, UNIQUE(blob_uuid, ciphertext_hash))`.
- **Clé de base SQLCipher** : 32 octets aléatoires (CSPRNG), **scellés par le Keystore** via le shim
  existant (`keystore_channel.dart`) — modèle d'enveloppe identique à la master-key (#11). La clé claire
  n'existe qu'en RAM le temps d'ouvrir la base (`PRAGMA key`), jamais persistée en clair. Absence de
  Keystore → échec **bruyant** (`KeystoreUnavailable`), **pas** de repli logiciel (ADR 0006).
- `enqueue` exécute un **INSERT transactionnel** (WAL activé) : durable face à un kill brutal.
- Aucune colonne en clair sensible : `ciphertext` est déjà opaque ; même sans SQLCipher, rien de lisible.
  SQLCipher est la défense en profondeur exigée par ADR 0006.
- **`ciphertext_hash`** (ex. SHA-256 des octets, calculé via le crypto-core/Rust si exposé, sinon une
  fonction de hachage non cryptographique suffit pour la déduplication) sert de clé d'idempotence sans
  stocker deux fois de gros blobs — **à confirmer** (un simple `UNIQUE(blob_uuid)` « dernier-gagne » est
  une alternative plus simple ; voir Open Questions).

### 3. Implémentation test : `InMemoryUploadQueue`

`Map`/`List` en mémoire respectant le même contrat (FIFO, idempotence, `count`). Permet de tester la
logique d'enfilement et le branchement `SessionEndService` **sans** natif, en host-only `flutter test`.

### 4. Branchement de `SessionEndService` (le cœur fonctionnel de #21)

Modifier `terminate(session)` pour **enfiler au lieu de perdre** quand le PUT échoue, tout en
**préservant le wipe** :

```dart
Future<SessionEndOutcome> terminate(ConsultationSession session) async {
  final blob = session.pendingBlob;
  try {
    if (blob != null) {
      await _client.put(session.payload.uuid, blob);
      return SessionEndOutcome.uploaded;
    }
    return SessionEndOutcome.nothingToUpload;
  } on BackendUnavailable {
    // Hors-ligne : NE PAS perdre l'ordonnance — l'enfiler chiffrée.
    if (blob != null) {
      await _queue.enqueue(session.payload.uuid, blob); // copie défensive des octets
    }
    return SessionEndOutcome.queued; // consultation validée hors-ligne
  } finally {
    session.wipe(); // invariant inchangé : clé de session + pendingBlob zéroïsés
  }
}
```

Points de vigilance :
- **Ordre critique :** `enqueue` lit/**copie** les octets du blob **avant** que `finally` n'appelle
  `wipe()` (qui zéroïse `pendingBlob` en place). L'`enqueue` doit faire une **copie défensive**
  (`Uint8List.fromList(blob)`) — ne pas stocker une vue qui sera ensuite remise à zéro.
- **Type de retour :** remplacer le `Future<void>` actuel par un `SessionEndOutcome`
  (`uploaded` / `queued` / `nothingToUpload`) pour que l'UI affiche « consultation enregistrée, en attente
  de synchronisation » au lieu d'une erreur. **Changement de signature** (voir API Changes) — adapter les
  appelants (#19 `RecordViewScreen`, tests #19/#20).
- **Échec d'enqueue** (ex. `KeystoreUnavailable`, disque plein) : c'est le **seul** cas où la fin de
  session peut encore perdre la donnée. Le propager (exception dédiée `OfflineQueueUnavailable`) **après**
  le `wipe`, et que l'UI alerte fortement le médecin (« échec d'enregistrement local — ne pas fermer »).
  Décider si l'on tente alors de **ne pas wiper** pour laisser une dernière chance — **à confirmer**
  (par défaut : on wipe toujours, conformément à l'invariant de sécurité ; la perte sur double-échec
  Keystore est un cas extrême tracé).

### 5. Câblage / DI

- Construire la `SqlCipherUploadQueue` au démarrage (`main.dart`), clé de base scellée via Keystore, et
  l'injecter dans `SessionEndService`. En tests, injecter `InMemoryUploadQueue`.
- Exposer un compteur `count()` pour un futur badge UI « N consultations en attente » (l'UI complète
  relève plutôt de #22 / #28 ; #21 peut se limiter au service + un indicateur minimal).

## Affected Files / Packages / Modules

À **créer** :
- `app-patient/lib/src/doctor/offline_upload_queue.dart` — interface `OfflineUploadQueue`, modèle
  `PendingUpload`, `SessionEndOutcome`, exceptions (`OfflineQueueUnavailable`), `InMemoryUploadQueue`.
- `app-patient/lib/src/doctor/sqlcipher_upload_queue.dart` — impl. drift + SQLCipher (table générée,
  ouverture avec `PRAGMA key`, clé scellée Keystore, WAL/transaction).
- (si drift) fichier de schéma/`.drift` + sortie `build_runner` (`*.g.dart`).
- `app-patient/test/doctor/offline_upload_queue_test.dart` — tests de la logique de file (in-memory).
- `app-patient/test/doctor/session_end_service_offline_test.dart` — chemin hors-ligne de `terminate`
  (ou étendre `session_end_service_test.dart`).

À **modifier** :
- `app-patient/lib/src/doctor/session_end_service.dart` — injecter la file ; enfiler sur
  `BackendUnavailable` ; retourner `SessionEndOutcome` ; préserver le `wipe` en `finally`.
- `app-patient/lib/main.dart` — construire/injecter la `SqlCipherUploadQueue` (lever le TODO #21) ;
  passer la file au `SessionEndService`.
- `app-patient/test/doctor/session_end_service_test.dart` — adapter à la nouvelle signature/au type de
  retour ; ajouter le cas « PUT 5xx → enfilé + wipe ».
- Éventuellement `app-patient/test/e2e/consultation_loop_e2e_test.dart` + harnais `consultation_loop_harness.dart` —
  variante hors-ligne : `FakeBlobBackend(failPut: true)` → la fin de session enfile, RAM wipée, file = 1.
- `app-patient/lib/src/record/medical_record_store.dart` — **lecture seule** ici ; ne lever le TODO #21
  du write patient que si l'on décide de réutiliser la file pour #14 (Open Question — par défaut **non**).

À **lire** (sans modifier) :
- `app-patient/lib/src/doctor/{consultation_session,consultation_edit_service}.dart`,
  `app-patient/lib/src/cloud/backend_client.dart`,
  `app-patient/lib/src/secure/{sealed_blob_store,keystore_channel,master_key_service}.dart`,
  `docs/adr/0006-offline-storage-and-keys.md`, `app-patient/pubspec.yaml`.

Hors `app-patient/` : `app-medecin/` n'est **pas** touché (variante IndexedDB hors périmètre). Pas de
modification backend (#9) : le serveur reçoit le même `PUT /blob/{uuid}` lors du drain #22.

## API / Interface Changes

- **Interne (paquet `app_patient`) :**
  - **Nouvelle** API publique de paquet : `OfflineUploadQueue` (`enqueue/pending/remove/count`),
    `PendingUpload`, `SessionEndOutcome`, `OfflineQueueUnavailable` — **à documenter** (commentaires
    de doc Dart + entrée dans la doc paquet, cf. « Documentation Updates »).
  - **Changement de signature** : `SessionEndService.terminate` passe de `Future<void>` à
    `Future<SessionEndOutcome>` et prend désormais un `OfflineUploadQueue` au constructeur. Appelants à
    adapter (UI + tests).
- **Réseau / endpoints :** **none.** Aucun nouvel endpoint ; le drain #22 réutilisera `PUT /blob/{uuid}`.
- **QR / jeton d'accès :** **none.** La file ne stocke ni ne manipule la clé de session ni le QR.
- **CLI :** **none.**

## Data Model / Protocol Changes

- **Nouveau schéma local** (table SQLCipher `pending_uploads`) : `id` (PK, UUID local), `blob_uuid`,
  `ciphertext` (BLOB opaque `nonce\|\|ct\|\|tag`), `attempts` (INTEGER, géré par #22), `enqueued_at` (ISO-8601),
  + contrainte d'unicité pour l'idempotence (`UNIQUE(blob_uuid, ciphertext_hash)` **ou** `UNIQUE(blob_uuid)`
  « dernier-gagne » — **à trancher**, voir Open Questions). Schéma **versionné** (migrations drift) car
  #22 y ajoutera vraisemblablement des colonnes (`last_attempt_at`, `last_error`).
- **Format de blob :** inchangé (`nonce(12) \|\| ciphertext \|\| tag(16)`, #10/#16). #21 ne (dé)chiffre pas
  le blob applicatif ; il le stocke tel quel.
- **Chiffrement de la base :** SQLCipher (AES-256) sur **toute** la base ; clé de base scellée Keystore
  (enveloppe, ADR 0006). Ce n'est pas un changement de protocole réseau, mais un nouveau format de
  persistance **chiffré** sur l'appareil.
- **Sérialisation :** aucune sur le fil ; la sérialisation locale est gérée par drift.

## Security & Compliance Considerations

- **Chiffrement client-side AES-256-GCM :** le blob enfilé est **déjà** chiffré (clé de session, #16/#18) ;
  #21 n'affaiblit ni ne réinvente la crypto. Couche **supplémentaire** SQLCipher (AES-256 full-DB) →
  défense en profondeur : *rien en clair sur le disque*, même base déverrouillée → seulement du ciphertext.
- **Zero-knowledge serveur :** inchangé. La file n'ajoute aucun champ nominatif ; elle indexe par **UUID
  anonyme**. Au drain (#22), le serveur reçoit le même octet opaque qu'un PUT normal — il ne peut toujours
  rien déchiffrer.
- **Gestion des clés :** la **clé de base SQLCipher** est scellée par le Keystore matériel (StrongBox/TEE,
  enveloppe comme #11), jamais en clair sur disque, présente en RAM uniquement le temps d'ouvrir la base.
  **Pas de repli logiciel** : Keystore absent → `KeystoreUnavailable` (échec bruyant), conformément à ADR 0006.
- **Accès éphémère QR (~120 s) & wipe RAM :** **invariant préservé** — `session.wipe()` reste appelé en
  `finally`, la **clé de session n'est jamais enfilée** (seul le ciphertext l'est). La file est durable ;
  la clé, non. La donnée enfilée ne peut être re-chiffrée/lue qu'avec la clé de session que **seul le QR**
  portait — point d'attention transverse (cf. Open Questions sur le ré-import patient), mais sans impact
  sur la sécurité de la persistance #21.
- **Résidence des données (ARTCI / loi n°2013-450) :** la file est **locale à l'appareil** (pas un service
  hébergé) ; au drain, la donnée part vers le backend souverain (#8/#9) en Côte d'Ivoire. Aucune donnée ne
  transite par un tiers étranger. À tracer dans la matrice de conformité (contrôle « pas de perte / pas de
  fuite hors-ligne »).
- **Budget ≤ 500 Kio :** garanti **en amont** par `RecordSizeGuard` (#15/#18) ; le blob enfilé respecte
  déjà le budget. La file devrait néanmoins **borner sa taille totale** (nb d'items / octets cumulés) pour
  ne pas saturer un Infinix 32 Go (cf. #29) — politique à définir (rejet bruyant vs purge des plus vieux ;
  **par défaut : borne haute + alerte**, jamais de purge silencieuse de données non synchronisées).
- **Images lourdes :** jamais sur l'appareil (PRD §4) ; le blob ne contient que des `imageUrls` éphémères.
  #21 n'enfile que ce blob texte chiffré — aucune image lourde dans la file.
- **Logs / redaction :** **ne jamais** logger le `ciphertext`, la clé de base, la clé de session, ni de PII.
  Journaux limités à `blob_uuid` + état (`queued`/`synced`) + `attempts`. Pas de `print` de blob dans les
  tests/fakes (cf. convention #20).

## Testing Plan

- **Unitaire — logique de file (`InMemoryUploadQueue`)** : `enqueue` ajoute (FIFO) ; `pending` liste sans
  supprimer ; `remove` supprime ; `count` exact ; **idempotence** (ré-enqueue identique → pas de doublon
  selon la clé d'unicité retenue) ; **copie défensive** (muter/zéroïser le `Uint8List` source après
  `enqueue` ne corrompt pas l'entrée stockée).
- **Unitaire — `SessionEndService` hors-ligne** :
  - PUT **réussi** → `uploaded`, **rien** enfilé, RAM wipée (non-régression #19).
  - PUT **échec** (`BackendUnavailable` / `FakeBlobBackend(failPut: true)`) → `queued`, **1** item en file,
    `pendingBlob` & clé de session **zéroïsés** (invariant wipe), item = ciphertext **opaque** (≠ clair).
  - `pendingBlob == null` (aucune édition) → `nothingToUpload`, rien enfilé.
  - **double-échec** (PUT échoue **et** `enqueue` lève) → `OfflineQueueUnavailable` propagé, comportement de
    wipe conforme à la décision retenue (Open Questions).
- **Intégration (e2e à fakes, #20)** : variante hors-ligne du `consultation_loop_e2e_test` :
  patient→médecin→`terminate` avec backend en panne → consultation **validée hors-ligne**, file=1, RAM
  wipée, **aucun clair** dans `FakeBlobBackend` ni dans la file.
- **Résilience / durabilité** *(device-backed, suivi — dépend de #1 + émulateur, sinon documenté comme
  non exécuté)* : crash/kill du process entre `enqueue` et la fin → l'item est **toujours** présent au
  redémarrage (durabilité WAL/transaction) ; **aucun** fichier en clair créé (inspection disque) ; la base
  SQLCipher est **illisible** sans la clé Keystore (ouverture sans `PRAGMA key` correct → échec).
- **Crypto-vectors :** **none propre à #21** (pas de nouvelle primitive) ; la crypto du blob reste couverte
  par les vecteurs NIST de `crypto-core` (#10).
- **Lint/format :** `dart format --output=none --set-exit-if-changed .` + `flutter analyze` propres
  (Flutter 3.41.5 : `info` bloquants ; pièges du mémoire `project-backlog-state`). Régénérer le code drift
  (`dart run build_runner build`) si l'on retient drift, et committer les `*.g.dart`.
- **Commande :** `cd app-patient && flutter test`. Noter que `just test` *skippe* `flutter test` si le SDK
  est absent ; le natif SQLCipher n'étant pas dispo en host-only, **seule** la logique in-memory s'exécute
  partout — la liaison SQLCipher réelle relève du suivi device-backed.

## Documentation Updates

- **BACKLOG.md :** ajouter une ligne *Avancement* sous **#21** (comme #18/#20) une fois livré (file
  SQLCipher + enqueue-on-failure ; `terminate` retourne `SessionEndOutcome` ; drain = #22).
- **ADR 0006 :** aucune nouvelle décision — mais **mettre à jour le statut/notes** pour pointer vers
  l'implémentation #21 (drift retenu, clé scellée Keystore) et **re-confirmer la déviation web** (IndexedDB)
  comme non encore livrée. Si le choix `drift` (vs `sqflite_sqlcipher`) est entériné, le noter.
- **`app-patient/README.md` :** documenter la nouvelle API publique (`OfflineUploadQueue`, `PendingUpload`,
  `SessionEndOutcome`) et le comportement « consultation validée hors-ligne » (lien vers #22 pour la synchro).
- **Matrice de conformité (`docs/compliance/`) :** tracer le contrôle « pas de perte de données hors-ligne »
  (US-2.4 / KPI 100 %) et « rien en clair sur l'appareil » vers cette implémentation (preuve).
- **Mémoire `project-backlog-state.md` :** ajouter #21 au tableau de livraison une fois mergé.
- **PRD :** pas de changement d'exigence.

## Risks and Open Questions

1. **Base dédiée vs base patient partagée.** #14 introduira (TODO) une base SQLCipher patient. Faut-il une
   base dédiée à la file, ou une table dans la base patient ? **Recommandation :** commencer par une base/
   table propre à la file pour découpler #21 de #14, quitte à fusionner plus tard. *À confirmer.*
2. **Clé d'idempotence.** `UNIQUE(blob_uuid)` « dernier-gagne » (simple, mais écrase une version non encore
   synchronisée) vs `UNIQUE(blob_uuid, ciphertext_hash)` (garde chaque version distincte, mais peut accumuler).
   Lié à la **stratégie de conflit de #22**. **Recommandation :** conserver chaque version distincte
   (`+ hash`) pour ne rien perdre, et laisser #22 résoudre l'ordre/les conflits. *À confirmer avec #22.*
3. **Re-chiffrement clé de session vs master-key (transverse, déjà soulevé en #20).** Le blob enfilé est
   chiffré avec la **clé de session** éphémère ; au drain, il devient le blob serveur courant. Le mécanisme
   par lequel le **patient** ré-intègre cet update dans sa sauvegarde **master-key** (#14) n'est couvert par
   **aucune issue**. #21 ne le résout pas et ne doit pas le simuler. **Recommander une issue de suivi**
   « sync patient post-consultation ».
4. **Comportement sur double-échec (PUT + enqueue).** Wipe-toujours (sûr, mais perte sur cas extrême
   Keystore/disque) vs tentative de conservation RAM. **Recommandation :** wipe-toujours + alerte UI forte
   + exception typée ; le double-échec est rare et tracé. *À confirmer (sécurité vs résilience).*
5. **Borne de taille de la file** sur appareils saturés (#29). Politique de rejet/alerte à définir ;
   **jamais** de purge silencieuse de données non synchronisées.
6. **Testabilité du natif en CI.** SQLCipher/drift non exécutables en host-only ; la couverture réelle de
   la liaison SQLCipher dépend d'un e2e *device-backed* (suivi, #1 + émulateur). Risque de fausse confiance
   si l'on s'arrête à l'in-memory — **documenter explicitement** ce qui n'est pas exécuté en CI.
7. **Stack non figée (#1).** `drift` vs `sqflite_sqlcipher`, et place de la logique médecin
   (`app-patient` vs futur `app-medecin`). Documenté comme dépendance, pas blocage : suivre #1.
8. **Variante PWA (IndexedDB).** Quand/si la boucle est portée vers `app-medecin/`, la file devra exister
   en version web (ciphertext-in-IndexedDB, ADR 0006). Hors périmètre #21 mais à garder en vue.

## Implementation Checklist

1. Lire ADR 0006, `session_end_service.dart`, `consultation_session.dart`, `backend_client.dart`,
   `sealed_blob_store.dart`, `keystore_channel.dart`, `pubspec.yaml` pour câbler exactement les signatures
   et le modèle d'enveloppe Keystore.
2. Créer `offline_upload_queue.dart` : `PendingUpload`, `SessionEndOutcome`, `OfflineQueueUnavailable`,
   l'interface `OfflineUploadQueue`, et `InMemoryUploadQueue` (FIFO + idempotence + **copie défensive** des
   octets).
3. Écrire `offline_upload_queue_test.dart` (in-memory) : enqueue/pending/remove/count, idempotence, copie
   défensive (muter la source après enqueue ne corrompt pas l'entrée).
4. Modifier `SessionEndService` : injecter `OfflineUploadQueue` ; sur `BackendUnavailable`, `enqueue(uuid,
   blob)` (copie défensive) **avant** le `wipe` du `finally` ; retourner `SessionEndOutcome`
   (`uploaded`/`queued`/`nothingToUpload`) ; gérer le double-échec (`OfflineQueueUnavailable`).
5. Adapter `session_end_service_test.dart` (nouvelle signature) + ajouter le cas hors-ligne
   (`FakeBlobBackend(failPut: true)` → `queued`, file=1, RAM wipée, ciphertext opaque ≠ clair).
6. Implémenter `SqlCipherUploadQueue` (drift) : table `pending_uploads` versionnée, ouverture avec
   `PRAGMA key` depuis la **clé de base scellée Keystore** (enveloppe comme #11, échec bruyant si
   Keystore absent), WAL/transaction pour la durabilité ; **ne pas** ajouter `sqlite3_flutter_libs`
   (cf. NB du pubspec). Régénérer le code (`dart run build_runner build`) et committer les `*.g.dart`.
7. Câbler dans `main.dart` : construire la `SqlCipherUploadQueue`, l'injecter dans `SessionEndService`
   (lever le TODO #21).
8. Ajouter la variante hors-ligne au e2e (#20) : consultation validée hors-ligne, file=1, RAM wipée,
   aucun clair côté serveur ni en file.
9. `dart format --output=none --set-exit-if-changed .` + `flutter analyze` propres (traiter les `info`
   comme bloquants ; pièges du mémoire `project-backlog-state`).
10. Mettre à jour la doc : *Avancement* #21 dans `BACKLOG.md`, note de statut dans ADR 0006, API publique
    dans `app-patient/README.md`, contrôle de conformité tracé, entrée #21 dans `project-backlog-state.md`.
11. (Suivi, hors #21) ouvrir : issue « sync patient post-consultation » (ré-import master-key) ; tâche
    « e2e device-backed file SQLCipher » (durabilité + illisibilité sans clé) ; variante PWA IndexedDB
    quand la boucle sera portée. Et **ne pas** implémenter la synchro réseau ici — c'est **#22**.
```
