# UX — interface médecin (`docs/ux/`)

> **Issue porteuse :** [#28 — Affûtage UX médecin (prise en main < 5 min)](../../BACKLOG.md) · Épic **E4 — Performance & UX** · Jalon **M4** · label `ux`.
> **Implémente :** NFR UX ([`PRD_HealthTech.md`](../../PRD_HealthTech.md) §5).

Ce répertoire matérialise la **norme UX opposable** de l'interface médecin et l'**outillage
anti-régression + protocole de test** qui la protègent. Il ne modifie ni la cryptographie, ni le
format de blob, ni le protocole réseau, ni le modèle de menace.

## Contenu

| Fichier | Rôle |
|---------|------|
| [`medecin-ux-guidelines.md`](./medecin-ux-guidelines.md) | **Guide UX normatif** (source unique) : mono-flux « zéro menu », parcours canonique en 4 étapes, hiérarchie de l'information critique, ergonomie clinique, microcopie FR, feedback d'état, gestion des erreurs, anti-patterns, **checklist de revue UX**. |
| [`usability-test-protocol.md`](./usability-test-protocol.md) | **Protocole de test utilisateur** reproductible : objectif mesurable, panel, environnement (bas de gamme + 3G simulé), scénario scripté, instruments (SUS FR + temps + succès/échec), seuils de réussite, éthique/consentement, gabarit de compte-rendu (statut « à produire »). |
| [`low-end-device-profile.md`](./low-end-device-profile.md) | **Profil d'appareil de référence bas de gamme** (#29, source de vérité partagée #28/#29/#31) : RAM/stockage/espace libre, API Android min, densité/écran, réglages d'accessibilité testés, budgets dérivés (mémoire, `StorageBudget`), traçabilité PRD §1/§2/§4. |
| [`low-end-validation-protocol.md`](./low-end-validation-protocol.md) | **Protocole de validation robustesse & accessibilité** (#29) : deux parcours, scénario « stockage saturé », scénario « micro-coupure » (points d'injection), grille d'accessibilité (échelle texte, TalkBack, contraste, cibles, une main), perf sous contrainte (#27/#28), gabarit « à produire », éthique/consentement (#7). |

## Artefacts de code liés

| Artefact | Rôle |
|----------|------|
| [`app-patient/lib/src/doctor/ux_budget.dart`](../../app-patient/lib/src/doctor/ux_budget.dart) | **Constante de budget d'étapes** (source de vérité) : `maxConsultationSteps`, `maxConsultationScreens`, `canonicalSteps`, `criticalSectionOrder`, proxy temps-tâche machine. |
| [`app-patient/lib/src/doctor/task_timing.dart`](../../app-patient/lib/src/doctor/task_timing.dart) | **Instrumentation temps-tâche** respectueuse de la vie privée (labels + durées uniquement ; désactivée par défaut). |
| [`app-patient/lib/src/doctor/storage_budget.dart`](../../app-patient/lib/src/doctor/storage_budget.dart) | **Budget de stockage local** (#29, source de vérité) : `maxQueueEntryBytes` (== `PerfBudget.maxCompressedBlobBytes`), `maxPendingQueueEntries`, `maxQueueFootprintBytes`, invariant « aucune image lourde sur l'appareil » (#23). |
| `app-patient/test/ux/` | **Garde-fou de parcours** (budget d'étapes + proxy temps-tâche machine, réseau exclu), **invariants UX** (ordre des sections, libellés FR, absence de menu), **test de redaction** de l'instrumentation. |
| [`app-medecin/src/walkthrough.test.ts`](../../app-medecin/src/walkthrough.test.ts) | **Test de fumée PWA** (vitest) : mono-flux du shell, `IDLE_TIMEOUT_MS`, absence de menu. Documente l'activation future du garde-fou d'étapes PWA (le flux arrive avec #17/#21/#22). |

## Gate

`just ux-check` ([`scripts/check-ux-docs.sh`](../../scripts/check-ux-docs.sh)) vérifie la
**cohérence** entre ces documents et le code (chemins et constantes référencés existent, honnêteté
du statut « campagne terrain à produire »). Il est intégré à `just lint`. Les tests de parcours
eux-mêmes roulent dans la CI existante via `flutter test` (`test/ux/`) et `npm test` (PWA).

`just lowend-check` ([`scripts/check-lowend-docs.sh`](../../scripts/check-lowend-docs.sh)) fait de
même pour le **profil d'appareil de référence** et le **protocole de robustesse & accessibilité**
(#29) : cohérence `docs/ux/` ↔ `storage_budget.dart` / `PerfBudget`, honnêteté du statut
« validation terrain à produire ». Également intégré à `just lint`.

## Portée & honnêteté

- Le critère d'acceptation (« un médecin non formé … lors d'un test utilisateur ») est **humain**
  et **non closable par du code**. Le garde-fou automatisé est un **proxy anti-régression**, pas
  une preuve — mêmes limites que #25 (pentest) et #30 (homologation).
- Les deux surfaces médecin (Flutter de référence `app-patient`, PWA `app-medecin`) se réfèrent à
  ce guide comme **source unique** et ne doivent pas diverger.
