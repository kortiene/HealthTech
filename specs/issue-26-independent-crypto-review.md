# Spec — Issue #26 : Revue Cryptographique Indépendante

**Épic :** E3 — Sécurité & audit
**Priorité :** Should · M4 — Durcissement & lancement
**Effort :** M
**Dépend de :** #10 (crypto-core review interne), #6 (STRIDE threat model)

---

## Problème

La bibliothèque `crypto-core` (Rust / RustCrypto) est le seul composant qui gère les clés, le chiffrement AES-256-GCM et la dérivation PBKDF2 pour l'ensemble de la plateforme. L'équipe a réalisé une revue interne (issue #10), mais aucun expert cryptographique externe n'a validé les choix de primitives, les paramètres de sécurité, les invariants zero-knowledge, ni le code d'implémentation. L'homologation ARTCI (#30) et le lancement M4 nécessitent cet avis externe.

---

## Objectifs

- Produire un **brief externe complet** permettant à un expert crypto tiers de réaliser la revue sans accès privilégié aux systèmes de production.
- Couvrir toutes les primitives : AES-256-GCM (nonces, tags, AAD), PBKDF2-HMAC-SHA256 (paramètres itérations, plancher), gestion des clés maîtresses, QR éphémère, HMAC-SHA256 capability URLs, compression avant chiffrement (#24).
- Lister les vecteurs de test NIST/RFC reproductibles localement.
- Formuler les questions ouvertes (PBKDF2 vs Argon2id, AAD différé, oracle de compression, wipe mémoire GC).
- Définir les livrables et critères d'acceptation attendus du réviseur.

## Non-objectifs

- Réaliser la revue externe elle-même (hors périmètre de cette issue).
- Corriger des vulnérabilités identifiées (feront l'objet d'issues dédiées).
- Couvrir l'infrastructure, la CI/CD, ou la conformité légale ARTCI.

---

## Contexte du dépôt

| Document | Pertinence |
|---|---|
| `docs/security/crypto-core-review.md` | Revue interne issue #10 (C1–C15) |
| `docs/threat-model/stride-threat-model.md` | Modèle STRIDE issue #6 (THR-01–THR-08) |
| `crypto-core/src/lib.rs` | Implémentation Rust à auditer |
| `crypto-core/tests/` | Vecteurs NIST CAVP et RFC 6070 |

---

## Composants affectés

- `crypto-core/` (Rust) — périmètre P1 de la revue
- `app-patient/lib/src/` (Flutter) — périmètre P2
- `backend/src/media/access.rs` (Axum) — périmètre P2

---

## Implémentation

### Livrable : `docs/security/independent-crypto-review-brief.md`

Document externe structuré en 9 sections :

1. **Contexte et enjeux** — architecture ZK, modèle de menace simplifié
2. **Périmètre** — fichiers P1 (crypto-core) et P2 (intégration Flutter/backend), hors périmètre
3. **Primitives** — AES-256-GCM, PBKDF2, gestion clé maîtresse, QR éphémère, HMAC-SHA256, compression
4. **Invariants ZK** — ZK-1 à ZK-5 (server never sees plaintext/key, RAM-only decrypt, session wipe, logs)
5. **Vecteurs de test** — commandes `cargo test` reproductibles hors réseau
6. **Dépendances RustCrypto** — versions épinglées à vérifier
7. **Questions ouvertes** — PBKDF2 vs Argon2id, AAD différé, oracle de compression, wipe GC
8. **Livrables attendus** — rapport, liste CVE, avis global (favorable / conditionnel)
9. **Accès au code** — instructions `git clone + cargo test` (aucun secret requis)

---

## Considérations de sécurité et vie privée

- Le document ne contient aucune clé, PII, secret de production, ni vecteur de test non officiel.
- Les vecteurs NIST/RFC listés sont 100 % publics et reproductibles.
- L'accès au code pour la revue se fait via le dépôt public GitHub (lecture seule).
- Le brief mentionne explicitement que les vecteurs sont déterministes et ne nécessitent pas de secrets réels.

---

## Plan de tests

Aucun test automatisé requis pour cette issue (le livrable est documentaire).
Les vecteurs de test listés dans le brief sont déjà couverts par `cargo test --package crypto-core`.

E2E : non applicable.

---

## Checklist d'implémentation

- [x] `specs/issue-26-independent-crypto-review.md` (ce fichier)
- [x] `docs/security/independent-crypto-review-brief.md` — brief externe complet (9 sections)

---

## Critère d'acceptation

Le brief est suffisamment complet pour qu'un expert crypto externe puisse :
- Identifier tous les fichiers à auditer (P1 et P2)
- Reproduire tous les vecteurs de test sans accès réseau ni secrets réels
- Répondre aux questions ouvertes listées
- Produire un avis favorable ou conditionnel (closes #26)
