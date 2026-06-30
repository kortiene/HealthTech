# Synchronisation au retour du réseau (#22)

> **Issue :** #22 — Synchronisation au retour du réseau · `feature` `tech-debt`
> **Épic :** E2 — Résilience médecin · **Effort :** M · **Priorité :** Must · **Implémente :** US-2.4
> **Dépend de :** #21 (file d'attente hors-ligne sécurisée SQLCipher, mergé PR #77), qui dépend lui-même de #10 (AES-256-GCM, PR #63) et #19 (fin de session : PUT blob + wipe RAM, PR #75).
> **Jalon :** M3 — Résilience hors-ligne & médias.
> **Décision d'architecture cadrante :** [ADR 0006 — Offline storage & key management](../docs/adr/0006-offline-storage-and-keys.md) (à étendre par un ADR de stratégie de conflits — voir « Documentation Updates »).

## Problem Statement

#21 a livré la moitié résiliente de US-2.4 : quand le médecin valide une consultation **hors réseau**,
`SessionEndService.terminate` n'écrase plus l'ordonnance dans le `finally` du wipe — il **enfile** le blob
chiffré (`nonce(12)||ct||tag(16)`) + l'UUID anonyme dans une file **SQLCipher** durable (`OfflineUploadQueue`),
et retourne `SessionEndOutcome.queued`. La consultation est « validée, en attente de synchronisation ».

Mais **rien ne draine cette file**. Les éléments enfilés restent indéfiniment sur l'appareil : ils ne
remontent jamais vers le backend zero-knowledge (#9), donc le patient ne récupère jamais l'ordonnance sur
son téléphone, et le KPI PRD §1 — « 100 % des consultations sans perte de données, même en cas de coupure
réseau totale » — n'est tenu **qu'à moitié** (pas de perte locale, mais pas de remontée). Le code et le spec
#21 délimitent explicitement cette frontière : « le *drain* effectif au retour du réseau est l'objet de #22 »,
et le commentaire d'en-tête de `offline_upload_queue.dart` interdit d'ajouter de la logique de retry à #21.

**#22 doit livrer ce drain** : dès le retour du réseau, parcourir la file, ré-émettre chaque `PUT /blob/{uuid}`
vers le backend souverain, retirer les éléments confirmés, et gérer proprement **renvois** (retry/backoff) et
**conflits** — sans jamais perdre ni dupliquer de données, et sans affaiblir le modèle zero-knowledge.

### Critères d'acceptation (issue #22)

- **Aucune perte ni doublon** après reconnexion.
- **Stratégie de résolution de conflits documentée.**

### Contrainte structurante (à intégrer dès la conception)

Le blob enfilé est chiffré avec la **clé de session éphémère** (~120 s, portée par le QR, #16), qui a été
**wipée** en fin de session (#19). L'appareil du médecin **ne peut donc plus déchiffrer** ce qu'il a enfilé :
au drain, #22 ne peut faire qu'un **PUT opaque et aveugle** des octets. Il ne peut ni lire, ni fusionner, ni
ré-chiffrer la donnée. Toute la stratégie de conflit en découle (voir « Proposed Implementation » §3).

## Goals

- **Drain au retour réseau :** un service de synchronisation parcourt `OfflineUploadQueue.pending()` (FIFO) et
  ré-émet chaque `PUT /blob/{uuid}` via le `BackendClient` existant ; à chaque PUT confirmé (2xx), il
  `remove(id)`.
- **Aucune perte :** un élément n'est **jamais** retiré de la file tant qu'un PUT n'a pas réussi (2xx). Tout
  échec laisse l'élément en file, incrémente `attempts` et programme un renvoi. Aucune purge silencieuse.
- **Aucun doublon :** l'idempotence repose sur deux propriétés — (a) `PUT /blob/{uuid}` est **idempotent côté
  serveur** (réécrit le blob à cet UUID, pas d'insertion en double) ; (b) `remove(id)` n'a lieu qu'**après**
  confirmation, et un crash entre le PUT et le `remove` provoque au pire un **re-PUT identique** (mêmes octets,
  même UUID) au prochain drain — sans effet observable (livraison *at-least-once* + PUT idempotent = exactement
  un état final).
- **Renvois robustes :** backoff exponentiel borné par tentative, plafond de tentatives configurable ; au-delà,
  l'élément reste en file et est **signalé** à l'UI (jamais abandonné) comme « échec persistant — action requise ».
- **Stratégie de conflits documentée et sûre :** définir explicitement le comportement quand le blob serveur a
  **divergé** depuis l'édition hors-ligne (autre consultation, sync patient), sachant que le drain ne peut pas
  déchiffrer pour fusionner. Par défaut : **détection de divergence + préservation des deux versions**, jamais
  d'écrasement silencieux d'une version non vue (voir §3).
- **Détection de retour réseau découplée :** abstraire le déclencheur de drain (`SyncTrigger`) derrière une
  interface injectable, pour que le choix du paquet de connectivité reste une décision #1 (non figée) sans
  bloquer la logique de drain testable en host-only.
- **Invariants préservés :** le wipe RAM (#19), l'opacité serveur (zero-knowledge) et l'absence de clé de
  session sur le chemin de drain restent intacts. Le drain n'a **jamais** besoin de la clé de session.
- **Observabilité sans fuite :** journaux limités à `blob_uuid` + état (`pending`/`syncing`/`synced`/`conflict`)
  + `attempts` + statut HTTP. **Jamais** de ciphertext, de clé, ni de PII.

## Non-Goals

- **Pas de nouvelle cryptographie ni de re-chiffrement applicatif.** Le drain PUT les octets tels quels.
- **Pas de fusion sémantique côté médecin.** Impossible : la clé de session est wipée. La réconciliation de
  versions divergentes (qui exige de déchiffrer) **n'appartient pas à #22** ; elle relève d'une issue de suivi
  « sync patient post-consultation » (déjà signalée en #20/#21), côté patient avec la master-key (#11/#14).
- **Pas de portage de la boucle médecin vers `app-medecin/` (PWA).** La logique vit dans `app-patient/` (Flutter)
  ; la variante IndexedDB du PWA (ADR 0006) reste documentée mais **hors périmètre de livraison** ici.
- **Pas de nouvel endpoint backend obligatoire.** Le drain réutilise `PUT /blob/{uuid}` (#9/#14). La
  **détection de divergence conditionnelle** (ETag/version, §3 option B) *suppose* une capacité serveur qui peut
  ne pas exister encore — à n'introduire que si #9 l'offre ; sinon, dégrader proprement (voir Open Questions).
- **Pas la file de sauvegarde patient (#14)** ni les images lourdes (#23) ni l'optimisation réseau dégradé (#24).
- **Pas de tâche d'arrière-plan OS systématique.** Un drain en *background* (WorkManager/BGTask) est une
  **option** (le drain n'a besoin que de la clé SQLCipher Keystore, pas de la session) ; à signaler, pas à livrer
  obligatoirement (voir Open Questions).

## Relevant Repository Context

### État du dépôt

Projet *greenfield* au démarrage du backlog, mais la boucle de consultation M2 + la file hors-ligne #21 sont
livrées : **toute la logique médecin vit dans `app-patient/lib/src/doctor/**`** (Flutter/Dart), exécutable via
`flutter test`. Par cohérence avec #17→#21 et ADR 0006, **#22 doit être livré dans `app-patient/`**. C'est une
observation d'architecture (la logique médecin n'est pas encore portée vers `app-medecin/`), à conserver, pas à
corriger ici.

### Composants existants à brancher

| Élément | Fichier | Rôle pour #22 |
| --- | --- | --- |
| File hors-ligne (#21) | `app-patient/lib/src/doctor/offline_upload_queue.dart` | Interface `OfflineUploadQueue` : `pending()` (FIFO), `remove(id)`, `count()`, `enqueue()`. **Surface à drainer.** `PendingUpload{id, blobUuid, ciphertext, attempts, enqueuedAtIso}`. `attempts` est **déclaré « possédé par #22 »** — c'est ici qu'on l'incrémente. |
| Impl. prod (#21) | `app-patient/lib/src/doctor/sqlcipher_upload_queue.dart` | Table drift `pending_uploads` (schemaVersion 1) ; le commentaire annonce déjà que **#22 ajoutera `last_attempt_at`, `last_error`** → migration drift v2. La clé de base est scellée Keystore ; le drain lit `pending()` donc déclenche l'ouverture (unseal Keystore). |
| Impl. test (#21) | `InMemoryUploadQueue` (même fichier) | À réutiliser pour tester la logique de drain en host-only. **NB :** ne porte pas encore `attempts`/`last_error` mutables ni d'API d'incrément → à étendre (voir §1 et API Changes). |
| Transport ZK (#14) | `app-patient/lib/src/cloud/backend_client.dart` | `BackendClient.put(uuid, ciphertext)` → 200/201 OK, sinon `BackendUnavailable`. `get(uuid)` → `BlobNotFound`/`BackendUnavailable`. **PUT idempotent au niveau UUID.** Le drain réutilise `put` tel quel (aucun changement requis pour l'option A). |
| Fin de session (#19/#21) | `app-patient/lib/src/doctor/session_end_service.dart` | Produit les éléments enfilés (`SessionEndOutcome.queued`). Point de **déclenchement opportuniste** : un PUT réussi en fin de session prouve que le réseau est revenu → bon moment pour drainer le reste. |
| UI médecin | `app-patient/lib/src/.../record_view_screen.dart` (snackbar « enregistrée hors-ligne » #21) | À enrichir : badge « N en attente », état de synchro, déclencheur manuel « Synchroniser », alerte sur conflit/échec persistant. |
| Keystore / scellage (#11) | `app-patient/lib/src/secure/{keystore_channel,sealed_blob_store}.dart` | Le drain n'utilise **que** la clé SQLCipher (déjà gérée par #21) pour lire la file ; **aucune** clé de session. |
| Harnais e2e (#20/#21) | `app-patient/test/support/consultation_loop_harness.dart` | `FakeBlobBackend(failPut: true)` (503) et `referenceRecord()`. **À étendre** : un `FakeBlobBackend` dont on peut **basculer `failPut` de `true`→`false`** pour simuler le retour réseau, et qui compte les PUT pour prouver l'idempotence. |

### Conventions établies (à réutiliser)

- Code sous `app-patient/lib/src/doctor/`, tests miroir sous `app-patient/test/doctor/`.
- En-tête de fichier listant rôle + invariants de sécurité (cf. `session_end_service.dart`).
- **Interface + impl. prod + impl. in-memory** pour rester testable host-only quand le natif n'est pas dispo.
- Injection de dépendances par constructeur.
- `dart format` + `flutter analyze` **stricts** (Flutter 3.41.5 : `info` bloquants ; pièges du mémoire
  `project-backlog-state` : `prefer_const_constructors`, indentation old-style Dart 3.8.1, imports minimaux).
- Régénérer + committer les `*.g.dart` drift (`dart run build_runner build`) à tout changement de schéma.

### Décisions déjà prises (ADR 0006) vs. encore ouvertes (#1)

**Tranché :** file = SQLCipher (Android/Flutter) via `drift` + `sqlcipher_flutter_libs` ; clé scellée Keystore.

**Encore ouvert (à confirmer) :**
- **Paquet de détection de connectivité.** Aucun (`connectivity_plus`, `internet_connection_checker`, …) n'est
  déclaré dans `pubspec.yaml`. C'est une décision toolchain (#1). → abstraire derrière `SyncTrigger` et **ne pas**
  câbler de paquet en dur dans la logique testable.
- **Capacité serveur de versionnage (ETag / generation).** #9 n'expose aujourd'hui que `PUT/GET /blob/{uuid}`
  sans version conditionnelle documentée. La détection de divergence (§3 option B) en dépend → conditionner.
- **Drain en arrière-plan (WorkManager).** Option, pas tranchée.

## Proposed Implementation

### Vue d'ensemble

Introduire un **`SyncService`** dans `app-patient/lib/src/doctor/` qui **draine** la `OfflineUploadQueue` au
retour du réseau, derrière un **`SyncTrigger`** injectable (déclencheur découplé de tout paquet de
connectivité). Étendre la file (#21) pour exposer l'incrément de `attempts` et un état de synchro persistés,
et le `FakeBlobBackend` du harnais pour simuler la reconnexion. Aucune crypto nouvelle ; le drain PUT des
octets opaques.

### 1. Surface de file à compléter (`OfflineUploadQueue`)

Le contrat #21 (`enqueue/pending/remove/count`) suffit pour le chemin nominal *succès*, mais le **renvoi** et
la **stratégie de conflits** exigent de persister l'état d'une tentative. Étendre l'interface (et les **deux**
implémentations) **sans** introduire de logique réseau dans la file :

```dart
abstract class OfflineUploadQueue {
  // ... #21 : enqueue / pending / remove / count ...

  /// Marque un élément après une tentative échouée : incrémente `attempts`,
  /// persiste `lastAttemptAtIso` et un `lastError` REDACTÉ (statut/catégorie,
  /// jamais de bytes/clé/PII). Le renvoi/backoff est décidé par le SyncService.
  Future<void> markAttempt(String id, {required String redactedError});

  /// (Option B) Marque un élément en conflit irrésolu côté drain (divergence
  /// serveur détectée). Il reste persisté, exclu du drain normal, et signalé
  /// à l'UI pour réconciliation patient (issue de suivi).
  Future<void> markConflict(String id, {required String redactedReason});
}
```

`PendingUpload` gagne les champs lus seuls correspondants (`lastAttemptAtIso?`, `lastError?`, `state`). La
table drift passe en **schemaVersion 2** (colonnes `last_attempt_at`, `last_error`, `state` — exactement ce que
le commentaire #21 anticipe) avec une **migration** depuis v1. `InMemoryUploadQueue` implémente les mêmes
méthodes en RAM (pour les tests host-only). **Frontière maintenue :** la file persiste l'état ; elle ne
contient toujours **aucune** détection réseau ni boucle de retry.

### 2. `SyncService` — le drain (cœur de #22)

`app-patient/lib/src/doctor/sync_service.dart` :

```dart
class SyncService {
  SyncService({
    required BackendClient client,
    required OfflineUploadQueue queue,
    RetryPolicy retry = const RetryPolicy(),   // backoff borné, maxAttempts
    DateTime Function()? clock,
  });

  /// Draine la file une fois : PUT chaque élément éligible (FIFO), retire les
  /// confirmés, marque les échecs. Idempotent et ré-entrant-safe (mutex interne
  /// : un seul drain à la fois → pas de double-PUT concurrent). Retourne un
  /// résumé { synced, failed, conflicts, remaining } pour l'UI/les logs.
  Future<SyncSummary> drain();
}
```

Algorithme de `drain()` :

1. **Verrou** : si un drain est déjà en cours, retourner immédiatement (ré-entrance sûre).
2. `final items = await queue.pending();` (FIFO par `enqueued_at`).
3. Pour chaque `item` **éligible** (attente respectée selon `attempts`/`lastAttemptAt` + backoff ;
   non `conflict`) :
   - `try { await client.put(item.blobUuid, item.ciphertext); await queue.remove(item.id); synced++; }`
   - `on BackendUnavailable { await queue.markAttempt(item.id, redactedError: 'PUT $status'); failed++; }`
     — réseau encore absent ou 5xx : on **garde**, on incrémente, on **arrête le drain** (inutile d'insister :
     le réseau est probablement toujours coupé ; le prochain `SyncTrigger` relancera).
   - **Option B (si #9 fournit le versionnage)** : un PUT conditionnel rejeté pour divergence (p. ex. 409)
     → `queue.markConflict(...)`, `conflicts++` ; ne pas écraser.
4. Retourner `SyncSummary`.

**Ordre des opérations critique pour « aucune perte / aucun doublon » :** `put` **puis** `remove`. Si le
process meurt entre les deux, l'élément survit (durabilité WAL #21) et sera **re-PUT** au prochain drain — PUT
idempotent ⇒ état serveur identique, **aucun doublon**.

### 3. Stratégie de résolution de conflits (livrable explicite du critère d'acceptation)

**Le fait structurant :** le blob enfilé est chiffré avec la **clé de session wipée** → le drain ne peut **pas
déchiffrer**, donc **aucune fusion sémantique n'est possible sur l'appareil du médecin**. Les options se
réduisent donc à trois, à documenter dans un ADR :

- **(A) Dernier-écrivain-gagne aveugle (par défaut, livrable #22).** Le drain PUT les octets ; le serveur
  réécrit le blob à cet UUID. Simple, idempotent, *aucun doublon*. **Risque résiduel :** si le blob serveur a
  divergé entre l'édition hors-ligne et le drain (autre consultation, sync patient), le PUT **écrase**
  silencieusement cette version → perte potentielle d'une édition concurrente. **Acceptable comme défaut**
  parce que, dans le parcours réel, les consultations d'un même patient sont **séquentielles** et la fenêtre de
  divergence est étroite (un seul appareil médecin par consultation ; le scan hors-ligne échouerait de toute
  façon faute de `GET`). **À tracer** comme risque connu + atténué par (B) si dispo.
- **(B) Détection de divergence + préservation (recommandé dès que #9 le permet).** Capturer à l'instant du
  **scan** (#17) un **jeton de version opaque** du blob serveur (ETag / compteur de génération exposé par #9),
  le stocker avec l'élément en file (champ `base_version`), puis faire un **PUT conditionnel** (`If-Match`) au
  drain. Si le serveur a bougé (precondition failed) : **ne pas écraser** → `markConflict` + signaler. La
  donnée n'est ni perdue (reste en file) ni écrasée. La **réconciliation** des deux versions divergentes est
  déléguée au **patient** (master-key, issue de suivi), seul capable de déchiffrer. *Dépend d'une capacité
  serveur à confirmer (#9) — sinon dégrader vers (A).*
- **(C) Réconciliation côté patient (transverse, hors #22).** Comme seul le patient peut déchiffrer (master-key),
  la vraie fusion appartient à l'app patient. #22 garantit la **livraison** de toutes les versions ; la
  réconciliation est une **issue de suivi** explicite (« sync patient post-consultation »), déjà signalée.

**Multiples versions pour un même `blob_uuid` dans la file** (#21 garde chaque ciphertext distinct via
`UNIQUE(blob_uuid, ciphertext_hash)`) : drainer en **ordre FIFO** (`enqueued_at`), PUT chacune ; l'état final
serveur = la **dernière** (chronologiquement la plus récente). Cas rare (un second scan hors-ligne échouerait
au `GET`), mais l'ordre FIFO garantit un résultat déterministe et cohérent avec « dernier-gagne ».

> **Décision par défaut livrée par #22 :** **(A)** dernier-écrivain-gagne aveugle + livraison *at-least-once*
> idempotente, **avec les crochets de (B)** (`base_version`, `markConflict`) câblés mais **inactifs** tant que
> #9 n'expose pas le versionnage. La stratégie complète (A → B → C) est **documentée dans un ADR**.

### 4. `SyncTrigger` — quand drainer (détection de retour réseau découplée)

`app-patient/lib/src/doctor/sync_trigger.dart` — interface injectable émettant un signal « tenter un drain » :

```dart
abstract class SyncTrigger {
  /// Flux d'événements « tente un drain maintenant ».
  Stream<void> get events;
}
```

Déclencheurs à câbler (sans coupler la logique de drain à un paquet précis) :
- **App resume / foreground** (cycle de vie Flutter) — sans nouvelle dépendance.
- **Démarrage d'app** — drainer ce qui restait d'une session précédente.
- **Succès opportuniste** — un `PUT` réussi en fin de session (#19) ⇒ réseau revenu ⇒ déclencher un drain du
  reste de la file.
- **Manuel** — bouton « Synchroniser maintenant » dans l'UI médecin (toujours utile, indépendant du réseau).
- **(Option, #1)** Changement de connectivité via `connectivity_plus`/équivalent — **derrière** `SyncTrigger`,
  à introduire quand #1 tranche le paquet ; ne pas l'imposer dans la logique testable.

`SyncService` s'abonne au `SyncTrigger` et appelle `drain()` (débouncé, mutex). Aucun de ces déclencheurs n'a
besoin de la clé de session ; le drain ne touche que la file (clé SQLCipher Keystore).

### 5. Câblage / DI

- Construire `SyncService(client, queue)` au démarrage (`main.dart`), avec le `BackendClient` (URL backend) et
  la **même** `SqlCipherUploadQueue` que `SessionEndService` (file partagée). S'abonner à un `SyncTrigger`
  concret (cycle de vie app + bouton manuel pour commencer).
- L'UI affiche `queue.count()` (badge « N en attente »), l'état du dernier `SyncSummary`, et alerte sur conflit
  / échec persistant.
- En tests : `SyncService(FakeBackend, InMemoryUploadQueue)` + déclenchement direct de `drain()`.

## Affected Files / Packages / Modules

À **créer** :
- `app-patient/lib/src/doctor/sync_service.dart` — `SyncService.drain()`, `RetryPolicy`, `SyncSummary`, mutex.
- `app-patient/lib/src/doctor/sync_trigger.dart` — interface `SyncTrigger` + impl. cycle-de-vie/manuelle ;
  (option) impl. connectivité derrière la même interface.
- `app-patient/test/doctor/sync_service_test.dart` — logique de drain (in-memory) : succès, retry, idempotence,
  no-loss/no-duplicate, ordre FIFO, conflits (option B), mutex de ré-entrance.
- (option B) ADR de stratégie de conflits sous `docs/adr/` (ou extension d'ADR 0006).

À **modifier** :
- `app-patient/lib/src/doctor/offline_upload_queue.dart` — ajouter `markAttempt` / `markConflict` à l'interface,
  les champs lecture-seule (`lastAttemptAtIso`, `lastError`, `state`) à `PendingUpload`, et les implémenter dans
  `InMemoryUploadQueue`.
- `app-patient/lib/src/doctor/sqlcipher_upload_queue.dart` (+ `.g.dart`) — **migration schemaVersion 1→2**
  (`last_attempt_at`, `last_error`, `state`) ; implémenter `markAttempt`/`markConflict` ; `pending()` ordonne
  toujours FIFO et peut filtrer les `conflict`. Régénérer le code drift et committer le `.g.dart`.
- `app-patient/lib/main.dart` — construire/injecter `SyncService` + `SyncTrigger` ; brancher resume/start/manuel.
- `app-patient/lib/src/.../record_view_screen.dart` — badge « N en attente », état de synchro, bouton
  « Synchroniser », alerte conflit/échec persistant ; déclenchement opportuniste après un PUT réussi.
- `app-patient/test/support/consultation_loop_harness.dart` — `FakeBlobBackend` : rendre `failPut` **mutable**
  (true→false) pour simuler la reconnexion, et exposer `putCount` par UUID pour prouver l'idempotence.
- `app-patient/test/e2e/consultation_loop_e2e_test.dart` — scénario reconnexion (voir Testing Plan).
- `app-patient/pubspec.yaml` — **seulement si** #1 tranche un paquet de connectivité (sinon, aucune nouvelle dép).

À **lire** (sans modifier) :
- `app-patient/lib/src/doctor/{consultation_session,session_end_service}.dart`,
  `app-patient/lib/src/cloud/backend_client.dart`,
  `app-patient/lib/src/secure/{keystore_channel,sealed_blob_store}.dart`,
  `docs/adr/0006-offline-storage-and-keys.md`, `specs/secure-offline-prescription-queue-sqlcipher.md`.

Hors `app-patient/` : `app-medecin/` n'est **pas** touché. Pas de modification backend (#9) **pour l'option A** ;
l'option B suppose une capacité de versionnage à confirmer côté #9 (Open Questions).

## API / Interface Changes

- **Interne (paquet `app_patient`) — nouvelle API publique à documenter :**
  - `SyncService` (`drain()`, `SyncSummary`), `RetryPolicy`, `SyncTrigger`.
  - Extension de `OfflineUploadQueue` : `markAttempt(id, {redactedError})`, `markConflict(id, {redactedReason})` ;
    nouveaux champs lecture-seule sur `PendingUpload` (`lastAttemptAtIso`, `lastError`, `state`). **Compat. :**
    additif (les signatures #21 existantes ne changent pas) ; impacte uniquement les deux implémentations de file.
- **Réseau / endpoints :** **none** pour l'option A (réutilise `PUT /blob/{uuid}`). L'**option B** *suppose* un
  contrat conditionnel (ETag/`If-Match` ou compteur de génération) sur #9 — **à confirmer**, pas livré par défaut.
- **QR / jeton d'accès :** **none.** Le drain n'utilise ni ne manipule la clé de session / le QR.
- **CLI :** **none.**

## Data Model / Protocol Changes

- **Migration locale `pending_uploads` v1→v2 :** ajout de `last_attempt_at TEXT?`, `last_error TEXT?` (redacté),
  `state TEXT` (`pending`/`syncing`/`conflict`), et — **si option B** — `base_version TEXT?` (jeton opaque
  capturé au scan). Migration drift versionnée (les colonnes étaient annoncées par le commentaire #21).
- **Format de blob :** **inchangé** (`nonce(12)||ct||tag(16)`). Le drain ne (dé)chiffre rien — PUT tel quel.
- **Protocole réseau :** **none** (option A). Option B = en-tête/contrat conditionnel sur #9 (à confirmer).
- **Sérialisation :** locale uniquement (drift) ; rien de nouveau sur le fil pour l'option A.

## Security & Compliance Considerations

- **Chiffrement AES-256-GCM côté client :** le blob drainé est **déjà** chiffré (clé de session, #16/#18) ; #22
  ne touche pas la crypto et ne ré-chiffre rien. La file reste protégée par SQLCipher (#21).
- **Zero-knowledge serveur :** **inchangé et renforcé conceptuellement** — le drain prouve que la remontée
  hors-ligne emprunte exactement le même `PUT /blob/{uuid}` opaque qu'un envoi normal. Le serveur ne reçoit que
  des octets indéchiffrables indexés par UUID anonyme ; il ne peut ni lire, ni fusionner, ni résoudre de conflit
  (d'où la stratégie client/patient de §3).
- **Clé de session jamais sur le chemin de drain :** le drain n'a **pas** besoin de la clé de session (wipée en
  #19) ; il ne fait que transporter des octets opaques. Conséquence : un drain peut tourner **après** la fin de
  session, voire en arrière-plan, **sans** ré-exposer de clé de session. Seule la clé **SQLCipher** (scellée
  Keystore, #21) est requise pour lire la file — inchangé.
- **Wipe RAM (US-2.3) préservé :** #22 ne modifie pas `session.wipe()` ni le `finally` de #19 ; il opère sur la
  file durable, hors session.
- **Résidence des données (ARTCI / loi n°2013-450) :** le drain envoie la donnée vers le backend **souverain**
  (#8/#9) en Côte d'Ivoire — aucune donnée ne transite par un tiers étranger. À tracer dans la matrice de
  conformité comme preuve du contrôle « pas de perte hors-ligne / remontée vers l'hébergement national ».
- **Budget ≤ 500 Kio :** garanti en amont par `RecordSizeGuard` (#15/#18) ; #22 n'y touche pas. Borne de **taille
  de file** (héritée de #21) : ne jamais purger silencieusement des éléments **non synchronisés** ; un échec
  persistant est **signalé**, pas abandonné.
- **Images lourdes :** jamais sur l'appareil (PRD §4) ; la file ne contient que le blob texte chiffré (≤ 500 Kio)
  avec des `imageUrls` éphémères. Le drain ne manipule aucune image lourde.
- **Logs / redaction :** **ne jamais** logger ciphertext, clé (session/SQLCipher), ni PII. `last_error` est une
  **catégorie redactée** (statut HTTP / type d'exception), jamais un corps de réponse. Journaux = `blob_uuid` +
  `state` + `attempts` + statut.
- **Renvois / DoS :** backoff borné pour ne pas marteler le backend souverain ni vider la batterie d'un Infinix
  bas de gamme (#29) ; un drain à la fois (mutex).

## Testing Plan

- **Unitaire — `SyncService.drain()` (avec `InMemoryUploadQueue` + fake backend) :**
  - **Succès :** 2 éléments en file, backend OK → 2 PUT, file vidée (`count()==0`), `SyncSummary.synced==2`.
  - **Aucune perte :** backend KO (`BackendUnavailable`) → 0 PUT confirmé, file **inchangée**, `attempts`
    incrémenté, drain s'arrête proprement (pas d'exception remontée à l'appelant).
  - **Reconnexion :** `FakeBlobBackend` bascule `failPut: true→false` entre deux `drain()` → 1er drain ne retire
    rien, 2e drain vide la file. **Aucun doublon** (compteur de PUT par UUID cohérent).
  - **Idempotence / at-least-once :** simuler un crash **entre** `put` et `remove` (fake `remove` qui throw une
    fois) → l'élément survit, re-drain → re-PUT du **même** UUID, état serveur identique, file finalement vidée,
    **aucun doublon**.
  - **Ordre FIFO :** plusieurs versions pour un même `blob_uuid` drainées dans l'ordre `enqueued_at` ; état final
    = la dernière.
  - **Renvoi/backoff :** un élément dont le PUT échoue voit `attempts++` et est **réessayé** après la fenêtre de
    backoff ; au-delà de `maxAttempts`, il reste en file marqué « échec persistant » (jamais supprimé).
  - **Ré-entrance :** deux `drain()` concurrents → un seul exécute (mutex), pas de double-PUT.
  - **Conflit (option B, si livrée) :** PUT conditionnel rejeté (divergence) → `markConflict`, élément exclu du
    drain normal, signalé ; **non écrasé**.
- **Unitaire — extension de file :** `markAttempt` persiste `attempts`/`lastAttemptAt`/`lastError` ;
  `markConflict` passe l'état à `conflict` et l'exclut de `pending()` éligible ; `lastError` est bien **redacté**
  (pas de bytes/PII). Non-régression du contrat #21 (`enqueue/pending/remove/count`, idempotence, copie défensive).
- **Intégration (e2e à fakes, #20) — scénario reconnexion :** patient→médecin→`terminate` **hors-ligne**
  (`failPut: true`) → `queued`, file=1, RAM wipée ; **puis** réseau revient (`failPut: false`) + `SyncTrigger`
  → `SyncService.drain()` → blob présent côté `FakeBlobBackend`, file=0, **aucun clair** nulle part, **aucun
  doublon**. (Le ré-import patient master-key reste hors périmètre — assert documenté.)
- **Crypto-vectors :** **none propre à #22** (aucune primitive nouvelle) ; couverts par les vecteurs NIST de
  `crypto-core` (#10).
- **Résilience / device-backed (suivi — dépend de #1 + émulateur, sinon documenté comme non exécuté en CI) :**
  drain réel sur SQLCipher (migration v1→v2, durabilité WAL après kill entre `put` et `remove`, illisibilité de
  la base sans clé Keystore) ; (option, si paquet retenu) drain déclenché par un vrai événement de connectivité.
- **Lint/format :** `dart format --output=none --set-exit-if-changed .` + `flutter analyze` propres (Flutter
  3.41.5 : `info` bloquants ; pièges mémoire `project-backlog-state`). `dart run build_runner build` après la
  migration drift, committer les `*.g.dart`.
- **Commande :** `cd app-patient && flutter test` (host-only couvre la logique in-memory ; la liaison SQLCipher
  réelle relève du suivi device-backed).

## Documentation Updates

- **ADR — stratégie de résolution de conflits :** créer un ADR (ou étendre [ADR 0006](../docs/adr/0006-offline-storage-and-keys.md))
  qui **documente A → B → C** (dernier-gagne aveugle par défaut, détection de divergence si #9 le permet,
  réconciliation patient en suivi) et la **contrainte clé** (clé de session wipée ⇒ pas de fusion sur l'appareil
  médecin). C'est la pièce qui satisfait le critère « stratégie de résolution de conflits documentée ».
- **BACKLOG.md :** ajouter une ligne *Avancement* sous **#22** une fois livré (drain `SyncService`, retry/backoff,
  stratégie de conflits documentée ; option B conditionnée à #9 ; ré-import patient en suivi).
- **`app-patient/README.md` :** documenter la nouvelle API publique (`SyncService`, `SyncTrigger`,
  extensions `OfflineUploadQueue`) et le comportement « synchronisation au retour du réseau ».
- **Matrice de conformité (`docs/compliance/`) :** tracer le contrôle « remontée hors-ligne sans perte ni
  doublon vers l'hébergement souverain » (US-2.4 / KPI 100 %) vers cette implémentation (preuve).
- **Mémoire `project-backlog-state.md` :** ajouter #22 au tableau de livraison une fois mergé.
- **PRD :** pas de changement d'exigence.
- **(Suivi)** ouvrir l'issue « sync patient post-consultation » (ré-import master-key) si elle n'existe pas, et —
  si l'option B est visée — l'issue/PR backend #9 « jeton de version / PUT conditionnel ».

## Risks and Open Questions

1. **Détection de retour réseau (paquet).** Aucun paquet de connectivité n'est encore une dépendance (#1).
   **Recommandation :** livrer avec des déclencheurs sans dépendance (resume/start/opportuniste/manuel) derrière
   `SyncTrigger` ; ajouter `connectivity_plus` plus tard, derrière la même interface. *À confirmer (#1).*
2. **Stratégie de conflits par défaut.** Dernier-gagne aveugle (A) peut écraser une version concurrente non vue.
   **Recommandation :** A par défaut + crochets B câblés-mais-inactifs + risque tracé en ADR, jusqu'à ce que #9
   expose un versionnage. *À confirmer (produit + #9).*
3. **Capacité serveur de versionnage (#9).** L'option B exige un ETag/compteur de génération + PUT conditionnel
   non documentés sur #9. **À confirmer** ; sinon, rester en A et documenter le risque résiduel.
4. **Réconciliation patient (transverse).** Le blob drainé reste chiffré clé de session ; seul le patient
   (master-key) peut le ré-intégrer dans sa sauvegarde (#14). **Non couvert par une issue** → recommander un
   suivi « sync patient post-consultation » (déjà signalé en #20/#21). #22 garantit la *livraison*, pas la fusion.
5. **Drain en arrière-plan (WorkManager/BGTask).** Possible (le drain n'a besoin que de la clé SQLCipher, pas de
   la session) mais hors périmètre par défaut. **Option** à signaler ; attention conso batterie (#29).
6. **Migration drift v1→v2 non testable en CI host-only.** La migration réelle SQLCipher relève d'un e2e
   *device-backed* (suivi #1 + émulateur). **Documenter** explicitement ce qui n'est pas exécuté en CI pour
   éviter une fausse confiance.
7. **Bornage des renvois.** Choisir `maxAttempts`, fenêtre de backoff et comportement au plafond (signaler, ne
   jamais purger). À calibrer pour réseau Edge/3G instable + batterie d'entrée de gamme (#29).
8. **Variante PWA (IndexedDB).** Quand la boucle sera portée vers `app-medecin/`, le drain devra exister en
   version web. Hors périmètre #22, à garder en vue (ADR 0006).

## Implementation Checklist

1. Relire `offline_upload_queue.dart`, `sqlcipher_upload_queue.dart`, `session_end_service.dart`,
   `backend_client.dart`, le harnais e2e et ADR 0006 pour câbler exactement signatures, schéma drift et modèle
   Keystore.
2. Étendre `OfflineUploadQueue` : ajouter `markAttempt` / `markConflict` et les champs lecture-seule sur
   `PendingUpload` (`lastAttemptAtIso`, `lastError`, `state`) ; implémenter dans `InMemoryUploadQueue` (RAM).
3. Migrer `sqlcipher_upload_queue.dart` en **schemaVersion 2** (`last_attempt_at`, `last_error`, `state` ; option
   B : `base_version`) + migration depuis v1 ; implémenter `markAttempt`/`markConflict` ; `pending()` reste FIFO
   et filtre les `conflict`. Régénérer + committer les `*.g.dart`.
4. Créer `sync_service.dart` : `drain()` (mutex, FIFO, `put`→`remove`, `markAttempt` sur échec, arrêt propre
   réseau-absent), `RetryPolicy` (backoff borné, `maxAttempts`), `SyncSummary`. Aucune crypto, aucun déchiffrement.
5. Créer `sync_trigger.dart` : interface + déclencheurs sans dépendance (resume/start/manuel/opportuniste) ;
   (option) impl. connectivité derrière la même interface si #1 tranche un paquet.
6. Étendre le harnais : `FakeBlobBackend.failPut` **mutable** (true→false) + `putCount` par UUID.
7. Écrire `sync_service_test.dart` : succès, no-loss (réseau KO), reconnexion, idempotence/at-least-once (crash
   entre put et remove), ordre FIFO, retry/backoff + plafond, ré-entrance (mutex), conflit (option B si livrée).
8. Étendre l'e2e #20 : scénario reconnexion (hors-ligne → `queued` → réseau revient → `drain()` → file vidée,
   aucun clair, aucun doublon, RAM wipée).
9. Câbler dans `main.dart` : `SyncService` + `SyncTrigger` (resume/start/manuel + drain opportuniste après PUT
   réussi en fin de session) ; enrichir l'UI (badge « N en attente », état, bouton « Synchroniser », alerte
   conflit/échec persistant).
10. `dart format --output=none --set-exit-if-changed .` + `flutter analyze` propres (traiter les `info` comme
    bloquants ; pièges mémoire `project-backlog-state`).
11. Rédiger l'**ADR stratégie de conflits** (A→B→C + contrainte clé de session wipée). Mettre à jour BACKLOG
    (*Avancement* #22), `app-patient/README.md` (API publique), matrice de conformité (preuve), et
    `project-backlog-state.md` une fois mergé.
12. (Suivi, hors #22) : ne **pas** implémenter la réconciliation patient ici (issue de suivi master-key) ;
    conditionner l'option B à une capacité de versionnage côté #9 ; envisager le drain en arrière-plan et la
    variante PWA IndexedDB le moment venu.
