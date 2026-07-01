# Revue Cryptographique Indépendante — Brief Externe (issue #26)

> **Commanditaire :** Équipe HealthTech (kortiene/HealthTech)
> **Périmètre :** Bibliothèque `crypto-core` (Rust, RustCrypto) et son intégration
> applicative (Flutter, PWA Preact/TS, backend Axum)
> **Priorité :** Should · M4 — Durcissement & lancement
> **Revue interne préalable :** [`docs/security/crypto-core-review.md`](./crypto-core-review.md) (issue #10)
> **Modèle de menace :** [`docs/threat-model/stride-threat-model.md`](../threat-model/stride-threat-model.md) (issue #6)
> **Acceptation :** Avis d'expert favorable ou correctifs appliqués (issue #26)

---

## 1. Contexte et enjeux

HealthTech est une plateforme de santé numérique **local-first / zero-knowledge** pour la Côte d'Ivoire. Le patient porte son dossier médical chiffré sur son smartphone et accorde un accès éphémère à un professionnel de santé via QR code (~120 s). Le serveur stocke exclusivement des blobs chiffrés opaques indexés par UUID anonymes — il n'a ni la clé ni aucun chemin de déchiffrement.

**La sécurité de toute la plateforme repose sur un seul module Rust** (`crypto-core`) et sur le respect strict de la frontière zero-knowledge. L'objectif de cette revue est d'obtenir une **confirmation indépendante** que les choix cryptographiques, l'implémentation et les paramètres de sécurité sont corrects et résistants aux attaques connues.

---

## 2. Périmètre de la revue

### 2.1 Fichiers à auditer (priorité P1)

| Fichier | Rôle |
|---|---|
| `crypto-core/src/lib.rs` | Implémentation AES-256-GCM, PBKDF2, gestion des clés — **code à auditer en priorité** |
| `crypto-core/Cargo.toml` | Dépendances épinglées (versions et checksums à vérifier) |
| `crypto-core/tests/aes_gcm_nist_vectors.rs` | Vecteurs NIST connus CAVP |
| `crypto-core/tests/pbkdf2_rfc6070_vectors.rs` | Vecteurs RFC 6070 PBKDF2 |
| `crypto-core/tests/vectors/PROVENANCE.md` | Traçabilité des vecteurs de test |

### 2.2 Fichiers à auditer (priorité P2 — intégration)

| Fichier | Rôle |
|---|---|
| `app-patient/lib/src/rust/crypto_core_bindings.dart` | Bindings FFI Flutter ↔ Rust |
| `app-patient/lib/src/secure/master_key_service.dart` | Gestion du handle de clé maîtresse |
| `app-patient/lib/src/qr/access_token.dart` | QR éphémère, TTL 120 s |
| `app-patient/lib/src/record/medical_record_store.dart` | Chiffrement + compression (#24) |
| `app-patient/lib/src/record/plaintext_compressor.dart` | Gzip avant AES-256-GCM (#24) |
| `backend/src/media/access.rs` | HMAC-SHA256 capability URLs (#23) |

### 2.3 Hors périmètre

- Interface utilisateur, flux d'onboarding, UI Flutter
- Infrastructure Terraform, secrets SOPS
- Tests de performance Edge/3G (issue #27)
- Revue légale ARTCI (issue #30)

---

## 3. Primitives cryptographiques utilisées

### 3.1 Chiffrement des données médicales

| Paramètre | Valeur | Justification |
|---|---|---|
| **Algorithme** | AES-256-GCM (AEAD) | NIST SP 800-38D ; confidentialité + intégrité en un seul passage |
| **Taille de clé** | 256 bits (32 octets) | Résiste à l'accélération quantique (Grover → sécurité 128 bits post-Q) |
| **Nonce** | 96 bits, aléatoire par appel, CSPRNG OS (`getrandom`) | Jamais compteur, jamais réutilisé sous une clé donnée |
| **Tag d'authentification** | 128 bits (16 octets, plein) | Jamais tronqué ; `TAG_LEN = 16` codé en dur |
| **Format de fil** | `nonce(12) ‖ ciphertext ‖ tag(16)` | Stable v1, 28 o de surcharge, pas d'octet de version (décision documentée) |
| **Implémentation** | `aes-gcm` (RustCrypto) | Crate auditée, `#![forbid(unsafe_code)]` |
| **AAD** | Vide en v1 (AAD différé au #11, additif) | Décision documentée dans `crypto-core-review.md` |

**Points à vérifier :**
- [ ] Aucune API n'expose un nonce choisi par l'appelant
- [ ] Le tag 128 bits n'est jamais tronqué dans aucune branche du code
- [ ] L'échec CSPRNG empêche toute émission de nonce nul/dégénéré
- [ ] La réutilisation de nonce est rendue structurellement impossible par l'API

### 3.2 Dérivation et récupération de clé

| Paramètre | Valeur | Justification |
|---|---|---|
| **Algorithme** | PBKDF2-HMAC-SHA256 | RFC 8018 / NIST SP 800-132 |
| **Itérations (défaut)** | 600 000 | OWASP 2023 recommande ≥ 600 000 pour PBKDF2-SHA256 |
| **Itérations (plancher)** | 210 000 | Calibré pour les smartphones entrée de gamme (Infinix ~500 ms) ; refus des enveloppes en dessous |
| **Sel** | 256 bits (32 octets), aléatoire CSPRNG, stocké avec l'enveloppe | Anti-dictionnaire, anti-rainbow |
| **Longueur de sortie** | 256 bits (32 octets → clé AES-256) | Adaptée |

**Format de l'enveloppe de récupération :**
```
byte 0  : version de schéma (actuellement = 1)
byte 1  : identifiant KDF (1 = PBKDF2-HMAC-SHA256)
byte 2  : longueur du sel (32)
bytes 3–34 : sel aléatoire (32 octets)
bytes 35–38 : itérations (u32 big-endian)
bytes 39–… : encrypt_record(recovery_key, master_key_clear)
```

**Points à vérifier :**
- [ ] Le plancher d'itérations est appliqué côté `open_recovery_envelope` (pas uniquement à la création)
- [ ] La clé dérivée est zéroïsée après usage (`Zeroizing<>`)
- [ ] L'enveloppe est transmise uniquement via un canal chiffré (TLS)
- [ ] La réponse culturelle (questions de récupération) est normalisée avant dérivation (casse, unicode)

### 3.3 Gestion de la clé maîtresse

| Mécanisme | Détail |
|---|---|
| **Génération** | CSPRNG OS 256 bits, `generate_master_key()` |
| **Stockage** | Android Keystore StrongBox/TEE — jamais en clair sur disque |
| **Export** | Uniquement via `export_sealable()` pour scellement immédiat hardware |
| **Zeroize** | `wipe()` consomme le handle (move) et zéroïse la mémoire via la crate `zeroize` |
| **In-RAM** | `MasterKeyHandle` : Rust, stack-only, dropped → zéroïsé automatiquement |

**Points à vérifier :**
- [ ] Aucune sérialisation de `MasterKeyHandle` (pas de `Debug`, pas de `Serialize`)
- [ ] `wipe()` est appelé dans tous les chemins (succès et échec) via `try { ... } finally`
- [ ] Le canal Kotlin ↔ Rust efface les bytes immédiates après scellement

### 3.4 QR d'accès éphémère

| Paramètre | Valeur |
|---|---|
| **Contenu du QR** | URL blob + clé AES-256 en clair (base64) |
| **TTL** | 120 secondes, vérifié côté professionnel |
| **Stockage clé** | Uniquement dans le QR (jamais persisté) |
| **Rafraîchissement** | Nouveau QR = nouvelle clé éphémère |

**Points à vérifier :**
- [ ] La clé éphémère QR n'est jamais persistée côté patient (RAM uniquement)
- [ ] Le TTL est vérifié cryptographiquement (timestamp signé ou claim JWT), pas seulement par confiance client
- [ ] Après 120 s, une présentation du QR expiré est refusée

### 3.5 URLs de médias éphémères (HMAC-SHA256)

| Paramètre | Valeur |
|---|---|
| **Signature** | HMAC-SHA256 sur `uuid:expires_at_unix` |
| **TTL** | 300 secondes (5 min) |
| **Secret** | `PRESIGNED_URL_SIGNING_KEY` (injecté via SOPS, jamais dans le code) |

**Points à vérifier :**
- [ ] La comparaison HMAC est en temps constant (pas de timing oracle)
- [ ] L'expiration est vérifiée côté serveur avant la vérification HMAC
- [ ] Le secret de signature est absent du code source et des logs

### 3.6 Compression avant chiffrement (#24)

| Décision | Valeur |
|---|---|
| **Ordre** | Gzip plaintext → AES-256-GCM → wire | 
| **Justification** | Standard (TLS fait de même) ; le tag GCM couvre le comprimé |
| **Rétrocompat** | Détection magic-byte `0x1f 0x8b` post-déchiffrement |

**Points à vérifier :**
- [ ] La compression est appliquée AVANT le chiffrement (pas après — ce serait inutile sur du ciphertext aléatoire)
- [ ] Le décompresseur est sûr vis-à-vis des données malformées (bombe gzip) — la taille est bornée par le budget 500 Kio du plaintext
- [ ] Aucune information sur le plaintext n'est inférée depuis la taille comprimée (oracle de compression sur canal chiffré) — pas un vecteur d'attaque ici car le canal est HTTPS, pas un oracle en temps réel

---

## 4. Frontière zero-knowledge — invariants à vérifier

| Invariant | Vérification attendue |
|---|---|
| **ZK-1** | Le serveur backend ne reçoit jamais de clé, de texte en clair, ni de PII |
| **ZK-2** | Les blobs sont indexés par UUID anonyme non corrélé à l'identité patient |
| **ZK-3** | Le déchiffrement se produit exclusivement en RAM côté professionnel |
| **ZK-4** | La session médecin est effacée (RAM wipe) à la fin ou après 15 min d'inactivité |
| **ZK-5** | Les logs backend ne contiennent que le status HTTP et l'UUID (jamais le corps, jamais les clés) |

---

## 5. Vecteurs de test connus à reproduire

```bash
# AES-256-GCM NIST CAVP (reproductibles localement)
cargo test --package crypto-core

# PBKDF2 RFC 6070
cargo test --package crypto-core pbkdf2

# Vérification des FAIL vectors (intégrité)
cargo test --package crypto-core nist_kat_decrypt_fails

# Vecteurs round-trip + bornage oracle
cargo test --package crypto-core -- --include-ignored
```

Tous les vecteurs sont reproductibles hors réseau. Le ficher `PROVENANCE.md` détaille la source officielle.

---

## 6. Dépendances RustCrypto à auditer

| Crate | Version épinglée | Rôle |
|---|---|---|
| `aes-gcm` | 0.10 | AES-256-GCM AEAD |
| `pbkdf2` | 0.12 | Dérivation PBKDF2 |
| `sha2` | 0.10 | SHA-256 (dans PBKDF2 et HMAC backend) |
| `hmac` | 0.12 | HMAC-SHA256 (backend capability URLs) |
| `getrandom` | via transitive | CSPRNG OS |
| `zeroize` | via transitive | Zéroïsation mémoire |
| `hex` | 0.4 | Encodage hex pour HMAC signatures |

Toutes ces crates font partie de l'organisation **RustCrypto** et ont été auditées par des tiers.
Le réviseur doit vérifier que les versions épinglées dans `Cargo.lock` correspondent aux checksums publiés sur crates.io.

---

## 7. Questions ouvertes pour le réviseur

1. **PBKDF2 vs Argon2id** : Le PRD mandate « PBKDF2 + questions culturelles » (#12). Un passage à Argon2id (mémoire-dur) est prévu si l'expert le juge nécessaire. Le plancher 210 000 itérations est-il suffisant sur un attaquant GPU 2026 ?

2. **AAD différé** : L'enveloppe GCM v1 n'inclut pas d'AAD (domaine de séparation). Le risque de confusion entre le blob de dossier et l'enveloppe de récupération est-il acceptable en l'état ?

3. **Compression oracle** : Même si le canal est TLS, l'envoi conditionnel de la taille comprimée vers le serveur crée-t-il un vecteur d'attaque oracle sur les sessions longues (CRIME-like) ?

4. **Wipe mémoire Dart/JS** : Le `wipe()` Rust est robuste. Mais le code Dart (`MasterKeyService.wipeHandle`) et TypeScript (`session.ts`) opèrent dans des runtimes à GC — le zéroïsage est-il suffisant ou faut-il une stratégie complémentaire (pinning mémoire) ?

5. **Enveloppe de récupération en transit** : La clé maîtresse chiffrée voyage via TLS. Est-ce qu'un mécanisme supplémentaire d'intégrité ou d'anti-replay est nécessaire ?

---

## 8. Livrables attendus du réviseur externe

1. **Rapport d'audit** couvrant chaque primitif listé en §3, les invariants ZK de §4, et les questions de §7.
2. **Liste des vulnérabilités** avec niveau de criticité (Critical/High/Medium/Low/Informational).
3. **Pour chaque Critical/High** : recommandation de correctif et protocole de re-test.
4. **Avis global** : « favorable » (système sûr pour le lancement M4) ou « conditionnel » (correctifs requis avant lancement).

L'avis favorable (ou les correctifs appliqués) est le critère d'acceptation de l'issue #26 et une pièce probante pour l'homologation ARTCI (#30).

---

## 9. Accès au code

```bash
git clone https://github.com/kortiene/HealthTech.git
cd HealthTech
# Compiler le module crypto
cd crypto-core && cargo test
# Lancer la revue ciblée
cargo test --package crypto-core -- --nocapture
```

Aucun secret réel n'est requis pour la revue. Les vecteurs de test sont entièrement déterministes.
