# Génération & gestion de la clé maîtresse locale (#11)

> **Issue :** #11 — Génération & gestion de la clé maîtresse locale · **Épic :** E5 — Cœur cryptographique · **Jalon :** M1 — Cœur cryptographique & onboarding patient · **Effort :** M · **Priorité :** Must · **Étiquettes :** `crypto` `security` · **Implémente :** US-1.1
>
> **Type :** spec de planification — **ne pas implémenter** dans cette phase.
>
> **Critères d'acceptation (BACKLOG / issue) :** (1) clé maîtresse **générée et scellée** dans le keystore matériel ; (2) **aucune fuite en mémoire persistante** (ni clair sur disque, ni clé dans les logs, buffers secrets effacés).
>
> **Dépend de :** #6 (modèle de menace, *merged*), #10 (module AES-256-GCM, *implement done*). **Débloque :** #12 (dérivation/récupération PBKDF2), #13 (création de compte chiffré), #14 (sauvegarde cloud ZK, qui consomme l'unseal de la clé de DB SQLCipher).

## Problem Statement

HealthTech est **local-first / zero-knowledge** : le patient « possède » réellement ses données parce que la racine de confiance — sa **clé maîtresse AES-256** — est générée **sur son appareil** et n'en sort jamais en clair (US-1.1, PRD §1 & §4). Toute la chaîne de valeur en dépend : le chiffrement du dossier (#10/#14), la sauvegarde cloud illisible par le serveur (#14), la clé de la base SQLCipher hors-ligne (ADR 0006), et la récupération sur un nouveau téléphone (#12).

Aujourd'hui, le matériel cryptographique brut existe mais **le scellement matériel n'est pas câblé** :

- `crypto-core` (Rust, ADR 0003) expose déjà `generate_master_key() -> [u8; 32]` (CSPRNG OS via `getrandom`) et `wipe(&mut [u8])` (zeroize) — voir `crypto-core/src/lib.rs`.
- Côté Flutter, `app-patient/lib/src/secure/keystore_channel.dart` n'est qu'un **stub** : `sealMasterKey(...)` et `unsealDbKey()` lèvent `UnimplementedError('… TODO(#11)')`. Le `MethodChannel('healthtech/keystore')` est déclaré mais **le code natif Kotlin/iOS n'existe pas**.
- `app-patient/lib/src/rust/crypto_core_bindings.dart` est un **placeholder** : la codegen `flutter_rust_bridge` (FRB) n'a pas été exécutée ; le `TODO(#11)` y liste `generateMasterKey() -> handle opaque` et `wipe(handle)` comme livrables.

**Le gap (cœur de #11) :** relier la **génération** (Rust) au **scellement matériel** (Android Keystore StrongBox/TEE, et amorce iOS Keychain/Secure Enclave) via le shim natif manquant, de sorte que la clé maîtresse soit **générée → scellée → persistée uniquement sous forme scellée**, et que la copie en clair soit **effacée immédiatement** — sans aucune fuite en mémoire persistante.

## Goals

- **G1.** La clé maîtresse 256-bit est **générée sur l'appareil** par le CSPRNG OS, à l'intérieur du cœur Rust, jamais en Dart/Kotlin/JS (ADR 0003).
- **G2.** La clé est **scellée dans le keystore matériel** : Android Keystore avec **StrongBox** quand présent, **repli TEE** sinon, clé de scellement **non-exportable** (`setIsStrongBoxBacked` + `KeyGenParameterSpec`, ADR 0001/0006).
- **G3.** **Pas de repli silencieux logiciel** : si aucun keystore matériel (ni StrongBox ni TEE) n'est disponible, l'opération **échoue bruyamment** (erreur typée remontée à l'UI) plutôt que de sceller dans une clé logicielle.
- **G4.** **Persistance uniquement sous forme scellée** : seul le *blob scellé* (chiffré par la clé matérielle) est écrit sur disque ; la clé maîtresse en clair ne touche jamais le stockage non-volatile.
- **G5.** **Aucune fuite en mémoire persistante** (critère d'acceptation) : la copie en clair côté Rust est `wipe()`-ée dès le scellement ; les copies Dart sont minimisées et le moins durables possible ; **aucune** clé/PII n'est journalisée.
- **G6.** **Idempotence & cycle de vie** : génération **unique** par appareil (ne pas écraser une clé existante) ; opérations `seal` / `unseal` / `exists` / `clear` définies et déterministes.
- **G7.** **Récupérabilité de l'état** : si la clé matérielle est invalidée (mise à jour OS, ré-enrôlement biométrique, OEM TEE qui efface) → état détecté et **dirigé vers le parcours de récupération #12**, sans crash ni perte silencieuse.
- **G8.** Surface FFI **minimale et auditable** : la clé maîtresse en clair **ne traverse pas** la frontière FFI sous forme exploitable plus que nécessaire (privilégier un *handle* opaque + un échange de bytes scellés), conformément à ADR 0003.
- **G9.** Suite de tests prouvant la génération (entropie/longueur), le `wipe`, l'absence de clé en clair persistée/journalisée, et le **refus du repli logiciel** ; tests matériels Keystore isolés en tests instrumentés (device lab #29).

## Non-Goals

- **Dérivation/récupération PBKDF2 & questions culturelles** (#12) — la *re-dérivation* de la clé sur un nouvel appareil est hors périmètre ; #11 fournit seulement le point d'accroche (état « clé absente/invalidée » → #12).
- **Parcours d'onboarding / création de compte (n° CMU/téléphone)** (#13) — l'UI consomme `generateMasterKey` + `sealMasterKey` mais n'est pas livrée ici.
- **Sauvegarde cloud zero-knowledge & clé de DB SQLCipher** (#14, ADR 0006) — l'`unseal` de la clé enveloppée de la DB est *consommé* par #14 ; #11 expose le mécanisme d'unseal mais n'implémente pas la sauvegarde ni l'ouverture de la DB.
- **Génération du QR éphémère / clé de session médecin** (#16, #17) — chemin médecin, clé symétrique distincte, jamais issue du keystore patient.
- **Module AES-256-GCM lui-même** (#10) — déjà implémenté ; #11 le réutilise tel quel.
- **Shim iOS complet (Secure Enclave/Keychain) de production** — ADR 0001 cible Android d'abord ; pour #11, livrer **a minima** l'interface et un stub iOS clairement marqué (décision : voir *Risks*), pas une implémentation iOS durcie.
- **Toute opération git/GitHub** (branches, commits, PR) — hors périmètre de cette phase ADW.

## Relevant Repository Context

**Statut « stack non finalisée (#1) » — à nuancer.** Le BACKLOG présente le projet comme greenfield à stack ouverte, mais à la date de cette spec **#1 est tranché** : ADR 0001–0009 sont *Accepted*. Pour #11, les décisions pertinentes **déjà prises** sont :

- **Cœur crypto : Rust `crypto-core`** (ADR 0003), seul lieu d'AES/PBKDF2, exposé via `flutter_rust_bridge` (patient), `wasm-bindgen` (PWA médecin) et UniFFI/natif. `generate_master_key()` et `wipe()` y existent déjà (`crypto-core/src/lib.rs`).
- **App patient : Flutter (Dart), `minSdk 24`** (ADR 0001). **Aucun chiffrement en Dart.** Le scellement matériel passe par un **`MethodChannel` Kotlin obligatoire** : `KeyGenParameterSpec` + `setIsStrongBoxBacked(true)` → repli TEE, non-exportable. `flutter_secure_storage` est réservé aux éléments **non critiques**.
- **Gestion de clés (ADR 0006) :** clé maîtresse générée dans le cœur Rust, **scellée dans l'Android Keystore** (StrongBox sinon TEE), non-exportable ; elle **enveloppe** la clé de DB SQLCipher et les clés de données par enregistrement. Le repli PBKDF2 (#12) est le backstop en cas de perte de la clé matérielle.
- **Modèle de menace (#6, *merged*) :** couvre vol de téléphone, serveur compromis, MITM, QR intercepté, attaque sur la phrase de passe ; le scellement matériel est la contre-mesure « vol de téléphone ».

**Scaffold existant à reprendre (ne pas réécrire) :**

| Fichier | Rôle actuel | Action #11 |
| --- | --- | --- |
| `crypto-core/src/lib.rs` | `generate_master_key`, `wipe` réels | Réutiliser ; éventuellement ajouter une abstraction *handle* opaque (G8) sans casser l'API |
| `app-patient/lib/src/secure/keystore_channel.dart` | Stub `sealMasterKey`/`unsealDbKey` lançant `UnimplementedError` | Implémenter le pont Dart→natif |
| `app-patient/lib/src/rust/crypto_core_bindings.dart` | Placeholder, FRB non générée | Câbler la codegen FRB ; exposer `generateMasterKey`/`wipe` |
| `app-patient/lib/main.dart`, `app-patient/test/smoke_test.dart` | Squelette d'app + smoke test | Étendre minimalement pour le câblage/test |

**Code natif manquant (à créer) :** côté Android, le `MethodChannel('healthtech/keystore')` n'a **aucun** récepteur Kotlin (`MainActivity`/plugin). C'est la pièce centrale de #11.

**Conventions observées (à respecter) :**
- Lints stricts : `crypto-core` est `#![forbid(unsafe_code)]` + `#![deny(warnings)]` ; clippy `-D warnings` en CI (ADR 0008, `justfile`).
- Pas de toolchain Rust dans la phase ADW (voir mémoire projet) : écrire du Rust conforme à `rustfmt` par défaut ; les gates tournent ailleurs.
- `TODO(#n)` traçant les dépendances inter-issues ; docs de module en `//!`.
- Specs : **prose FR, titres EN** (cf. `specs/zero-knowledge-blob-storage-service.md`).
- Gate de test canonique : `just test` ; côté Flutter, `flutter test` / analyse `flutter analyze` (à confirmer dans le `justfile`).

## Proposed Implementation

Approche recommandée : **chiffrement par enveloppe (envelope encryption)** — c'est la seule qui réconcilie « clé maîtresse générée dans Rust » (ADR 0006) avec « clé non-exportable du keystore » (ADR 0001), car une clé arbitraire produite par Rust ne peut pas *être* la clé résidente non-exportable du keystore.

**Modèle de données de confiance :**

1. **KEK matérielle (Key-Encryption-Key)** — générée **par** l'Android Keystore (`KeyGenParameterSpec`, AES-256-GCM, `setIsStrongBoxBacked(true)` → repli TEE), **non-exportable**, jamais visible hors du matériel. Alias fixe (ex. `healthtech.master.kek.v1`).
2. **Clé maîtresse (DEK racine)** — générée par `crypto-core::generate_master_key()` dans la RAM Rust. Elle est **scellée** = chiffrée AES-GCM par la KEK matérielle. Seul le **blob scellé** `iv || ciphertext || tag` est persisté.
3. **Usage** : à l'unseal, la KEK déchiffre le blob → la clé maîtresse réapparaît en RAM (Rust de préférence), sert à chiffrer/déchiffrer (#14) ou à envelopper la clé de DB SQLCipher / les clés par enregistrement (ADR 0006), puis est **`wipe()`-ée**.

> **Décision ouverte (voir *Risks*) :** l'alternative « import direct de la clé Rust dans le Keystore comme clé non-exportable via *wrapped key import* (`WRAP_KEY`/`PURPOSE_*`) » est plus complexe et moins portable que la KEK-enveloppe. Recommandation : **enveloppe**.

**Flux de génération (onboarding, appelé par #13) :**

```
Dart UI (#13)
  └─ FRB: generateMasterKey()            // Rust: getrandom -> [u8;32] (handle opaque)
       └─ FRB: exportSealable(handle)    // Rust: rend les bytes UNIQUEMENT pour scellement immédiat
            └─ MethodChannel.seal(bytes) // Kotlin: KEK.encrypt(bytes) -> blobScellé
                 └─ persist(blobScellé)  // stockage privé app (non secret en clair)
            └─ FRB: wipe(handle)         // Rust: zeroize la copie en clair
       └─ zeroize bytes Dart (best-effort) immédiatement après seal
```

**Flux d'unseal (consommé par #14 / ouverture session locale) :**

```
read(blobScellé) -> MethodChannel.unseal(blob) -> bytes en clair (Kotlin)
  -> remis au cœur Rust (handle) -> usage -> wipe()
```

**Côté Rust (`crypto-core`) :** réutiliser `generate_master_key`/`wipe`. Pour G8, introduire une fine abstraction de *handle* (la clé reste dans une structure Rust `Zeroizing<[u8;32]>` ; le franchissement FFI en clair est limité à `exportSealable`, documenté comme « pour scellement matériel immédiat uniquement »). Ne **pas** ajouter d'AAD ici si cela complexifie #10 ; le format de scellement est interne au keystore et distinct du format de fil `nonce||ct||tag` de #10.

**Côté Kotlin (nouveau) :** récepteur `MethodChannel('healthtech/keystore')` dans `MainActivity` (ou plugin dédié) exposant `seal`, `unseal`, `exists`, `clear`. Détection StrongBox (`PackageManager.FEATURE_STRONGBOX_KEYSTORE`) → repli TEE → **échec typé** si rien. Gérer `KeyPermanentlyInvalidatedException` → code d'erreur dédié routé vers #12.

**Côté Dart :** implémenter `KeystoreChannel.sealMasterKey/unseal*/exists/clear` en routant via le `MethodChannel`, **sans repli logiciel** ; mapper les erreurs natives vers des exceptions typées (`KeystoreUnavailable`, `KeyInvalidated`). Persister le blob scellé dans le stockage privé de l'app (le blob n'est **pas** un secret en clair) — *décision : fichier privé vs `flutter_secure_storage` vs `SharedPreferences` (voir Risks)*.

**iOS (amorce) :** définir l'équivalent Secure Enclave/Keychain derrière la même interface Dart, en **stub explicite `TODO(#11/iOS)`** si non durci dans cette itération (ADR 0001 : iOS « plus tard »).

## Affected Files / Packages / Modules

À lire / modifier / créer :

- `crypto-core/src/lib.rs` — réutiliser `generate_master_key`/`wipe` ; éventuel *handle* opaque + `exportSealable` (G8) ; mettre à jour les `TODO(#11)`.
- `crypto-core/README.md` — documenter le rôle de la clé maîtresse et la frontière scellement.
- `app-patient/lib/src/secure/keystore_channel.dart` — **implémenter** `sealMasterKey`, `unseal*`, ajouter `exists`/`clear`, exceptions typées.
- `app-patient/lib/src/rust/crypto_core_bindings.dart` — câbler la codegen FRB ; exposer `generateMasterKey`/`wipe`/`exportSealable`.
- `app-patient/android/app/src/main/kotlin/.../MainActivity.kt` (**nouveau** ou existant) — récepteur `MethodChannel`, logique Keystore. *(Confirmer le chemin exact du package une fois le projet Android Flutter généré.)*
- `app-patient/ios/Runner/*.swift` (**nouveau**, amorce) — interface Keychain/Secure Enclave (stub possible).
- `app-patient/lib/main.dart` — câblage minimal du flux génération→seal (sans dupliquer l'UI de #13).
- `app-patient/test/…` — tests Dart (mock `MethodChannel`) ; `app-patient/android/app/src/androidTest/…` — tests instrumentés Keystore.
- `app-patient/pubspec.yaml` — dépendances FRB / stockage si nécessaire.
- ADR 0006 / 0001 — annoter l'implémentation effective ; éventuel nouvel ADR si l'option « import direct » est retenue à la place de l'enveloppe.
- `docs/compliance/controles.md` / matrice — preuve « clé jamais en clair hors RAM » (ARTCI).

## API / Interface Changes

- **FFI / FRB (Dart↔Rust)** — *nouveau* : `generateMasterKey() -> KeyHandle (opaque)`, `wipe(handle)`, et `exportSealable(handle) -> bytes` (réservé au scellement matériel immédiat). Surface volontairement minimale (ADR 0003).
- **Platform channel `healthtech/keystore`** — *nouveau* contrat Dart↔natif : méthodes `seal(bytes) -> sealedBlob`, `unseal(sealedBlob) -> bytes`, `exists() -> bool`, `clear() -> void` ; codes d'erreur `KEYSTORE_UNAVAILABLE`, `KEY_INVALIDATED`, `STRONGBOX_UNSUPPORTED`.
- **API publique Dart** : `KeystoreChannel` passe de stubs `UnimplementedError` à une API réelle ; documenter (commentaires d'API + README app-patient).
- **Endpoints réseau / QR / tokens** : **none** — #11 est entièrement local-appareil ; rien ne transite vers le serveur ivoirien (cohérent avec « aucune donnée nominative envoyée en clair », US-1.1).

## Data Model / Protocol Changes

- **Blob scellé persisté (nouveau, local uniquement)** : format `version(1o) || iv(12o) || ciphertext(32o) || tag(16o)` (clé maîtresse de 32 o scellée par la KEK matérielle en AES-GCM). Le **byte de version** est recommandé ici (contrairement au format de fil #10) car ce format est purement interne à l'appareil et doit pouvoir migrer (rotation KEK, changement d'algo) — *à confirmer*.
- **Emplacement de persistance** : stockage privé de l'app (le blob n'est pas un secret en clair). **Décision ouverte** : fichier privé vs `flutter_secure_storage` vs `SharedPreferences` (voir *Risks*).
- **Aucun changement de schéma serveur / blob réseau** : le format de fil zero-knowledge (#9/#10, `nonce||ct||tag`) n'est pas touché.
- **Aucune persistance de clé en clair** — par construction (critère d'acceptation #2).

## Security & Compliance Considerations

- **Clé jamais exportée en clair (US-1.1) :** la clé maîtresse n'existe en clair qu'en **RAM** (Rust de préférence), le temps du scellement/usage, puis est `wipe()`-ée (`zeroize`). Sur disque : **uniquement** le blob scellé par le matériel.
- **Scellement matériel (G2/G3) :** StrongBox (secure element) si présent, sinon TEE ; **jamais** de repli logiciel silencieux — l'absence de matériel doit **échouer** et être traçable (preuve ARTCI). Envisager `setUserAuthenticationRequired` « where UX allows » (ADR 0006) — *décision UX à arbitrer avec #13/#28*.
- **Aucune fuite mémoire persistante (critère #2) :** `wipe` côté Rust ; **minimiser les copies Dart** (limitation connue : `Uint8List` ne se zeroize pas de façon déterministe, cf. ADR 0001/0002) — garder le clair dans Rust, ne faire transiter que les bytes strictement nécessaires au seal. **Ne jamais journaliser** clé, blob scellé, ni PII (redaction) ; pas de clé dans les rapports de crash.
- **Zero-knowledge (rappel) :** #11 ne touche pas au serveur ; le chiffrement AES-256-GCM côté patient (#10) et le serveur ne voyant que des **blobs opaques par UUID anonyme** restent inchangés. La clé maîtresse ne quitte jamais l'appareil → le serveur ne peut pas déchiffrer.
- **Accès éphémère médecin (QR ~120 s, déchiffrement RAM-only, wipe de fin de session) :** hors périmètre #11 (chemin médecin, clé de session distincte) — à ne pas confondre avec la clé maîtresse patient.
- **Résidence des données (ARTCI / loi n°2013-450) :** la clé étant locale-appareil, aucune donnée ne transite ; cohérent avec la résidence souveraine (#8). Tracer dans la matrice de conformité la preuve « clé scellée matériellement, jamais en clair persistant ».
- **Budget ≤ 500 Ko & images lourdes :** non concernés directement (#11 gère une clé de 32 o), mais la clé maîtresse enveloppera la clé de DB SQLCipher et les clés de données (ADR 0006) qui, elles, respectent ces contraintes.
- **Perte de clé matérielle = perte de données :** l'invalidation (MAJ OS, OEM TEE, ré-enrôlement biométrique) doit router vers la **récupération #12 (PBKDF2)** — sans ce backstop, le patient est verrouillé hors de ses données (risque BACKLOG #1).

## Testing Plan

- **Unit (Rust `crypto-core`) :** `generate_master_key` renvoie 32 o, non-tout-zéro, deux appels diffèrent (entropie de base) ; `wipe` remet à zéro le buffer ; (si *handle* ajouté) `exportSealable` ne fuit pas après `wipe`.
- **Unit (Dart) :** `KeystoreChannel` avec **`MethodChannel` mocké** — `seal`/`unseal` round-trip, `exists`/`clear`, mapping des erreurs natives vers exceptions typées, **absence de repli logiciel** (une indisponibilité keystore *throw*, ne renvoie pas une clé logicielle).
- **Instrumented (Android, device lab #29) :** scellement réel dans Keystore StrongBox **et** TEE ; non-exportabilité (tentative d'export échoue) ; round-trip seal→unseal ; comportement sur `KeyPermanentlyInvalidatedException`. *Robolectric/JVM ne fournissent pas un vrai Keystore → ces tests doivent tourner sur émulateur/appareil.*
- **Crypto-vectors :** non applicable directement à #11 (les KAT AES-GCM relèvent de #10) ; vérifier que le format de blob scellé round-trip pour des clés connues.
- **Resilience / dégradé :** génération + scellement **hors-ligne** (US-1.1 : compte créé sans réseau) ; coupure pendant le seal → état cohérent (pas de blob partiel utilisable) ; ré-exécution idempotente (ne pas écraser une clé existante).
- **Sécurité / non-fuite :** test prouvant qu'aucun log n'émet la clé/le blob/PII ; (si faisable) inspection mémoire/disque post-génération montrant l'absence de clé en clair persistée — *aligné sur les preuves d'audit #25*.
- **Documentation :** vérifier que README app-patient + commentaires d'API décrivent la frontière de scellement et l'interdiction de repli logiciel.

## Documentation Updates

- **ADR 0006 / 0001 :** annoter l'implémentation réelle (enveloppe KEK retenue) ; si l'option « import direct » était choisie, rédiger un nouvel ADR de gestion de clé.
- **`crypto-core/README.md` & `app-patient/README.md` :** documenter `generateMasterKey`/`wipe`/`exportSealable` (API publique, contrainte ADR 0003) et le contrat du `MethodChannel` keystore (API publique).
- **`docs/compliance/controles.md` + matrice loi 2013-450 :** ajouter la preuve « clé maîtresse scellée matériellement, jamais en clair persistant » (rattachée à US-1.1).
- **BACKLOG :** rien à changer dans la structure ; éventuellement noter la décision « enveloppe vs import direct » et le statut iOS (amorce).
- **`SECURITY.md` / modèle de menace #6 :** confirmer que la contre-mesure « vol de téléphone » est désormais câblée (renvoi vers #12 pour la récupération).

## Risks and Open Questions

1. **Modèle de scellement** — enveloppe KEK (recommandé) **vs** import direct de la clé Rust comme clé Keystore non-exportable. *À confirmer.*
2. **Sémantique de `sealMasterKey(Uint8List wrappedKey)`** — le paramètre est nommé `wrappedKey` dans le stub : passe-t-on la clé **brute** (le natif l'enveloppe) ou une clé **déjà enveloppée** ? Clarifier le contrat (la spec recommande : Dart passe les bytes bruts issus de `exportSealable`, le natif scelle).
3. **Emplacement de persistance du blob scellé** — fichier privé app vs `flutter_secure_storage` vs `SharedPreferences`. ADR 0001 réserve `flutter_secure_storage` au non-critique ; comme le blob est déjà chiffré matériellement, un fichier privé suffit, mais à trancher.
4. **`setUserAuthenticationRequired`** — exiger une authentification utilisateur (biométrie/PIN) au déverrouillage de la KEK améliore la sécurité mais peut friction­ner l'UX d'onboarding hors-ligne (#13/#28). Arbitrage UX/sécurité.
5. **Inconstance StrongBox/TEE sur Infinix bas de gamme** (ADR 0006) — certains OEM TEE effacent les clés à la MAJ OS → verrouillage patient ; dépend du backstop #12. Tester device lab #29.
6. **Zeroization Dart best-effort** — `Uint8List` non effaçable de façon déterministe (ADR 0001) ; comment minimiser/borner la fenêtre d'exposition côté Dart ?
7. **Portée iOS dans #11** — livrer une implémentation Secure Enclave ou seulement l'interface + stub ? (ADR 0001 : Android d'abord.)
8. **Chemin du package Android** — `MainActivity.kt` n'existe pas encore tant que le projet Android Flutter n'est pas matérialisé ; confirmer l'arborescence générée.
9. **Toolchain dans la phase ADW** — pas de Rust ni (potentiellement) de SDK Android/Flutter pour exécuter les gates ; les tests instrumentés Keystore ne tourneront pas dans cette phase (à exécuter en device lab / CI mobile).
10. **Granularité des clés** — #11 livre-t-il aussi l'enveloppe de la clé de DB SQLCipher et des clés par enregistrement (ADR 0006), ou seulement la clé maîtresse racine (le reste à #14) ? Recommandation : **clé maîtresse racine uniquement**, l'enveloppe des sous-clés relève de #14.

## Implementation Checklist

1. **Confirmer les décisions ouvertes** clés : modèle de scellement (enveloppe), contrat `seal`, emplacement du blob, périmètre iOS, granularité des clés (questions 1–3, 7, 10).
2. **Rust `crypto-core`** : réutiliser `generate_master_key`/`wipe` ; ajouter (si retenu) un *handle* opaque `Zeroizing` + `exportSealable` ; conserver `#![forbid(unsafe_code)]`/`#![deny(warnings)]` ; mettre à jour les `TODO(#11)`.
3. **FRB codegen** : configurer `flutter_rust_bridge` contre `crypto-core` ; remplacer le placeholder `crypto_core_bindings.dart` par la surface générée minimale (`generateMasterKey`, `wipe`, `exportSealable`).
4. **Kotlin shim** : créer le récepteur `MethodChannel('healthtech/keystore')` ; `KeyGenParameterSpec` AES-256-GCM, `setIsStrongBoxBacked(true)` + détection `FEATURE_STRONGBOX_KEYSTORE` → repli TEE → **échec typé** si rien ; implémenter `seal/unseal/exists/clear` ; gérer `KeyPermanentlyInvalidatedException`.
5. **Dart `KeystoreChannel`** : implémenter les méthodes via le channel, **sans repli logiciel** ; exceptions typées (`KeystoreUnavailable`, `KeyInvalidated`, `StrongBoxUnsupported`) ; persistance du blob scellé (emplacement décidé).
6. **Câblage flux** : `main.dart` (ou service dédié consommé par #13) enchaîne `generateMasterKey → exportSealable → seal → persist → wipe`, avec zeroization Dart best-effort immédiate.
7. **iOS** : interface Keychain/Secure Enclave derrière la même API Dart (implémentation ou stub `TODO(#11/iOS)` selon décision 7).
8. **Détection d'état** : `exists()` au démarrage ; clé absente → onboarding (#13) ; clé invalidée → récupération (#12).
9. **Tests** : unit Rust (génération/wipe), unit Dart (mock channel, no-fallback, mapping erreurs), instrumentés Android (StrongBox+TEE, non-export, invalidation), non-fuite logs, génération hors-ligne/idempotente.
10. **Hygiène anti-fuite** : audit des logs (aucune clé/blob/PII) ; redaction ; pas de clé dans crash reports.
11. **Docs & conformité** : ADR 0006/0001 annotés, README app-patient + commentaires d'API, preuve matrice loi 2013-450, note threat model #6 (renvoi #12).
12. **Vérifier les gates** : `flutter analyze`/`flutter test` + `just test` (Rust) là où la toolchain est disponible ; documenter ce qui ne tourne pas dans la phase ADW (tests instrumentés en device lab/CI mobile).
