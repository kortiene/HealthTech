# Service de stockage de blobs zero-knowledge (#9)

> **Issue :** #9 — Service de stockage de blobs zero-knowledge · **Épic :** E7 — Hébergement souverain & backend zero-knowledge · **Jalon :** M0 — Fondations & Conformité · **Effort :** L · **Priorité :** Must · **Étiquettes :** `feature` `backend` `security`
>
> **Type :** spec de planification — **ne pas implémenter** dans cette phase.
>
> **Critères d'acceptation (BACKLOG / issue) :** (1) endpoints `PUT/GET /blob/{uuid}` ; (2) aucune donnée en clair persistée ; (3) des tests **prouvant que le serveur ne peut pas déchiffrer**.

## Problem Statement

HealthTech est **local-first / zero-knowledge** : le dossier médical est chiffré côté patient en **AES-256-GCM** (`crypto-core`, ADR 0003) avant tout transit, et le serveur ne stocke que des **blobs opaques** indexés par un **UUID anonyme**. La sauvegarde cloud du patient (#14), le scan médecin (#17) et la fin de session (#19) dépendent tous d'un service de stockage capable de **persister** et **restituer** ces blobs sans jamais voir de donnée nominative ni de clé.

Aujourd'hui le dépôt contient un **scaffold structure-only** de ce service (`backend/`, marqué `TODO(#9)`) :

- `backend/src/main.rs` — router Axum exposant `GET /health`, `PUT /blob/:uuid`, `GET /blob/:uuid`, avec un **`AppState` en mémoire** (`Arc<RwLock<HashMap<Uuid, Bytes>>>`). Le corps est persisté verbatim ; aucun chemin de déchiffrement n'existe.
- `backend/src/config.rs` — config opérationnelle (#4 / ADR 0007) déjà câblée : `DATABASE_URL`, `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, `PRESIGNED_URL_SIGNING_KEY`, chargées depuis le vault SOPS/age, **fail-fast** en staging/prod, **redaction** systématique des secrets en `Debug`/`Display`. Ces champs sont aujourd'hui `#[allow(dead_code)]`/`Option`, **explicitement réservés à la consommation par #9/#23**.
- ADR 0004 (Rust + Axum), ADR 0005 (stockage : **MinIO** pour les blobs/médias + **PostgreSQL 16** pour les métadonnées non-identifiantes, hébergés in-country).

**Le gap :** remplacer le store en mémoire par la persistance réelle (MinIO + PostgreSQL), durcir l'API (validation d'UUID, budget de taille, codes d'erreur, comportement upsert/concurrence), garantir qu'**aucun clair n'est jamais persisté ni journalisé**, et livrer une **suite de tests prouvant l'impossibilité de déchiffrer côté serveur** — le cœur du critère d'acceptation.

## Goals

- **G1.** Endpoints `PUT /blob/{uuid}` et `GET /blob/{uuid}` fonctionnels sur une persistance durable, conformes à la sémantique HTTP (codes 200/201/400/404/413/503, idempotence, en-têtes de taille/version).
- **G2.** **Persistance des blobs** dans MinIO (objet S3-compatible) et **des métadonnées non-identifiantes** dans PostgreSQL 16 (UUID anonyme, taille du ciphertext, version d'enregistrement, horodatages, paramètres KDF publics) — **aucune PII, aucun clair, aucune clé** (ADR 0005).
- **G3.** **Validation d'entrée** : rejet d'un `{uuid}` non conforme (400) ; **budget de taille** appliqué au ciphertext (≤ 500 Ko de clair + overhead AES-GCM nonce 12 o + tag 16 o, marge documentée), rejet en `413 Payload Too Large` au-delà.
- **G4.** **Zero-knowledge prouvé** : le binaire backend n'a **aucun chemin de déchiffrement** ni champ détenant du matériel de clé patient ; la dépendance à `crypto-core` reste cantonnée à la vérification de vecteurs de test (KAT) et aux types partagés.
- **G5.** **Aucune fuite par les logs** : ni le corps (ciphertext), ni des en-têtes sensibles, ni de PII ne sont journalisés ; seuls des champs non-identifiants (UUID anonyme, taille, statut HTTP, latence) le sont, à niveau maîtrisé.
- **G6.** Abstraction `BlobStore` permettant une implémentation **en mémoire** (tests/dev) et une implémentation **MinIO + Postgres** (staging/prod), sélectionnée par `APP_ENV`/config, sans dupliquer la logique HTTP.
- **G7.** **Résilience** : indisponibilité du store → `503` propre (pas de panique, pas de fuite de détail interne) ; comportement défini en cas d'écriture concurrente / réécriture d'un même UUID (versionnement optimiste).
- **G8.** Suite de tests (unitaires + intégration) **prouvant** : (a) le round-trip opaque d'octets arbitraires, (b) qu'aucun clair n'est persisté, (c) que sans la clé patient le déchiffrement échoue, (d) que le backend n'expose aucun symbole de déchiffrement.

## Non-Goals

- **Chiffrement/déchiffrement côté client** (#10, `crypto-core`) — déjà scaffoldé ; le backend ne chiffre ni ne déchiffre, il stocke des octets.
- **Sauvegarde cloud côté patient** (#14) et **scan/déchiffrement médecin en RAM** (#17) — *consommateurs* de cette API, hors périmètre.
- **Déport des images médicales lourdes + URL éphémère présignée** (#23) — la signature des URLs présignées (`PRESIGNED_URL_SIGNING_KEY`) et le store média sont une issue distincte ; on provisionne MinIO mais on n'implémente pas la logique d'URL éphémère ici. *À cadrer : un GET par range basique peut atterrir ici ou en #24.*
- **File offline SQLCipher / synchronisation au retour réseau** (#21, #22) — côté client ; le backend expose seulement le relais de blobs idempotent qu'elles consommeront.
- **Génération du QR éphémère (~120 s)** (#16) — côté patient ; le backend ne voit jamais la clé symétrique transportée par le QR.
- **Provisionnement de l'hébergement souverain in-country** (#8) — MinIO/Postgres/TLS/HA sont déployés par l'IaC de #8 ; #9 *consomme* ces services via la config injectée.
- **Authentification/autorisation forte des appelants** — voir *Risks & Open Questions* : à trancher avec le threat model (#6) ; un contrôle d'écriture minimal peut être inclus si décidé, sinon documenté comme dette.
- **Toute opération git/GitHub** (branches, commits, PR) — hors périmètre de cette phase ADW.

## Relevant Repository Context

**Statut stack — déjà tranché (nuance importante vs framing de l'issue).** Le BACKLOG décrit le projet comme greenfield « stack non finalisée (#1) », mais à la date de cette spec **#1 est tranché** : les ADR 0001–0008 sont *Accepted*. Pour #9 cela signifie :

- **Backend : Rust + Axum (Tokio)**, binaire statique musl, même workspace cargo que `crypto-core` (ADR 0004). `Cargo.toml` racine : `members = ["crypto-core", "backend"]`.
- **Stockage : MinIO** (blobs/médias, S3-compatible, self-hosted) **+ PostgreSQL 16** (métadonnées non-identifiantes) (ADR 0005).
- **Secrets/config** : injectés depuis SOPS/age via l'environnement (ADR 0007), déjà modélisés dans `backend/src/config.rs`.
- **Crypto** : `crypto-core` (ADR 0003) est le **seul** lieu d'AES-256-GCM/PBKDF2 ; format de fil `nonce(12) || ciphertext || tag(16)`. Le backend n'en consomme **que** les types/KAT.

**Décisions encore ouvertes (à confirmer, voir checklist) :** client S3 Rust (`aws-sdk-s3` vs `rust-s3`/`minio`), couche Postgres (`sqlx` vs `tokio-postgres` + `deadpool`), outil de migrations (`sqlx migrate` vs `refinery`), harnais d'intégration (`testcontainers` vs MinIO/Postgres éphémères en CI), stratégie de versionnement/concurrence (ETag/`If-Match` vs colonne `version`), et présence ou non d'un contrôle d'écriture (token de capacité). Ce sont des choix **d'implémentation** sous les ADR existants, pas une réouverture de #1.

**Conventions observées (à respecter) :**
- Lints stricts : `crypto-core` est `#![forbid(unsafe_code)]` + `#![deny(warnings)]` ; viser la même rigueur côté backend (clippy `-D warnings` en CI, cf. `justfile`/ADR 0008).
- Secrets : tout secret enveloppé dans `Secret` (redaction `Debug`/`Display`, accès explicite via `.expose()`).
- Tests : `cargo test --workspace` via `just test-rust` ; `just test` est le **gate ADW** canonique.
- Docs de module en `//!`, handlers documentés, `TODO(#n)` traçant les dépendances inter-issues.
- Specs : prose FR, titres EN (cf. `specs/sovereign-hosting-provisioning-cote-divoire.md`).

## Proposed Implementation

### 1. Abstraction de stockage (`BlobStore`)

Introduire un trait async `BlobStore` (objet-safe ou générique selon le choix client) découplant les handlers HTTP du backing :

```text
trait BlobStore {
    async fn put(uuid, ciphertext, meta) -> Result<PutOutcome, StoreError>;   // Created | Replaced(version)
    async fn get(uuid) -> Result<Option<StoredBlob>, StoreError>;             // None => 404
    async fn health() -> Result<(), StoreError>;                              // pour /health profond
}
```

- **`MemoryStore`** — reprend le `HashMap` actuel ; backing par défaut en `dev` et dans les tests.
- **`ObjectMetaStore`** (MinIO + Postgres) — backing en `staging`/`prod` :
  - **MinIO** : `put_object`/`get_object` du **ciphertext opaque** dans un bucket dédié (clé d'objet = UUID). SSE-at-rest activé (défense en profondeur *sous* le chiffrement client — la confidentialité n'en dépend jamais, ADR 0005).
  - **PostgreSQL** : table `blob_metadata` avec **uniquement** des colonnes non-identifiantes (cf. *Data Model*). Aucune écriture de PII/clair/clé.
- Sélection du backing par `Config`/`APP_ENV` au démarrage (fail-fast si secrets requis manquants — déjà géré par `config.rs`).

### 2. Handlers HTTP (Axum)

- `PUT /blob/{uuid}` :
  1. Extraire/valider `Uuid` (l'extracteur `Path<Uuid>` renvoie déjà 400 sur format invalide ; confirmer le mapping).
  2. Appliquer un **plafond de corps** (`DefaultBodyLimit`/layer) = 500 Ko + overhead AES-GCM + petite marge ; dépassement → `413`.
  3. Persister le corps **verbatim** (jamais inspecté) + enregistrer la métadonnée (taille, version, timestamps).
  4. Répondre `201 Created` (création) ou `200 OK` (réécriture/upsert) ; exposer `ETag`/`X-Blob-Version` pour la concurrence optimiste (cf. #22).
- `GET /blob/{uuid}` :
  1. Valider l'UUID, récupérer le ciphertext ; absent → `404`.
  2. Répondre `200` avec `Content-Type: application/octet-stream`, `Content-Length`, `ETag`.
  3. *(À cadrer)* support `Range`/reprise pour la résilience 3G (ADR 0004) — peut être un sous-incrément, sinon laissé à #24.
- `GET /health` : conserver la liveness `200 "ok"` ; optionnellement une variante *readiness* qui ping `BlobStore::health()`.
- **Gestion d'erreur centralisée** : `StoreError` → statut HTTP **sans détail interne** (indispo → `503`, introuvable → `404`, validation → `400/413`). Aucune panique sur chemin requête (remplacer les `.expect("blob store poisoned")` par une gestion d'erreur propre).

### 3. Garanties zero-knowledge & journalisation

- Le backend **ne dépend de `crypto-core`** que pour les types partagés et la vérification KAT — **interdiction de tout appel à `decrypt_record`** côté backend (vérifié par test, cf. *Testing*).
- **Aucun corps journalisé.** Logging structuré `tracing` limité à : UUID anonyme (capability — voir Open Questions sur l'opportunité de le logger), taille, statut, latence. Jamais d'en-tête d'autorisation, jamais de clé, jamais de clair.
- Réutiliser le pattern `Secret` pour tout credential de connexion (DSN, clés MinIO).

### 4. Migrations & démarrage

- Migration SQL versionnée créant `blob_metadata` (idempotente, rejouable en CI).
- Au boot : charger `Config`, instancier le backing, exécuter/vérifier les migrations (staging/prod), bind, servir. Fail-fast déjà en place.

## Affected Files / Packages / Modules

**À lire :**
- `backend/src/main.rs`, `backend/src/config.rs`, `backend/Cargo.toml`, `backend/README.md`
- `crypto-core/src/lib.rs` (types/KAT, format de fil)
- `docs/adr/0003`, `0004`, `0005`, `0007` ; `Cargo.toml` (racine) ; `justfile` (gates `test-rust`, `ci`)
- `docs/threat-model/stride-threat-model.md` (#6) ; `docs/compliance/loi-2013-450-artci-matrix.md` (#5)

**À créer / modifier (probable) :**
- `backend/src/main.rs` — router + handlers branchés sur `BlobStore`, body-limit, gestion d'erreur (remplacer les `expect`).
- `backend/src/store.rs` (+ `store/memory.rs`, `store/object_meta.rs`) — trait + implémentations.
- `backend/src/error.rs` — `StoreError`/`ApiError` → mapping HTTP.
- `backend/src/db.rs` — pool Postgres + accès `blob_metadata`.
- `backend/migrations/0001_blob_metadata.sql` — schéma métadonnées.
- `backend/src/config.rs` — éventuel ajout `MAX_BLOB_BYTES`/nom de bucket (sinon constantes).
- `backend/Cargo.toml` — client S3, couche Postgres, harnais de test (décisions à confirmer).
- `backend/tests/*.rs` — tests d'intégration (round-trip, no-decrypt, no-plaintext, 4xx/503).
- `backend/README.md` — endpoints, codes, contrat de config, garanties ZK.
- `justfile` / CI — étape d'intégration (services éphémères MinIO+Postgres) si retenue.
- *(éventuel)* `docs/adr/00xx-blob-store-abstraction.md` si un choix structurant le justifie.

## API / Interface Changes

Surface réseau (formalise et durcit le scaffold existant) :

| Méthode | Chemin | Corps | Réponses |
| --- | --- | --- | --- |
| `GET` | `/health` | — | `200 "ok"` (liveness) ; *(option)* `503` si readiness profond échoue |
| `PUT` | `/blob/{uuid}` | ciphertext opaque (`application/octet-stream`) | `201 Created` (nouveau) · `200 OK` (réécrit) · `400` UUID invalide · `413` au-delà du budget · `503` store indisponible |
| `GET` | `/blob/{uuid}` | — | `200` (ciphertext + `Content-Length`, `ETag`) · `400` UUID invalide · `404` inconnu · `503` store indisponible |

- `{uuid}` = **index anonyme** (UUID v4) ; jamais dérivé d'une PII.
- En-têtes ajoutés : `ETag`/`X-Blob-Version` (concurrence optimiste, support futur `If-Match` pour #22). À confirmer.
- *(À cadrer)* `Range`/`206 Partial Content` en GET pour la reprise sur réseau dégradé (ADR 0004) — sinon différé à #24.
- **Pas de nouvelle surface CLI ni de QR/token** dans #9. Les URL présignées éphémères relèvent de #23.

## Data Model / Protocol Changes

- **Format de blob : inchangé et opaque.** Le backend ne connaît **pas** la structure interne ; le format de fil `nonce(12) || ciphertext || tag(16)` est défini et géré par `crypto-core` côté client. Le serveur stocke/retourne des octets bruts.
- **Nouveau : table PostgreSQL `blob_metadata`** — *uniquement non-identifiant* :
  - `uuid` (PK, UUID anonyme) ; `ciphertext_size` (octets) ; `record_version` / `blob_version` (entier, concurrence) ; `created_at`, `updated_at` ; *(optionnel, publics par design)* `kdf_salt`, `kdf_iterations` (ADR 0005). **Aucune** colonne PII / clair / clé / CMU / téléphone.
- **Nouveau : objets MinIO** — un objet ciphertext par UUID dans un bucket dédié, SSE-at-rest activé.
- Le **budget ≤ 500 Ko de clair** se traduit côté serveur par un plafond sur la **taille du ciphertext** (500 Ko + 28 o d'overhead AES-GCM + marge), appliqué à `PUT` et reflété dans `ciphertext_size`.

## Security & Compliance Considerations

- **AES-256-GCM côté client uniquement** (`crypto-core`, ADR 0003) ; le serveur ne chiffre ni ne déchiffre — il n'a **ni clé ni chemin de déchiffrement**. C'est la garantie zero-knowledge centrale, à **prouver par test** (critère d'acceptation #9).
- **Blobs opaques indexés par UUID anonyme** : le serveur ne voit jamais de donnée nominative ; l'UUID n'est jamais dérivé d'une PII.
- **Clés patient (maîtresse, dérivée PBKDF2, clé de session QR)** : **jamais** transmises au serveur. Seules des **clés opérationnelles** (DSN Postgres, credentials MinIO, signature d'URL présignée) existent côté serveur, toutes enveloppées dans `Secret` (redaction) et injectées via SOPS/age (ADR 0007).
- **QR éphémère (~120 s) & déchiffrement en RAM + wipe de session** (#16/#17/#19) : hors backend, mais #9 ne doit rien introduire qui suppose la persistance d'une clé ou d'un clair côté serveur.
- **Résidence des données (ARTCI / loi n°2013-450)** : blobs (MinIO), métadonnées (Postgres) et sauvegardes **restent en Côte d'Ivoire** ; aucun cloud managé étranger dans le chemin de données. Le garde-fou `scripts/check-residency.sh` (CI) reste vert ; aucune dépendance/endpoint étranger introduit. Tracer les contrôles dans la matrice de conformité (#5).
- **Budget ≤ 500 Ko** : plafond appliqué au ciphertext (rejet `413`) pour garantir téléchargement/déchiffrement instantanés en Edge/3G.
- **Images médicales lourdes** : jamais sur l'appareil patient ; stockées via MinIO + URL éphémère — **logique en #23**, non implémentée ici.
- **Logging/redaction** : ne **jamais** journaliser le corps (ciphertext), les credentials, ni de PII. Logs limités à des champs non-identifiants. Pas de panique exposant un état interne.
- **Surface d'écriture** : un `PUT` non authentifié permet écrasement/DoS d'un UUID connu (le ciphertext reste illisible, mais disponibilité/intégrité sont en jeu). À arbitrer avec le threat model (#6) : token de capacité, concurrence optimiste `If-Match`, quotas/rate-limit. Voir *Open Questions*.

## Testing Plan

**Unitaires (backend) :**
- Validation d'UUID : format valide accepté, invalide → `400`.
- Budget de taille : corps ≤ plafond accepté ; > plafond → `413`.
- `MemoryStore` : put→get round-trip d'octets arbitraires (y compris octets nuls/0xFF) ; get inconnu → `None`/`404` ; réécriture incrémente la version.
- Mapping `StoreError` → HTTP (indispo → `503`) sans fuite de détail.

**Preuve zero-knowledge (critère d'acceptation — obligatoire) :**
- **No-plaintext-persisted** : chiffrer un marqueur clair connu via `crypto-core`, `PUT` le ciphertext, puis inspecter ce que le serveur détient (octets stockés + lignes `blob_metadata`) et **asserter l'absence** du marqueur clair et de toute PII.
- **Server-cannot-decrypt** : à partir des seules données persistées (ciphertext + métadonnées) et **sans** la clé, `crypto-core::decrypt_record` échoue (`CryptoError::Decrypt`) ; avec la bonne clé (côté client de test) il réussit — démontrant que seul le détenteur de la clé peut lire.
- **No-decrypt-symbol** : test/garde-fou vérifiant que le crate backend n'appelle aucun chemin de déchiffrement et ne détient aucun champ de clé patient (revue + assertion statique : aucune référence à `decrypt_record` hors KAT).
- **Opaque round-trip (property-based)** : pour des octets arbitraires, `GET(PUT(x)) == x` exactement.

**Intégration (MinIO + Postgres) :**
- Round-trip complet contre des services éphémères (`testcontainers` ou conteneurs CI) ; persistance survit à un redémarrage du process ; métadonnées correctement écrites (taille/version/timestamps), **sans PII**.
- Concurrence : deux `PUT` concurrents sur le même UUID → état cohérent + sémantique de version définie.

**Résilience / dégradé :**
- Store indisponible (MinIO/Postgres down) → `503` propre, pas de panique, pas de fuite.
- *(Si Range retenu)* reprise d'un GET partiel ; sinon documenter le report en #24.

**Sécurité/logs :**
- Asserter qu'aucune sortie `tracing` ne contient le ciphertext, un credential, ou de PII (test de capture de logs sur un cas nominal et un cas d'erreur).

**Gate :** tout passe sous `just test` (`cargo test --workspace`), clippy `-D warnings`, garde-fou résidence vert.

## Documentation Updates

- **`backend/README.md`** : endpoints définitifs, codes HTTP, en-têtes (`ETag`/version), budget de taille, contrat de config, et énoncé explicite des garanties zero-knowledge (no-decrypt, no-plaintext).
- **BACKLOG.md** : marquer #9 livré une fois mergé (cohérence avec l'ordre d'implémentation) — *via l'orchestrateur, pas dans cette phase*.
- **ADR** : addendum à ADR 0004/0005 si un choix structurant émerge (abstraction `BlobStore`, versionnement) ; sinon référencer les ADR existants.
- **Matrice de conformité (#5)** : ajouter/mettre à jour les preuves « aucun clair persisté » et « pas de clé serveur » (lien vers les tests ZK).
- **Threat model (#6)** : refléter la décision sur le contrôle d'écriture / rate-limit.
- **`.env.example`** : confirmer la présence des variables consommées (déjà listées) + éventuel `MAX_BLOB_BYTES`/nom de bucket.

## Risks and Open Questions

1. **Authz d'écriture (à trancher avec #6).** `PUT` non authentifié = risque d'écrasement/DoS sur UUID connu. Faut-il un token de capacité, `If-Match`/version optimiste, rate-limit, quotas ? Décision à confirmer ; à défaut, documenter comme dette tracée.
2. **Versionnement & conflits.** Schéma de version (ETag vs colonne `version`) à figer maintenant car #22 (sync offline) en dépendra ; un mauvais choix est coûteux à rétro-fitter.
3. **Choix de bibliothèques (sous ADR existants).** Client S3 (`aws-sdk-s3` vs `rust-s3`), Postgres (`sqlx` vs `tokio-postgres`+pool), migrations, harnais d'intégration (`testcontainers`) — à confirmer ; impact sur `deny.toml`/SCA.
4. **Range/resumable.** Inclus dans #9 (ADR 0004) ou différé à #24 ? Décision de périmètre.
5. **MinIO + Postgres réels** dépendent du provisionnement #8 (in-country). Pour dev/CI, des services éphémères suffisent ; staging/prod attendent #8.
6. **Cohérence inter-stores (MinIO/Postgres).** Écriture en deux temps (objet puis métadonnée) : définir l'ordre et le comportement en cas d'échec partiel (idempotence du `PUT`, réconciliation).
7. **Framing « stack non finalisée » du BACKLOG.** Superseded par les ADR 0001–0008 *Accepted* ; confirmer qu'aucun choix de #9 ne réouvre #1.

## Implementation Checklist

1. Confirmer les décisions ouvertes (Open Questions 1–4) : authz d'écriture, versionnement, libs, Range — idéalement via une note/ADR courte.
2. Définir le trait `BlobStore` (`put`/`get`/`health`) dans `backend/src/store.rs`.
3. Extraire l'implémentation `MemoryStore` (depuis l'`AppState` actuel) comme backing dev/test.
4. Ajouter `StoreError`/`ApiError` + mapping HTTP centralisé ; **supprimer les `.expect()`** des chemins requête (plus de panique → `503`).
5. Implémenter `ObjectMetaStore` : client MinIO (put/get objet, SSE-at-rest) + pool Postgres + accès `blob_metadata`.
6. Écrire la migration `0001_blob_metadata.sql` (colonnes **non-identifiantes** uniquement) ; rejouable en CI.
7. Câbler la sélection du backing via `Config`/`APP_ENV` (réutiliser `injected_storage_secrets()` pour le fail-fast).
8. Durcir les handlers : validation UUID (`400`), `DefaultBodyLimit` au budget (≤500 Ko clair + overhead → `413`), `201`/`200`, en-têtes `Content-Length`/`ETag`.
9. *(Si retenu)* support `Range`/`206` en GET ; sinon noter le report en #24.
10. Garantir le contrat de logs : aucun corps/credential/PII journalisé ; champs non-identifiants seulement.
11. Tests unitaires : UUID, budget, round-trip mémoire, mapping d'erreur.
12. Tests preuve ZK : no-plaintext-persisted, server-cannot-decrypt, no-decrypt-symbol, opaque round-trip (property-based).
13. Tests d'intégration MinIO+Postgres (services éphémères) : round-trip, persistance après redémarrage, métadonnées sans PII, concurrence, `503` si store down.
14. Mettre à jour `backend/Cargo.toml` (libs) et vérifier `deny.toml`/SCA.
15. Mettre à jour `backend/README.md`, la matrice de conformité (#5) et le threat model (#6) selon les décisions.
16. Vérifier les gates verts : `just test` (`cargo test --workspace`), clippy `-D warnings`, `scripts/check-residency.sh`.
