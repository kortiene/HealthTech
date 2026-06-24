# Modèle de menace STRIDE — HealthTech

> **Issue :** [#6](https://github.com/kortiene/HealthTech/issues/6) · **Milestone :** M0 — Fondations & Conformité
> **Statut :** En cours de revue *(greenfield — aucune fonctionnalité livrée à ce jour)*
> **Méthode :** STRIDE (Microsoft Threat Modeling)
> **Dernière mise à jour :** Juin 2026
>
> Ce document est la **PREUVE-16** référencée dans
> [`docs/compliance/controles.md`](../compliance/controles.md) (CTRL-20) et la
> [`matrice de conformité`](../compliance/loi-2013-450-artci-matrix.md) (REQ-LEX-16).
> Il constitue une pièce probante du dossier d'homologation ARTCI ([#30](https://github.com/kortiene/HealthTech/issues/30)).

---

## Table des matières

1. [Portée et architecture de référence](#1-portée-et-architecture-de-référence)
2. [Hypothèses de sécurité](#2-hypothèses-de-sécurité)
3. [Flux de données et frontières de confiance](#3-flux-de-données-et-frontières-de-confiance)
4. [Catalogue des menaces](#4-catalogue-des-menaces)
   - [THR-01 — Vol de téléphone](#thr-01--vol-de-téléphone)
   - [THR-02 — Serveur compromis](#thr-02--serveur-compromis)
   - [THR-03 — MITM réseau](#thr-03--mitm-réseau)
   - [THR-04 — QR code intercepté](#thr-04--qr-code-intercepté)
   - [THR-05 — Attaque sur la phrase de passe de récupération](#thr-05--attaque-sur-la-phrase-de-passe-de-récupération)
   - [THR-06 — Répudiation d'actes médicaux](#thr-06--répudiation-dactes-médicaux)
   - [THR-07 — Déni de service](#thr-07--déni-de-service)
   - [THR-08 — Accès d'urgence / break-glass](#thr-08--accès-durgence--break-glass)
5. [Tableau de synthèse — contre-mesures `Must`](#5-tableau-de-synthèse--contre-mesures-must)
6. [Risques résiduels et limites connues](#6-risques-résiduels-et-limites-connues)
7. [Revue et mise à jour](#7-revue-et-mise-à-jour)

---

## 1. Portée et architecture de référence

### 1.1 Composants analysés

| Composant | Description | ADR de référence |
|-----------|-------------|-----------------|
| **App patient** (Android, Flutter) | Génère la clé maîtresse, chiffre le dossier, génère le QR d'accès éphémère | [ADR 0001](../adr/0001-patient-app-flutter.md) |
| **App médecin** (PWA Preact/TS) | Scanne le QR, déchiffre en RAM uniquement, édite, rechiffre, wipe RAM | [ADR 0002](../adr/0002-doctor-interface-pwa.md) |
| **Crypto-core** (Rust, RustCrypto) | Bibliothèque partagée AES-256-GCM, PBKDF2, gestion de nonces | [ADR 0003](../adr/0003-shared-crypto-core-rust.md) |
| **Backend** (Rust/Axum) | Store de blobs zero-knowledge `PUT/GET /blob/{uuid}`, métadonnées non identifiantes | [ADR 0004](../adr/0004-backend-rust-axum.md) |
| **Stockage** (MinIO + PostgreSQL) | Blobs opaques chiffrés, métadonnées UUID uniquement, hébergé en Côte d'Ivoire | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md) |
| **Infrastructure** (SOPS + age, Terraform) | Secrets in-country, pas de KMS étranger | [ADR 0007](../adr/0007-secrets-and-environments.md) |

> **État greenfield :** au moment de la rédaction, seul le squelette de monorepo est livré (#1–#5). Toutes les fonctionnalités métier sont **planifiées, non implémentées**. Ce threat model porte sur l'**architecture cible** décidée par les ADRs.

### 1.2 Actifs à protéger (assets)

| Asset | Sensibilité | Localisation |
|-------|-------------|--------------|
| Dossier médical en clair | **Critique** | RAM uniquement (apps) ; jamais sur disque en clair |
| Clé maîtresse AES-256 | **Critique** | Android Keystore côté patient ; jamais en clair côté serveur |
| Blob chiffré du dossier | **Élevée** | Cloud souverain (Côte d'Ivoire) ; illisible sans clé |
| Clé éphémère QR | **Élevée** | QR code uniquement (~120 s) ; jamais stockée |
| Phrase de passe / réponses culturelles de récupération | **Critique** | Côté patient uniquement ; non transmises |
| UUID d'indexation du blob | **Faible** | Serveur (métadonnée non identifiante) |

---

## 2. Hypothèses de sécurité

Ces hypothèses délimitent le périmètre du modèle. Les menaces qui violent ces hypothèses sont hors portée ou traitées comme des risques résiduels.

| ID | Hypothèse | Justification |
|----|-----------|---------------|
| **A-01** | Le système d'exploitation Android du patient est non compromis (ni rooté volontairement pour exfiltrer des clés, ni infecté par un malware ayant accès à l'Android Keystore) | L'Android Keystore est la racine de confiance ; un OS compromis la détruit |
| **A-02** | Le navigateur du médecin est non compromis et exécute le WASM crypto-core sans altération | La chaîne de livraison PWA (CI + TLS) garantit l'intégrité du WASM |
| **A-03** | Le canal TLS vers le backend est protégé par des certificats valides et non compromis | Mitigé par le chiffrement client-side indépendant du canal |
| **A-04** | L'hébergement est opéré sur le territoire national ivoirien conformément à l'ARTCI | Prouvé par attestation de localisation — [#8](https://github.com/kortiene/HealthTech/issues/8), PREUVE-05 |
| **A-05** | Le patient choisit un facteur de récupération (phrase ou réponses) de complexité suffisante | PBKDF2 rend le brute-force coûteux ; la responsabilité du secret reste côté utilisateur |

---

## 3. Flux de données et frontières de confiance

```
┌─────────────────────────────────────────────────────────┐
│ TÉLÉPHONE PATIENT (Android) — frontière de confiance #1 │
│                                                          │
│  ┌──────────────────┐  clé maîtresse  ┌───────────────┐│
│  │  App patient     │◄────────────────│Android Keystore││
│  │  (Flutter/Dart)  │                 └───────────────┘│
│  │                  │ appel FFI                        │
│  │  dossier en clair│◄───────────────┐                 │
│  └──────┬───────────┘                │                 │
│         │ chiffre                    │                 │
│         ▼ AES-256-GCM               │                 │
│  ┌──────────────────┐     ┌──────────────────┐        │
│  │  blob chiffré    │     │  crypto-core      │        │
│  │  (Rust WASM/FFI) │     │  (Rust RustCrypto)│        │
│  └──────┬───────────┘     └──────────────────┘        │
│         │ TLS + [blob déjà chiffré]                    │
└─────────┼───────────────────────────────────────────────┘
          │
          ▼  ◄── frontière réseau — MITM possible ici
┌─────────────────────────────────────────────────────────┐
│ BACKEND (Rust/Axum) — frontière de confiance #2         │
│  Côte d'Ivoire uniquement · zero-knowledge              │
│                                                          │
│  PUT /blob/{uuid} → MinIO (blob opaque)                  │
│  GET /blob/{uuid} ← MinIO                               │
│                                                          │
│  PostgreSQL : uuid | taille | horodatage | params KDF   │
│  (aucune PII, aucune clé, aucun plaintext)              │
└─────────────────────────────────────────────────────────┘
          │
          │  TLS + [blob opaque]
          ▼
┌─────────────────────────────────────────────────────────┐
│ NAVIGATEUR MÉDECIN — frontière de confiance #3          │
│  (PWA Preact/TS + WASM crypto-core)                     │
│                                                          │
│  QR scan → extrait clé éphémère + uuid                  │
│  GET /blob/{uuid} → déchiffre en RAM uniquement          │
│  édite → rechiffre → PUT /blob/{uuid} → wipe RAM        │
│                                                          │
│  ⚠ RAM-only best-effort en navigateur (ADR 0000 risque #1)│
└─────────────────────────────────────────────────────────┘
```

**Frontières de confiance :**
- **FC-1** : Téléphone patient — la clé maîtresse ne franchit jamais cette frontière en clair
- **FC-2** : Backend / Cloud souverain — ne voit que des blobs opaques et des UUIDs anonymes
- **FC-3** : Navigateur médecin — le clair est éphémère, wipe obligatoire en fin de session
- **FC-N** : Canal réseau — toujours TLS, et le clair est chiffré en amont indépendamment

---

## 4. Catalogue des menaces

### Légende STRIDE

| Lettre | Catégorie | Description |
|--------|-----------|-------------|
| **S** | Spoofing | Usurpation d'identité |
| **T** | Tampering | Altération d'intégrité |
| **R** | Repudiation | Déni d'une action réalisée |
| **I** | Information Disclosure | Divulgation non autorisée |
| **D** | Denial of Service | Déni de service |
| **E** | Elevation of Privilege | Élévation de privilèges |

---

### THR-01 — Vol de téléphone

**Catégories STRIDE :** `S` · `I` · `T`
**Priorité :** `Must`
**Composants exposés :** App patient, Keystore, stockage local

#### Scénarios d'attaque

| ID | Vecteur | Description | Sévérité |
|----|---------|-------------|----------|
| THR-01a | Vol + écran déverrouillé | L'attaquant accède à l'app en cours d'exécution et lit le dossier en clair en mémoire | Critique |
| THR-01b | Vol + écran verrouillé | L'attaquant tente d'extraire le blob local chiffré depuis le stockage Android | Élevée |
| THR-01c | Vol + extraction clé Keystore | L'attaquant tente d'extraire la clé maîtresse de l'Android Keystore par voie logicielle ou physique | Élevée |
| THR-01d | Usurpation patient | L'attaquant génère un QR code en se faisant passer pour le patient auprès d'un médecin | Élevée |

#### Contre-mesures

| Contrôle | Description | Issue | Statut |
|----------|-------------|-------|--------|
| **CTRL-01** | Chiffrement AES-256-GCM du dossier avant tout stockage local | [#10](https://github.com/kortiene/HealthTech/issues/10) | Planifié |
| **CTRL-03** | Clé maîtresse scellée dans l'Android Keystore, non exportable en clair | [#11](https://github.com/kortiene/HealthTech/issues/11) | Planifié |
| **OS-01** | Verrouillage écran obligatoire (PIN/biométrie) — contrôle OS, documenté en pré-requis d'onboarding | [#13](https://github.com/kortiene/HealthTech/issues/13) | Planifié |
| **CTRL-05** | QR éphémère 120 s — une session volée expire rapidement | [#16](https://github.com/kortiene/HealthTech/issues/16) | Planifié |

#### Risque résiduel

- THR-01a (écran déverrouillé) : risque faible côté données si l'app ne garde pas le plaintext en mémoire entre sessions. À garantir dans l'implémentation #13/#16.
- THR-01c (extraction Keystore physique) : contre-mesure = StrongBox si disponible ; PBKDF2 recovery (#12) est le backstop si le Keystore est perdu/wipé.

---

### THR-02 — Serveur compromis

**Catégories STRIDE :** `I` · `T`
**Priorité :** `Must`
**Composants exposés :** Backend, MinIO, PostgreSQL

#### Scénarios d'attaque

| ID | Vecteur | Description | Sévérité |
|----|---------|-------------|----------|
| THR-02a | Admin serveur / hébergeur malveillant | Un opérateur avec accès root lit les blobs stockés | Élevée |
| THR-02b | Intrusion backend | Un attaquant compromise le service Axum et intercepte les requêtes | Élevée |
| THR-02c | Intrusion base de données | L'attaquant lit la table PostgreSQL de métadonnées | Modérée |
| THR-02d | Altération de blob | L'attaquant modifie un blob en transit ou en stockage pour corrompre un dossier | Élevée |

#### Contre-mesures

| Contrôle | Description | Issue | Statut |
|----------|-------------|-------|--------|
| **CTRL-02** | Architecture zero-knowledge : blobs opaques indexés par UUID anonymes ; aucune voie de déchiffrement côté serveur | [#9](https://github.com/kortiene/HealthTech/issues/9) | Planifié |
| **CTRL-01** | AES-256-GCM authentifié côté client — le blob chiffré est illisible ET toute altération est détectée à la vérification du tag GCM | [#10](https://github.com/kortiene/HealthTech/issues/10) | Planifié |
| **CTRL-13** | Aucune PII, aucune clé, aucun plaintext en base — métadonnées non identifiantes uniquement | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md) | Planifié |
| **CTRL-14** | Redaction des logs : aucune PII/clé/clair journalisée côté backend | [ADR 0007](../adr/0007-secrets-and-environments.md) | Partiel |
| **CTRL-08** | Hébergement souverain in-country uniquement (pas de cloud étranger dans le chemin de données) | [#8](https://github.com/kortiene/HealthTech/issues/8) | Planifié |

#### Risque résiduel

- Un serveur compromis peut **détruire ou corrompre** les blobs (THR-02d), causant une perte de données. Mitigé par : HA in-country (sauvegarde en Côte d'Ivoire) et local-first (le patient garde sa copie chiffrée). Disponibilité et intégrité à consolider dans #9.
- Un admin malveillant ne peut **pas lire** le contenu médical (zero-knowledge prouvé par conception), mais peut collecter des métadonnées de timing / corrélation d'accès. Minimisé par CTRL-13.

---

### THR-03 — MITM réseau

**Catégories STRIDE :** `I` · `T` · `S`
**Priorité :** `Must`
**Composants exposés :** Canal réseau patient→backend, canal médecin→backend

#### Scénarios d'attaque

| ID | Vecteur | Description | Sévérité |
|----|---------|-------------|----------|
| THR-03a | Wi-Fi public / point d'accès malveillant | L'attaquant intercepte le trafic entre l'app et le backend (Yopougon, Cocody) | Élevée |
| THR-03b | Faux certificat TLS (CA compromise ou cert pinning absent) | L'attaquant décrypte le TLS et lit les requêtes | Élevée |
| THR-03c | Replay d'une requête PUT | L'attaquant rejoue une ancienne requête pour écraser un blob mis à jour | Modérée |
| THR-03d | Altération du blob en transit | L'attaquant modifie le blob entre le client et le serveur | Élevée |

#### Contre-mesures

| Contrôle | Description | Issue | Statut |
|----------|-------------|-------|--------|
| **CTRL-01** | Chiffrement AES-256-GCM **avant** tout transit : même sans TLS, l'attaquant ne voit que du ciphertext illisible | [#10](https://github.com/kortiene/HealthTech/issues/10) | Planifié |
| **CTRL-23** | TLS obligatoire sur toutes les routes backend (reverse proxy in-country) | [ADR 0005](../adr/0005-storage-and-sovereign-hosting.md), [#8](https://github.com/kortiene/HealthTech/issues/8) | Planifié |
| **CTRL-01** (GCM tag) | Le tag d'authentification GCM détecte toute altération du blob en transit (THR-03d) | [#10](https://github.com/kortiene/HealthTech/issues/10) | Planifié |

#### Risque résiduel

- **Cert pinning absent** (hypothèse A-03) : mitigé par le chiffrement indépendant du canal (CTRL-01). Un MITM TLS ne donne que du ciphertext illisible sans la clé.
- **Replay (THR-03c)** : les nonces AES-GCM sont à usage unique — un replay rejoue un blob déjà daté ; le versioning de blob (#9) doit rejeter les rééécritures obsolètes.
- **Réseau dégradé** : l'architecture local-first permet de continuer hors-ligne sans dépendre du canal réseau.

---

### THR-04 — QR code intercepté

**Catégories STRIDE :** `I` · `S`
**Priorité :** `Must`
**Composants exposés :** App patient (génération QR), App médecin (scan QR)

#### Scénarios d'attaque

| ID | Vecteur | Description | Sévérité |
|----|---------|-------------|----------|
| THR-04a | Capture visuelle (shoulder surfing, caméra cachée) | L'attaquant photographie le QR affiché sur le téléphone du patient dans la salle d'attente | Critique |
| THR-04b | Screenshot / partage accidentel | Le patient fait une capture d'écran du QR et la partage (réseau social, messagerie) | Élevée |
| THR-04c | Interception réseau du QR | L'attaquant capture le QR via MITM si celui-ci est transmis par réseau (cas non nominal) | Modérée |
| THR-04d | Réutilisation d'un QR expiré | L'attaquant tente de réutiliser un QR déjà scanné ou expiré | Faible |

#### Contre-mesures

| Contrôle | Description | Issue | Statut |
|----------|-------------|-------|--------|
| **CTRL-05** | QR éphémère : expiration à **~120 secondes** ; clé jamais stockée hors du QR | [#16](https://github.com/kortiene/HealthTech/issues/16) | Planifié |
| **CTRL-05** | Clé déchiffrée **uniquement en RAM** côté médecin — jamais persistée | [#17](https://github.com/kortiene/HealthTech/issues/17) | Planifié |
| **CTRL-07** | Wipe RAM à la fin de session (clic « Terminer » ou 15 min d'inactivité) | [#19](https://github.com/kortiene/HealthTech/issues/19) | Planifié |
| **DESIGN-QR** | Le QR contient à la fois l'UUID du blob ET la clé éphémère : l'attaquant doit intercepter les deux ET accéder au backend dans la fenêtre de 120 s — condition doublement contrainte | [#16](https://github.com/kortiene/HealthTech/issues/16), [#9](https://github.com/kortiene/HealthTech/issues/9) | Planifié |

#### Risque résiduel

- Une capture visuelle dans la fenêtre des 120 s avec un accès réseau au backend constitue une attaque réaliste dans un scénario de menace interne (personnel soignant malveillant). Mitigé par la brièveté de la fenêtre et le wipe post-scan.
- L'utilisation d'un QR expiré (THR-04d) doit être rejetée côté serveur et/ou côté médecin (#16, #17).
- **UX à risque** : le QR ne doit pas être affiché en permanence — afficher uniquement à la demande du patient avec compte à rebours visible (#16).

---

### THR-05 — Attaque sur la phrase de passe de récupération

**Catégories STRIDE :** `E`
**Priorité :** `Must`
**Composants exposés :** Crypto-core (PBKDF2), App patient (onboarding/récupération)

#### Scénarios d'attaque

| ID | Vecteur | Description | Sévérité |
|----|---------|-------------|----------|
| THR-05a | Brute-force en ligne de la récupération | L'attaquant tente en boucle des combinaisons de réponses culturelles via l'app ou l'API | Élevée |
| THR-05b | Brute-force hors ligne après exfiltration | L'attaquant vole le blob chiffré et la valeur KDF (sel + paramètres) et lance un brute-force GPU | Critique |
| THR-05c | Attaque par dictionnaire (réponses culturelles prévisibles) | Les réponses aux questions culturelles ivoiriennes ont une entropie limitée | Élevée |
| THR-05d | Ingénierie sociale | L'attaquant convainc le patient de révéler sa phrase de passe | Élevée |

#### Contre-mesures

| Contrôle | Description | Issue | Statut |
|----------|-------------|-------|--------|
| **CTRL-04** | PBKDF2 avec paramètres de coût calibrés pour les SoCs d'entrée de gamme (itération haute, sel aléatoire 256 bits) — brute-force GPU coûteux même hors ligne | [#12](https://github.com/kortiene/HealthTech/issues/12) | Planifié |
| **CTRL-04** | Sel aléatoire stocké avec les paramètres KDF : chaque compte a un espace de brute-force distinct | [#12](https://github.com/kortiene/HealthTech/issues/12) | Planifié |
| **DESIGN-KDF** | Questions culturelles ivoiriennes + phrase libre en combinaison pour augmenter l'entropie | [#12](https://github.com/kortiene/HealthTech/issues/12) | Planifié |
| **RATE-LIMIT** | Limitation de débit pour les tentatives de récupération en ligne (app + éventuellement API) | [#12](https://github.com/kortiene/HealthTech/issues/12) | Planifié |

#### Risque résiduel

- **THR-05b (brute-force hors ligne)** : le blob chiffré est public sur le serveur (zero-knowledge) ; un attaquant déterminé peut brute-forcer PBKDF2 avec du matériel GPU. La résistance dépend entièrement du coût KDF et de l'entropie de la phrase. Le paramétrage de #12 est critique : documenter le coût minimal recommandé.
- **THR-05c (faible entropie culturelle)** : les réponses seules sont insuffisantes — la combinaison phrase + réponses est requise. À valider en test d'utilisabilité (#28).
- **THR-05d (ingénierie sociale)** : hors portée technique ; couvert par la formation et la politique de consentement (#7).

---

### THR-06 — Répudiation d'actes médicaux

**Catégories STRIDE :** `R`
**Priorité :** `Should`
**Composants exposés :** App médecin, backend, dossier médical

#### Scénarios d'attaque

| ID | Vecteur | Description | Sévérité |
|----|---------|-------------|----------|
| THR-06a | Déni de note / ordonnance | Un médecin conteste avoir ajouté une note ou prescrit un traitement | Modérée |
| THR-06b | Attribution erronée | Une note est incorrectement attribuée à un médecin (multiples praticiens sur le même appareil) | Modérée |

#### Contre-mesures

| Contrôle | Description | Issue | Statut |
|----------|-------------|-------|--------|
| **CTRL-18** | Rechiffrement du dossier mis à jour avec horodatage de session inclus dans le clair rechiffré | [#18](https://github.com/kortiene/HealthTech/issues/18) | Planifié |
| **DESIGN-AUDIT** | Inclure dans le dossier (clair, partie chiffrée) un journal d'actes avec horodatage et identifiant praticien | [#15](https://github.com/kortiene/HealthTech/issues/15), [#18](https://github.com/kortiene/HealthTech/issues/18) | Planifié |

#### Risque résiduel

- L'identifiant praticien dans le dossier chiffré est auto-déclaré (non cryptographiquement prouvé faute de PKI médecin). Une PKI est hors portée pour M0–M2 ; à noter pour #25 (pentest) et #30 (dossier ARTCI).

---

### THR-07 — Déni de service

**Catégories STRIDE :** `D`
**Priorité :** `Should`
**Composants exposés :** Backend, MinIO, App patient

#### Scénarios d'attaque

| ID | Vecteur | Description | Sévérité |
|----|---------|-------------|----------|
| THR-07a | Inondation du store de blobs | L'attaquant charge des milliers de faux blobs saturant le stockage MinIO | Élevée |
| THR-07b | Coupure réseau intentionnelle | Indisponibilité du backend empêchant la sauvegarde cloud / récupération | Modérée |
| THR-07c | Épuisement des UUIDs valides | Attaque par énumération ou flooding d'UUIDs (faible probabilité) | Faible |

#### Contre-mesures

| Contrôle | Description | Issue | Statut |
|----------|-------------|-------|--------|
| **CTRL-17** | Architecture local-first : la consultation fonctionne hors ligne — le déni de service cloud n'interrompt pas les soins | [#14](https://github.com/kortiene/HealthTech/issues/14) | Planifié |
| **RATE-API** | Rate-limiting et quotas par UUID sur l'API blob | [#9](https://github.com/kortiene/HealthTech/issues/9) | Planifié |
| **CTRL-21** | File hors-ligne SQLCipher/IndexedDB synchronisée au retour réseau | [#21](https://github.com/kortiene/HealthTech/issues/21) | Planifié |
| **INFRA-HA** | HA in-country (primaire + réplique + warm standby) pour minimiser les interruptions de disponibilité | [#8](https://github.com/kortiene/HealthTech/issues/8) | Planifié |

#### Risque résiduel

- Un serveur indisponible bloque la **sauvegarde cloud** mais pas la consultation locale (local-first). La donnée chiffrée reste sur le téléphone.
- La coupure longue d'hébergement unique en Côte d'Ivoire reste un SPOF de disponibilité (cf. ADR 0000 risque #5) : aucun failover étranger autorisé.

---

### THR-08 — Accès d'urgence / break-glass

**Catégories STRIDE :** `E`
**Priorité :** `Could` *(hors portée M0–M2, signalé comme ECART-08)*
**Composants exposés :** Architecture globale (porte dérobée potentielle)

#### Scénario d'attaque

| ID | Vecteur | Description | Sévérité |
|----|---------|-------------|----------|
| THR-08a | Patient inconscient | Un médecin urgentiste a besoin du dossier sans QR patient | Élevée (médicale) |
| THR-08b | Pression réglementaire / judiciaire | Une autorité demande l'accès à un dossier sans consentement patient | Élevée (juridique) |

#### Position du projet

> **Règle absolue :** aucune porte dérobée (backdoor) serveur n'est introduite. Le zero-knowledge doit rester total côté serveur.

| Contrôle | Description | Issue | Statut |
|----------|-------------|-------|--------|
| **DESIGN-TRUST** | Toute solution d'accès d'urgence doit être **initiée côté patient** (ex. : clé de délégation scellée dans un tiers de confiance de son choix) — jamais côté serveur | [ECART-08](../compliance/ecarts.md) | Analyse requise |

#### Risque résiduel

- Cette menace est **délibérément non résolue en M0**. Elle fait l'objet de ECART-08 et sera instruite avec le conseil juridique avant M2. Ne pas introduire de solution technique ad hoc sans analyse de risque et validation juridique.

---

## 5. Tableau de synthèse — contre-mesures `Must`

> Conformément au critère d'acceptation de l'issue #6 : **chaque menace `Must` est tracée vers au moins une issue du backlog**.

| Menace | STRIDE | Priorité | Contre-mesure principale | Issues porteuses |
|--------|--------|----------|--------------------------|-----------------|
| **THR-01** Vol de téléphone | S, I, T | **Must** | AES-256-GCM at rest + Android Keystore | [#10](https://github.com/kortiene/HealthTech/issues/10), [#11](https://github.com/kortiene/HealthTech/issues/11), [#13](https://github.com/kortiene/HealthTech/issues/13) |
| **THR-02** Serveur compromis | I, T | **Must** | Architecture zero-knowledge (blobs opaques + UUID) | [#9](https://github.com/kortiene/HealthTech/issues/9), [#10](https://github.com/kortiene/HealthTech/issues/10), [#8](https://github.com/kortiene/HealthTech/issues/8) |
| **THR-03** MITM réseau | I, T, S | **Must** | Chiffrement AES-256-GCM avant transit + TLS | [#10](https://github.com/kortiene/HealthTech/issues/10), [#8](https://github.com/kortiene/HealthTech/issues/8) |
| **THR-04** QR code intercepté | I, S | **Must** | Expiration 120 s + clé éphémère + RAM-only + wipe | [#16](https://github.com/kortiene/HealthTech/issues/16), [#17](https://github.com/kortiene/HealthTech/issues/17), [#19](https://github.com/kortiene/HealthTech/issues/19) |
| **THR-05** Attaque sur phrase de récupération | E | **Must** | PBKDF2 coût élevé + sel aléatoire + rate-limiting | [#12](https://github.com/kortiene/HealthTech/issues/12) |
| **THR-06** Répudiation actes médicaux | R | Should | Horodatage + journal dans le dossier chiffré | [#18](https://github.com/kortiene/HealthTech/issues/18), [#15](https://github.com/kortiene/HealthTech/issues/15) |
| **THR-07** Déni de service | D | Should | Local-first + file hors-ligne + HA in-country | [#14](https://github.com/kortiene/HealthTech/issues/14), [#21](https://github.com/kortiene/HealthTech/issues/21), [#8](https://github.com/kortiene/HealthTech/issues/8) |
| **THR-08** Accès d'urgence | E | Could | Analyse requise — aucune backdoor serveur (ECART-08) | [ECART-08](../compliance/ecarts.md) |

---

## 6. Risques résiduels et limites connues

Ces risques sont connus et acceptés dans l'état actuel du projet. Ils doivent être réévalués à chaque milestone.

| ID | Risque résiduel | Mitigation actuelle | À escalader vers |
|----|-----------------|--------------------|--------------------|
| **RR-01** | RAM-only navigateur best-effort (JS GC peut copier/pager du plaintext) | Reload-to-drop-heap, durée de vie minimale du plaintext, zeroize WASM | [#25](https://github.com/kortiene/HealthTech/issues/25) (pentest) |
| **RR-02** | Brute-force hors-ligne PBKDF2 si entropie de phrase insuffisante | Paramétrage coût PBKDF2 + sel 256 bits | [#12](https://github.com/kortiene/HealthTech/issues/12), [#26](https://github.com/kortiene/HealthTech/issues/26) |
| **RR-03** | Absence de cert pinning — MITM TLS possible (avec CA compromise) | Chiffrement client-side indépendant du canal | [#25](https://github.com/kortiene/HealthTech/issues/25) |
| **RR-04** | Accès d'urgence non résolu (patient inconscient) | ECART-08 — analyse requise | [ECART-08](../compliance/ecarts.md) |
| **RR-05** | SPOF de disponibilité (datacenter unique en CI) | Local-first, HA in-country | [#8](https://github.com/kortiene/HealthTech/issues/8) |
| **RR-06** | Identifiant praticien auto-déclaré (pas de PKI médecin) | Hors portée M0–M2 | [#30](https://github.com/kortiene/HealthTech/issues/30) (ARTCI) |
| **RR-07** | StrongBox Android absent sur certains appareils bas de gamme | PBKDF2 recovery (#12) est le backstop | [#12](https://github.com/kortiene/HealthTech/issues/12), [#29](https://github.com/kortiene/HealthTech/issues/29) |

---

## 7. Revue et mise à jour

| Événement déclencheur | Action requise |
|-----------------------|----------------|
| Nouvelle fonctionnalité modifiant les frontières de confiance | Mise à jour de la section 3 et du catalogue section 4 |
| Livraison d'un milestone (M1, M2, M3, M4) | Réviser les statuts des contre-mesures (Planifié → Livré) |
| Résultat du pentest externe ([#25](https://github.com/kortiene/HealthTech/issues/25)) | Intégrer les vulnérabilités identifiées comme nouvelles menaces ou contre-mesures renforcées |
| Revue crypto indépendante ([#26](https://github.com/kortiene/HealthTech/issues/26)) | Mettre à jour THR-01c, THR-05, RR-02 |
| Instruction de l'accès d'urgence (ECART-08) | Compléter THR-08 avec la solution retenue |
| Modification de la loi n°2013-450 ou des exigences ARTCI | Vérifier l'alignement des contre-mesures avec la matrice [#5](https://github.com/kortiene/HealthTech/issues/5) |

> **Propriétaire :** Équipe Sécurité / Product Team
> **Prochaine revue planifiée :** Avant la clôture de M1
> **Validé par :** *à signer avant soumission au dossier ARTCI (#30)*
