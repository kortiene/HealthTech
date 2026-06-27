# Spec — Politique de consentement & parcours juridique patient (issue #7)

## Problem Statement

Avant que le parcours d'onboarding patient (#13) puisse être implémenté, la loi n°2013-450
relative à la protection des données à caractère personnel exige que le patient soit informé
des traitements le concernant (REQ-LEX-03, REQ-LEX-04, REQ-LEX-11) et que son consentement
soit recueilli de manière **libre, spécifique et éclairée**. Sans textes juridiques ni modèle
de données de consentement, le critère d'acceptation de CTRL-15 ne peut pas être satisfait et
#13 ne peut pas démarrer.

## Goals

- G1 — Produire les **textes juridiques draft** (consentement, CGU, politique de confidentialité)
  couvrant les exigences REQ-LEX-03/04/05/11 de la loi n°2013-450.
- G2 — Définir un **modèle de données de consentement** (`ConsentRecord`) versionné, sérialisable
  en JSON, prêt à être persisté par #13 dans le compte patient chiffré.
- G3 — Marquer CTRL-15 (écrans de consentement + CGU + politique de confidentialité) comme **Partiel**
  dans la matrice de contrôles ; mettre à jour PREUVE-11 et PREUVE-27.
- G4 — Constituer la **preuve documentaire** nécessaire pour le dossier d'homologation ARTCI (#30).

## Non-Goals

- Implémentation des écrans Flutter (responsabilité de #13).
- Validation juridique finale par le conseil juridique (à faire avant la production).
- Horodatage cryptographique de la capture (CTRL-16 — responsabilité de #13).
- Gestion du retrait de consentement ou du régime des mineurs (ECART-05 — à résoudre avant #30).

## Relevant Repository Context

- **loi n°2013-450** — loi ivoirienne sur la protection des données personnelles. La
  [matrice de conformité](../docs/compliance/loi-2013-450-artci-matrix.md) mappe chaque article
  vers un contrôle technique et une preuve.
- **CTRL-15** — contrôle organisationnel « Écrans de consentement + CGU + politique de
  confidentialité dans l'onboarding » — actuellement **Planifié**, cible **Partiel** après ce PR.
- **#13** — dépend de #7 (dependency confirmée dans `BACKLOG.md`).
- **Zéro-connaissance** — le serveur ne voit jamais les données patient ; le `ConsentRecord`
  sera intégré dans le compte chiffré (client-side only).
- `app-patient/` — application Flutter pour Android (Flutter 3.41.5 / Dart 3.8.1).
- Le modèle `MedicalRecord` (issue #15) et `ConsentRecord` (cette issue) suivent le même
  pattern : classe Dart immuable + `fromJson`/`toJson` + tests de round-trip.

## Proposed Implementation

### 1. Textes juridiques (`docs/legal/consent-v1.md`)

Un seul fichier Markdown contenant :
- **Politique de consentement** — base légale, finalités, droits, contact ARTCI.
- **Conditions Générales d'Utilisation (CGU)** — obligations, responsabilités, droit applicable.
- **Politique de confidentialité** — données collectées, durée de conservation, droits d'accès.

Les textes sont **version 1.0**, marqués **`[DRAFT — en attente de validation juridique]`**.
Tous les `[article]` et `[à compléter]` sont explicitement signalés pour le conseil juridique.

### 2. Modèle de données (`app-patient/lib/src/legal/consent_model.dart`)

```dart
const String consentBundleVersion = '1.0';

class ConsentRecord {
  final String version;   // identifiant de version du bundle (= consentBundleVersion)
  final String acceptedAt; // ISO-8601 UTC
}
```

- `version` référence la version des textes affichés au patient.
- `acceptedAt` est l'horodatage de l'acceptation (rempli par #13 via `DateTime.now().toUtc()`).
- `fromJson`/`toJson` pour l'intégration dans le compte chiffré.
- La classe est immuable (`const`-eligible) et comparable (`==`, `hashCode`).

### 3. Mise à jour des contrôles (`docs/compliance/controles.md`)

- CTRL-15 : Planifié → **Partiel** (textes draft livrés ; validation juridique + intégration UX en attente).
- PREUVE-11 : À produire → **Draft** (lien vers `docs/legal/consent-v1.md`).
- PREUVE-27 : À produire → **Draft** (lien vers `docs/legal/consent-v1.md`).

## Affected Files / Packages / Modules

| Fichier | Action |
|---|---|
| `specs/issue-7-consent-policy-onboarding.md` | Nouveau (ce fichier) |
| `docs/legal/consent-v1.md` | Nouveau — textes juridiques draft |
| `app-patient/lib/src/legal/consent_model.dart` | Nouveau — modèle `ConsentRecord` |
| `app-patient/test/legal/consent_model_test.dart` | Nouveau — tests |
| `docs/compliance/controles.md` | Mise à jour CTRL-15, PREUVE-11, PREUVE-27 |

## API / Interface Changes

Aucune interface réseau ni API publique. La structure JSON de `ConsentRecord` est introduite :

```json
{ "version": "1.0", "accepted_at": "2024-01-15T10:30:00Z" }
```

## Data Model / Protocol Changes

`ConsentRecord` sera intégré dans le compte patient chiffré par #13 — probablement comme champ
optionnel de la structure de compte (non définie par cette issue).

## Security & Compliance Considerations

- Le `ConsentRecord` ne contient **aucune donnée médicale, aucune clé, aucun PII** : uniquement
  une version de texte et un horodatage. Il peut être persisté en clair dans les métadonnées du
  compte local, ou chiffré au même titre que le dossier médical — décision laissée à #13.
- Les textes juridiques eux-mêmes ne contiennent pas de données patient.
- La présence d'un `ConsentRecord` horodaté satisfait la preuve de recueil (REQ-LEX-04) lorsque
  l'intégration UX de #13 est complète.
- **ECART-05** (régime mineurs) reste ouvert ; les textes draft incluent un avertissement.

## Testing Plan

- Round-trip JSON : `ConsentRecord.fromJson(r.toJson()) == r`.
- Rejet des champs manquants : `fromJson` lève une `TypeError` si `version` ou `accepted_at`
  est absent.
- Constante `consentBundleVersion` : vaut `'1.0'` (régression si montée de version sans test).
- `ConsentRecord` const-eligible (tous les champs `String`, constructeur `const`).

## Documentation Updates

- `docs/compliance/controles.md` : CTRL-15 Partiel, PREUVE-11 Draft, PREUVE-27 Draft.
- `specs/` : ce fichier.

## Implementation Checklist

- [x] Spec rédigée
- [ ] `docs/legal/consent-v1.md` créé
- [ ] `app-patient/lib/src/legal/consent_model.dart` créé
- [ ] `app-patient/test/legal/consent_model_test.dart` créé
- [ ] `docs/compliance/controles.md` mis à jour
- [ ] `dart format` vérifié (0 fichier modifié)
- [ ] `flutter analyze` vérifié (0 info/warning)
