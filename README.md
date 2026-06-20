# HealthTech

[![CI](https://github.com/kortiene/HealthTech/actions/workflows/ci.yml/badge.svg)](https://github.com/kortiene/HealthTech/actions/workflows/ci.yml)

**Plateforme de santé numérique décentralisée pour la Côte d'Ivoire** — *local-first / zero-knowledge*.

Le patient transporte son dossier médical chiffré dans son smartphone et en octroie un accès éphémère et
contrôlé aux professionnels de santé via un QR code dynamique, sans dépendre d'une connexion permanente.
Le serveur ne stocke que des blobs chiffrés (AES-256-GCM côté client) indexés par UUID anonymes et ne peut
jamais les déchiffrer.

- **Exigences produit :** [`PRD_HealthTech.md`](./PRD_HealthTech.md)
- **Backlog & roadmap :** [`BACKLOG.md`](./BACKLOG.md) · issues [kortiene/HealthTech](https://github.com/kortiene/HealthTech/issues)
- **Décisions d'architecture :** [`docs/adr/`](./docs/adr/0000-index.md)
- **Pipeline de livraison agentique (ADW) :** [`adw_sdlc/`](./adw_sdlc/HEALTHTECH_PORT.md)

## Structure du monorepo

| Paquet | Stack | Rôle | ADR | Build | Test |
| --- | --- | --- | --- | --- | --- |
| [`crypto-core/`](./crypto-core) | Rust | Cœur cryptographique partagé (AES-256-GCM, PBKDF2) | [0003](./docs/adr/0003-shared-crypto-core-rust.md) | `cargo build -p crypto-core` | `cargo test -p crypto-core` |
| [`backend/`](./backend) | Rust + Axum | Service zero-knowledge de stockage de blobs | [0004](./docs/adr/0004-backend-rust-axum.md) | `cargo build -p backend` | `cargo test -p backend` |
| [`app-patient/`](./app-patient) | Flutter (Dart) | App patient (mobile-first Android), crypto via `flutter_rust_bridge` | [0001](./docs/adr/0001-patient-app-flutter.md) | `flutter build appbundle --split-per-abi` | `flutter test` |
| [`app-medecin/`](./app-medecin) | Preact + TS (PWA) | Interface médecin, déchiffrement RAM-only via WASM | [0002](./docs/adr/0002-doctor-interface-pwa.md) | `npm run build` | `npm test` |
| [`infra/`](./infra) | Terraform + Ansible | Hébergement souverain en Côte d'Ivoire (ARTCI) | [0005](./docs/adr/0005-storage-and-sovereign-hosting.md) | — | — |

> Le statut est **greenfield** : ces paquets sont des squelettes (stubs compilables) à étoffer issue par issue.

## Démarrage

```bash
# Tout tester (gate du pipeline ADW)
just test

# Par paquet
cargo test --workspace                 # crypto-core + backend
cd app-medecin && npm install && npm test
cd app-patient && flutter test         # nécessite le SDK Flutter
```

Prérequis : Rust (cargo), Node ≥ 20, [`just`](https://github.com/casey/just), et le SDK Flutter pour
l'app patient.

## Intégration continue (CI/CD)

[`.github/workflows/ci.yml`](./.github/workflows/ci.yml) s'exécute à chaque PR ([ADR 0008](./docs/adr/0008-ci-cd-pipeline.md)) :
lint + tests + build de chaque paquet, scan de dépendances (SCA), et production de **deux artefacts** —
l'APK patient et l'image conteneur du backend (musl statique → distroless).

```bash
just ci           # miroir local : lint + test + build + sca
just sca          # scan de vulnérabilités/licences (cargo-deny + npm audit + osv-scanner)
just build-image  # construit l'image backend (nécessite Docker)
```

Le check agrégé **`CI success`** doit être configuré comme *required status check* (protection de branche) :
une CI rouge bloque le merge. Le SCA combine `cargo-deny` (avis + licences Rust) et `osv-scanner`
(Cargo + npm + pub.dev) ; [`dependabot.yml`](./.github/dependabot.yml) maintient les dépendances à jour.

## Contribuer

Voir [`CONTRIBUTING.md`](./CONTRIBUTING.md) — Conventional Commits, invariants zero-knowledge (jamais de
secret/donnée en clair committé), `just test` vert avant merge.
