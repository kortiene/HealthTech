# Module AES-256-GCM (chiffrement/déchiffrement de blob) (#10)

> **Issue :** #10 — Module AES-256-GCM (chiffrement/déchiffrement de blob) · **Épic :** E5 — Cœur cryptographique · **Jalon :** M1 — Cœur cryptographique & onboarding patient · **Effort :** M · **Priorité :** Must · **Étiquettes :** `crypto` `security` · **Dépend de :** #6 (modèle de menace).
>
> **Type :** spec de planification — **ne pas implémenter** dans cette phase ADW.
>
> **Critères d'acceptation (BACKLOG / issue) :** (1) **vecteurs de test officiels passants** ; (2) **revue de sécurité du module** ; (3) **API stable réutilisée par les apps**.

## Problem Statement

Le chiffrement authentifié AES-256-GCM est la **pierre angulaire** de l'architecture local-first / zero-knowledge de HealthTech : le dossier médical est chiffré sur le smartphone du patient **avant tout transit**, et le serveur ne stocke que des blobs opaques (cf. #9). Le BACKLOG identifie explicitement #10 comme bloquant #14 (sauvegarde cloud), #16 (QR éphémère), #17 (scan/déchiffrement médecin) et #21 (file offline SQLCipher) — toute la boucle de valeur en dépend.

Aujourd'hui le dépôt contient un **scaffold réel mais non durci** de ce module, livré avec la structure du monorepo (#2) :

- `crypto-core/src/lib.rs` expose déjà `generate_master_key`, `encrypt_record`, `decrypt_record`, `derive_key`, `wipe`. Le câblage AES-256-GCM (via la crate `aes-gcm` 0.10 de RustCrypto) **est réel et round-trip**, avec un nonce 96 bits aléatoire **préfixé** au format `nonce(12) || ciphertext || tag(16)`.
- Le crate est `#![forbid(unsafe_code)]` + `#![deny(warnings)]`, dépendances RustCrypto épinglées (ADR 0003).
- Les tests présents sont des **smoke tests** (round-trip, rejet de blob falsifié, rejet de blob court, déterminisme de `derive_key`, wipe), **explicitement pas des vecteurs de gating** : deux marqueurs `TODO(#10)` / `TODO(#12)` documentent ce qui manque.

**Le gap que #10 doit combler :**

1. **Aucun vecteur de test officiel (NIST CAVP / RFC) n'existe** pour AES-256-GCM — le module n'est prouvé que *self-consistant*, pas conforme au standard. C'est le premier critère d'acceptation.
2. La **gestion des nonces** n'est pas formellement revue ni durcie (unicité, source d'entropie, limite d'usage par clé, comportement en cas d'échec du CSPRNG).
3. L'**API n'est pas figée** : pas de garantie de stabilité du format de fil ni de la signature des fonctions, alors que trois consommateurs (Flutter via FFI, PWA médecin via WASM, harnais backend) doivent s'appuyer dessus.
4. La **revue de sécurité du module** (second critère d'acceptation) n'est pas tracée.

> **Note de cadrage importante.** Le marqueur `TODO(#12)` (calibration PBKDF2 + vecteurs RFC 6070) et l'AAD différé par `TODO(#11)` appartiennent à d'**autres** issues. #10 se concentre sur **AES-256-GCM et la gestion des nonces**. La conception de l'AAD doit toutefois être *anticipée* ici pour ne pas figer une API qui empêcherait #11 d'ajouter un canal d'associated data sans rupture (voir Open Questions).

## Goals

- **G1 — Vecteurs officiels passants.** Intégrer les **known-answer tests (KAT) NIST CAVP AES-GCM** (jeux `gcmEncryptExtIV256` / `gcmDecrypt256`, clé 256 bits, IV 96 bits) en **tests de gating CI** : pour clé+nonce+AAD+plaintext fixés, le ciphertext **et** le tag produits doivent être exactement ceux attendus, et la décryption doit reproduire le plaintext. Inclure des vecteurs **négatifs** (tag falsifié → rejet).
- **G2 — Conformité du chemin de décryption.** Tester la branche `gcmDecrypt256` incluant des cas où l'authentification **doit échouer** (FAIL vectors), pour prouver qu'aucun plaintext n'est jamais renvoyé sur tag invalide.
- **G3 — Gestion des nonces durcie et documentée.** Formaliser : nonce 96 bits **aléatoire par appel** issu du CSPRNG OS (`getrandom`), **jamais réutilisé** sous une même clé, échec du RNG remonté en erreur (jamais un nonce nul/dégénéré). Documenter la **borne d'usage** (risque de collision d'un nonce aléatoire 96 bits ≈ après ~2³² messages par clé) et conclure qu'elle est sans risque au vu du volume réel (un blob patient réécrit par consultation).
- **G4 — API publique stable et documentée.** Figer la signature des fonctions, le format de fil `nonce || ciphertext || tag`, les invariants d'erreur (erreurs coarse, pas d'oracle), et publier un **contrat d'API** (doc-comments `//!`/`///` + section README + éventuel ADR/CHANGELOG) que #14/#16/#17/#21 et les bindings (#11 FFI, #17 WASM) peuvent consommer sans surprise.
- **G5 — Revue de sécurité tracée.** Produire un artefact de revue (checklist de revue crypto du module, traçant chaque point vers le code/test) répondant au second critère d'acceptation ; alimenter et préparer #26 (revue crypto indépendante).
- **G6 — Robustesse des entrées.** Couvrir explicitement : blob plus court que le nonce, blob de taille nonce+tag sans ciphertext (plaintext vide légal), mauvaise clé, ciphertext tronqué/étendu, plaintext vide, plaintext à la borne 500 Ko + overhead.
- **G7 — Pas de régression de surface.** L'API doit rester l'**unique** lieu d'AES (ADR 0003) ; aucun chemin n'introduit de crypto plateforme ni d'`unsafe`.

## Non-Goals

- **Calibration PBKDF2 + vecteurs RFC 6070 / NIST PBKDF2** — c'est **#12** (`TODO(#12)`), bien que la dérivation `derive_key` vive dans le même crate. Hors périmètre ici, sauf à ne rien casser.
- **Génération & scellement de la clé maîtresse dans le keystore matériel** — c'est **#11** (Android Keystore) ; #10 produit/consomme une clé brute `[u8; 32]` mais ne gère pas son stockage scellé.
- **Canal d'associated data (AAD) liant métadonnées d'enregistrement (id/version)** — différé à **#11** (`TODO(#11)`). #10 doit seulement **ne pas fermer la porte** à son ajout (voir Open Questions sur le versionnement du format).
- **Génération des bindings FFI (`flutter_rust_bridge`) et WASM (`wasm-bindgen`)** — câblage applicatif de #11 (FFI) et #17 (WASM). #10 fige l'API Rust que ces codegen exposeront, sans réaliser le codegen lui-même.
- **Service de stockage backend (#9), QR éphémère (#16), scan/wipe RAM médecin (#17/#19), file offline SQLCipher (#21)** — *consommateurs* du module, hors périmètre.
- **Revue cryptographique indépendante externe (#26)** — #10 fait la revue **interne** du module et prépare le terrain ; l'avis d'expert tiers reste #26.
- **Toute opération git/GitHub** (branches, commits, PR, merge, commentaires) — réalisée par l'orchestrateur ADW, hors de cette phase.

## Relevant Repository Context

**Statut stack — déjà tranché (nuance vs framing « greenfield » de l'issue).** Le BACKLOG décrit le projet comme greenfield à « stack non finalisée (#1) », mais à la date de cette spec **#1 est tranché** et les ADR 0001–0009 sont *Accepted*. Pour #10 cela signifie que **le langage et la toolchain de ce module ne sont PAS une décision ouverte** :

- **Crypto-core : Rust**, crate `crypto-core`, membre du workspace cargo racine (`Cargo.toml` racine, partagé avec `backend`). Stack **RustCrypto épinglée** : `aes-gcm` 0.10 (AES-256-GCM AEAD), `getrandom` 0.2 (CSPRNG OS), `zeroize` 1 (wipe), `pbkdf2` 0.12 + `sha2` 0.10 (pour #12). Dev-dep `hex` 0.4 déjà présente pour décoder les vecteurs (ADR 0003).
- **C'est l'unique lieu d'AES** : la crypto plateforme (`javax.crypto`, WebCrypto AES) est **interdite** par ADR 0003. Flutter consomme via `flutter_rust_bridge` (FFI), la PWA médecin via WASM en Web Worker.

**Restent des décisions d'implémentation (sous les ADR existants, PAS une réouverture de #1), à confirmer dans la checklist :**

- **Source des vecteurs KAT** : fichiers `.rsp` officiels NIST CAVP (`gcmEncryptExtIV256.rsp` / `gcmDecrypt256.rsp`) committés comme fixtures vs un sous-ensemble de vecteurs encodés en dur dans le test. Trancher entre fidélité (fichier complet) et empreinte/lisibilité (sous-ensemble représentatif + provenance documentée).
- **Emplacement des fixtures** : `crypto-core/tests/vectors/` (test d'intégration) vs module `#[cfg(test)]` inline. Cohérence avec la convention du dépôt (le ZK blob spec place les harnais en `backend/tests/`).
- **Forme de l'artefact de revue de sécurité** : `docs/security/` (à côté du threat model STRIDE `docs/threat-model/stride-threat-model.md`, #6) vs section dédiée du README crypto-core vs nouvel ADR.

**Conventions observées (à respecter) :**

- Lints stricts : `#![forbid(unsafe_code)]` + `#![deny(warnings)]` déjà en tête de `crypto-core/src/lib.rs` ; clippy `-D warnings` en CI (ADR 0008, `justfile`).
- Erreurs **coarse** et sans oracle : `CryptoError::{Rng, Decrypt}` ne distingue pas mauvaise clé / tag invalide / blob malformé.
- Secrets wipés via `zeroize` ; pas de `Debug`/log de matériel sensible.
- Tests : `cargo test -p crypto-core` ; gate ADW canonique `just test` (et `just test-rust` pour le workspace Rust).
- Marqueurs `TODO(#n)` traçant explicitement les dépendances inter-issues — à **retirer/mettre à jour** quand #10 livre sa part.
- Specs : prose **FR**, titres **EN** (cf. `specs/zero-knowledge-blob-storage-service.md`, `specs/sovereign-hosting-provisioning-cote-divoire.md`).

**Threat model (#6) — entrées pertinentes pour #10 :** vol de téléphone, serveur compromis, MITM réseau, QR intercepté. AES-256-GCM est la contre-mesure tracée pour la confidentialité+intégrité du blob ; #10 doit refermer les points crypto que le threat model assigne au module (intégrité authentifiée, pas d'oracle de padding/erreur, nonce non réutilisé).

## Proposed Implementation

L'approche est un **durcissement ciblé du scaffold existant**, pas une réécriture. Le câblage `aes-gcm` est conservé ; on ajoute la preuve de conformité, on durcit les nonces et on fige le contrat.

1. **Vecteurs NIST CAVP AES-GCM (KAT) — gating (G1, G2).**
   - Ajouter des fixtures de vecteurs 256 bits / IV 96 bits pour le chiffrement (`gcmEncryptExtIV256`) et le déchiffrement (`gcmDecrypt256`), incluant des cas avec **AAD non vide** et des cas **AAD vide** (l'API actuelle utilise `aad: &[]`).
   - Le format de fil du module préfixe le nonce ; les vecteurs NIST fournissent (Key, IV, PT, AAD, CT, Tag) **séparément**. Donc **tester au niveau primitive** : soit (a) exposer un chemin de test interne qui chiffre avec un **nonce fixé** (et non aléatoire) et compare `CT || Tag`, soit (b) tester directement `Aes256Gcm` dans le module de test et, séparément, vérifier que `encrypt_record` produit bien `nonce || CT || Tag` en re-décomposant sa sortie. **Recommandation :** ajouter une fonction de test (ou un helper `#[cfg(test)]`/`pub(crate)`) `encrypt_with_nonce(key, nonce, aad, pt)` pour permettre la comparaison déterministe aux vecteurs, sans exposer un nonce choisi par l'appelant dans l'API publique de production (qui doit rester nonce-aléatoire).
   - Inclure des **FAIL vectors** (tag/CT altéré) prouvant le rejet (`CryptoError::Decrypt`), et la non-divulgation de plaintext.
   - Documenter la **provenance exacte** des vecteurs (URL/fichier NIST, version) en commentaire de fixture.

2. **Gestion des nonces (G3).**
   - Conserver le nonce **aléatoire 96 bits** par appel via `getrandom`. **Durcir le chemin d'erreur** : aujourd'hui `encrypt_record` mappe l'échec de chiffrement sur `CryptoError::Rng` (commentaire « absurd input sizes ») — clarifier/séparer les causes (échec RNG du nonce vs échec AEAD), sans introduire d'oracle exploitable.
   - Documenter en `//!` la **politique de nonce** : unicité par (clé, message), interdiction de réutilisation, borne de sécurité du nonce aléatoire, et le fait qu'un nouvel enregistrement = nouveau nonce (pas de nonce déterministe/compteur dans ce design).
   - **Garde-fou anti-régression** : test vérifiant que deux chiffrements du même plaintext sous la même clé produisent des sorties **différentes** (preuve d'un nonce frais) — déjà implicite, à rendre explicite.

3. **Stabilité de l'API (G4).**
   - Figer et documenter le **contrat** : signatures (`encrypt_record(&[u8;32], &[u8]) -> Result<Vec<u8>, CryptoError>`, etc.), format de fil, constantes `KEY_LEN`/`NONCE_LEN`, sémantique d'erreur coarse.
   - **Versionnement du format** : décider si un **octet/préfixe de version** précède `nonce || ct || tag` pour permettre l'évolution (ajout d'AAD en #11, futur changement d'algorithme). **Recommandation :** réserver explicitement la question dans la doc et, si retenu, l'introduire **maintenant** (avant que des blobs soient produits en prod) car le format est un contrat de persistance difficile à rétrofiter (cf. risque BACKLOG sur le schéma 500 Ko).
   - Mettre à jour `crypto-core/README.md` (tableau d'API) et les commentaires de placeholder côté consommateurs (`app-patient/lib/src/rust/crypto_core_bindings.dart`, `app-medecin/src/session.ts`) — **sans** réaliser le codegen FFI/WASM (hors périmètre).

4. **Revue de sécurité du module (G5).**
   - Produire une **checklist de revue crypto** traçant chaque exigence (AEAD authentifié, nonce unique, pas d'oracle d'erreur, wipe des secrets, pas d'`unsafe`, dépendances épinglées + `cargo-audit`/`cargo-deny`, pas de log de clair/clé) vers le code et les tests correspondants. La placer là où le threat model #6 est référençable (cf. décision d'emplacement ci-dessus).

5. **Nettoyage des marqueurs.**
   - Retirer/mettre à jour le `TODO(#10)` dans le module de test une fois les vecteurs livrés ; laisser intacts `TODO(#11)` (AAD) et `TODO(#12)` (PBKDF2).

## Affected Files / Packages / Modules

**À modifier :**

- `crypto-core/src/lib.rs` — durcissement du chemin d'erreur nonce/AEAD, doc `//!` de politique de nonce + contrat d'API, helper de test `encrypt_with_nonce` (cfg(test)/pub(crate)), retrait du `TODO(#10)`.
- `crypto-core/Cargo.toml` — au besoin, dev-deps pour parser les `.rsp` (sinon `hex` 0.4 suffit pour des vecteurs pré-décodés).
- `crypto-core/README.md` — figer le tableau d'API, statut (« vecteurs NIST passants, API stable »), provenance des vecteurs.

**À créer :**

- `crypto-core/tests/aes_gcm_nist_vectors.rs` (ou module `#[cfg(test)]`) — KAT NIST AES-GCM-256, branches encrypt/decrypt + FAIL vectors.
- `crypto-core/tests/vectors/` — fixtures de vecteurs (sous-ensemble `.rsp` ou JSON) + note de provenance.
- Artefact de revue de sécurité : `docs/security/crypto-core-review.md` (à confirmer l'emplacement, à côté de `docs/threat-model/`).

**À lire / cohérence (ne pas modifier sauf commentaires) :**

- `docs/adr/0003-shared-crypto-core-rust.md`, `docs/threat-model/stride-threat-model.md`.
- `app-patient/lib/src/rust/crypto_core_bindings.dart`, `app-medecin/src/session.ts` — placeholders consommateurs (mettre à jour les commentaires de contrat si utile).
- `justfile`, `.github/workflows/ci.yml` — vérifier que `cargo test -p crypto-core` / `just test` exécutent bien les nouveaux vecteurs en gating.
- `Cargo.toml` racine, `deny.toml` — politique de dépendances.

## API / Interface Changes

**API publique Rust de `crypto-core` (figée par #10, pas de rupture attendue par rapport au scaffold) :**

- `pub const KEY_LEN: usize = 32;`
- `pub const NONCE_LEN: usize = 12;`
- `pub enum CryptoError { Rng, Decrypt }` (coarse, sans oracle).
- `pub fn generate_master_key() -> [u8; KEY_LEN]`
- `pub fn encrypt_record(key: &[u8; KEY_LEN], plaintext: &[u8]) -> Result<Vec<u8>, CryptoError>` — sortie `nonce || ciphertext || tag`.
- `pub fn decrypt_record(key: &[u8; KEY_LEN], blob: &[u8]) -> Result<Vec<u8>, CryptoError>`
- `pub fn derive_key(...)` (existe, propriété de #12 — inchangé ici).
- `pub fn wipe(secret: &mut [u8])`

**Changements potentiels à trancher (voir Open Questions) :** ajout éventuel d'un **octet de version** en tête du format de fil, et préparation d'un futur paramètre **AAD** (#11) sans casser la signature actuelle (p. ex. via une fonction additionnelle plutôt qu'une rupture). Aucun changement CLI, réseau, ni QR/token n'est introduit par #10. Les **bindings FFI/WASM** ne sont pas générés ici (#11/#17).

## Data Model / Protocol Changes

- **Format de blob chiffré (contrat de persistance, consommé par #9/#14/#17) :** `nonce (12 o) || ciphertext || tag (16 o)`. #10 **fige et documente** ce format ; il définit aussi l'**overhead** (28 o : 12 nonce + 16 tag) que #9 doit prévoir dans son budget de taille (≤ 500 Ko de clair + overhead AES-GCM).
- **Décision ouverte :** introduction (ou non) d'un **préfixe de version** d'un octet pour permettre l'évolution du format sans rupture (AAD #11, changement d'algo futur). Si retenu, c'est un changement de format à acter **avant** toute production de blobs. State : à trancher (Open Questions).
- Aucune autre modification de schéma de dossier, de sérialisation, ou de persistance backend (propriété de #9/#15).

## Security & Compliance Considerations

- **Chiffrement client-side AES-256-GCM (cœur de #10) :** AEAD authentifié, confidentialité **et** intégrité ; tout chiffrement se fait sur l'appareil avant transit. Ne **jamais** affaiblir la primitive (pas de mode non authentifié, pas de troncature de tag, AES-256 uniquement).
- **Garantie zero-knowledge :** le module ne sort que `nonce || ct || tag` ; le serveur (#9) stocke des **blobs opaques** indexés par **UUID anonyme** et ne détient **aucune clé** ni chemin de déchiffrement. #10 ne doit créer aucune API qui exfiltre une clé hors du crate.
- **Gestion des clés :** clé 256 bits du CSPRNG OS ; **jamais** loggée, sérialisée en clair, ni incluse dans un `Debug`. `wipe`/`zeroize` pour effacer les copies en RAM. Le scellement keystore est #11 ; #10 doit rendre le wipe facile et documenté pour les appelants.
- **Nonces :** 96 bits aléatoires, **jamais réutilisés** sous une clé ; échec du CSPRNG → **erreur**, jamais un nonce dégénéré. Documenter la borne d'usage (collision d'un nonce aléatoire ≈ 2³² messages/clé), sans risque au volume réel.
- **Pas d'oracle :** erreurs coarse (`Decrypt`) ne distinguant pas mauvaise clé / tag invalide / blob court — empêche un oracle exploitable côté médecin/serveur.
- **Accès QR éphémère (~120 s) & déchiffrement en RAM (#16/#17/#19) :** la clé symétrique transite par le QR, hors périmètre #10, mais le module doit rester **utilisable purement en mémoire** (pas d'écriture disque, pas de cache de clé) pour que #17 décrypte en RAM et #19 wipe en fin de session.
- **Résidence des données (ARTCI / loi n°2013-450) :** la crypto rend les blobs illisibles hors de l'appareil ; #10 renforce la matrice de conformité (contrôle technique « chiffrement client-side » → preuve = vecteurs NIST passants + revue). Aucune donnée ne quitte le territoire en clair.
- **Budget ≤ 500 Ko & images lourdes :** #10 documente l'overhead AES-GCM (28 o) pour le garde-fou de taille (#9/#15) ; le module chiffre des octets arbitraires, l'application n'embarque qu'une **URL éphémère** pour les images lourdes (#23), jamais l'image sur l'appareil.
- **Logs / redaction :** **ne jamais** logger plaintext médical, clés, nonces associés à un contexte sensible, ni PII. Les messages d'erreur restent génériques (déjà le cas).
- **Supply-chain :** dépendances RustCrypto **épinglées**, `cargo-audit` + `cargo-deny` (`deny.toml`), `#![forbid(unsafe_code)]`, `#![deny(warnings)]` — un crate compromis poisonne les trois clients (SPOF reconnu en ADR 0003) ; la revue #10 le retrace.

## Testing Plan

- **Vecteurs crypto (gating, critère d'acceptation #1) :**
  - KAT NIST CAVP `gcmEncryptExtIV256` : pour (Key, IV96, PT, AAD) fixés → `CT` et `Tag` exacts.
  - KAT NIST CAVP `gcmDecrypt256` : cas PASS (plaintext recouvré) **et** cas FAIL (tag invalide → rejet, aucun plaintext renvoyé).
  - Couvrir AAD vide **et** AAD non vide (anticipe #11 ; l'API prod utilise aujourd'hui AAD vide).
- **Tests de format / round-trip :**
  - `encrypt_record` produit `nonce || ct || tag` ; recomposition/décomposition correcte ; `decrypt_record(encrypt_record(x)) == x`.
  - Deux chiffrements du même plaintext sous la même clé → sorties différentes (nonce frais).
- **Robustesse des entrées (G6) :** blob < `NONCE_LEN` → `Decrypt` ; blob = nonce+tag sans ct (plaintext vide) ; mauvaise clé → `Decrypt` ; ct tronqué/étendu → `Decrypt` ; plaintext vide ; plaintext à 500 Ko + overhead.
- **Wipe :** `wipe` met le buffer à zéro (déjà présent, conservé).
- **Anti-oracle :** les erreurs ne fuitent pas la cause (assertion sur le variant unique `Decrypt`).
- **CI / gating :** s'assurer que `cargo test -p crypto-core` et le gate ADW `just test` exécutent les vecteurs ; échec d'un vecteur = build rouge.
- **Résilience (offline/réseau dégradé) :** non applicable directement au module pur (pas d'I/O) ; à valider chez les consommateurs (#17 RAM, #21 SQLCipher). Documenter que le module est **sans I/O et sans état**.
- **Documentation tests :** doc-tests sur les exemples de `encrypt_record`/`decrypt_record` si ajoutés au doc-comment.

## Documentation Updates

- `crypto-core/README.md` — figer le tableau d'API, marquer le statut « vecteurs NIST passants, API stable », documenter format de fil + overhead 28 o + provenance des vecteurs.
- `crypto-core/src/lib.rs` — doc `//!` : politique de nonce, contrat d'API, borne de sécurité, (option) octet de version.
- **Artefact de revue de sécurité** (`docs/security/crypto-core-review.md` ou équivalent) — checklist tracée, critère d'acceptation #2.
- `docs/adr/0003-shared-crypto-core-rust.md` — éventuel addendum si le **versionnement de format** est introduit (décision architecturale).
- `BACKLOG.md` — possible mise à jour du statut de #10 (le statut réel est géré par l'orchestrateur ; ne pas committer ici).
- `docs/compliance/loi-2013-450-artci-matrix.md` / `controles.md` — pointer la preuve « chiffrement client-side » vers les vecteurs NIST passants + la revue, si la matrice attend cette preuve.
- Commentaires de placeholder consommateurs (`crypto_core_bindings.dart`, `session.ts`) — aligner sur l'API figée (sans codegen).

## Risks and Open Questions

1. **Octet de version dans le format de fil — trancher MAINTENANT.** Ajouter un préfixe de version permet d'évoluer (AAD #11, futur algo) sans rupture, mais c'est un changement de **contrat de persistance** quasi impossible à rétrofiter une fois des blobs produits en prod. **Recommandation : décider explicitement avec #11/#9** avant la première mise en production.
2. **AAD différé (#11) vs API figée.** Si #11 ajoute un canal AAD (id/version d'enregistrement), faut-il le prévoir comme **fonction additionnelle** (`encrypt_record_aad`) pour ne pas casser la signature actuelle ? À acter pour ne pas re-rompre l'API « stable » promise par #10.
3. **Source/empreinte des vecteurs.** Committer les `.rsp` NIST complets (fidélité, volume) vs un sous-ensemble représentatif encodé (lisibilité, empreinte) — trancher avec la provenance documentée.
4. **Exposition d'un chemin à nonce fixé pour les tests.** Tester les KAT exige de fixer le nonce ; le faire **sans** introduire dans l'API publique de prod une fonction nonce-choisi-par-l'appelant (risque de réutilisation de nonce). Recommandation : helper `#[cfg(test)]`/`pub(crate)`.
5. **Emplacement de l'artefact de revue** (`docs/security/` vs README vs ADR) — à confirmer pour rester cohérent avec #6.
6. **PBKDF2/Argon2id (#12) hors périmètre mais adjacent** : ne pas figer un contrat de `derive_key` qui gênerait #12 (calibration d'itérations, éventuel passage à Argon2id si le PRD relâche « PBKDF2 »).
7. **Dépendance #6.** #10 dépend du modèle de menace (#6, déjà livré `docs/threat-model/stride-threat-model.md`) : vérifier que toutes les menaces crypto assignées au module y ont une contre-mesure tracée par #10.
8. **« Greenfield / stack non finalisée » du framing de l'issue est obsolète** : ADR 0001–0009 sont Accepted ; le langage (Rust) et la stack RustCrypto **ne sont pas** une décision ouverte pour ce module. Seuls des choix d'implémentation sous ADR restent à confirmer (ci-dessus).

## Implementation Checklist

1. Lire `crypto-core/src/lib.rs`, ADR 0003, le threat model #6 et confirmer le périmètre (#10 = AES-GCM + nonces ; PBKDF2 = #12, AAD = #11, keystore = #11).
2. Décider (avec #9/#11) : **octet de version** dans le format de fil — oui/non. Documenter la décision (addendum ADR 0003 si oui).
3. Récupérer les vecteurs **NIST CAVP AES-GCM 256 / IV 96** (`gcmEncryptExtIV256`, `gcmDecrypt256`), choisir fichier complet vs sous-ensemble, committer dans `crypto-core/tests/vectors/` avec note de provenance.
4. Ajouter un helper de test `encrypt_with_nonce(key, nonce, aad, pt)` (`#[cfg(test)]`/`pub(crate)`) permettant la comparaison déterministe aux KAT, **sans** exposer un nonce choisi par l'appelant dans l'API de prod.
5. Écrire `crypto-core/tests/aes_gcm_nist_vectors.rs` : KAT encrypt (CT+Tag exacts), KAT decrypt PASS, KAT decrypt **FAIL** (rejet, pas de plaintext), AAD vide + non vide.
6. Durcir `encrypt_record` : séparer clairement l'échec RNG du nonce de l'échec AEAD, sans introduire d'oracle ; garder les erreurs coarse.
7. Ajouter le test « nonce frais » (deux chiffrements identiques → sorties différentes) et les cas de robustesse (G6 : blob court, plaintext vide, mauvaise clé, ct tronqué/étendu, 500 Ko + overhead).
8. Documenter en `//!`/`///` : politique de nonce, format de fil + overhead 28 o, borne de sécurité, contrat d'API, (option) version.
9. Mettre à jour `crypto-core/README.md` (tableau d'API figé, statut, provenance des vecteurs) et aligner les commentaires des placeholders consommateurs (`crypto_core_bindings.dart`, `session.ts`) — **sans** codegen FFI/WASM.
10. Rédiger l'artefact de **revue de sécurité** (`docs/security/crypto-core-review.md`) : checklist tracée (AEAD, nonce unique, no-oracle, wipe, no-unsafe, deps épinglées + audit/deny, no-log de clair/clé) → code/test.
11. Retirer/mettre à jour le `TODO(#10)` dans le module de test ; laisser `TODO(#11)` et `TODO(#12)`.
12. Vérifier le gating : `cargo test -p crypto-core` et `just test` exécutent les vecteurs et échouent si un vecteur casse ; clippy `-D warnings` propre.
13. Mettre à jour la matrice de conformité (preuve « chiffrement client-side » → vecteurs + revue) si attendu.
14. Relire contre les critères d'acceptation : (1) vecteurs officiels passants, (2) revue de sécurité tracée, (3) API stable réutilisable par les apps.
