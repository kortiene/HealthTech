# Cartographie des données & flux

> Inventaire des données + schéma de flux **matérialisant la frontière zero-knowledge**
> ([REQ-LEX-07/16/19](./exigences-legales.md) — contrôle **CTRL-25**, preuve **PREUVE-18**).
> Décrit le modèle **existant/décidé** (UUID anonyme ↔ blob AES-256-GCM, métadonnées non identifiantes)
> **sans le modifier**.
>
> ⚠️ **Aucune donnée patient réelle** — uniquement catégories, schémas et flux.

## 1. Principe directeur

Le serveur est **zero-knowledge** : il ne voit **jamais** ni donnée nominative, ni clé, ni plaintext. Il ne
détient que des **blobs chiffrés opaques** indexés par des **UUID anonymes** + des métadonnées **non
identifiantes**. La frontière de confiance se situe **sur l'appareil du patient** (chiffrement client) et,
en consultation, **dans la RAM du professionnel** (déchiffrement éphémère).

## 2. Où vit chaque donnée

| Donnée | Sur l'appareil patient | En transit | Côté serveur (in-country) | RAM professionnel (consultation) |
| --- | --- | --- | --- | --- |
| Dossier médical (plaintext) | ✅ (local-first, ≤ 500 Ko) | ❌ **jamais en clair** | ❌ **jamais** | ✅ éphémère (déchiffré, puis **wipe**) |
| Dossier médical (blob AES-256-GCM) | ✅ (miroir SQLCipher) | ✅ chiffré (TLS par-dessus) | ✅ **blob opaque** | — |
| Clé maîtresse | ✅ Android Keystore (non exportable) | ❌ | ❌ **jamais** | ❌ |
| Clé de session (QR) | ✅ (générée, dans le QR) | ✅ via QR ~120 s | ❌ **jamais** | ✅ éphémère (zeroize en fin de session) |
| UUID anonyme | ✅ | ✅ | ✅ (index) | ✅ |
| Métadonnées non identifiantes (version/taille, horodatages, KDF params publics) | ✅ | ✅ | ✅ | — |
| Identifiant compte (n° CMU/téléphone) | ✅ (local) | ❌ **jamais en clair** | ❌ | ❌ |
| Médias lourds (images) | ❌ **interdits sur le téléphone** | ✅ chiffré | ✅ objet chiffré + URL éphémère | ✅ via URL éphémère |
| Secrets opérationnels | ❌ | — | ✅ in-country (SOPS+age) ; **jamais** de clé patient | ❌ |

## 3. Flux principaux (texte — schéma à enrichir avec le conseil juridique)

### Flux A — Sauvegarde zero-knowledge ([#14](https://github.com/kortiene/HealthTech/issues/14))

```
[Patient device]
  dossier (plaintext ≤500 Ko)
    --(AES-256-GCM, clé maîtresse, CTRL-01)-->  blob opaque
        --(HTTPS/TLS, CTRL-23)-->  [Backend in-country]
            PUT /blob/{uuid_anonyme}  -->  [MinIO: blob opaque]  +  [PostgreSQL: métadonnées non identifiantes]
```
Le backend **ne peut pas déchiffrer** (CTRL-02 ; preuve PREUVE-02). Aucune PII, aucune clé ne franchit la
frontière de l'appareil.

### Flux B — Consultation (partage contrôlé par le patient, [#16](https://github.com/kortiene/HealthTech/issues/16)→[#19](https://github.com/kortiene/HealthTech/issues/19))

```
[Patient device] --(QR ~120 s : URL + clé de session, CTRL-05)--> [Professionnel]
[Professionnel] GET /blob/{uuid} --(TLS)--> [Backend] --> blob opaque
[Professionnel] déchiffre EN RAM uniquement (CTRL-06) --> consulte/édite
[Professionnel] « Terminer » / 15 min : rechiffre --> PUT /blob/{uuid} --> wipe RAM (CTRL-07)
```
Le QR expire à ~120 s ; la clé n'est **jamais persistée** hors du QR ; le plaintext **ne touche jamais le
disque** côté professionnel (réserve best-effort en navigateur — [ADR 0000](../adr/0000-index.md) risque #1).

### Flux C — Médias lourds ([#23](https://github.com/kortiene/HealthTech/issues/23))

```
image chiffrée --> [MinIO in-country]   ;   dossier texte n'embarque qu'une URL presigned éphémère (CTRL-11)
```
Aucune image lourde sur le téléphone patient ; URL révoquée après expiration.

### Flux D — Hors-ligne ([#21](https://github.com/kortiene/HealthTech/issues/21)/[#22](https://github.com/kortiene/HealthTech/issues/22))

```
coupure réseau --> ordonnance DÉJÀ chiffrée --> file locale chiffrée (SQLCipher / IndexedDB-ciphertext)
retour réseau   --> synchronisation --> [Backend in-country]
```
Aucun plaintext sur disque, même hors-ligne ([ADR 0006](../adr/0006-offline-storage-and-keys.md)).

## 4. Frontière zero-knowledge (résumé probant)

| Côté serveur, le système voit… | Le système ne voit **jamais**… |
| --- | --- |
| Blobs chiffrés opaques | Le contenu médical en clair |
| UUID anonymes | L'identité du patient (n° CMU/téléphone) |
| Version/taille du chiffré, horodatages | Les clés (maîtresse, session, données) |
| Paramètres KDF publics (sel, itérations) | Le mot de passe / la phrase de récupération |
| Secrets **opérationnels** (in-country) | Toute clé **patient** (frontière [ADR 0007](../adr/0007-secrets-and-environments.md)) |

> **Conséquence conformité.** Cette frontière est l'argument central de **minimisation** (REQ-LEX-07),
> **sécurité/confidentialité** (REQ-LEX-16/17) et de **quasi-anonymisation côté serveur**. Elle ne doit
> **jamais** être franchie pour « faciliter » une fonctionnalité : tout besoin contraire devient un
> **écart** ([`ecarts.md`](./ecarts.md)), jamais un affaiblissement de la crypto.
