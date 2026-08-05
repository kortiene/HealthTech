# HealthTech — Runbook opérationnel

Référence technique pour lancer, tester, construire et déployer la plateforme HealthTech.  
Statut du projet : [`docs/project/status.html`](./status.html) · Architecture : [`docs/adr/`](../adr/0000-index.md)

---

## Table des matières

1. [Prérequis et outillage](#1-prérequis-et-outillage)
2. [Première installation](#2-première-installation)
3. [Stack de développement local](#3-stack-de-développement-local)
4. [Lancer les tests](#4-lancer-les-tests)
5. [Lint et formatage](#5-lint-et-formatage)
6. [Construire le projet](#6-construire-le-projet)
7. [SCA — analyse de dépendances](#7-sca--analyse-de-dépendances)
8. [Contrôles de sécurité et secrets](#8-contrôles-de-sécurité-et-secrets)
9. [Infrastructure et déploiement](#9-infrastructure-et-déploiement)
10. [Pipeline de livraison agentique (ADW)](#10-pipeline-de-livraison-agentique-adw)
11. [Vérifications ponctuelles](#11-vérifications-ponctuelles)
12. [Dépannage](#12-dépannage)

---

## 1. Prérequis et outillage

### Outillage obligatoire

| Outil | Version min | Installation | Rôle |
|---|---|---|---|
| **Rust + cargo** | stable (1.80+) | `curl https://sh.rustup.rs -sSf \| sh` | `crypto-core` + `backend` |
| **just** | 1.x | `cargo install just` | task runner monorepo |
| **Docker** (+ Compose v2) | 24+ | Docker Desktop / `docker.io` | stack dev local + image backend |
| **Node.js** | ≥ 20 LTS | `nvm install 20` | `app-medecin` (PWA) |
| **Flutter SDK** | 3.x stable | <https://docs.flutter.dev/get-started/install> | `app-patient` (Android) |
| **pnpm** | 9+ | `npm i -g pnpm` | ADW pipeline (`adw_sdlc/`) |

### Outillage sécurité / compliance

| Outil | Installation | Rôle |
|---|---|---|
| **cargo-deny** | `cargo install cargo-deny` | SCA Rust (advisories + licences) |
| **osv-scanner** | `brew install osv-scanner` ou [releases](https://github.com/google/osv-scanner) | SCA multi-écosystème |
| **gitleaks** | `brew install gitleaks` | détection de secrets dans git |
| **sops** | `brew install sops` | chiffrement des bundles de secrets |
| **age** | `brew install age` | backend de chiffrement SOPS |

### Outillage infrastructure (optionnel, staging/prod uniquement)

| Outil | Version | Rôle |
|---|---|---|
| **Terraform** | ≥ 1.9 | provisionnement IaC |
| **Ansible** | ≥ 2.16 | configuration des nœuds |

### Vérification rapide de l'environnement

```bash
cargo --version && just --version && docker --version && node --version && flutter --version
```

---

## 2. Première installation

```bash
# 1. Cloner le dépôt
git clone https://github.com/kortiene/HealthTech.git
cd HealthTech

# 2. Configurer le fichier d'environnement local (identifiants throwaway, non sensibles)
cp .env.example .env

# 3. Installer les dépendances Node (ADW pipeline + app-medecin)
cd adw_sdlc && pnpm install && cd ..
cd app-medecin && npm install && cd ..

# 4. Installer les dépendances Rust
cargo fetch

# 5. (optionnel) Installer le hook pre-commit pour détecter les fuites avant commit
printf '#!/usr/bin/env bash\ngitleaks protect --staged --no-banner --redact --config .gitleaks.toml\nbash scripts/check-secrets.sh\n' \
  > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

---

## 3. Stack de développement local

La stack locale simule la forme de staging (Postgres 16 + MinIO) avec des identifiants
**throwaway non-sensibles**. Aucune vraie credential n'est jamais nécessaire pour développer.

```bash
# Démarrer Postgres + MinIO en arrière-plan
just dev-up

# Arrêter et supprimer les conteneurs (les volumes sont conservés)
just dev-down
```

**Services exposés :**

| Service | Port | URL |
|---|---|---|
| PostgreSQL | 5432 | `postgres://healthtech:dev_throwaway_pg@localhost:5432/healthtech` |
| MinIO API | 9000 | `http://localhost:9000` |
| MinIO Console | 9001 | `http://localhost:9001` (admin: `dev_minio_root` / `dev_throwaway_minio`) |

> Les credentials ci-dessus sont des valeurs de développement évidentes. Ne jamais mettre
> de vraies valeurs dans `.env` — le fichier est gitignored mais `.env.example` est committé.

---

## 4. Lancer les tests

### Tous les tests (gate CI)

```bash
just test
```

Exécute dans l'ordre : Rust → PWA → Flutter → scripts de compliance → modèle de menaces →
scripts de résidence → scripts d'homologation.

### Par composant

```bash
# Rust : crypto-core + backend
cargo test --workspace

# PWA médecin (Preact + TypeScript)
cd app-medecin && npm test

# App patient (Flutter/Dart)
cd app-patient && flutter test

# Tests de performance (gate NFR §5 — budget 3G-STABLE)
just perf
```

### Suites spécialisées

```bash
# Tests unitaires Rust uniquement
cargo test -p crypto-core
cargo test -p backend

# Régression de performance (Rust) — déchiffrement < 100 ms
cargo test -p crypto-core --test decrypt_perf_regression

# Régression de performance (Dart) — chaîne CPU + taille blob ≤ 128 Kio
cd app-patient && flutter test test/perf test/record/blob_size_budget_test.dart

# Tests UX / accessibilité Flutter
cd app-patient && flutter test test/ux/

# Tests de sécurité Flutter (zero-knowledge, RAM wipe, offline queue)
cd app-patient && flutter test test/security/

# Tests de walkthrough PWA (Preact)
cd app-medecin && npm test -- --grep walkthrough

# Scripts de compliance, homologation, threat-model, résidence
bash scripts/check-compliance-matrix.sh
bash scripts/check-homologation-dossier.sh
bash scripts/check-threat-model.sh
bash scripts/check-residency.sh
bash scripts/check-ux-docs.sh
bash scripts/check-lowend-docs.sh
```

---

## 5. Lint et formatage

### Lint agrégé (tous composants)

```bash
just lint
```

Enchaîne : `cargo fmt --check` → `cargo clippy` → compliance-check → homologation-check →
threat-model-check → ux-check → lowend-check.

### Par composant

```bash
# Rust : format + clippy
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings

# Rust : corriger le formatage
cargo fmt

# Dart : vérifier le formatage
/Users/macbook/development/flutter/bin/dart format --set-exit-if-changed app-patient/

# Dart : corriger le formatage (OBLIGATOIRE avant tout commit Dart)
/Users/macbook/development/flutter/bin/dart format app-patient/

# Flutter : analyse statique (traite les infos comme des erreurs)
cd app-patient && flutter analyze

# TypeScript / PWA
cd app-medecin && npx tsc --noEmit
```

> **Règle absolue :** toujours lancer `dart format` et `cargo fmt` avant chaque commit
> sur des fichiers Dart ou Rust. Le CI bloque la PR si ces checks échouent.

---

## 6. Construire le projet

### Build complet

```bash
just build
```

Construit Rust (workspace) + PWA (Preact). Le build Flutter APK et l'image Docker sont
réservés au CI (artefacts de release).

### Par composant

```bash
# Rust workspace (crypto-core + backend)
cargo build --workspace
cargo build --workspace --release

# PWA médecin (bundle de production)
cd app-medecin && npm run build

# App patient — APK Android (nécessite Flutter SDK + Android toolchain)
cd app-patient && flutter build appbundle --split-per-abi

# Image Docker backend (musl statique → distroless, nécessite Docker)
just build-image
# équivalent : docker build -f backend/Dockerfile -t healthtech-backend:local .
```

---

## 7. SCA — analyse de dépendances

```bash
# Scan complet (Rust + npm + multi-écosystème)
just sca

# Rust : advisories + licences + politique de sources (deny.toml)
cargo deny check

# PWA : audit des dépendances de production uniquement
cd app-medecin && npm audit --omit=dev --audit-level=high

# Multi-écosystème (Cargo + npm + pub.dev) via OSV
osv-scanner scan source \
  --lockfile=Cargo.lock \
  --lockfile=app-medecin/package-lock.json \
  --lockfile=app-patient/pubspec.lock \
  --lockfile=adw_sdlc/package-lock.json
```

---

## 8. Contrôles de sécurité et secrets

### Détection de fuites (obligatoire avant merge)

```bash
just secrets-lint
# enchaîne :
# gitleaks detect --no-banner --redact --config .gitleaks.toml
# bash scripts/check-secrets.sh
```

### Gestion des bundles SOPS (staging / prod uniquement)

Les secrets de staging et prod sont chiffrés avec SOPS + age. La clé privée age
ne quitte **jamais** l'hôte in-country.

```bash
# Déchiffrer un bundle vers stdout (nécessite la clé age de l'environnement)
just secrets-decrypt staging
just secrets-decrypt prod

# Éditer un bundle en place (re-chiffrement à la sauvegarde)
just secrets-edit staging
just secrets-edit prod
```

> Les credentials dev (`.env`) sont des valeurs throwaway. Pour staging/prod,
> seule la personne en possession de la clé age in-country peut déchiffrer le bundle.

### Résidence des données (anti-régression)

```bash
# Tripwire résidence uniquement (sans credentials cloud, sans réseau)
just infra-residency
# bash scripts/check-residency.sh — échoue si un provider étranger entre dans infra/
```

---

## 9. Infrastructure et déploiement

### Validation IaC (credential-free)

```bash
just infra-validate
# enchaîne :
# bash scripts/check-residency.sh
# terraform -chdir=infra/terraform fmt -check
# terraform -chdir=infra/terraform init -backend=false
# terraform -chdir=infra/terraform validate
# ansible-playbook --syntax-check -i infra/ansible/inventories/<env> infra/ansible/playbook.yml
# (pour dev, staging, prod)
```

### Déploiement staging (in-country uniquement)

Pré-requis : accès SSH à un nœud en Côte d'Ivoire + clé age staging.

```bash
# 1. Déchiffrer le bundle de secrets vers un fichier 0600 temporaire
sops -d secrets/staging/services.sops.yaml > /run/healthtech/staging.env
chmod 0600 /run/healthtech/staging.env

# 2. Provisionner l'infrastructure
sops exec-env secrets/staging/services.sops.yaml \
  'terraform -chdir=infra/terraform apply -var-file=environments/staging.tfvars'

# 3. Configurer les nœuds
ansible-playbook -i infra/ansible/inventories/staging \
  infra/ansible/playbook.yml -e env=staging

# Nettoyer le fichier temporaire
shred -u /run/healthtech/staging.env
```

### Déploiement prod

Même flux que staging, en remplaçant `staging` par `prod`. La clé age prod ne quitte
jamais l'infrastructure in-country. Aucun outil de déchiffrement étranger n'est utilisé.

> **Note :** La mise en service complète dépend de l'issue #8 (provisionnement souverain).
> Le chemin ci-dessus est la procédure idempotente documentée que #8 finalise.

---

## 10. Pipeline de livraison agentique (ADW)

Le pipeline ADW (`adw_sdlc/`) orchestre la livraison d'une issue GitHub de bout en bout :
setup → classify → plan → implement → tests → resolve → e2e → review → patch → ship.

### Lancer le pipeline

```bash
# Depuis la racine du monorepo
just issue <N> --runner claude --yes

# Si adw_sdlc/pnpm-lock.yaml ou pnpm-workspace.yaml sont non-trackés
just issue <N> --runner claude --yes --allow-dirty
```

**Exemple :**
```bash
just issue 31 --runner claude --yes --allow-dirty
```

### Prérequis ADW

- `ANTHROPIC_API_KEY` exportée dans l'environnement (ou abonnement Anthropic actif)
- `pnpm install` dans `adw_sdlc/` effectué au préalable
- `adw_sdlc/pnpm-workspace.yaml` doit contenir `allowBuilds: esbuild: true`

### En cas d'échec à la phase ship (session limit)

Le pipeline peut atteindre la limite de session à la phase `ship`. Pour finaliser manuellement :

```bash
# 1. Trouver l'agent le plus récent
ls -lt agents/ | head -5

# 2. Lire le state pour récupérer commit_message et pr_body
cat agents/<adw_id>/state.json | python3 -m json.tool | grep -A5 "completed_phases"

# 3. Formater tous les fichiers Dart modifiés
/Users/macbook/development/flutter/bin/dart format app-patient/

# 4. Vérifier flutter analyze (doit être propre)
cd app-patient && flutter analyze

# 5. Vérifier cargo fmt (doit être propre)
cargo fmt --check

# 6. Stager les fichiers (exclure adw_sdlc/pnpm-lock.yaml et pnpm-workspace.yaml)
git add $(git diff --name-only HEAD) # ajuster selon les fichiers modifiés
git reset HEAD adw_sdlc/pnpm-lock.yaml adw_sdlc/pnpm-workspace.yaml 2>/dev/null || true

# 7. Committer, pousser, créer la PR
git commit -m "<commit_message de state.json>"
git push -u origin <branche>
gh pr create --title "<titre>" --body "<pr_body de state.json>"

# 8. Suivre la CI
gh pr checks <N> --watch --interval 30

# 9. Merger
gh pr merge <N> --squash --delete-branch
```

---

## 11. Vérifications ponctuelles

### Gate CI complet en local

```bash
just ci
# lint + test + build + sca — miroir du pipeline CI GitHub Actions
```

### Performance (budget 3G-STABLE)

```bash
just perf
```

Vérifie : déchiffrement Rust < 100 ms · blob compressé ≤ 128 Kio ·
chaîne CPU Dart · assertions compile-time dans `crypto-core`.

### Dossier homologation ARTCI

```bash
just homologation-check
# 46 assertions fail-closed sur les 18 pièces du dossier
```

### Compliance matrix (loi n°2013-450 / ARTCI)

```bash
bash scripts/check-compliance-matrix.sh
```

### Modèle de menaces

```bash
bash scripts/check-threat-model.sh
```

---

## 12. Dépannage

### `just dev-up` échoue — port déjà utilisé

```bash
# Identifier le processus occupant le port
lsof -i :5432   # Postgres
lsof -i :9000   # MinIO

# Changer le port dans .env
echo "POSTGRES_PORT=5433" >> .env
just dev-down && just dev-up
```

### `cargo test` échoue — Rust toolchain absente

```bash
rustup update stable
rustup target add aarch64-linux-android  # si build APK nécessaire
```

### `flutter test` échoue — SDK absent ou version incorrecte

```bash
flutter upgrade
flutter pub get  # dans app-patient/
```

### `cargo fmt --check` échoue (CI rouge)

```bash
cargo fmt       # corriger
git add -u && git commit --amend --no-edit   # ou nouveau commit
```

### `dart format` échoue (CI rouge)

```bash
/Users/macbook/development/flutter/bin/dart format app-patient/
git add -u
```

### `flutter analyze` signale `curly_braces_in_flow_control_structures`

```dart
// Mauvais
if (condition) doSomething();

// Correct
if (condition) {
  doSomething();
}
```

### `flutter analyze` signale `prefer_const_constructors`

```dart
// Mauvais
TextScaler.linear(1.5)

// Correct
const TextScaler.linear(1.5)
```

### Pipeline ADW : erreur `could not parse JSON from agent output`

La session Claude a expiré pendant la phase ship. Suivre la procédure de ship manuel
décrite à la [section 10](#10-pipeline-de-livraison-agentique-adw).

### `osv-scanner` non trouvé

```bash
# macOS
brew install osv-scanner

# Linux
wget -q https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_linux_amd64 \
  -O /usr/local/bin/osv-scanner && chmod +x /usr/local/bin/osv-scanner
```

### `sops -d` échoue — clé age absente

La clé age privée de l'environnement cible est hébergée in-country et ne doit jamais
quitter l'infrastructure souveraine. Contacter l'opérateur in-country pour accès.

---

## Références

| Ressource | Lien |
|---|---|
| Exigences produit | [`PRD_HealthTech.md`](../../PRD_HealthTech.md) |
| Backlog & roadmap | [`BACKLOG.md`](../../BACKLOG.md) |
| Décisions d'architecture | [`docs/adr/0000-index.md`](../adr/0000-index.md) |
| Matrice de conformité | [`docs/compliance/`](../compliance/) |
| Dossier homologation ARTCI | [`docs/compliance/homologation-artci/`](../compliance/homologation-artci/) |
| Budget de performance | [`docs/perf/decryption-budget.md`](../perf/decryption-budget.md) |
| Norme UX médecin | [`docs/ux/medecin-ux-guidelines.md`](../ux/medecin-ux-guidelines.md) |
| Statut du projet | [`docs/project/status.html`](./status.html) |
| Pipeline ADW | [`adw_sdlc/HEALTHTECH_PORT.md`](../../adw_sdlc/HEALTHTECH_PORT.md) |
| Gestion des secrets | [`secrets/README.md`](../../secrets/README.md) |
| Infra souveraine | [`infra/README.md`](../../infra/README.md) |
