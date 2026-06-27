# Revue de sécurité — module `crypto-core` (AES-256-GCM)

> **Périmètre :** issue [#10](https://github.com/kortiene/HealthTech/issues/10) — module
> AES-256-GCM (chiffrement/déchiffrement de blob) et **gestion des nonces**. Couvre le
> second critère d'acceptation de #10 (« revue de sécurité du module »).
>
> **Hors périmètre :** PBKDF2 / calibration (#12), scellement keystore + canal AAD (#11),
> bindings FFI/WASM (#11/#17), service de stockage (#9), QR/RAM/wipe applicatifs
> (#16/#17/#19), **revue cryptographique indépendante externe (#26)**. Ce document est la
> revue **interne** qui prépare #26.
>
> **Artefacts référencés :** [`crypto-core/src/lib.rs`](../../crypto-core/src/lib.rs),
> [`crypto-core/tests/aes_gcm_nist_vectors.rs`](../../crypto-core/tests/aes_gcm_nist_vectors.rs),
> [`crypto-core/tests/vectors/PROVENANCE.md`](../../crypto-core/tests/vectors/PROVENANCE.md),
> [ADR 0003](../adr/0003-shared-crypto-core-rust.md),
> [modèle de menace STRIDE](../threat-model/stride-threat-model.md) (#6).

## 1. Décisions de conception arrêtées par #10

| Sujet | Décision | Justification |
| --- | --- | --- |
| **Octet de version** dans le format de fil | **Non** en v1. Format figé = `nonce(12) \|\| ciphertext \|\| tag(16)` | L'overhead de **28 o** est déjà budgété par le service de blob #9 (mergé). Un octet de version le ferait passer à 29 o et contredirait du code en place. L'évolution (AAD #11, futur algo) se fera de façon **additive** (nouvelle fonction / nouveau format auto-descriptif), pas par réinterprétation silencieuse de ces octets. |
| **Canal AAD** (#11) | Différé, ajouté plus tard comme **fonction additive** (p. ex. `encrypt_record_aad`) | Préserve la signature « stable » promise par #10. Le chemin AEAD+AAD est **déjà prouvé** par un vecteur KAT à AAD non vide, donc #11 peut s'y appuyer sans rupture. |
| **Source des vecteurs** | Sous-ensemble représentatif encodé en dur + provenance documentée | Lisibilité/empreinte vs committer les `.rsp` NIST multi-Mo. Couvre encrypt exact, decrypt PASS, decrypt FAIL, AAD vide + non vide. Extension au corpus CAVP complet documentée dans `PROVENANCE.md`. |
| **Emplacement des KAT exacts** | Module interne `#[cfg(test)]` de `lib.rs` (nonce fixé) + test d'intégration public | Comparer à un IV fixe impose un nonce choisi ; ce chemin reste **crate-interne** pour ne pas exposer une API à nonce-choisi-par-l'appelant (risque de réutilisation). |

## 2. Checklist de revue crypto (exigence → preuve)

| # | Exigence de sécurité | Statut | Preuve (code / test) |
| --- | --- | :---: | --- |
| C1 | **AEAD authentifié** AES-256-GCM, confidentialité **et** intégrité ; pas de mode non authentifié, pas de troncature de tag (tag 128 bits plein) | ✅ | `seal`/`open` via `Aes256Gcm` ; `TAG_LEN = 16` ; aucune API n'expose un mode non authentifié (`lib.rs`). |
| C2 | **Vecteurs officiels passants** (critère d'acceptation #1) — encrypt exact `CT\|\|Tag`, decrypt PASS | ✅ | `nist_kat_encrypt_exact_ciphertext_and_tag`, `nist_kat_decrypt_recovers_plaintext` (`lib.rs`) ; `public_decrypt_matches_nist_empty_aad_vectors` (intégration). |
| C3 | **FAIL vectors** : tag/CT altéré → rejet, **aucun** plaintext renvoyé | ✅ | `nist_kat_decrypt_fails_on_tampered_tag`, `nist_kat_decrypt_fails_on_wrong_aad`, `public_decrypt_rejects_tampered_nist_vectors`. |
| C4 | **Nonce 96 bits aléatoire par appel**, jamais réutilisé sous une clé | ✅ | `encrypt_record` tire `getrandom` à chaque appel ; `fresh_nonce_makes_outputs_differ`. |
| C5 | **Échec CSPRNG → erreur**, jamais un nonce nul/dégénéré | ✅ | `encrypt_record` : `getrandom(...).map_err(Rng)?` **avant** tout chiffrement ; aucun chemin n'émet un nonce par défaut. |
| C6 | **Borne d'usage du nonce** documentée (collision ≈ 2³² msg/clé) et jugée sans risque | ✅ | Doc `//!` « Nonce policy / Usage bound » (`lib.rs`) : un blob réécrit par consultation ≪ 2³². |
| C7 | **Pas d'oracle** : erreurs coarse ne distinguant pas mauvaise clé / tag / blob court | ✅ | `CryptoError { Rng, Decrypt }` ; `decrypt_record` mappe tous les échecs sur `Decrypt` ; tests wrong-key / truncated / extended / short → même variante. |
| C8 | **Robustesse des entrées** (G6) : blob court, plaintext vide, mauvaise clé, CT tronqué/étendu, borne 500 Ko | ✅ | `empty_plaintext_round_trips`, `blob_of_exactly_overhead_is_legal_empty_record`, `wrong_key_is_rejected`, `truncated_ciphertext_is_rejected`, `extended_ciphertext_is_rejected`, `blob_shorter_than_nonce_is_rejected`, `record_at_500kb_budget_round_trips`. |
| C9 | **Wipe des secrets** via `zeroize` | ✅ | `wipe` + `wipe_zeroes_buffer` ; `generate_master_key` documente le devoir de wipe côté appelant. |
| C10 | **Aucune fuite de matériel sensible** : pas de `Debug`/log de clé/clair/nonce, messages d'erreur génériques | ✅ | `CryptoError` ne contient aucune donnée ; `Display` renvoie des chaînes fixes ; aucune clé/nonce/clair n'implémente `Debug` exporté ni n'est loggé. |
| C11 | **Pas d'`unsafe`, pas de warnings** | ✅ | `#![forbid(unsafe_code)]` + `#![deny(warnings)]` en tête de `lib.rs` ; clippy `-D warnings` en CI (ADR 0008). |
| C12 | **Unique lieu d'AES** (ADR 0003) : pas de crypto plateforme | ✅ | `lib.rs` est le seul implémenteur ; placeholders consommateurs (`crypto_core_bindings.dart`, `session.ts`) interdisent explicitement la crypto Dart/WebCrypto. |
| C13 | **Dépendances épinglées + supply-chain** : RustCrypto pinné, `cargo-audit`/`cargo-deny` | ✅ | `crypto-core/Cargo.toml` (versions épinglées) ; `deny.toml` ; `just sca` → `cargo deny check`. |
| C14 | **Sans I/O, sans état** (utilisable en RAM pure pour #17, file offline #21) | ✅ | Aucune API n'effectue d'I/O ni ne met en cache ; documenté en `//!` (« Stateless, no-I/O »). |
| C15 | **Zero-knowledge** : aucune API n'exfiltre la clé hors du crate ; sortie = `nonce\|\|ct\|\|tag` opaque | ✅ | `encrypt_record` ne renvoie que le blob ; la clé reste un `[u8; 32]` fourni/produit, jamais sérialisé par le module. |

## 3. Couverture du modèle de menace (#6)

| Menace (STRIDE #6) | Contre-mesure tracée par #10 |
| --- | --- |
| Vol de téléphone | Blob chiffré AES-256-GCM ; la confidentialité repose sur la clé scellée hors module (#11). |
| Serveur compromis | Le serveur ne voit que `nonce\|\|ct\|\|tag` (C15) ; aucune clé ni chemin de déchiffrement côté serveur. |
| MITM réseau | Intégrité authentifiée (C1/C3) : toute altération en transit → `Decrypt`, jamais de clair. |
| QR intercepté | Hors périmètre #10 (transport de clé = #16) ; le module reste utilisable RAM-only (C14) pour le wipe #19. |

## 4. Risques résiduels / suites

- **R1 — Réutilisation de nonce sous contrainte d'entropie faible.** Mitigé : échec RNG →
  erreur (C5). À re-confirmer côté appelants (#11) que `getrandom` est bien câblé sur
  l'entropie OS Android/WASM.
- **R2 — SPOF supply-chain** (ADR 0003) : un crate RustCrypto compromis poisonne les trois
  clients. Mitigé par épinglage + `cargo-deny`/`cargo-audit` ; à surveiller en continu.
- **R3 — Évolution de format.** Si un octet de version devient nécessaire (algo futur),
  l'introduire **avant** toute mise en production de blobs (cf. §1) ; coordination #9/#11.
- **R4 — Revue indépendante (#26)** non encore réalisée : ce document est la revue interne ;
  l'avis d'expert tiers reste requis avant production.

## 5. Verdict

Les trois critères d'acceptation de #10 sont couverts : **(1)** vecteurs officiels
AES-256-GCM passants en gating CI, **(2)** revue de sécurité tracée (ce document), **(3)**
API publique figée et documentée, réutilisable par #14/#16/#17/#21 et les bindings
#11/#17. Aucun point crypto assigné au module par le modèle de menace #6 n'est laissé
ouvert. Reste la revue indépendante externe **#26** avant mise en production.
