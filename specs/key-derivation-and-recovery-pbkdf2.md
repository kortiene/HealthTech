# Dérivation & récupération de clé (PBKDF2 + questions culturelles) (#12)

> **Issue :** #12 — Dérivation & récupération de clé (PBKDF2 + questions culturelles) · **Épic :** E5 — Cœur cryptographique · **Jalon :** M1 — Cœur cryptographique & onboarding patient · **Effort :** M · **Priorité :** Must · **Étiquettes :** `security` `ux` `crypto` · **Implémente :** US-1.4
>
> **Type :** spec de planification — **ne pas implémenter** dans cette phase. Aucune opération git/GitHub.
>
> **Critères d'acceptation (BACKLOG / issue) :** (1) **restauration réussie sur un nouvel appareil** à partir de la phrase de passe / des réponses ; (2) **paramètres résistants au brute-force documentés**.
>
> **Dépend de :** #6 (modèle de menace, *merged*), #11 (clé maîtresse locale & scellement matériel, *implement done*). **Réutilise :** #10 (AES-256-GCM, `crypto-core`). **Débloque le backstop de :** #13 (onboarding), #14 (sauvegarde cloud ZK).

## Problem Statement

HealthTech est **local-first / zero-knowledge** : la racine de confiance est la **clé maîtresse AES-256** générée sur l'appareil du patient et scellée dans le keystore matériel (#11, ADR 0006). Ce scellement matériel est excellent contre le vol de téléphone, mais il crée un **point de défaillance unique** : si le téléphone est perdu, volé, cassé, ou si la clé matérielle est invalidée (mise à jour OS, ré-enrôlement biométrique, OEM TEE qui efface ses clés sur les Infinix bas de gamme — cf. ADR 0006 « Negative / risks »), le patient est **verrouillé hors de toutes ses données de santé**. Le serveur ne peut pas l'aider : par construction zero-knowledge, il ne détient que des blobs opaques indéchiffrables.

US-1.4 exige donc un **backstop de récupération** : « récupérer mes données sur un nouveau téléphone si je perds le mien », via une **dérivation de clé PBKDF2** basée sur une **phrase de passe** ou des **questions de sécurité adaptées au contexte ivoirien**.

**État actuel (le gap, cœur de #12) :**

- `crypto-core/src/lib.rs` expose déjà `derive_key(passphrase, salt, iterations) -> [u8; 32]` (PBKDF2-HMAC-SHA256 via RustCrypto `pbkdf2` 0.12 + `sha2`). **Mais** il n'est aujourd'hui que **smoke-testé** (`derive_key_is_deterministic`) : pas de vecteurs RFC 6070 / NIST gatant le build, **aucun paramètre de coût calibré** (l'appelant passe `iterations` librement), et **aucune politique** (salt, normalisation, format de stockage).
- Le TODO explicite est posé dans le code (`crypto-core/src/lib.rs`, fin du module) : *« add the RFC 6070 / NIST PBKDF2-HMAC-SHA256 known-answer vectors as GATING CI tests… calibrate the default iteration count on entry-level Android… evaluate Argon2id if the PRD's "PBKDF2" wording is relaxed »*.
- Côté app patient, `master_key_service.dart` **expose déjà le point d'accroche** : `MasterKeyState.invalidated` et la doc « route to the PBKDF2 recovery flow (#12) » ; `SealedBlobStore.delete()` est annoté « used on crypto-erase / **recovery reset** ». **Mais le flux de récupération lui-même n'existe pas** : ni dérivation côté Dart, ni écran, ni enveloppe de récupération, ni mécanisme pour **retrouver et déchiffrer** la clé maîtresse sur un appareil neuf.

**Le manque conceptuel central** : une clé maîtresse aléatoire scellée *uniquement* en matériel n'est **pas récupérable** — il n'y a rien à re-dériver. #12 doit introduire une **enveloppe de récupération** : la clé maîtresse est *aussi* chiffrée sous une clé dérivée du secret mémorisable du patient (PBKDF2), et ce blob de récupération est plaçable hors de l'appareil pour survivre à sa perte. La récupération = retrouver ce blob, le déchiffrer avec la clé re-dérivée, puis re-sceller la clé maîtresse dans le matériel du **nouvel** appareil.

## Goals

- **G1 — Récupérabilité (critère #1).** Depuis un appareil neuf, le patient restaure l'accès à sa clé maîtresse (et donc à son dossier) en saisissant sa phrase de passe **ou** ses réponses aux questions culturelles, **sans** que la clé matérielle d'origine ait jamais quitté l'ancien appareil.
- **G2 — Enveloppe de récupération.** La clé maîtresse (DEK racine) est chiffrée AES-256-GCM (#10) sous une **clé de récupération** dérivée par PBKDF2 ; seul ce blob chiffré est conservé hors de l'appareil. Le secret mémorisable n'est **jamais** stocké, ni en clair ni dérivé.
- **G3 — Calibration anti-brute-force (critère #2).** Le nombre d'itérations PBKDF2-HMAC-SHA256 est **calibré par classe d'appareil** (cible : téléphone d'entrée de gamme type Infinix) pour un coût UX acceptable tout en maximisant la résistance au brute-force hors-ligne d'un secret à **faible entropie** (réponses culturelles). Les paramètres et leur justification sont **documentés** (ADR + matrice de conformité).
- **G4 — Paramètres versionnés & forward-tunables.** `salt` (public, aléatoire ≥ 16 o), `iterations`, l'algorithme et la version du schéma sont **stockés avec** le blob de récupération (jamais devinés), pour permettre l'augmentation des itérations dans le temps et une éventuelle migration KDF (ADR 0003).
- **G5 — Vecteurs de test gatants.** Ajouter les vecteurs **RFC 6070** (et/ou équivalents NIST) PBKDF2-HMAC-SHA256 comme **tests gatants CI** sur `crypto-core`, prouvant `derive_key` contre la spec et non seulement contre lui-même.
- **G6 — Normalisation déterministe & robuste des réponses.** Les réponses aux questions sont normalisées (casse, espaces, accents/diacritiques, ponctuation) de façon **stable et reproductible** entre l'ancien et le nouvel appareil, pour que la dérivation soit fiable malgré les variations de saisie — sans pour autant détruire l'entropie résiduelle.
- **G7 — Questions adaptées au contexte ivoirien.** Un jeu de questions de sécurité culturellement pertinentes (FR, et termes locaux), choisies pour la **mémorabilité durable** *et* la **non-devinabilité** par un proche/attaquant ; phrase de passe recommandée comme option à plus haute entropie.
- **G8 — Pas de fuite de secret.** Aucun secret mémorisable, aucune clé dérivée, aucune clé maîtresse en clair n'est journalisé, persisté en clair, ni envoyé au serveur (zero-knowledge). Buffers `zeroize`-és (réutiliser `wipe`/`Zeroizing` de `crypto-core`).
- **G9 — Routage du cycle de vie.** Brancher la récupération sur l'état `MasterKeyState.invalidated`/`absent` déjà exposé par `master_key_service.dart`, et sur `SealedBlobStore.delete()` (reset de récupération) ; après récupération réussie, **re-sceller** la clé maîtresse dans le keystore matériel du nouvel appareil (#11).
- **G10 — Anti-énumération / limitation de tentatives.** Décourager le brute-force en ligne du blob de récupération (si stocké côté serveur) : rate-limiting, pas d'oracle d'existence, lookup ID non corrélable à une PII (cf. *Risks*).

## Non-Goals

- **Génération & scellement matériel de la clé maîtresse (#11)** — déjà livré ; #12 le *consomme* (re-seal après récupération) mais ne le réécrit pas.
- **Module AES-256-GCM (#10)** — réutilisé tel quel pour chiffrer/déchiffrer l'enveloppe de récupération ; aucune modification du format de fil frozen.
- **Parcours d'onboarding / création de compte (#13)** — #13 déclenchera la *mise en place* du secret de récupération (choix passphrase/questions) ; #12 fournit le moteur de dérivation, l'enveloppe et l'écran de **restauration**, pas tout l'onboarding nominatif.
- **Sauvegarde cloud du dossier (#14) & service blob ZK (#9)** — #12 peut **réutiliser** le canal de stockage opaque par UUID pour le blob de récupération, mais la sauvegarde du dossier médical lui-même reste #14. Si #12 écrit un blob de récupération côté serveur, c'est un nouvel objet, distinct du blob de dossier.
- **QR éphémère / session médecin (#16/#17)** — chemin médecin, clé de session distincte ; sans rapport avec la récupération patient.
- **Migration vers Argon2id** — hors périmètre tant que la formulation « PBKDF2 » du PRD n'est pas relâchée ; à *préparer* via le champ de version (G4), pas à implémenter (cf. *Risks*).
- **Rotation/ révocation périodique de la clé maîtresse** — non requis par US-1.4.
- **Toute opération git/GitHub.**

## Relevant Repository Context

**Statut « stack non finalisée (#1) » — à nuancer.** Le BACKLOG décrit un projet greenfield à stack ouverte, mais à la date de cette spec **#1 est tranché** (ADR 0001–0009 *Accepted*). Décisions déjà prises et pertinentes pour #12 :

- **Cœur crypto : Rust `crypto-core`** (ADR 0003) — seul lieu d'AES/PBKDF2. `derive_key()` (PBKDF2-HMAC-SHA256), `encrypt_record`/`decrypt_record` (AES-256-GCM, format `nonce||ct||tag`, overhead 28 o, **pas de version byte** en v1), `wipe()`/`Zeroizing` existent déjà. Lints : `#![forbid(unsafe_code)]` + `#![deny(warnings)]`. ADR 0003 fixe : *« la valeur d'itération PBKDF2 est benchmarkée sur Android d'entrée de gamme et stockée à côté du salt »* et *« les vecteurs PBKDF2-HMAC-SHA256 sont des tests gatants CI »*.
- **App patient : Flutter/Dart, `minSdk 24`** (ADR 0001). **Aucun chiffrement en Dart** : la dérivation PBKDF2 doit passer par `crypto-core` via `flutter_rust_bridge` (FRB), pas par un paquet Dart. La FRB n'est pas encore générée (`crypto_core_bindings.dart` est un *seam* hand-written + impl `FrbCryptoCore` qui throw `CryptoCoreUnavailable`).
- **Gestion de clés (ADR 0006) :** enveloppe matérielle (KEK Keystore non-exportable) pour l'usage quotidien ; **PBKDF2 = backstop** explicite en cas de perte de la clé matérielle. Le master key wrappe la clé de DB SQLCipher et les clés par enregistrement.
- **Modèle de menace (#6, *merged*) :** inclut explicitement *« attaque sur la phrase de passe de récupération »* — #12 est la contre-mesure ; chaque choix (itérations, normalisation, anti-énumération) doit être traçable vers cette menace.

**Scaffold existant à reprendre (ne pas réécrire) :**

| Fichier | Rôle actuel | Action #12 |
| --- | --- | --- |
| `crypto-core/src/lib.rs` | `derive_key` réel mais smoke-testé ; `TODO(#12)` posé | Ajouter vecteurs RFC 6070/NIST **gatants** ; figer paramètres/politique ; éventuel helper d'enveloppe de récupération (additif, sans casser l'API #10) |
| `crypto-core/tests/` (+ `tests/vectors/`) | KAT AES-GCM (#10) + `PROVENANCE.md` | Ajouter un fichier de vecteurs PBKDF2 + provenance, sur le modèle de `nist_aes256gcm.rs` |
| `app-patient/lib/src/secure/master_key_service.dart` | `MasterKeyState.invalidated` → « route to #12 » ; `unsealForUse`, `ensureMasterKey` | Ajouter le flux de récupération (dérivation → décryptage enveloppe → re-seal) |
| `app-patient/lib/src/secure/sealed_blob_store.dart` | `delete()` « recovery reset » | Réutiliser pour reset ; éventuel store du blob de récupération |
| `app-patient/lib/src/rust/crypto_core_bindings.dart` | seam FRB (`CryptoCore`), pas de `deriveKey` exposé | Étendre l'interface avec `deriveKey`/helper d'enveloppe (FFI minimal, ADR 0003) |
| `app-patient/lib/main.dart` + `app-patient/test/…` | squelette + tests host-only | Câblage minimal + tests Dart avec fake core |

**Conventions observées (à respecter) :** specs en **prose FR, titres EN** (cf. specs existantes) ; `TODO(#n)` traçant les dépendances inter-issues ; docs de module Rust en `//!` ; vecteurs de test avec `PROVENANCE.md` ; pas de toolchain Rust/Flutter garantie dans la phase ADW (écrire conforme `rustfmt`/`flutter analyze`, gates exécutés ailleurs) ; gate canonique `just test` (+ `flutter test`/`flutter analyze` côté app — à confirmer dans le `justfile`).

## Proposed Implementation

**Principe directeur : enveloppe de récupération (« recovery wrap »).** La clé maîtresse aléatoire (#11) reste la racine ; #12 ajoute une **deuxième manière de la déchiffrer**, à partir d'un secret mémorisable, indépendante du matériel.

### Modèle de données de confiance

1. **Secret mémorisable** : soit une **phrase de passe** (option à plus haute entropie, recommandée), soit un jeu de **réponses aux questions culturelles** concaténées après **normalisation déterministe** (G6).
2. **Clé de récupération (KEK de récupération)** : `recovery_key = PBKDF2-HMAC-SHA256(secret_normalisé, salt, iterations)` (32 o), via `crypto-core::derive_key`. `salt` aléatoire ≥ 16 o, **public**, stocké avec l'enveloppe.
3. **Enveloppe de récupération** : `recovery_blob = encrypt_record(recovery_key, master_key_clear)` (AES-256-GCM #10). Seul ce blob (chiffré) quitte potentiellement l'appareil ; **jamais** la clé maîtresse en clair, **jamais** le secret.
4. **Métadonnées d'enveloppe (en clair, non secrètes)** : `version`, `kdf = pbkdf2-hmac-sha256`, `iterations`, `salt`, identifiant du jeu de questions (si applicable). Permet la re-dérivation exacte et la montée future d'itérations / migration KDF (G4).

### Flux de mise en place (déclenché par l'onboarding #13, moteur fourni ici)

```
1. Master key déjà générée & scellée matériellement (#11).
2. Patient choisit passphrase OU répond aux questions culturelles.
3. normalize(secret) -> salt aléatoire -> recovery_key = deriveKey(secret, salt, iters)  [Rust]
4. master_key_clear = unseal(#11) en RAM (handle Rust)
5. recovery_blob = encryptRecord(recovery_key, master_key_clear)                          [Rust, #10]
6. persister { version, kdf, iters, salt, recovery_blob } hors-appareil (voir Décision ci-dessous)
7. wipe(recovery_key), wipe(master_key handle), zeroize buffers Dart best-effort
```

### Flux de restauration sur appareil neuf (cœur du critère #1)

```
1. Aucune master key locale -> MasterKeyState.absent ; l'UI propose « Restaurer mon compte ».
2. Patient saisit passphrase / réponses.
3. Récupérer { version, kdf, iters, salt, recovery_blob } (lookup, voir Décision).
4. recovery_key = deriveKey(normalize(secret), salt, iters)                                [Rust]
5. master_key_clear = decryptRecord(recovery_key, recovery_blob)                           [Rust, #10]
     -> échec d'authentification GCM = mauvais secret (erreur coarse, pas d'oracle).
6. re-seal master_key_clear dans le keystore matériel du NOUVEL appareil (#11, MethodChannel)
7. persister le nouveau sealed blob ; wipe tous les clairs.
8. (Plus tard, #14) télécharger & déchiffrer le dossier avec la master key restaurée.
```

> **Décision ouverte — emplacement & lookup du `recovery_blob` (voir *Risks*).** Pour survivre à la **perte** de l'appareil, l'enveloppe ne peut pas vivre uniquement sur l'ancien téléphone. Options :
> - **(A, recommandé) Côté serveur ZK (#9), objet opaque par UUID anonyme**, distinct du blob de dossier. Le nouvel appareil doit pouvoir **retrouver** l'objet : dériver un *recovery lookup ID* déterministe à partir d'un identifiant que le patient re-saisit (ex. n° CMU/téléphone) **+** un sel/poivre — jamais à partir du secret de déchiffrement lui-même, et non corrélable à une PII en clair côté serveur. Impose un **rate-limiting** anti-brute-force en ligne (G10) et **aucun oracle d'existence**.
> - **(B) Kit de récupération hors-ligne** : QR/feuille imprimée encodant `{salt, iters, recovery_blob}` que le patient conserve physiquement. Zéro dépendance serveur, mais friction UX et risque de perte/vol du papier.
> - **(C) Hybride** : (A) par défaut + (B) en option avancée.
> Recommandation : **(A)** alignée sur l'architecture ZK existante, avec **(B)** en option. À trancher avec #9/#14 et le volet conformité.

### Côté Rust (`crypto-core`)

- **Figer la politique PBKDF2** : documenter en `//!`/doc-comments que `salt` est public et obligatoire (≥ 16 o aléatoire), que `iterations` est stocké avec l'enveloppe, et la **valeur par défaut calibrée** (constante `RECOVERY_PBKDF2_DEFAULT_ITERS`, *valeur à fixer après benchmark* — cf. G3 / *Risks*). Ne pas coder en dur une valeur non benchmarkée sans l'annoter clairement.
- **Vecteurs gatants** (G5) : ajouter `crypto-core/tests/pbkdf2_rfc6070_vectors.rs` + `tests/vectors/` avec `PROVENANCE.md`, sur le modèle de `aes_gcm_nist_vectors.rs`. Utiliser les vecteurs **RFC 6070** ; comme RFC 6070 est PBKDF2-HMAC-**SHA1**, fournir en complément des vecteurs PBKDF2-HMAC-**SHA256** de provenance documentée (réimplémentation indépendante / valeurs publiées) puisque c'est l'algo réellement utilisé. Documenter clairement la provenance comme pour #10.
- **Helper d'enveloppe (optionnel, additif)** : éventuel `derive_recovery_key`/wrapper documentant le couplage `derive_key` + `encrypt_record`, **sans** casser l'API #10/#11 (introduction additive uniquement, comme pour les `TODO` déjà posés). La normalisation des réponses (G6) peut vivre côté Rust (déterministe, testable) plutôt que Dart.
- **Hygiène** : `recovery_key` dans `Zeroizing`, `wipe` après usage ; conserver `#![forbid(unsafe_code)]`/`#![deny(warnings)]`.

### Côté Dart (app patient)

- Étendre le seam `CryptoCore` (`crypto_core_bindings.dart`) avec `deriveKey(secret, salt, iters)` (et/ou le helper d'enveloppe), délégué à la FRB ; **pas de PBKDF2 en Dart**.
- Étendre `MasterKeyService` : `setUpRecovery(secret, …)` (mise en place) et `recoverFromSecret(secret, …)` (restauration → re-seal via `KeystoreChannel.seal` → `SealedBlobStore.write`). Réutiliser `probeState()`/`MasterKeyState` et `SealedBlobStore.delete()` (reset).
- Erreurs typées : mauvais secret → exception dédiée mappée sur l'erreur **coarse** `CryptoError::Decrypt` (pas d'oracle), distinct de « enveloppe introuvable » côté lookup.

### Côté UX (questions culturelles, G7)

- Proposer **phrase de passe** (recommandée) **ou** **N questions** parmi un jeu adapté au contexte ivoirien (FR + termes locaux), choisies pour mémorabilité durable et non-devinabilité (éviter les infos publiques/devinables par un proche). Exiger un nombre minimal de questions et/ou un seuil d'entropie estimé.
- Indiquer clairement la conséquence : **secret perdu = données irrécupérables** (zero-knowledge, le serveur ne peut pas aider).
- Localisation : libellés en français ; prévoir l'extension à des langues locales (décision produit). La **normalisation** (G6) doit gérer accents/diacritiques pour fiabiliser la ressaisie.

## Affected Files / Packages / Modules

À lire / modifier / créer :

- `crypto-core/src/lib.rs` — figer la politique PBKDF2 (salt, défaut d'itérations calibré, doc) ; éventuel helper d'enveloppe additif ; normalisation des réponses ; mettre à jour le `TODO(#12)`.
- `crypto-core/tests/pbkdf2_rfc6070_vectors.rs` (**nouveau**) + `crypto-core/tests/vectors/` (**nouveau** fichier de vecteurs + `PROVENANCE.md`) — vecteurs gatants RFC 6070 / SHA256.
- `crypto-core/README.md` — documenter la dérivation de récupération, les paramètres, le statut « calibré » (remplacer la mention « calibration deferred to #12 »).
- `app-patient/lib/src/rust/crypto_core_bindings.dart` — exposer `deriveKey`/helper d'enveloppe dans le seam `CryptoCore` + `FrbCryptoCore`.
- `app-patient/lib/src/secure/master_key_service.dart` — `setUpRecovery` / `recoverFromSecret` ; re-seal post-récupération ; routage `MasterKeyState`.
- `app-patient/lib/src/secure/sealed_blob_store.dart` — réutilisé pour reset/persistance ; éventuel store dédié du `recovery_blob` (option B).
- `app-patient/lib/src/secure/recovery_*.dart` (**nouveau**) — modèle d'enveloppe de récupération (version/kdf/iters/salt/blob), normalisation, lookup.
- `app-patient/lib/main.dart` + écrans de restauration/mise en place (squelette ; UI complète relève de #13/#28).
- `app-patient/test/secure/…` (**nouveau**) — tests Dart (fake `CryptoCore`, round-trip set-up→recover, mauvais secret, normalisation).
- `app-patient/pubspec.yaml` — dépendances si nécessaires (aucune lib crypto Dart).
- `backend/…` — **uniquement si** l'option (A) est retenue : un nouvel objet « recovery blob » opaque par UUID (réutilise le service #9 ; à cadrer avec #9/#14).
- ADR 0003 / 0006 — annoter les paramètres PBKDF2 retenus et la décision d'emplacement de l'enveloppe.
- `docs/compliance/controles.md` + matrice loi 2013-450 — preuve « récupération sans que le serveur puisse lire ni la clé ni le dossier ».
- `SECURITY.md` / threat model #6 — confirmer la contre-mesure « attaque sur la phrase de passe de récupération ».

## API / Interface Changes

- **FFI / FRB (Dart↔Rust)** — *nouveau* : `deriveKey(secretBytes, salt, iterations) -> 32 bytes` exposé via le seam `CryptoCore` (et impl FRB) ; éventuel helper d'enveloppe `deriveRecoveryKey`/wrap. Surface volontairement minimale (ADR 0003), **pas de crypto Dart**.
- **API publique Dart** : `MasterKeyService.setUpRecovery(...)` et `MasterKeyService.recoverFromSecret(...)` ; nouvelles exceptions typées (mauvais secret vs enveloppe introuvable). À documenter (commentaires d'API + README app-patient).
- **Rust public API** : `derive_key` reste, sa **politique/paramètres** sont figés et documentés ; éventuels helpers **additifs** (l'API #10/#11 n'est pas cassée).
- **Endpoint réseau / blob** : **dépend de la décision d'emplacement.** Si option (A), un **nouveau** point d'accès « recovery blob » (PUT/GET opaque par UUID, réutilisant le contrat #9) + un **lookup ID anonyme** ; aucun secret/PII en clair. Si option (B/offline), **none**. À trancher (voir *Risks*).
- **QR / access-token** : **none** (la récupération n'est pas le partage médecin). Si l'option (B) encode l'enveloppe en QR, c'est un **kit de récupération** local, distinct du QR d'accès éphémère (#16).

## Data Model / Protocol Changes

- **Enveloppe de récupération (nouveau format, local et/ou serveur)** : structure auto-décrite, ex.
  `version(1o) || kdf_id(1o) || iterations(u32) || salt_len(1o) || salt(≥16o) || recovery_blob`
  où `recovery_blob = nonce(12) || ciphertext(32) || tag(16)` = `encrypt_record(recovery_key, master_key)` au format #10. Le **byte de version** est recommandé ici (contrairement au format de fil #10 sans version) car ce format doit pouvoir migrer (montée d'itérations, futur Argon2id) — *à confirmer*.
- **`salt` & `iterations` stockés en clair** avec l'enveloppe (non secrets, requis pour re-dériver) — G4.
- **Aucun changement du format de fil zero-knowledge #9/#10** (`nonce||ct||tag`) ; le `recovery_blob` *réutilise* ce format mais sous une clé différente.
- **Aucune persistance du secret mémorisable ni de la clé dérivée** — par construction (G8).
- **Si option (A)** : nouvel objet serveur opaque par UUID + champ de lookup anonyme ; aucune corrélation PII↔blob côté serveur. À cadrer avec le schéma #9.

## Security & Compliance Considerations

- **Zero-knowledge préservé :** le serveur ne reçoit, au plus, que des **blobs opaques** (enveloppe de récupération chiffrée + dossier #14) indexés par UUID anonyme. La clé de récupération et la clé maîtresse en clair **ne quittent jamais l'appareil** ; le serveur **ne peut ni dériver le secret ni déchiffrer** quoi que ce soit. À tracer dans la matrice ARTCI.
- **Résistance au brute-force (critère #2 — à documenter) :** le secret est potentiellement à **faible entropie** (réponses culturelles), donc l'attaque dominante est le **brute-force hors-ligne** du `recovery_blob` exfiltré. Contre-mesures et leur documentation :
  - **Itérations PBKDF2 calibrées** au maximum compatible avec l'UX sur entrée de gamme (G3) ; valeur **stockée et forward-tunable** (G4). Documenter le coût attaquant estimé (itérations × coût/hash × taille d'espace de réponses).
  - **Préférer la phrase de passe** (entropie ≫ questions) et **plusieurs questions** combinées ; estimer/forcer un seuil d'entropie minimal côté UX.
  - **Salt aléatoire ≥ 16 o par patient** (anti-rainbow-table) ; envisager un **poivre (pepper)** côté app/binaire pour relever la barre (décision, *Risks*).
  - **Erreur coarse, pas d'oracle** : un mauvais secret produit l'échec d'authentification GCM indifférencié de #10 (pas de distinction clé/tag/blob).
  - **Anti-brute-force en ligne** (si option A) : rate-limiting serveur, pas d'oracle d'existence, lookup ID non corrélable (G10).
  - **Honnête sur la limite** : PBKDF2 n'est **pas mémoire-dur** ; documenter qu'Argon2id serait plus fort si la formulation PRD était relâchée (préparé par le champ version, non implémenté ici).
- **Pas de fuite (G8) :** ne **jamais** journaliser secret, réponses, clé dérivée, clé maîtresse, ni le `recovery_blob` ; `zeroize`/`Zeroizing` côté Rust, overwrite best-effort côté Dart (limite `Uint8List` connue, ADR 0001). Pas de secret dans les rapports de crash.
- **Re-seal matériel post-récupération (#11) :** après restauration, re-sceller immédiatement la clé maîtresse dans le keystore du nouvel appareil ; ne pas laisser le clair en RAM au-delà du nécessaire ; gérer l'absence de keystore matériel (échec typé, pas de repli logiciel).
- **Accès éphémère médecin (QR ~120 s, RAM-only, wipe fin de session)** : hors périmètre #12 (ne pas confondre avec la récupération patient).
- **Résidence des données (ARTCI / loi n°2013-450) :** si l'enveloppe est stockée côté serveur (option A), elle réside sur le sol ivoirien (#8) comme tout autre blob ; tracer la preuve. Aucune donnée nominative en clair ne transite (US-1.1).
- **Budget ≤ 500 Ko & images lourdes :** non concernés (#12 manipule une clé de 32 o et un petit blob d'enveloppe) ; les contraintes restent portées par #14/#15/#23.
- **Disponibilité vs confidentialité :** un secret perdu = **données irrécupérables** (propriété voulue du zero-knowledge). L'UX doit le dire clairement ; envisager (option B) un kit hors-ligne pour réduire le risque de lockout sur les TEE qui effacent leurs clés (ADR 0006).

## Testing Plan

- **Crypto-vectors (Rust, gatants — G5) :** vecteurs **RFC 6070** + PBKDF2-HMAC-SHA256 (provenance documentée) ; `derive_key` byte-exact contre la spec ; ces tests **bloquent le build** (ADR 0003), à l'image des KAT AES-GCM de #10.
- **Unit (Rust) :** déterminisme (`derive_key` même entrées ⇒ même clé) ; sensibilité au salt et aux itérations ; round-trip enveloppe (`derive_key` → `encrypt_record` → `decrypt_record` restitue la clé maîtresse) ; mauvais secret ⇒ `CryptoError::Decrypt` ; normalisation des réponses (idempotente, stable accents/casse/espaces) ; `wipe` effectif.
- **Unit (Dart) :** avec **fake `CryptoCore`** — `setUpRecovery` → `recoverFromSecret` round-trip ; mauvais secret ⇒ exception typée (pas d'oracle) ; enveloppe introuvable ⇒ exception distincte ; re-seal appelé après récupération (mock `KeystoreChannel`) ; `SealedBlobStore` mis à jour ; **aucun secret/clé dans les logs**.
- **Integration / E2E (critère #1) :** simuler **appareil A** (set-up) → perte → **appareil B** (restauration) : la clé maîtresse restaurée déchiffre un dossier chiffré sur A (réutilise #10/#14). À automatiser quand FRB + harness mobile dispo (device lab #29) ; sinon test host-only sur le moteur Rust/fake.
- **Résistance brute-force (documentation + micro-bench) :** mesurer le temps de `derive_key` à l'itération calibrée sur classe entrée de gamme ; documenter le coût attaquant ; **garde-fou CI** sur la valeur minimale d'itérations (anti-régression).
- **Résilience / dégradé :** set-up et restauration **hors-ligne** si option (B) ; si option (A), comportement en réseau coupé (file d'attente / retry) ; interruption pendant le re-seal ⇒ état cohérent (pas de clé partiellement scellée inutilisable).
- **Sécurité / non-fuite :** test prouvant qu'aucun log n'émet secret/clé/blob/PII ; (si faisable) inspection mémoire post-récupération.
- **Documentation :** vérifier que README + ADR documentent les paramètres anti-brute-force (critère #2).

## Documentation Updates

- **ADR 0003** : remplacer « PBKDF2 iteration count benchmarked… » (intention) par la **valeur retenue + méthode de benchmark** ; statuer sur Argon2id (préparé, non adopté) ; lier les vecteurs gatants.
- **ADR 0006** : préciser le mécanisme de récupération (enveloppe), l'emplacement du `recovery_blob` (décision A/B/C), et le lien avec `MasterKeyState.invalidated`.
- **`crypto-core/README.md`** : documenter `derive_key` (politique salt/itérations, défaut calibré), le format d'enveloppe, et retirer la mention « calibration deferred to #12 ».
- **`app-patient/README.md`** : documenter `MasterKeyService.setUpRecovery/recoverFromSecret`, le jeu de questions, et la conséquence « secret perdu = données perdues ».
- **`docs/compliance/controles.md` + matrice loi 2013-450** : preuve « récupération zero-knowledge » (US-1.4) — serveur incapable de lire clé/dossier.
- **`SECURITY.md` / threat model #6** : marquer « attaque sur la phrase de passe de récupération » comme couverte, avec les paramètres anti-brute-force.
- **BACKLOG** : éventuelle note sur la décision d'emplacement de l'enveloppe et le couplage #9/#14.

## Risks and Open Questions

1. **Emplacement & lookup du `recovery_blob`** (A serveur ZK / B kit hors-ligne / C hybride) — **décision structurante**, à trancher avec #9/#14 et la conformité. Impacte API réseau, anti-énumération, résilience hors-ligne.
2. **Lookup ID anonyme (option A)** — comment retrouver l'enveloppe sur un appareil neuf sans corréler une PII en clair côté serveur, ni créer un oracle d'existence ? (dérivation depuis n° CMU/téléphone + sel ? rate-limiting ?).
3. **Valeur d'itérations PBKDF2** — non encore benchmarkée sur entrée de gamme (Infinix) ; arbitrage UX (latence acceptable, p.ex. ≤ 1–2 s) vs résistance brute-force d'un secret faible. Doit être **mesurée**, pas devinée (G3). Pas de toolchain mobile dans la phase ADW.
4. **Entropie des questions culturelles** — réponses potentiellement devinables (proche, réseaux sociaux) ou peu stables (orthographe). Combien de questions ? seuil d'entropie ? phrase de passe par défaut ? Arbitrage sécurité ↔ mémorabilité (risque BACKLOG #1 « blocage patient »).
5. **Normalisation des réponses (G6)** — agressive (fiabilité de ressaisie) vs conservatrice (préserver l'entropie) ; gestion des accents/langues locales. À spécifier précisément et tester.
6. **Poivre (pepper) applicatif** — relèverait la barre du brute-force mais complique la portabilité multi-build et la récupération ; à trancher.
7. **PBKDF2 vs Argon2id** — PRD impose « PBKDF2 » ; PBKDF2 n'est pas mémoire-dur. Préparer la migration via le champ version sans l'implémenter ; condition de relâchement de la formulation PRD (ADR 0003).
8. **Provenance des vecteurs SHA256** — RFC 6070 est SHA1 ; sourcer proprement des vecteurs PBKDF2-HMAC-SHA256 (réimplémentation indépendante / valeurs publiées) et le documenter dans `PROVENANCE.md`.
9. **Disponibilité du keystore sur l'appareil neuf** — re-seal impossible si pas de keystore matériel (cohérent avec #11 : échec typé, pas de repli logiciel) ; UX de cet échec.
10. **Couplage #13/#28** — la *mise en place* du secret (choix questions/passphrase) et l'UX fine appartiennent à l'onboarding (#13) et à l'affûtage UX (#28) ; #12 fournit le moteur + l'écran de restauration. Délimiter précisément la frontière.
11. **Toolchain dans la phase ADW** — Rust/Flutter/FRB et device lab non garantis ici ; les benchmarks d'itérations et l'E2E multi-appareils tourneront en CI mobile / device lab (#29).

## Implementation Checklist

1. **Trancher les décisions structurantes** : emplacement de l'enveloppe (A/B/C) + lookup ID anonyme (Q1–Q2) ; option passphrase vs questions et seuil d'entropie (Q4) ; politique de normalisation (Q5) ; pepper oui/non (Q6).
2. **Benchmarker** `derive_key` sur classe d'appareil entrée de gamme (device lab #29) et **fixer** `iterations` par défaut + garde-fou CI (Q3).
3. **Rust `crypto-core`** : figer la politique PBKDF2 (salt ≥ 16 o public obligatoire, défaut calibré documenté, `iterations`/`salt` stockés), ajouter la normalisation déterministe des réponses, éventuel helper d'enveloppe **additif** ; `Zeroizing`/`wipe` ; conserver `#![forbid(unsafe_code)]`/`#![deny(warnings)]` ; mettre à jour `TODO(#12)`.
4. **Vecteurs gatants** : `crypto-core/tests/pbkdf2_rfc6070_vectors.rs` + `tests/vectors/` + `PROVENANCE.md` (RFC 6070 + SHA256, provenance documentée) — build-gating (ADR 0003).
5. **FRB** : exposer `deriveKey`/helper d'enveloppe dans le seam `CryptoCore` + `FrbCryptoCore` (pas de crypto Dart).
6. **Dart `MasterKeyService`** : `setUpRecovery` (dériver → wrap → persister enveloppe) et `recoverFromSecret` (dériver → unwrap → **re-seal #11** → `SealedBlobStore.write`) ; exceptions typées (mauvais secret vs enveloppe introuvable) ; réutiliser `MasterKeyState`/`delete()`.
7. **Modèle d'enveloppe** (`recovery_*.dart`) : sérialisation versionnée `version||kdf||iters||salt_len||salt||recovery_blob` ; lookup selon décision A/B/C.
8. **Backend (si option A)** : objet « recovery blob » opaque par UUID (réutilise #9) + lookup anonyme + rate-limiting ; aucun PII/secret en clair. (Sinon : none.)
9. **UX** : écrans de mise en place (choix passphrase/questions, avertissement « secret perdu = données perdues ») et de restauration ; jeu de questions ivoirien localisé (cadré avec #13/#28).
10. **Tests** : vecteurs gatants ; unit Rust (déterminisme, salt/iters, round-trip enveloppe, mauvais secret coarse, normalisation, wipe) ; unit Dart (fake core, round-trip, mauvais secret, re-seal, no-log) ; E2E A→B (device lab) ; garde-fou CI sur itérations minimales.
11. **Hygiène anti-fuite** : audit des logs (aucun secret/clé/blob/PII), redaction, pas de secret en crash report.
12. **Docs & conformité** : ADR 0003/0006 annotés (paramètres + emplacement), README crypto-core & app-patient, preuve matrice loi 2013-450, note threat model #6.
13. **Gates** : `just test` (Rust) + `flutter analyze`/`flutter test` là où la toolchain est dispo ; documenter ce qui ne tourne pas dans la phase ADW (benchmarks, E2E multi-appareils → CI mobile/device lab).
