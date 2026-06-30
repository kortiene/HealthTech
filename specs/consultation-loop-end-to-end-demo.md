# Démo end-to-end de la boucle de consultation (#20)

> **Issue :** #20 — Démo end-to-end de la boucle de consultation · `feature` `docs`
> **Épic :** E2 — Interface Professionnel de Santé · **Effort :** S · **Priorité :** Should
> **Dépend de :** #16 (QR), #17 (scan + déchiffrement RAM), #18 (note/ordonnance + fusion RAM), #19 (fin de session + wipe) — **tous mergés** (PR #72–#75).
> **Jalon :** M2 — Boucle de consultation.

## Problem Statement

Les quatre maillons de la boucle de consultation (M2) ont été livrés et testés **isolément** :
génération du QR patient (#16), scan + déchiffrement en RAM côté médecin (#17), ajout/fusion
d'une note ou ordonnance en mémoire (#18), et fin de session avec renvoi cloud + wipe RAM (#19).
Chaque maillon a sa propre suite de tests unitaires, mais **aucun test ne prouve que les quatre
s'enchaînent correctement** : que la clé de session générée par le patient est bien celle qui
déchiffre le blob côté médecin, que la note ajoutée par le médecin survit au ré-chiffrement puis
au renvoi cloud, et que la mise à jour est observable après la consultation.

Le cœur de valeur démontrable du produit (PRD §3, Épic 2 ; BACKLOG M2) n'est donc pas couvert par
un test de régression de bout en bout. C'est précisément l'objet de #20 : un scénario automatisé
*patient génère QR → médecin scanne, édite, termine → la mise à jour est observable*, vert en CI.

## Goals

- Un test d'intégration automatisé, **exécutable sans appareil/émulateur ni bibliothèque native**,
  qui enchaîne les services **réels** des issues #16→#19 (pas de logique réécrite dans le test).
- Couvrir le cycle complet en un seul flux :
  1. le patient génère un `QrPayload` (clé de session 256 bits, blob session poussé au backend) ;
  2. le médecin parse le QR, télécharge le blob, le déchiffre **en RAM** → `MedicalRecord` ;
  3. le médecin fusionne une note + une ordonnance (append-only) et ré-chiffre avec la clé de session ;
  4. le médecin termine la session → renvoi cloud du blob mis à jour + wipe RAM ;
  5. la mise à jour est **observable** : un re-déchiffrement du blob serveur (avec la clé de session,
     encore détenue par le patient pendant la fenêtre de 120 s) montre la consultation ajoutée.
- Asserter les invariants transverses que les tests unitaires ne peuvent pas voir au niveau du flux :
  identité du blob serveur entre PUT patient et GET médecin, préservation append-only de l'historique,
  wipe effectif de la clé de session et du blob en attente en fin de session, et **aucune écriture
  disque/log de clair** sur le chemin.
- Factoriser les *fakes* aujourd'hui dupliqués (`_FakeCryptoCore`, backend HTTP en mémoire) dans un
  module de support de test partagé réutilisable par l'e2e et, à terme, par les tests unitaires.
- Vert dans l'étape CI existante (`flutter test`, job `flutter` de `.github/workflows/ci.yml`) — pas
  de nouveau pipeline.

## Non-Goals

- **Ne pas** implémenter de nouvelle fonctionnalité produit. #20 est un test + de la doc ; aucune
  modification du comportement des services #16–#19.
- **Ne pas** introduire un mécanisme par lequel le patient ré-importe l'update du médecin dans sa
  sauvegarde *master-key* locale/cloud (#14). Ce ré-chiffrement master-key post-consultation **n'est
  couvert par aucune issue à ce jour** (voir « Risks and Open Questions ») — le test ne doit pas
  prétendre qu'il existe.
- **Ne pas** écrire un test piloté par appareil/émulateur (`integration_test/` Flutter avec vrai
  scan caméra, vrai `crypto-core` natif via FRB, vrai `flutter_secure_storage`). C'est un suivi plus
  lourd, dépendant de la finalisation de la stack (#1) et d'une `crypto-core` compilée — hors périmètre S.
- **Ne pas** tester le job `app-medecin` (PWA TS/Vite) : la logique de la boucle a été livrée dans
  `app-patient/lib/src/doctor/**` (Flutter), pas dans `app-medecin/` qui reste un squelette (voir
  « Relevant Repository Context »).
- **Ne pas** couvrir la résilience hors-ligne (#21/#22, file SQLCipher) ni les images lourdes (#23) :
  ce sont des jalons M3 ultérieurs.

## Relevant Repository Context

### Où vit réellement la boucle de consultation

Bien que l'Épic 2 vise « l'interface professionnel de santé » et qu'un projet `app-medecin/`
(PWA TypeScript/Vite : `src/app.tsx`, `src/session.ts`, `src/main.tsx`) existe, **toute la logique
de la boucle #16–#19 a été implémentée en Dart dans le paquet patient** `app-patient/`, sous
`lib/src/doctor/**` et `lib/src/qr/**`. `app-medecin/` reste un squelette. **Le test e2e doit donc
vivre dans `app-patient/` et s'exécuter via `flutter test`.** (À signaler comme observation
d'architecture ; ce n'est pas l'objet de #20 de la corriger.)

### Composants réels à enchaîner

| Issue | Composant (réel) | Rôle dans la boucle |
| --- | --- | --- |
| #16 | `lib/src/qr/access_token.dart` — `AccessTokenService.generate(uuid, handle, backendUrl)` | génère clé session 256 bits (CSPRNG), lit + déchiffre le dossier (clé maître), ré-chiffre avec la clé session, **PUT** le blob session, renvoie un `QrPayload` (TTL 120 s, clé en RAM). `QrPayload.toQrString()`/`fromQrString()` (de)sérialisent le QR ; `QrPayload.wipe()` zéroïse la clé. |
| #17 | `lib/src/doctor/scan_service.dart` — `ScanService.parseQr(raw)` + `fetchAndDecrypt(payload)` | `parseQr` rejette les QR expirés (`ExpiredQrCode`) ; `fetchAndDecrypt` **GET** le blob, le déchiffre **en RAM** (handle Rust wipé en `finally`), renvoie un `MedicalRecord`. |
| #18 | `lib/src/doctor/consultation_merge.dart` — `mergeConsultation(...)` (fonction pure) ; `lib/src/doctor/consultation_edit_service.dart` — `ConsultationEditService.reEncrypt(merged, payload, newConsultationId:)` | fusion **append-only** d'une note/ordonnance ; ré-chiffrement avec la **clé de session** (jamais la clé maître côté médecin) ; garde 500 Kio préservant la nouvelle note (`RecordFullException` sinon). |
| #18 | `lib/src/doctor/consultation_session.dart` — `ConsultationSession` | porteur RAM unique : `current`, `pendingBlob`, `applyMerge(merged, blob)`, `wipe()`. |
| #19 | `lib/src/doctor/session_end_service.dart` — `SessionEndService.terminate(session)` | **PUT** `pendingBlob` (si présent) puis `session.wipe()` en `finally` (clé + blob zéroïsés même si le PUT échoue) ; propage `BackendUnavailable`. |
| support | `lib/src/cloud/backend_client.dart` — `BackendClient` (`PUT/GET /blob/{uuid}`) | transport ZK ; injecte un `http.Client` en test. |
| support | `lib/src/record/medical_record.dart`, `prescription.dart`, `medical_record_store.dart`, `record_size_guard.dart` | modèle du dossier (`toUtf8Bytes()`, `fromJson`, `copyWith`, `consultations`), ordonnance, store, garde 500 Kio. |
| seam | `lib/src/rust/crypto_core_bindings.dart` — `CryptoCore` (interface), `MasterKeyHandle`, `FrbCryptoCore`, `DecryptError`, `CryptoCoreUnavailable` | **seul** point crypto. `FrbCryptoCore` lève `CryptoCoreUnavailable` tant que la lib native n'est pas générée. |

### Conventions de test établies (à réutiliser)

- Tests sous `app-patient/test/**`, miroir de `lib/src/**` (ex. `test/doctor/scan_service_test.dart`).
- En-tête de commentaire listant les propriétés vérifiées (voir `session_end_service_test.dart`).
- Backend faké via `package:http/testing.dart` `MockClient` (callback `(req) async => http.Response`).
- Crypto fakée par un **`_FakeCryptoCore` XOR déterministe et inversible** (`encrypt == decrypt == XOR 0x5A`),
  aujourd'hui **dupliqué** dans `scan_service_test.dart`, `consultation_edit_service_test.dart`,
  `access_token_test.dart`, `medical_record_store_test.dart`, etc. → candidat naturel à la factorisation.
- `dart format` + `flutter analyze` stricts (Flutter 3.41.5 traite les `info` comme bloquants ;
  voir le mémoire `project-backlog-state` pour les pièges `prefer_const_constructors`, indentation, etc.).

### Décisions encore ouvertes (stack non figée — #1)

- ADR 0001 a retenu Flutter (patient) + Rust `crypto-core` via `flutter_rust_bridge`, mais **#1 n'est
  pas clos** et la commande de test « officielle » du monorepo reste `just test` (qui *skippe*
  `flutter test` si le SDK Flutter est absent — cf. `justfile:90`). La place de l'e2e dans la CI
  dépend donc de ce qui reste vrai après #1 : ici on cible le job `flutter` existant.
- La lib native `crypto-core` n'est **pas compilée** dans l'environnement ADW/CI Flutter actuel
  (`FrbCryptoCore` lève `CryptoCoreUnavailable`). Tout test exécutable aujourd'hui **doit** utiliser
  le `FakeCryptoCore` — d'où le choix d'un e2e *host-runnable à fakes*, pas device-backed.

## Proposed Implementation

### Approche : test d'intégration « à fakes », services réels

Écrire un test Dart unique qui instancie les **classes de service réelles** #16→#19 et les câble
ensemble autour de deux *fakes* partagés :

1. **`FakeBlobBackend`** — un `MockClient` *avec état* enveloppant une `Map<String, Uint8List>`
   (le serveur ZK en mémoire) :
   - `PUT /blob/{uuid}` → stocke une **copie** des octets, renvoie `201`/`200` ;
   - `GET /blob/{uuid}` → renvoie les octets stockés (`200`) ou `404` si absent ;
   - expose éventuellement un compteur d'appels et la map pour les assertions (ex. « le serveur ne
     contient que des octets opaques différents du clair »).
2. **`FakeCryptoCore`** — l'implémentation XOR déterministe déjà utilisée, **extraite** dans le module
   de support. Propriété clé exploitée par l'e2e : `decrypt(encrypt(x, k)) == x` **indépendamment de
   la valeur de la clé**, ce qui suffit à prouver le round-trip patient↔médecin tant que la **même**
   clé de session circule (le QR transporte la clé ; le test réutilise le même `QrPayload`/les mêmes
   octets de clé des deux côtés).

> **Note d'honnêteté crypto :** le `FakeCryptoCore` XOR **ne** valide **pas** l'authentification GCM,
> le format `nonce(12)||ct||tag(16)`, ni le rejet « mauvaise clé ». L'e2e prouve le **câblage** de la
> boucle, **pas** la cryptographie — celle-ci est couverte par les vecteurs NIST de `crypto-core`
> (#10) et le sera de bout en bout par l'e2e device-backed (suivi). Le commentaire d'en-tête du test
> doit l'énoncer explicitement pour ne pas laisser croire à une garantie crypto réelle.

### Le module de support partagé

Créer `app-patient/test/support/consultation_loop_harness.dart` (ou `test/support/fakes.dart`)
exposant : `FakeCryptoCore`, `FakeMasterKeyHandle`, `FakeBlobBackend` (+ son `http.Client`), et des
fabriques de `MedicalRecord` de référence (ex. un dossier patient initial avec 1 consultation et
quelques allergies). Migrer progressivement les fakes dupliqués des tests unitaires vers ce module
(refactor mécanique, sans changer les assertions) — **optionnel mais recommandé**, à garder hors du
chemin critique de #20 si le risque de churn est jugé trop élevé.

### Câblage du scénario (un seul `test(...)`)

Côté patient (un `MedicalRecordStore`/account UUID factices ou un `AccessTokenService` alimenté
directement par un `MedicalRecordStore` fake renvoyant le dossier de référence) :

```
// 1. PATIENT — génère le QR
final qr = await accessTokenService.generate(uuid, masterHandle, backendUrl);
final raw = qr.toQrString();                    // ce qui s'affiche dans le QR

// 2. MÉDECIN — parse + scanne + déchiffre en RAM
final payload = ScanService.parseQr(raw);        // rejette si expiré
final record  = await scanService.fetchAndDecrypt(payload);
expect(record.consultations, hasLength(1));      // dossier initial vu

// 3. MÉDECIN — fusionne note + ordonnance (append-only) et ré-chiffre
final merged = mergeConsultation(record, practitionerRef: 'practitioner-unverified',
    date: '2026-06-29', summary: 'Paludisme — repos', prescription: rx,
    newConsultationId: newId, nowIso: '2026-06-29T10:00:00Z');
final session = ConsultationSession(payload: payload, record: record);
final blob = await editService.reEncrypt(merged, payload, newConsultationId: newId);
session.applyMerge(merged, blob);

// 4. MÉDECIN — termine : renvoi cloud + wipe RAM
await sessionEndService.terminate(session);
expect(session.pendingBlob, isNull);             // RAM vidée
expect(payload.sessionKey, everyElement(0));     // clé zéroïsée

// 5. MISE À JOUR OBSERVABLE — re-déchiffrement du blob serveur
//    (le patient détient encore la clé de session dans la fenêtre 120 s)
final after = await freshScanService.fetchAndDecrypt(payloadCopyHoldingKey);
expect(after.consultations, hasLength(2));        // la note du médecin est là
expect(after.consultations.last.summary, contains('Paludisme'));
```

> **Subtilité du wipe à gérer dans le test.** `SessionEndService.terminate` **zéroïse en place** la
> clé de session du `payload` (étape 4). L'étape 5 a besoin d'une clé valide pour re-déchiffrer le
> blob serveur. Solutions, par ordre de préférence :
> - **A (recommandée, fidèle au modèle).** Le patient et le médecin ont des *objets `QrPayload`
>   distincts* construits depuis la **même chaîne QR** (`QrPayload.fromQrString(raw)`), comme dans la
>   réalité (le QR transfère la clé, il n'y a pas de partage d'objet). Le médecin wipe **sa** copie ;
>   le patient garde la sienne pour l'étape 5. C'est aussi plus réaliste pour l'assertion de wipe.
> - **B.** Capturer une copie des octets de clé avant l'étape 4 et reconstruire un `QrPayload` pour
>   l'étape 5. Moins fidèle, à éviter sauf contrainte.

### Assertions transverses (au-delà des unitaires)

- **Identité du blob :** les octets PUT par le patient (#16) == ceux GET par le médecin (#17) ;
  les octets PUT en fin de session (#19) == ceux re-GET à l'étape 5.
- **Append-only :** `after.consultations.length == before + 1`, l'historique initial intact,
  `createdAt`/`patientId`/version du schéma inchangés.
- **Zéro-clair côté serveur :** aucune valeur de la map `FakeBlobBackend` n'est égale aux
  `record.toUtf8Bytes()` en clair (le fake XOR transforme bien les octets).
- **Wipe :** clé de session du médecin et `pendingBlob` à zéro après `terminate`.
- **Robustesse PUT en échec (variante) :** si le backend renvoie 5xx en fin de session,
  `terminate` propage `BackendUnavailable` **mais** la RAM est tout de même wipée (déjà testé en
  unitaire #19 ; à ré-asserter au niveau flux, optionnel).
- **QR expiré (variante) :** un `raw` avec `exp` dans le passé → `ScanService.parseQr` lève
  `ExpiredQrCode` (chemin de refus du flux).

## Affected Files / Packages / Modules

À **créer** :

- `app-patient/test/e2e/consultation_loop_e2e_test.dart` — le test d'intégration (nom alternatif :
  `test/integration/consultation_loop_test.dart` si l'on préfère ce dossier ; les deux sont ramassés
  par `flutter test`).
- `app-patient/test/support/consultation_loop_harness.dart` — fakes + fabriques partagés
  (`FakeCryptoCore`, `FakeMasterKeyHandle`, `FakeBlobBackend`, dossiers de référence).

À **lire** (pour câbler fidèlement, sans les modifier) :

- `app-patient/lib/src/qr/access_token.dart`
- `app-patient/lib/src/doctor/{scan_service,consultation_merge,consultation_edit_service,consultation_session,session_end_service}.dart`
- `app-patient/lib/src/cloud/backend_client.dart`
- `app-patient/lib/src/record/{medical_record,prescription,medical_record_store,record_size_guard}.dart`
- `app-patient/lib/src/rust/crypto_core_bindings.dart`
- Tests unitaires existants pour les conventions de fakes : `test/doctor/scan_service_test.dart`,
  `test/doctor/session_end_service_test.dart`, `test/qr/access_token_test.dart`.

À **mettre à jour éventuellement** (refactor optionnel) : les tests unitaires qui dupliquent
`_FakeCryptoCore`, pour consommer le module de support.

Hors `app-patient/` : éventuellement `justfile`/`.github/workflows/ci.yml` **seulement** si l'on veut
un commentaire/alias explicite « e2e » ; par défaut **aucune** modification CI n'est requise (le test
est ramassé par l'étape `flutter test` existante).

## API / Interface Changes

**None.** Aucune nouvelle commande, API publique, endpoint réseau ni champ de QR/jeton d'accès.
#20 consomme les surfaces existantes (`AccessTokenService`, `ScanService`, `mergeConsultation`,
`ConsultationEditService`, `ConsultationSession`, `SessionEndService`, `BackendClient`) sans les
modifier. Le module de support de test est interne (`test/`), pas une API publique du paquet.

## Data Model / Protocol Changes

**None.** Le test réutilise tels quels : le schéma `MedicalRecord` (#15), le format de blob
`nonce(12) || ciphertext || tag(16)` (#10) — simulé par le fake XOR au niveau octet, **non** validé
crypto-graphiquement — et la chaîne QR JSON (`{v, uuid, url, key(base64url), exp}`, #16). Aucune
migration, aucune sérialisation nouvelle.

## Security & Compliance Considerations

- **Chiffrement client-side AES-256-GCM :** inchangé. L'e2e **ne** teste **pas** la crypto réelle
  (fake XOR) ; il vérifie le câblage et l'absence de clair côté « serveur ». Le commentaire d'en-tête
  doit l'affirmer pour ne pas laisser croire à une preuve crypto. La crypto réelle reste couverte par
  les vecteurs NIST `crypto-core` (#10) et par l'e2e device-backed à venir.
- **Zero-knowledge :** asserter que le `FakeBlobBackend` ne détient que des octets **opaques**
  (différents du clair) indexés par UUID anonyme, et que le médecin n'utilise **jamais** la clé maître
  (uniquement la clé de session du QR). Le `BackendClient` ne logge que UUID + statut HTTP — à
  préserver ; **ne jamais logger** le corps (ciphertext), le clair, ni la clé dans le test ou les fakes.
- **Accès éphémère 120 s :** inclure la variante « QR expiré → `ExpiredQrCode` » pour matérialiser la
  borne d'expiration au niveau du flux (TTL = `_kTtlSeconds = 120`).
- **Déchiffrement RAM-only + wipe de fin de session :** asserter explicitement le wipe (clé de session
  et `pendingBlob` à zéro après `terminate`) ; aucun fichier temporaire/log de clair ne doit être créé
  par le test (les services écrivent déjà uniquement en RAM — l'e2e ne doit pas introduire de I/O disque).
- **Résidence des données (ARTCI / loi n°2013-450) :** non impactée par un test ; le `FakeBlobBackend`
  est en mémoire. Aucun secret/PII réel ne doit figurer dans les fixtures (utiliser des données
  synthétiques type « Awa » du PRD, jamais de vraie PII).
- **Budget ≤ 500 Kio :** le dossier de référence doit rester petit ; la garde `RecordSizeGuard` est
  déjà exercée par #18. Optionnellement, une variante peut vérifier qu'une note ajoutée à un dossier
  proche du plafond lève `RecordFullException` plutôt que de perdre la note — mais c'est secondaire
  pour #20.
- **Images lourdes :** hors périmètre (M3/#23) ; le dossier de fixture n'embarque que des `imageUrls`
  vides (comportement actuel de `mergeConsultation`).
- **Logs/redaction :** ne jamais imprimer (`print`/log) de clair, de clé, ou de PII dans le test/fakes.

## Testing Plan

L'objet **est** le test, mais préciser la matrice :

- **e2e (nominal), bloquant :** le scénario complet patient→médecin→patient ci-dessus, vert.
- **e2e (variantes) :** QR expiré rejeté (`ExpiredQrCode`) ; fin de session avec backend 5xx →
  `BackendUnavailable` propagé **et** RAM wipée ; (optionnel) note sur dossier saturé → `RecordFullException`.
- **Assertions d'invariants :** identité des blobs aux frontières PUT/GET ; append-only de l'historique ;
  opacité côté serveur (clair absent de la map) ; wipe clé + blob.
- **Non-régression unitaire :** si le refactor du module de support est fait, **toutes** les suites
  unitaires existantes (`test/doctor/**`, `test/qr/**`, `test/record/**`, `test/cloud/**`) doivent
  rester vertes — aucune assertion modifiée.
- **Lint/format :** `dart format --output=none --set-exit-if-changed .` et `flutter analyze` propres
  (Flutter 3.41.5 : traiter les `info` comme bloquants ; respecter les pièges d'indentation documentés
  dans le mémoire `project-backlog-state`).
- **Commande :** `cd app-patient && flutter test` (job `flutter` de la CI). Noter que `just test`
  *skippe* `flutter test` si le SDK est absent — l'e2e ne s'exécute donc réellement que dans le job
  `flutter` de la CI, qui pin Flutter 3.41.5.
- **Hors périmètre de ce test, à tracer :** un e2e *device-backed* (vrai `crypto-core` natif via FRB,
  vrai scan caméra, `flutter_secure_storage`) sous `app-patient/integration_test/` — suivi dépendant
  de #1 + d'une `crypto-core` compilée + d'un émulateur en CI.

## Documentation Updates

- **BACKLOG.md :** ajouter une ligne *Avancement* sous #20 (comme #8/#18) une fois le test livré,
  et — si pertinent — cocher l'enchaînement M2 « premier end-to-end atteint ».
- **`app-patient/README.md` :** documenter la commande de l'e2e et la nature « à fakes » du test
  (préciser qu'il ne valide pas la crypto réelle, renvoyer vers `crypto-core` #10 et l'e2e device-backed à venir).
- **Mémoire `project-backlog-state.md` :** ajouter #20 au tableau de livraison une fois mergé.
- **ADR :** aucun nouvel ADR requis (pas de décision d'architecture nouvelle). Si le module de support
  de test devient une convention, une note dans `CONTRIBUTING.md` (section tests) suffit.
- **Pas de mise à jour PRD** (aucun changement d'exigence).

## Risks and Open Questions

1. **« Le patient voit la mise à jour » — mécanisme réel non implémenté (principal).** Le blob serveur
   en fin de session est chiffré avec la **clé de session** éphémère, alors que la sauvegarde
   patient (#14) est chiffrée avec la **clé maître**. Aucune issue ne couvre aujourd'hui la
   ré-importation/ré-chiffrement master-key de l'update post-consultation dans le dossier local du
   patient. **Décision à confirmer :** l'e2e prouve l'« observabilité » via re-déchiffrement *clé de
   session* (fidèle au code actuel, recommandé) — **ne pas** simuler un ré-chiffrement master-key
   inexistant. Recommander la création d'une issue de suivi (« sync patient post-consultation ») et
   l'y renvoyer en commentaire de test.
2. **Honnêteté du fake crypto.** Le XOR ne prouve ni l'authentification GCM, ni le rejet « mauvaise
   clé », ni le format `nonce||ct||tag`. Risque : surinterprétation comme preuve crypto. *Mitigation :*
   commentaire d'en-tête explicite + renvoi vers #10 et l'e2e device-backed.
3. **Place du test côté patient, pas `app-medecin`.** La logique « médecin » vit dans `app-patient/`.
   À confirmer que c'est volontaire/acceptable pour #20 (ce l'est, vu le code livré) ; sinon, l'e2e
   devrait migrer quand/si la boucle est portée vers `app-medecin`.
4. **Refactor des fakes dupliqués.** Bénéfique mais introduit du churn dans des suites vertes. *Option :*
   livrer l'e2e avec ses propres fakes dans `test/support/`, puis migrer les unitaires dans un PR
   séparé pour garder #20 (effort S) focalisé.
5. **Stack non figée (#1).** Si #1 change le toolchain de test ou déplace la logique médecin,
   l'emplacement/commande de l'e2e devra suivre. Documenté comme dépendance, pas comme blocage.
6. **`DateTime.now()` dans `QrPayload`/`AccessTokenService`.** L'expiration et `exp` reposent sur
   l'horloge réelle ; l'e2e nominal génère un TTL de 120 s frais (non flaky). La variante « expiré »
   doit construire la chaîne QR avec un `exp` passé **explicite** (via `QrPayload(...).toQrString()`)
   plutôt que d'attendre 120 s.

## Implementation Checklist

1. Lire les services réels #16–#19 et `BackendClient`/`MedicalRecord` (liste « Affected Files ») pour
   câbler exactement leurs signatures.
2. Créer `app-patient/test/support/consultation_loop_harness.dart` :
   - `FakeCryptoCore` (XOR 0x5A, `encrypt==decrypt`) + `FakeMasterKeyHandle` (repris des unitaires) ;
   - `FakeBlobBackend` : `MockClient` avec `Map<String,Uint8List>` stateful (PUT stocke une copie/200-201,
     GET renvoie/404), exposant la map pour assertions ;
   - fabrique d'un `MedicalRecord` de référence synthétique (1 consultation, allergies, pas de PII réelle)
     et d'un `MedicalRecordStore` fake renvoyant ce dossier pour `AccessTokenService`.
3. Créer `app-patient/test/e2e/consultation_loop_e2e_test.dart` avec en-tête de commentaire listant les
   propriétés vérifiées **et** la mise en garde « test de câblage, pas de preuve crypto ».
4. Écrire le test nominal enchaînant : `generate` (patient) → `toQrString` → `parseQr` →
   `fetchAndDecrypt` (médecin) → `mergeConsultation` + `reEncrypt` → `ConsultationSession.applyMerge`
   → `SessionEndService.terminate` → re-`fetchAndDecrypt` (patient, **objet `QrPayload` distinct**
   construit depuis la même chaîne QR — option A).
5. Ajouter les assertions transverses : identité des blobs aux frontières, append-only
   (`consultations.length` +1, historique/`createdAt`/`patientId` intacts), opacité côté serveur
   (clair absent de la map), wipe (clé + `pendingBlob` à zéro après `terminate`).
6. Ajouter les variantes : QR expiré → `ExpiredQrCode` ; (optionnel) backend 5xx en fin de session →
   `BackendUnavailable` + RAM wipée.
7. Lancer `cd app-patient && flutter test` ; corriger jusqu'au vert.
8. Lancer `dart format --output=none --set-exit-if-changed .` et `flutter analyze` ; corriger les
   `info`/format (pièges du mémoire `project-backlog-state`).
9. (Optionnel, PR séparé) migrer les `_FakeCryptoCore` dupliqués des unitaires vers le module de
   support, en vérifiant que toutes les suites restent vertes.
10. Mettre à jour la doc : ligne *Avancement* sous #20 dans `BACKLOG.md`, note e2e dans
    `app-patient/README.md`, entrée #20 dans le mémoire `project-backlog-state.md`.
11. (Suivi, hors #20) ouvrir une issue « sync patient post-consultation » (ré-import master-key) et une
    issue « e2e device-backed » (crypto-core natif + scan réel), et y renvoyer en commentaire du test.
```
