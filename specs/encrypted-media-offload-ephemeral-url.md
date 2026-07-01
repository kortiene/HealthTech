# Déport des images médicales sur serveur chiffré + URL éphémère (issue #23)

> **Issue :** #23 — Déport des images médicales sur serveur chiffré + URL éphémère · **Épic :** E5 — Gestion des médias lourds · **Jalon :** M3 — Résilience hors-ligne & médias · **Effort :** L · **Priorité :** Must · **Étiquettes :** `feature` `security` `infra`
>
> **Type :** spec de planification — **ne pas implémenter** dans cette phase. Aucune opération git/GitHub (l'orchestrateur ADW s'en charge).
>
> **Critères d'acceptation (BACKLOG / issue) :** (1) **aucune image lourde sur le téléphone patient** ; (2) **URL éphémère révoquée après expiration**.
>
> **Implémente :** PRD §4 (« Interdiction de stocker les images médicales lourdes … sur le téléphone du patient. Elles sont stockées sur un serveur distant chiffré et seul un lien d'accès (URL éphémère) est intégré au dossier texte. »).

## Problem Statement

Les radiographies et scans sont volumineux (souvent plusieurs Mo) et ne peuvent pas tenir dans le
budget de **≤ 500 Ko de texte brut** du dossier médical (PRD §4, BACKLOG #15). Les stocker sur le
téléphone du patient — souvent un Infinix d'entrée de gamme à 32 Go saturé (persona « Awa ») —
saturerait l'appareil et créerait un dépôt non chiffré de données de santé sensibles vulnérable au
vol de téléphone (menace #6).

L'architecture cible (PRD §4, ADR 0005) impose donc de **déporter** ces médias lourds : ils sont
chiffrés côté client, stockés sur le serveur souverain (MinIO in-country), et **seul un lien d'accès
éphémère** est rattaché au dossier texte. Le dossier reste léger et le téléphone ne conserve aucune
image lourde.

**Aujourd'hui le dépôt ne contient que des points d'ancrage, pas de logique média :**

- **Schéma dossier (`app-patient/lib/src/record/medical_record.dart`)** : `Consultation.imageUrls`
  (`image_urls: string[]`) existe déjà, documenté « Ephemeral CDN URLs — no binary data, no
  credentials » (#15). C'est un placeholder : **aucune** logique de téléversement, de chiffrement, de
  fetch, ni de minting d'URL n'existe.
- **Backend (`backend/src/config.rs`)** : `presigned_url_signing_key` (`PRESIGNED_URL_SIGNING_KEY`,
  `Option<Secret>`) est câblé et explicitement marqué *« Consumed by #23 »*, de même que les champs
  MinIO (`minio_endpoint`, `minio_access_key`, `minio_secret_key`). Aucun endpoint média n'existe.
- **Backend (`backend/src/main.rs`)** : `TODO(#23): presigned short-TTL ephemeral media URLs + HTTP
  range / resumable (tus) uploads.` — le routeur n'expose que `/health` et `/blob/{uuid}` (#9).
- **ADR 0005 (Accepted)** scope explicitement #23 : *« media object store: self-hosted MinIO … The
  Rust backend issues **short-TTL presigned/ephemeral URLs** for heavy media, tightly per-object
  scoped and revocable. »*

**Le gap :** définir et livrer (a) un **store média chiffré** côté serveur (bucket MinIO dédié +
métadonnées non-identifiantes), (b) une **API de téléversement/minting d'URL éphémère/lecture**
côté backend, (c) le **chiffrement client + déport** côté app (capture médecin → chiffrement
AES-256-GCM → upload → descripteur dans le dossier), (d) la garantie qu'**aucune image lourde n'est
persistée sur le téléphone patient** et que **l'URL éphémère expire/est révoquée**.

## Goals

- **G1.** Les médias lourds sont **chiffrés côté client** (AES-256-GCM via `crypto-core`) avant tout
  transit ; le serveur ne stocke que des **octets opaques** keyés par un **UUID média anonyme** et
  n'a **aucun chemin de déchiffrement** (zero-knowledge, comme #9).
- **G2.** **Aucune image lourde n'est persistée sur le téléphone patient** : pas d'écriture disque du
  binaire (ni en clair ni chiffré) côté app patient ; l'affichage éventuel est **RAM-only** et évincé
  (même discipline que le wipe de #17/#19).
- **G3.** Le dossier texte (≤ 500 Ko) ne contient qu'un **descripteur média stable** (UUID + clé de
  contenu + intégrité) et/ou une **URL éphémère** — **jamais** de binaire ; le budget 500 Ko reste
  tenu (le média est hors-budget, hors-dossier).
- **G4.** Le backend **mint des URL d'accès éphémères, à TTL court, scoppées par objet et
  révocables** (ADR 0005) ; **une URL expirée est refusée** (critère d'acceptation #2).
- **G5.** **Résidence des données** : objets média (MinIO), métadonnées (Postgres) et tout
  CDN/edge éventuel restent **en Côte d'Ivoire** (ARTCI / loi n°2013-450) ; le garde-fou
  `scripts/check-residency.sh` reste vert ; aucun endpoint/cloud étranger dans le chemin média.
- **G6.** **Résilience réseau dégradé** : un média capturé hors-ligne est mis en file chiffrée
  (réutilisation de la discipline SQLCipher #21) et synchronisé au retour réseau (#22) sans perte ni
  doublon ; le descripteur est rattaché au dossier dès la capture (UUID assigné côté client).
- **G7.** **Budget de taille média** distinct et borné (rejet `413` au-delà), bien supérieur au
  budget dossier mais plafonné pour rester soutenable sur lien Edge/3G.
- **G8.** **Aucune fuite par les logs** : ni octets média, ni clé de contenu, ni token de capacité /
  URL signée, ni PII ne sont journalisés ; seuls des champs non-identifiants (UUID, taille, statut,
  latence) le sont.
- **G9.** Suite de tests prouvant : round-trip opaque d'octets, **serveur incapable de déchiffrer**,
  expiration/refus d'URL, absence de persistance disque côté patient, no-loss/no-duplicate offline.

## Non-Goals

- **Optimisation fine du réseau dégradé pour les médias lourds** (compression d'image, reprise de
  téléchargement, budget perceptuel) — relève de **#24** ; #23 borne la taille et chiffre/déporte,
  mais ne livre pas l'algorithme de compression ni le tuning Edge/3G.
- **Téléversement résumable / chunké (HTTP Range, protocole tus)** — *cadré ici comme décision
  ouverte* (voir *Open Questions*) ; si retenu comme sous-incrément il s'appuie sur le `TODO(#23)` de
  `main.rs`, sinon il est différé à #24. Le chemin nominal de #23 est un upload one-shot borné.
- **Service de stockage de blobs dossier `/blob/{uuid}`** (#9) — réutilisé/voisin mais distinct ; le
  média a son propre bucket, ses propres endpoints et son propre budget de taille.
- **Provisionnement de l'hébergement souverain in-country** (#8) — MinIO/Postgres/TLS sont déployés
  par l'IaC de #8 ; #23 *consomme* ces services via la config injectée.
- **QR éphémère ~120 s (#16)** et **scan/déchiffrement RAM + wipe de session (#17/#19)** — le média
  réutilise leurs invariants (clé en RAM, wipe) mais ne les réimplémente pas.
- **Politique de rétention / crypto-effacement formel** (ECART-01/02 de la matrice #5) — la
  *révocation* d'une URL et l'éventuel `DELETE /media/{uuid}` sont cadrés ici ; la *politique* de
  rétention reste pilotée par #5.
- **Capture/UI caméra finalisée côté médecin (PWA `app-medecin`)** — `app-medecin/lib` est un
  scaffold vide aujourd'hui ; #23 définit le service de déport et son point d'intégration, le polish
  UI relève de #28.

## Relevant Repository Context

**Statut stack — nuance importante vs framing « greenfield ».** Le BACKLOG décrit le projet comme
greenfield « stack non finalisée (#1) », mais à la date de cette spec **#1 est tranché** : les ADR
0001–0008 sont *Accepted*. Pour #23 :

- **Backend : Rust + Axum (Tokio)** (ADR 0004), même workspace cargo que `crypto-core`/`backend`.
- **Store objet : MinIO** (S3-compatible, self-hosted in-country) + **PostgreSQL 16** (métadonnées
  non-identifiantes) (ADR 0005). ADR 0005 nomme explicitement #23 et le mécanisme d'URL présignée.
- **App patient : Flutter/Dart** (ADR 0001) ; **interface médecin : PWA** (ADR 0002, scaffold vide).
- **Crypto : `crypto-core` (Rust, ADR 0003)** est le **seul** lieu d'AES-256-GCM ; format de fil
  `nonce(12) || ciphertext || tag(16)` ; `NONCE_LEN` exporté ; `encrypt_record`/`decrypt_record`
  exposés (single-shot). Les apps l'appellent via FRB (`crypto_core_bindings.dart`).
- **Secrets/config** : injectés depuis SOPS/age (ADR 0007), déjà modélisés dans `backend/src/config.rs`
  (dont `PRESIGNED_URL_SIGNING_KEY`, champs MinIO), redaction `Secret`, fail-fast staging/prod.

**Décisions encore ouvertes (choix d'implémentation *sous* les ADR, à confirmer — voir checklist) :**
mécanisme d'URL éphémère (capability token HMAC servi par le backend **vs** presigned S3/MinIO natif),
TTL exact de l'URL, budget `MAX_MEDIA_BYTES`, chiffrement single-shot **vs** chunké/streaming pour
les gros médias, schéma exact du descripteur média dans le dossier (extension de `image_urls` vs
nouveau champ `media`), file offline dédiée vs extension de `OfflineUploadQueue`, upload résumable
(tus/Range) inclus ou différé à #24, client S3 Rust (`aws-sdk-s3` vs `rust-s3`/`minio`). **Aucun de
ces choix ne réouvre #1.**

**Conventions observées (à respecter) :**
- Backend : lints stricts (clippy `-D warnings`), tout secret dans `Secret` (redaction), gestion
  d'erreur centralisée sans fuite de détail interne, aucune panique sur chemin requête, `TODO(#n)`
  traçant les dépendances. Tests via `cargo test --workspace` (`just test-rust`) ; `just test` = gate
  ADW. Garde-fou résidence `scripts/check-residency.sh` (CI).
- App patient : services en `lib/src/<domaine>/`, exceptions typées (`BackendUnavailable`,
  `BlobNotFound`…), client HTTP testable par injection (`BackendClient`), wipe RAM systématique en
  `finally`, file offline FIFO idempotente (`OfflineUploadQueue` / `SqlCipherUploadQueue`).
- Specs : prose FR, titres EN (cf. `specs/zero-knowledge-blob-storage-service.md`).

**Points d'ancrage déjà présents pour #23 :**
| Emplacement | État |
|---|---|
| `app-patient/lib/src/record/medical_record.dart` — `Consultation.imageUrls` | Placeholder `image_urls: string[]`, « no binary data, no credentials ». |
| `app-patient/lib/src/cloud/backend_client.dart` — `BackendClient` | Client `/blob/{uuid}` réutilisable comme modèle pour un `MediaClient`. |
| `app-patient/lib/src/doctor/scan_service.dart`, `session_end_service.dart` | Discipline RAM-only + wipe à répliquer pour le média. |
| `app-patient/lib/src/doctor/offline_upload_queue.dart` + `sqlcipher_upload_queue.dart` | File chiffrée + drain (#21/#22) à réutiliser/étendre pour le média. |
| `backend/src/config.rs` — `presigned_url_signing_key`, MinIO `Option<Secret>` | Câblé, marqué « Consumed by #23 ». |
| `backend/src/store.rs` — seam `BlobStore`, `MAX_BLOB_BYTES` | Modèle pour un `MediaStore` voisin + budget média distinct. |
| `backend/src/main.rs` — `TODO(#23)` | Point d'extension du routeur. |
| `docs/adr/0005-storage-and-sovereign-hosting.md` | Décision de référence (MinIO + URL présignée révocable). |

## Proposed Implementation

> Architecture recommandée : **descripteur média stable dans le dossier chiffré + URL éphémère mintée
> à la demande**. Les octets persistent (chiffrés) côté serveur ; l'**URL** est volatile. Voir
> *Risks & Open Questions §1* pour l'alternative littérale « URL stockée dans le dossier ».

### 1. Modèle de bout en bout

```
[Médecin capture une radio]
   → clé de contenu aléatoire (32 o, OS CSPRNG)         (client)
   → AES-256-GCM(image, clé_contenu) → ciphertext        (crypto-core, client)
   → UUID média v4 assigné côté client
   → PUT /media/{uuid}  (ciphertext opaque)              (réseau ; si offline → file #21)
   → descripteur {uuid, clé_contenu, hash, mime, taille} ajouté à consultation.media  (RAM)
   → dossier re-chiffré + renvoyé au cloud en fin de session (#19)
[Affichage d'une image]
   → POST /media/{uuid}/access → { url, expires_at }     (URL éphémère, TTL court)
   → GET <url> → ciphertext opaque                        (réseau)
   → AES-256-GCM⁻¹(ciphertext, clé_contenu) → image       (crypto-core, RAM-only)
   → décodage + affichage transitoire ; évincé à la fermeture (jamais sur disque)
```

**Clé de contenu :** une clé AES-256 **par média**, tirée du CSPRNG. Elle est rangée **à l'intérieur
du dossier déjà chiffré** (descripteur média), donc protégée par le chiffrement zero-knowledge du
dossier — pas de KEK supplémentaire nécessaire. Le serveur ne la voit jamais.

**UUID média assigné côté client** *avant* l'upload : le descripteur peut être rattaché au dossier
immédiatement (en RAM), même si les octets partent plus tard (offline). Pas d'URL volatile stockée →
pas de problème d'URL périmée dans un dossier durable.

### 2. Backend — store média (`MediaStore`)

Voisin de `BlobStore` (#9), **séparé** (bucket, budget, métadonnées distincts) :

```text
trait/enum MediaStore {
    async fn put(uuid, ciphertext) -> Result<PutOutcome, StoreError>;   // 201/200, version
    async fn get(uuid) -> Result<Option<StoredMedia>, StoreError>;      // None => 404
    async fn delete(uuid) -> Result<(), StoreError>;                    // révocation/erasure (option)
    async fn health() -> Result<(), StoreError>;
}
```

- **`MemoryMediaStore`** — backing dev/test (HashMap), comme `MemoryStore`.
- **`ObjectMediaStore`** (MinIO + Postgres) — backing staging/prod, livré avec le bring-up #8 :
  - **MinIO** : `put_object`/`get_object`/`remove_object` du **ciphertext opaque** dans un **bucket
    média dédié** (≠ bucket dossier), SSE-at-rest activé (défense en profondeur *sous* le chiffrement
    client — la confidentialité n'en dépend jamais).
  - **PostgreSQL** : table `media_metadata` — **uniquement non-identifiant** (cf. *Data Model*).

### 3. Backend — minting d'URL éphémère + lecture (cœur du critère d'acceptation #2)

**Recommandé : capability URL servie par le backend** (utilise `PRESIGNED_URL_SIGNING_KEY`, garde
MinIO privé, point d'audit/révocation côté backend) :

- `POST /media/{uuid}/access` → vérifie l'existence, **mint** un token de capacité signé HMAC
  (`PRESIGNED_URL_SIGNING_KEY`) encodant `{uuid, exp}`, renvoie `{ "url": "…/media/{uuid}?exp=…&sig=…",
  "expires_at": "<ISO-8601>" }`. **TTL court** (à fixer ; piste : ~quelques minutes, borne supérieure
  alignée sur l'éphémérité du parcours — *Open Question §3*).
- `GET /media/{uuid}?exp=…&sig=…` → **vérifie la signature et l'expiration** (rejet `401`/`403` si
  invalide **ou expirée**), streame le **ciphertext opaque** depuis MinIO. Le déchiffrement est
  exclusivement côté client.
- **Révocation** : l'expiration du TTL invalide la signature (révocation par le temps). Révocation
  *forcée* possible via rotation du `PRESIGNED_URL_SIGNING_KEY` (révocation globale) et/ou
  `DELETE /media/{uuid}` (révocation par objet) — *Open Question §4*.

**Alternative (à arbitrer) : presigned S3/MinIO natif** (SigV4 avec credentials MinIO, expiry S3) —
plus standard mais expose l'endpoint MinIO aux clients et **n'utilise pas** `PRESIGNED_URL_SIGNING_KEY`.
ADR 0005 dit « presigned/ephemeral URLs … revocable » sans trancher le mécanisme ; le champ de config
existant penche pour la capability URL backend. **À confirmer (Open Question §2).**

### 4. Backend — upload média

- `PUT /media/{uuid}` : valider l'UUID (`400`), **plafond de corps** `MAX_MEDIA_BYTES`
  (`DefaultBodyLimit`, dépassement → `413` *avant* bufferisation), persister le corps **verbatim**
  (jamais inspecté), enregistrer la métadonnée (taille, version, timestamps). `201`/`200` + `ETag`.
  Réutiliser le mapping d'erreur centralisé (`ApiError`), aucune panique → `503` si store down.
- *(Décision ouverte)* upload résumable (Range/tus) pour gros médias sur lien instable — sinon
  différé à #24.

### 5. App patient/médecin — déport client

- **`MediaCipher`** (`record/media_cipher.dart`) : tire la clé de contenu (CSPRNG), chiffre/déchiffre
  via `crypto_core_bindings.dart` (`encrypt_record`/`decrypt_record` ou variante bytes), calcule le
  hash d'intégrité. **RAM-only** ; wipe du handle Rust en `finally` (discipline #17/#19).
- **`MediaClient`** (`cloud/media_client.dart`) : transport `PUT /media/{uuid}`,
  `POST /media/{uuid}/access`, `GET <url>` ; modelé sur `BackendClient` (injection `http.Client` pour
  les tests, exceptions typées, jamais de log du corps ni du token).
- **`MediaUploadService`** (`doctor/media_upload_service.dart`) : orchestration capture → chiffrement
  → assignation UUID → upload (ou enfilage offline) → renvoi du **descripteur** à fusionner dans
  `consultation.media`. **Aucune écriture disque du binaire** (G2) ; si la plateforme exige un fichier
  temporaire pour la capture caméra, il doit être *chiffré ou immédiatement supprimé* — **décision à
  cadrer (Open Question §6)**.
- **Affichage** : `MediaViewService` mint l'URL d'accès, télécharge, déchiffre en RAM, fournit les
  octets décodés à un widget *sans cache disque* (pas de `cacheWidth` persistant, pas de fichier).

### 6. Schéma dossier — descripteur média

Évolution recommandée du schéma (#15) : remplacer/compléter `image_urls: string[]` par un
descripteur structuré **dans le dossier chiffré** :

```jsonc
"media": [
  {
    "uuid": "<uuid-v4>",            // index serveur anonyme
    "content_key": "<base64 32o>",  // clé AES-256 par-média (protégée par le chiffrement du dossier)
    "alg": "A256GCM",
    "content_hash": "<sha-256>",    // intégrité de bout en bout
    "mime": "image/jpeg",
    "size_bytes": 2300000,
    "added_at": "2024-01-15T10:30:00Z"
  }
]
```

Le champ `image_urls` (URL éphémère littérale) devient soit **déprécié**, soit réservé à un cache
*transitoire* d'URL mintées (non persisté). **Décision touchant #15 — à confirmer (Open Question §1).**
Le descripteur (clé + hash) est petit ; le budget 500 Ko du dossier reste tenu.

### 7. Résilience offline (réutilisation #21/#22)

- Média capturé hors-ligne → ciphertext **enfilé** dans une file chiffrée (extension de
  `OfflineUploadQueue`/`SqlCipherUploadQueue` ou file média dédiée — *Open Question §5*, vu la taille
  des médias vs les blobs dossier). Le descripteur est rattaché au dossier **immédiatement** (UUID
  déjà assigné).
- Au retour réseau, `SyncService.drain()` (#22) téléverse les médias en file ; livraison
  *at-least-once* + `PUT /media/{uuid}` idempotent au niveau UUID → **no-loss / no-duplicate**.

## Affected Files / Packages / Modules

**À lire :**
- `backend/src/main.rs`, `config.rs`, `store.rs` (+ `store/memory.rs`), `error.rs`, `Cargo.toml`,
  `backend/README.md`.
- `crypto-core/src/lib.rs` (API encrypt/decrypt, `NONCE_LEN`, format de fil).
- `app-patient/lib/src/record/medical_record.dart`, `record_size_guard.dart`,
  `cloud/backend_client.dart`, `doctor/scan_service.dart`, `session_end_service.dart`,
  `consultation_merge.dart`, `offline_upload_queue.dart`, `sqlcipher_upload_queue.dart`,
  `sync_service.dart`, `rust/crypto_core_bindings.dart`.
- ADR `0003`, `0004`, `0005`, `0007`, `0010` ; `justfile` ; `scripts/check-residency.sh` ;
  `docs/compliance/loi-2013-450-artci-matrix.md` (#5) ; `docs/threat-model/` (#6) ; `specs/medical-record-schema.md`,
  `specs/zero-knowledge-blob-storage-service.md`.

**À créer / modifier (probable) :**
- Backend :
  - `backend/src/media/mod.rs` (+ `media/store.rs`, `media/memory.rs`, `media/object.rs`) — `MediaStore`
    + implémentations + `MAX_MEDIA_BYTES`/`MediaMeta`.
  - `backend/src/media/access.rs` — minting + vérification du token de capacité (HMAC `PRESIGNED_URL_SIGNING_KEY`).
  - `backend/src/main.rs` — routes `PUT /media/{uuid}`, `POST /media/{uuid}/access`,
    `GET /media/{uuid}` (+ option `DELETE`), body-limit média, headers.
  - `backend/migrations/000x_media_metadata.sql` — table `media_metadata` (non-identifiante).
  - `backend/src/config.rs` — éventuel `MAX_MEDIA_BYTES`/nom de bucket média (sinon constantes).
  - `backend/Cargo.toml` — client S3, lib HMAC (selon décisions) ; vérifier `deny.toml`/SCA.
  - `backend/tests/*.rs` — tests d'intégration média (round-trip, expiry, no-decrypt, 4xx/503).
  - `backend/README.md` — endpoints média, codes, budget, garanties ZK + éphémérité.
- App patient/médecin :
  - `app-patient/lib/src/record/media_cipher.dart`, `cloud/media_client.dart`,
    `doctor/media_upload_service.dart`, `doctor/media_view_service.dart`.
  - `app-patient/lib/src/record/medical_record.dart` — descripteur `media` (+ migration `v`).
  - `app-patient/lib/src/doctor/offline_upload_queue.dart` / `sqlcipher_upload_queue.dart` — extension
    média (si retenue).
  - `app-patient/lib/src/ui/consultation_edit_screen.dart` / `record_view_screen.dart` — attache &
    affichage RAM-only (point d'intégration ; polish UI = #28).
  - Tests : `app-patient/test/record/`, `app-patient/test/doctor/`, `app-patient/test/e2e/`.
- Docs : `specs/medical-record-schema.md` (#15), matrice de conformité (#5), threat model (#6),
  addendum ADR 0005 si un choix structurant émerge, `.env.example`.

## API / Interface Changes

Nouvelle surface réseau backend (sous ADR 0004/0005). UUID = **index média anonyme** (UUID v4),
jamais dérivé d'une PII.

| Méthode | Chemin | Corps | Réponses |
|---|---|---|---|
| `PUT` | `/media/{uuid}` | ciphertext média opaque (`application/octet-stream`) | `201 Created` · `200 OK` (réécrit) · `400` UUID invalide · `413` au-delà de `MAX_MEDIA_BYTES` · `503` store down |
| `POST` | `/media/{uuid}/access` | — | `200 { "url", "expires_at" }` (URL éphémère mintée) · `404` média inconnu · `503` |
| `GET` | `/media/{uuid}?exp=…&sig=…` | — | `200` (ciphertext + `Content-Length`, `ETag`) · `401/403` signature invalide **ou expirée** · `404` · `503` |
| `DELETE` | `/media/{uuid}` *(option, révocation/erasure)* | — | `204` · `404` · `503` — *Open Question §4* |

- **Token de capacité / URL signée = secret porteur** : à traiter comme un `Secret` côté backend
  (jamais journalisé) ; côté client jamais persisté.
- **Pas de nouvelle surface CLI.** Le **QR (#16)** n'est pas modifié : il transporte la clé de session
  du dossier, pas les clés de contenu média (celles-ci vivent dans le dossier chiffré).
- *(Décision ouverte)* `Range`/`206` ou tus pour upload/download résumable — sinon différé à #24.

## Data Model / Protocol Changes

- **Nouveau bucket MinIO média** (dédié, ≠ bucket dossier #9), SSE-at-rest, un objet ciphertext par
  UUID.
- **Nouvelle table PostgreSQL `media_metadata`** — *uniquement non-identifiant* : `uuid` (PK, anonyme),
  `size_bytes`, `version` (concurrence optimiste), `created_at`, `updated_at`. **Aucune** colonne PII /
  clair / clé / mime/hash sensible / CMU / téléphone. *(mime & hash restent côté client dans le
  descripteur chiffré, pas en base serveur.)*
- **Format du ciphertext média : opaque** côté serveur. Côté client : `nonce(12) || ciphertext ||
  tag(16)` (`crypto-core`, ADR 0003), single-shot pour le chemin nominal ; *chunké/streaming à
  cadrer* pour les gros médias (Open Question §7).
- **Schéma dossier (`medical_record.dart`, #15)** : ajout du descripteur `media[]` (uuid, content_key,
  alg, content_hash, mime, size_bytes, added_at) ; bump du champ `v` + chemin de migration depuis
  `image_urls`. **Touche #15 — à confirmer.**
- **Token de capacité** : structure signée `{uuid, exp}` (HMAC `PRESIGNED_URL_SIGNING_KEY`) ; aucune
  PII, non réutilisable après `exp`.

## Security & Compliance Considerations

- **AES-256-GCM côté client uniquement** (`crypto-core`, ADR 0003) : le serveur ne chiffre/déchiffre
  jamais le média ; il stocke des octets opaques. **Zero-knowledge prouvé par test** (comme #9).
- **Clé de contenu par-média** : tirée du CSPRNG, rangée **dans le dossier chiffré** (protégée par le
  chiffrement du dossier) ; **jamais** transmise au serveur. Seules des **clés opérationnelles**
  (credentials MinIO, `PRESIGNED_URL_SIGNING_KEY`) existent côté serveur, enveloppées dans `Secret`
  (redaction) et injectées via SOPS/age (ADR 0007).
- **Aucune image lourde sur le téléphone patient** (critère #1) : interdiction d'écrire le binaire
  (clair ou chiffré) sur disque côté app patient ; décodage/affichage **RAM-only** évincé à la
  fermeture (discipline wipe #17/#19). Tout fichier temporaire de capture caméra doit être chiffré ou
  immédiatement supprimé (Open Question §6).
- **URL éphémère révoquée après expiration** (critère #2) : TTL court signé ; `GET` refuse une URL
  expirée (`401/403`). Révocation forcée par rotation de clé de signature et/ou `DELETE` par objet.
  La signature/token est un **secret porteur** : jamais journalisée, jamais persistée côté client.
- **Résidence des données (ARTCI / loi n°2013-450)** : objets média (MinIO), métadonnées (Postgres),
  backups et **tout CDN/edge éventuel restent en Côte d'Ivoire**. Le commentaire « cdn.healthtech.ci »
  du schéma #15 n'implique **aucun** CDN étranger : si un CDN est introduit, il doit être in-country,
  sinon servir directement depuis MinIO/backend in-country. `scripts/check-residency.sh` reste vert ;
  aucun endpoint/dépendance étranger introduit. Tracer les contrôles dans la matrice (#5) ; pertinent
  pour l'homologation #30.
- **Budget de taille** : le **dossier texte reste ≤ 500 Ko** (le média est hors-dossier) ; le média a
  son propre plafond `MAX_MEDIA_BYTES` (rejet `413`) pour rester soutenable sur Edge/3G.
- **Surface d'écriture** (comme #9) : un `PUT /media` non authentifié permet écrasement/DoS d'un UUID
  connu (le ciphertext reste illisible). À arbitrer avec le threat model (#6) : token de capacité en
  écriture, concurrence optimiste, quotas/rate-limit. Voir *Open Questions*.
- **Logging/redaction** : ne **jamais** journaliser les octets média, la clé de contenu, le token /
  l'URL signée, ni de PII. Logs limités aux champs non-identifiants (UUID anonyme, taille, statut,
  latence). Pas de panique exposant un état interne.
- **Intégrité** : le `content_hash` du descripteur permet au client de détecter une altération du
  média côté serveur (le tag GCM couvre déjà l'authenticité, le hash ajoute une vérif de bout en bout
  indépendante du transport).

## Testing Plan

**Backend — unitaires :**
- Validation UUID (`400`) ; budget `MAX_MEDIA_BYTES` (≤ accepté, > → `413`).
- `MemoryMediaStore` : put→get round-trip d'octets arbitraires (nuls/0xFF) ; get inconnu → `None`/`404` ;
  réécriture incrémente la version ; `delete` → `404` ensuite.
- Mapping `StoreError` → HTTP (down → `503`) sans fuite de détail.

**Backend — minting & expiration (cœur du critère #2) :**
- Token valide → `GET` `200` ; **token expiré → `401/403`** ; signature falsifiée → `401/403` ;
  token d'un autre UUID → refus (scope par objet).
- *(Si `DELETE` retenu)* après `DELETE`, `GET` → `404` et token devenu inutile.

**Backend — preuve zero-knowledge :**
- **No-plaintext / server-cannot-decrypt** : chiffrer un média marqueur via `crypto-core`, `PUT`,
  inspecter octets stockés + ligne `media_metadata` → **absence** du marqueur clair et de PII ; sans
  la clé de contenu, `decrypt` échoue.
- **No-decrypt-symbol** : le crate backend n'appelle aucun chemin de déchiffrement et ne détient
  aucune clé de contenu.

**Backend — intégration (MinIO + Postgres éphémères) :**
- Round-trip complet ; persistance après redémarrage process ; métadonnées correctes **sans PII** ;
  concurrence (deux `PUT` même UUID → état cohérent) ; `503` si store down.

**App — unitaires/widget :**
- `MediaCipher` : round-trip chiffrement/déchiffrement ; **vecteurs crypto** cohérents avec
  `crypto-core` (KAT) ; wipe du handle en `finally`.
- **No-disk-persistence** (critère #1) : test prouvant qu'aucun fichier binaire (clair ni chiffré)
  n'est écrit côté patient lors d'un cycle attach/view (assertion sur le FS sandbox).
- Migration de schéma `image_urls` → `media` ; round-trip JSON ; budget 500 Ko préservé.

**App — résilience offline (#21/#22) :**
- Média capturé hors-ligne → enfilé chiffré → drainé au retour réseau ; **no-loss / no-duplicate** ;
  descripteur présent dans le dossier dès la capture.

**E2E :**
- Extension de `consultation_loop_e2e_test.dart` : médecin attache une image → upload (ou queue) →
  descripteur dans le dossier → fin de session/renvoi cloud → ré-ouverture → mint URL → fetch →
  déchiffrement RAM → affichage ; variantes **URL expirée** et **offline→reconnexion**.

**Sécurité/logs :**
- Aucune sortie `tracing`/log app ne contient d'octets média, de clé de contenu, de token/URL signée,
  ni de PII (capture de logs sur cas nominal + cas d'erreur).

**Gate :** `just test` (`cargo test --workspace` + tests Flutter), clippy `-D warnings`,
`scripts/check-residency.sh` vert.

## Documentation Updates

- **`backend/README.md`** : endpoints média, codes HTTP, budget `MAX_MEDIA_BYTES`, TTL & révocation
  d'URL, contrat de config, garanties zero-knowledge + éphémérité.
- **`specs/medical-record-schema.md` (#15)** : descripteur `media[]`, dépréciation/usage de
  `image_urls`, bump `v` + migration. *(Touche le schéma #15 — coordination requise.)*
- **ADR** : addendum à ADR 0005 si un choix structurant émerge (mécanisme d'URL : capability backend
  vs presigned S3 ; bucket/budget média ; révocation). Sinon référencer ADR 0005 tel quel.
- **Matrice de conformité (#5)** : preuves « aucune image lourde sur le téléphone », « URL éphémère
  révoquée », « média chiffré client + résidence in-country » (liens vers tests) — pièce #30.
- **Threat model (#6)** : décision sur l'authz d'écriture média / rate-limit / révocation.
- **`.env.example`** : confirmer `PRESIGNED_URL_SIGNING_KEY`, MinIO `*`, + éventuel `MAX_MEDIA_BYTES`/
  nom de bucket média.
- **BACKLOG.md** : marquer #23 livré une fois mergé — *via l'orchestrateur, pas dans cette phase*.

## Risks and Open Questions

1. **Descripteur stable vs URL littérale dans le dossier.** Le PRD §4 et le schéma #15 actuel parlent
   d'« URL éphémère intégrée au dossier ». Une URL à TTL court stockée dans un dossier durable serait
   **périmée** à la relecture. **Recommandation :** stocker un *descripteur média stable* (UUID + clé
   + hash) et **minter l'URL à la demande**. À confirmer avec le propriétaire de #15 (impact schéma).
2. **Mécanisme d'URL éphémère.** Capability URL servie par le backend (HMAC `PRESIGNED_URL_SIGNING_KEY`,
   MinIO privé, audit/révocation backend) **vs** presigned S3/MinIO natif (SigV4, plus standard mais
   expose MinIO et n'utilise pas le champ de config existant). Recommandation : capability backend. À
   trancher (éventuel addendum ADR 0005).
3. **TTL exact de l'URL.** Quelques minutes ? Aligné sur l'éphémérité du parcours (le QR est à 120 s,
   mais le visionnage d'image peut demander plus) ? À fixer avec #6/#28.
4. **Révocation forcée.** Suffit-il de l'expiration par TTL, ou faut-il `DELETE /media/{uuid}` et/ou
   rotation de `PRESIGNED_URL_SIGNING_KEY` ? Lien avec la rétention/crypto-effacement (ECART-01/02, #5).
5. **File offline : dédiée vs partagée.** Les médias (Mo) ne doivent pas étouffer la file des blobs
   dossier/ordonnances (#21). File média séparée ou file commune avec priorités/quotas ? À cadrer.
6. **Fichier temporaire de capture caméra.** Selon la plateforme (Flutter/PWA), la capture peut écrire
   un fichier temporaire — incompatible avec « aucune image lourde sur le téléphone » si en clair. Doit
   être chiffré à la volée ou supprimé immédiatement ; à valider par plateforme.
7. **Chiffrement single-shot vs chunké/streaming.** `crypto-core` est single-shot ; un média de
   plusieurs Mo en RAM est acceptable sur entrée de gamme mais limité. Faut-il un chiffrement chunké
   (et un upload résumable tus/Range) dès #23, ou différer à #24 ? Décision de périmètre.
8. **Authz d'écriture (avec #6).** `PUT /media` non authentifié = risque d'écrasement/DoS sur UUID
   connu (ciphertext illisible mais disponibilité/intégrité en jeu). Token de capacité en écriture /
   rate-limit / quotas à décider.
9. **Dépendance #8.** MinIO/Postgres réels dépendent du provisionnement souverain (#8). Dev/CI :
   services éphémères suffisent ; staging/prod attendent #8 (même posture que #9).
10. **CDN éventuel.** Le commentaire `cdn.healthtech.ci` (#15) ne doit pas introduire de CDN étranger ;
    si CDN il y a, il doit être in-country (ARTCI). À expliciter.

## Implementation Checklist

1. Confirmer les décisions ouvertes structurantes : §1 (descripteur vs URL), §2 (mécanisme d'URL),
   §3 (TTL), §5 (file offline), §7 (chunké/résumable) — idéalement via une note/ADR courte (addendum
   ADR 0005) et coordination avec #15/#6.
2. **Backend — store média :** définir `MediaStore` (`put`/`get`/`delete`/`health`), `MemoryMediaStore`
   (dev/test), `MediaMeta`, `MAX_MEDIA_BYTES` (distinct de `MAX_BLOB_BYTES`).
3. **Backend — upload :** route `PUT /media/{uuid}` (validation UUID `400`, body-limit `413`, persist
   verbatim, `201`/`200` + `ETag`), mapping d'erreur centralisé, aucune panique → `503`.
4. **Backend — minting/lecture :** `POST /media/{uuid}/access` (token HMAC `PRESIGNED_URL_SIGNING_KEY`,
   `expires_at`), `GET /media/{uuid}?exp&sig` (vérif signature **et expiration** → `401/403`, stream
   ciphertext), *(option)* `DELETE /media/{uuid}`.
5. **Backend — persistance durable :** `ObjectMediaStore` (bucket MinIO dédié + SSE-at-rest + pool
   Postgres) ; migration `media_metadata` (colonnes **non-identifiantes** uniquement) ; sélection du
   backing par `APP_ENV` (fail-fast via secrets injectés). Livrable avec le bring-up #8.
6. **Backend — logs/redaction :** aucun octet média / clé / token / URL signée / PII journalisé ;
   token traité comme `Secret`.
7. **App — crypto média :** `MediaCipher` (clé de contenu CSPRNG, encrypt/decrypt via `crypto-core`,
   hash d'intégrité, wipe `finally`).
8. **App — transport :** `MediaClient` (`PUT`/`POST access`/`GET url`), modelé sur `BackendClient`,
   exceptions typées, jamais de log de corps/token, `http.Client` injectable.
9. **App — orchestration :** `MediaUploadService` (capture → chiffrement → UUID → upload/enqueue →
   descripteur) **sans écriture disque du binaire** ; `MediaViewService` (mint → fetch → décrypt RAM →
   affichage évincé).
10. **App — schéma dossier :** ajouter le descripteur `media[]` à `medical_record.dart`, bump `v` +
    migration depuis `image_urls`, préserver le garde-fou 500 Ko ; fusion append-only (#18) inchangée.
11. **App — offline :** étendre/ajouter la file chiffrée média (#21) et son drain (#22) ; descripteur
    rattaché dès la capture ; PUT idempotent (no-loss/no-duplicate).
12. **App — intégration UI :** points d'attache (consultation edit) et d'affichage RAM-only (record
    view) ; polish UI = #28.
13. **Tests :** unitaires backend (UUID/budget/round-trip/erreur), minting/expiration, preuve ZK,
    intégration MinIO+Postgres ; unitaires/widget app (MediaCipher KAT, no-disk-persistence, migration
    schéma), résilience offline, E2E (attach→upload→mint→fetch→décrypt→affichage + variantes expiré /
    offline), capture de logs (no-leak).
14. **Docs :** `backend/README.md`, `specs/medical-record-schema.md` (#15), addendum ADR 0005 (si
    besoin), matrice #5, threat model #6, `.env.example`.
15. **Gates verts :** `just test` (cargo workspace + Flutter), clippy `-D warnings`,
    `scripts/check-residency.sh` (aucun endpoint/dépendance étranger dans le chemin média).
